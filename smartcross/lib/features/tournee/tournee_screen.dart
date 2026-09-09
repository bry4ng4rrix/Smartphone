import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/order_historique_view.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _tourneeDateFmt = DateFormat('dd/MM/yyyy');

/// Module Livreur (§7.3 README) : UX ultra simplifiée, orientée tournée. Le
/// serveur renvoie aussi les commandes "En préparation" (visibilité/planning,
/// pas encore actionnable pour ce rôle) en plus de PRETE/EN_LIVRAISON.
class TourneeScreen extends ConsumerStatefulWidget {
  const TourneeScreen({super.key});

  @override
  ConsumerState<TourneeScreen> createState() => _TourneeScreenState();
}

class _TourneeScreenState extends ConsumerState<TourneeScreen> {
  bool _historique = false;

  // Filtre "Ma tournée" : une seule date (pas de plage Du/Au) — § demande.
  // Réutilise le même `ordersFilterProvider` que la page Commandes du gérant
  // (date_debut = date_fin côté serveur).
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

  void _clearDate() => ref.read(ordersFilterProvider.notifier).set(const OrdersFilter());

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersProvider);
    final filter = ref.watch(ordersFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_historique ? 'Tournée — Historique' : 'Ma tournée'),
        actions: [
          IconButton(
            tooltip: _historique ? 'Tournée active' : 'Historique',
            icon: Icon(_historique ? Icons.local_shipping_outlined : Icons.history),
            onPressed: () => setState(() => _historique = !_historique),
          ),
        ],
      ),
      body: _historique
          ? OrderHistoriqueView(cardBuilder: (context, order) => _TourneeHistoriqueCard(order: order))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(filter),
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            filter.dateDebut != null ? _tourneeDateFmt.format(filter.dateDebut!) : 'Filtrer par date',
                          ),
                        ),
                      ),
                      if (filter.dateDebut != null)
                        IconButton(onPressed: _clearDate, icon: const Icon(Icons.clear)),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
                    child: switch (async) {
                      AsyncData(:final value) => value.isEmpty
                          ? const EmptyState(message: 'Aucune commande en tournée.', icon: Icons.local_shipping_outlined)
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: value.length,
                              itemBuilder: (context, i) => _TourneeCard(order: value[i]),
                            ),
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
    );
  }
}

class _TourneeCard extends ConsumerStatefulWidget {
  const _TourneeCard({required this.order});
  final Order order;

  @override
  ConsumerState<_TourneeCard> createState() => _TourneeCardState();
}

class _TourneeCardState extends ConsumerState<_TourneeCard> {
  bool _loading = false;

  Future<void> _changeStatus(OrderStatus target, {String note = ''}) async {
    setState(() => _loading = true);
    try {
      await ref.read(ordersProvider.notifier).changeStatus(widget.order.id, target.apiValue, note: note);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _actionLabel(OrderStatus target) =>
      target == OrderStatus.enLivraison ? 'Récupérer le colis' : target.label;

  Future<void> _confirm(OrderStatus target) async {
    final result = await showOrderConfirmDialog(context, title: 'Confirmer : ${_actionLabel(target)}', order: widget.order);
    if (result != null) _changeStatus(target, note: result.note);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPrete = order.statutCourant == OrderStatus.prete;
    final isEnPreparation = order.statutCourant == OrderStatus.enPreparation;
    final dueToday = isJourJ(order.dateCommande);

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
                Text(order.numero, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
                    Text(order.telephone!, style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            for (final item in order.items) Text('• ${item.referenceName} — ${item.couleur} (x${item.quantite})'),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 16),
                const SizedBox(width: 6),
                Text(order.livraisonZone.shortLabel),
              ],
            ),
            if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(order.adresseLivraison!)),
                  ],
                ),
              ),
            if (order.totalAPayer != null) ...[
              const SizedBox(height: 4),
              Text('Total à encaisser : ${_ar(order.totalAPayer!)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (isEnPreparation)
              // Visible pour planning uniquement — pas encore prête, rien à
              // faire ici pour le livreur.
              Row(
                children: [
                  Icon(Icons.hourglass_empty, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text('En cours de préparation', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                ],
              )
            else if (isPrete)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: dueToday ? () => _confirm(OrderStatus.enLivraison) : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    dueToday || order.dateCommande == null
                        ? 'Récupérer le colis'
                        : 'Disponible le ${dueDateLabel(order.dateCommande!)}',
                  ),
                ),
              )
            else ...[
              if (!dueToday && order.dateCommande != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Disponible le ${dueDateLabel(order.dateCommande!)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: dueToday ? () => _confirm(OrderStatus.livre) : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Livré'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: dueToday ? () => _confirm(OrderStatus.retour) : null,
                      icon: const Icon(Icons.undo),
                      label: const Text('Retour'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TourneeHistoriqueCard extends StatelessWidget {
  const _TourneeHistoriqueCard({required this.order});
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
                Text(order.numero, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                OrderStatusBadge(status: order.statutCourant),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.clientNom, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (order.telephone != null)
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(order.telephone!),
                ],
              ),
            const SizedBox(height: 4),
            for (final item in order.items) Text('• ${item.referenceName} — ${item.couleur} (x${item.quantite})'),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 16),
                const SizedBox(width: 6),
                Text(order.livraisonZone.shortLabel),
              ],
            ),
            if (order.totalAPayer != null) ...[
              const SizedBox(height: 4),
              Text('Total : ${_ar(order.totalAPayer!)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
