import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_time.dart';
import '../../data/repositories/catalog_repository.dart' show catalogErrorMessage;
import '../../models/supplier.dart';
import '../../state/suppliers_provider.dart';
import '../../widgets/async_state_widgets.dart';
import 'supplier_status.dart';

final _dateFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat("dd/MM/yyyy 'à' HH'h'mm");

/// Fiche d'une commande fournisseur — équivalent du dialog « Commande
/// fournisseur `numero` » de frontend/app/(app)/suppliers/page.tsx :
/// description, Prix fournisseur / Fret/import / Douane, « Coût total (N
/// u.) », « Coût unitaire », lignes « `référence (couleur) xqté` » avec
/// leur marge unitaire, et le bouton « Réceptionner (entrée stock) » tant que
/// le statut n'est pas RECU.
///
/// Contrairement au dialog web (instantané figé de la ligne du tableau), la
/// fiche est rechargée à chaque événement temps réel.
class SupplierOrderDetailScreen extends ConsumerStatefulWidget {
  const SupplierOrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  @override
  ConsumerState<SupplierOrderDetailScreen> createState() => _SupplierOrderDetailScreenState();
}

class _SupplierOrderDetailScreenState extends ConsumerState<SupplierOrderDetailScreen> {
  bool _receiving = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// `receive(detail)` du web : POST receive -> toast « Commande `numero`
  /// reçue — stock mis à jour » -> liste rechargée -> fermeture du détail.
  Future<void> _receive(SupplierOrder order) async {
    if (_receiving) return;
    if (!await confirmSupplierReceive(context, order.numero)) return;
    setState(() => _receiving = true);
    try {
      await ref.read(supplierOrdersProvider.notifier).receive(order.id);
      ref.invalidate(supplierOrderDetailProvider(order.id));
      if (!mounted) return;
      _snack('Commande ${order.numero} reçue — stock mis à jour');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/suppliers');
      }
    } catch (e) {
      _snack(catalogErrorMessage(e, 'Réception impossible'));
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supplierOrderDetailProvider(widget.orderId));
    final order = async.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'Commande fournisseur' : 'Commande fournisseur ${order.numero}'),
      ),
      body: order != null
          ? _Body(order: order, receiving: _receiving, onReceive: () => _receive(order))
          : async.hasError
              ? ErrorState(
                  message: catalogErrorMessage(async.error!, 'Erreur de chargement'),
                  onRetry: () => ref.invalidate(supplierOrderDetailProvider(widget.orderId)),
                )
              : const LoadingState(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.order, required this.receiving, required this.onReceive});

  final SupplierOrder order;
  final bool receiving;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    final description = (order.description ?? '').trim();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text(order.numero, style: Theme.of(context).textTheme.headlineSmall)),
            SupplierStatusBadge(statut: order.statut),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(description, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    _Cell(label: 'Prix fournisseur', value: supplierAr(order.prixFournisseur), muted: muted),
                    _Cell(label: 'Fret/import', value: supplierAr(order.fretImport), muted: muted),
                    _Cell(label: 'Douane', value: supplierAr(order.douane), muted: muted),
                    if (order.date != null) _Cell(label: 'Date', value: _dateFmt.format(order.date!), muted: muted),
                    if (order.receivedAt != null)
                      _Cell(label: 'Reçue le', value: _dateTimeFmt.format(appLocal(order.receivedAt!)), muted: muted),
                  ],
                ),
                const Divider(height: 24),
                _Row('Coût total (${order.totalQty} u.)', supplierAr(order.coutTotal), emphasize: true),
                _Row('Coût unitaire', supplierAr(order.coutUnitaire)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Lignes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: order.lines.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Aucune ligne', style: TextStyle(color: scheme.onSurfaceVariant)),
                )
              : Column(
                  children: [
                    for (final line in order.lines)
                      ListTile(
                        title: Text('${line.referenceName} (${line.couleur}) x${line.quantite}'),
                        subtitle: Text(
                          'Coût unitaire ${supplierAr(line.coutUnitaireCalcule)} · total ligne ${supplierAr(line.totalLigne)}',
                          style: muted,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Marge unitaire', style: muted),
                            Text(
                              supplierAr(line.margeUnitaire),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: line.margeUnitaire < 0 ? scheme.error : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (!order.isReceived) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: receiving ? null : onReceive,
            icon: receiving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.inventory_outlined),
            label: const Text('Réceptionner (entrée stock)'),
          ),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.muted});
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
        Text(value),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
