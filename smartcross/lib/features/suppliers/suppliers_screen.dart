import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/catalog_repository.dart' show catalogErrorMessage;
import '../../models/supplier.dart';
import '../../state/suppliers_provider.dart';
import '../../widgets/async_state_widgets.dart';
import 'supplier_status.dart';

/// Page `/suppliers` du web (frontend/app/(app)/suppliers/page.tsx) —
/// module Commandes Fournisseur (§7.6 README) : lister les commandes, en
/// créer (écran dédié `/suppliers/new`, équivalent du dialog
/// `CreateSupplierOrderDialog`), consulter le détail (`/suppliers/:id`,
/// équivalent du dialog de détail) et réceptionner (entrée stock).
///
/// Gating : la page web n'a AUCUN garde interne (menu `adminOnly` + 403
/// serveur). Ici le contrôle est fait en amont par `core/router.dart` /
/// `core/nav_items.dart::canAccessPath` (gérant = admin | magasin).
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  /// Rechargement NON silencieux en cours (bouton « Rafraîchir », après une
  /// réception) — Riverpod 3 conserve la valeur précédente pendant un
  /// `AsyncLoading`, l'écran s'en souvient donc lui-même pour afficher le
  /// skeleton comme le web.
  bool _refreshing = false;

  /// Commande en cours de réception (bouton désactivé + spinner).
  int? _receivingId;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Bouton « Rafraîchir » du web : `fetchOrders()` NON silencieux.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(supplierOrdersProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    _signalRefreshError();
  }

  /// Tirer-pour-rafraîchir : la liste reste affichée (`fetchOrders(true)`).
  Future<void> _silentRefresh() async {
    await ref.read(supplierOrdersProvider.notifier).refreshSilencieux();
    _signalRefreshError();
  }

  /// Web : `toast.error(err.message || 'Erreur de chargement')`, la liste
  /// précédente reste affichée.
  void _signalRefreshError() {
    if (!mounted) return;
    final after = ref.read(supplierOrdersProvider);
    if (after.hasError && after.hasValue) _snack(catalogErrorMessage(after.error!, 'Erreur de chargement'));
  }

  /// `receive(order)` du web : POST receive -> toast succès -> `fetchOrders()`
  /// non silencieux. Erreur : `toast.error(err.message || 'Réception
  /// impossible')` (ex : « Cette commande fournisseur a déjà été reçue. »).
  Future<void> _receive(SupplierOrder order) async {
    if (_receivingId != null) return;
    if (!await confirmSupplierReceive(context, order.numero)) return;
    setState(() {
      _receivingId = order.id;
      _refreshing = true;
    });
    try {
      await ref.read(supplierOrdersProvider.notifier).receive(order.id);
      _snack('Commande ${order.numero} reçue — stock mis à jour');
    } catch (e) {
      _snack(catalogErrorMessage(e, 'Réception impossible'));
    } finally {
      if (mounted) {
        setState(() {
          _receivingId = null;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supplierOrdersProvider);
    final scheme = Theme.of(context).colorScheme;
    // Chargement « bloquant » : premier chargement et « Rafraîchir »
    // uniquement. Un rafraîchissement WebSocket garde la liste à l'écran.
    final initialLoading = !async.hasValue && !async.hasError;
    final loading = _refreshing || initialLoading;
    final orders = async.value ?? const <SupplierOrder>[];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_shipping_outlined),
            SizedBox(width: 8),
            Text('Fournisseurs'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: loading ? null : _refresh,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Coût de revient réel : marchandise + fret/import + douane (§7.6 du cahier des charges).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: loading
                ? const LoadingState()
                : (async.hasError && !async.hasValue)
                    ? ErrorState(
                        message: catalogErrorMessage(async.error!, 'Erreur de chargement'),
                        onRetry: _refresh,
                      )
                    : RefreshIndicator(
                        onRefresh: _silentRefresh,
                        child: orders.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  EmptyState(message: 'Aucune commande fournisseur.', icon: Icons.local_shipping_outlined),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                                itemCount: orders.length,
                                itemBuilder: (context, i) => _SupplierOrderCard(
                                  order: orders[i],
                                  receiving: _receivingId == orders[i].id,
                                  onReceive: _receivingId == null ? () => _receive(orders[i]) : null,
                                ),
                              ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/suppliers/new'),
        icon: const Icon(Icons.add),
        label: const Text('Commande fournisseur'),
      ),
    );
  }
}

/// Une ligne du tableau web : N° (gras), description ('-' si vide), coût
/// total, coût unitaire, badge statut, et le bouton « Réceptionner » (statut
/// != RECU uniquement) — indépendant du tap sur la carte, qui ouvre le
/// détail (`e.stopPropagation()` du web).
class _SupplierOrderCard extends StatelessWidget {
  const _SupplierOrderCard({required this.order, required this.receiving, required this.onReceive});

  final SupplierOrder order;
  final bool receiving;
  final VoidCallback? onReceive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    final description = (order.description ?? '').trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/suppliers/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  SupplierStatusBadge(statut: order.statut),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description.isEmpty ? '-' : description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Kv(label: 'Coût total', value: supplierAr(order.coutTotal), muted: muted),
                  _Kv(label: 'Coût unitaire', value: supplierAr(order.coutUnitaire), muted: muted),
                  _Kv(label: 'Quantité', value: '${order.totalQty} u.', muted: muted),
                ],
              ),
              if (!order.isReceived) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: onReceive,
                    icon: receiving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.inventory_outlined, size: 18),
                    label: const Text('Réceptionner'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value, required this.muted});
  final String label;
  final String value;
  final TextStyle muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: muted),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
