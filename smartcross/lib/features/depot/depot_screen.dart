import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/order_historique_view.dart';
import '../../widgets/status_badge.dart';

enum _DepotView { aPreparer, recuperations, historique }

final _depotDateFmt = DateFormat('dd/MM/yyyy');
final _depotDateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Module Dépôt — Préparateur (§7.2 README) : UX mobile simplifiée, lecture
/// seule sauf statut. Le serveur ne renvoie déjà que NOUVELLE/EN_PREPARATION
/// pour ce rôle, sans aucune donnée financière (serializer restreint). Onglet
/// "Récupérations" : commandes de retrait sur place que le préparateur peut
/// créer lui-même (§ demande — bouton "Nouvelle récupération").
class DepotScreen extends ConsumerStatefulWidget {
  const DepotScreen({super.key});

  @override
  ConsumerState<DepotScreen> createState() => _DepotScreenState();
}

class _DepotScreenState extends ConsumerState<DepotScreen> {
  _DepotView _view = _DepotView.aPreparer;

  // Filtre "À préparer"/"Récupérations" : une seule date (pas de plage
  // Du/Au) — § demande. Réutilise le même `ordersFilterProvider` que la
  // page Commandes du gérant (date_debut = date_fin côté serveur).
  Future<void> _pickDate(OrdersFilter filter) async {
    final date = await showDatePicker(
      context: context,
      initialDate: filter.dateDebut ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    ref.read(ordersFilterProvider.notifier).set(filter.copyWith(dateDebut: date, dateFin: date));
  }

  // « Effacer » ramène au jour J, la valeur par défaut — pas à « aucune
  // date », qui afficherait tout l'historique du préparateur.
  void _clearDate() => ref.read(ordersFilterProvider.notifier).set(jourJFilter(UserRole.preparateur));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersProvider);
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);

    final filter = ref.watch(ordersFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dépôt')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('À préparer'),
                    selected: _view == _DepotView.aPreparer,
                    onSelected: (_) => setState(() => _view = _DepotView.aPreparer),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Récupérations'),
                    selected: _view == _DepotView.recuperations,
                    onSelected: (_) => setState(() => _view = _DepotView.recuperations),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Historique'),
                    selected: _view == _DepotView.historique,
                    onSelected: (_) => setState(() => _view = _DepotView.historique),
                  ),
                ),
              ],
            ),
          ),
          if (_view != _DepotView.historique)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(filter),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        filter.dateDebut != null
                            ? _depotDateFmt.format(filter.dateDebut!)
                            : 'Filtrer par date',
                      ),
                    ),
                  ),
                  if (filter.dateDebut != null)
                    IconButton(onPressed: _clearDate, icon: const Icon(Icons.clear)),
                ],
              ),
            ),
          Expanded(
            child: _view == _DepotView.historique
                ? OrderHistoriqueView(cardBuilder: (context, order) => _DepotHistoriqueCard(order: order))
                : RefreshIndicator(
                    onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
                    child: switch (async) {
                      AsyncData(value: final all) => (() {
                        final isRecup = _view == _DepotView.recuperations;
                        final value = all
                            .where((o) => (o.livraisonZone == kRecuperationCode) == isRecup)
                            .toList();
                        return value.isEmpty
                            ? EmptyState(
                                message: isRecup ? 'Aucune récupération.' : 'Aucune commande à préparer.',
                                icon: Icons.inventory_outlined,
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: value.length,
                                itemBuilder: (context, i) => _DepotCard(order: value[i]),
                              );
                      })(),
                      AsyncError(:final error) => ErrorState(
                        message: ApiClient.messageFromError(error),
                        onRetry: () => ref.read(ordersProvider.notifier).refresh(),
                      ),
                      _ => const LoadingState(),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle récupération'),
      ),
    );
  }
}

class _DepotHistoriqueCard extends StatelessWidget {
  const _DepotHistoriqueCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.numero,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                OrderStatusBadge(status: order.statutCourant),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.clientNom, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final item in order.items)
              Text('• ${item.referenceName} — ${item.couleur} (x${item.quantite})'),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 16),
                const SizedBox(width: 6),
                Text(DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
              ],
            ),
            // Mêmes repères que sur la file du jour : qui livre, et quand
            // (prévu, ou réellement livré une fois la commande terminée).
            if (order.livreurName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.moped_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Livreur : ${order.livreurName}'),
                  ],
                ),
              ),
            if (order.dateCommande != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      order.statutCourant == OrderStatus.livre
                          ? 'Livrée le ${_depotDateTimeFmt.format(appLocal(order.dateCommande!))}'
                          : 'Livraison prévue le ${_depotDateTimeFmt.format(appLocal(order.dateCommande!))}',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepotCard extends ConsumerStatefulWidget {
  const _DepotCard({required this.order});
  final Order order;

  @override
  ConsumerState<_DepotCard> createState() => _DepotCardState();
}

class _DepotCardState extends ConsumerState<_DepotCard> {
  bool _loading = false;

  Future<void> _advance() async {
    final order = widget.order;
    final target = order.statutCourant == OrderStatus.nouvelle
        ? OrderStatus.enPreparation
        : OrderStatus.prete;
    final actionLabel = order.statutCourant == OrderStatus.nouvelle
        ? 'Commencer la préparation'
        : 'Commande prête';
    // Preuve que la préparation est faite — proposée uniquement au passage
    // "Prête" (§ demande), visible ensuite par le livreur et dans l'historique.
    final result = await showOrderConfirmDialog(
      context,
      title: 'Confirmer : $actionLabel',
      order: order,
      showPhoto: target == OrderStatus.prete,
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(ordersProvider.notifier)
          .changeStatus(order.id, target.apiValue, note: result.note, photoPath: result.photoPath);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isNouvelle = order.statutCourant == OrderStatus.nouvelle;
    final dueToday = isJourJ(order.dateCommande, UserRole.preparateur);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.numero,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                OrderStatusBadge(status: order.statutCourant),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.clientNom, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (order.telephone != null)
              InkWell(
                onTap: () => launchUrl(Uri.parse('tel:${order.telephone}')),
                child: Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      order.telephone!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            for (final item in order.items)
              Text('• ${item.referenceName} — ${item.couleur} (x${item.quantite})'),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 16),
                const SizedBox(width: 6),
                Text(DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
              ],
            ),
            // Qui livrera, et quand : le préparateur doit remettre le colis à
            // la bonne personne, au bon moment (§ demande).
            if (order.livreurName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.moped_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Livreur : ${order.livreurName}'),
                  ],
                ),
              ),
            if (order.dateCommande != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Livraison prévue le ${_depotDateTimeFmt.format(appLocal(order.dateCommande!))}'),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_loading || !dueToday) ? null : _advance,
                icon: _loading
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(
                  !dueToday && order.dateCommande != null
                      ? 'Disponible le ${dueDateLabel(order.dateCommande!, UserRole.preparateur)}'
                      : (isNouvelle ? 'Commencer la préparation' : 'Commande prête'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
