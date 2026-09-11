import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Filtres de statut de la tournée active (§ demande). « À récupérer » =
/// commande prête au dépôt, que le livreur doit venir chercher (PRETE) — le
/// libellé métier du livreur, plus parlant que « Prête ».
const _tourneeStatutFilters = <({String? value, String label})>[
  (value: null, label: 'Tous'),
  (value: 'EN_PREPARATION', label: 'En préparation'),
  (value: 'PRETE', label: 'À récupérer'),
  (value: 'EN_LIVRAISON', label: 'En livraison'),
];

/// Tournée du jour (§ demande) : le livreur ne voit QUE les commandes dont
/// la fenêtre d'affichage est ouverte — le jour de livraison, et 5 h avant.
/// Une commande du lundi n'apparaît donc qu'à partir du dimanche 19h00, heure
/// de Madagascar ; les suivantes restent invisibles.
///
/// Le bouton d'action reste soumis à sa propre règle, plus stricte : minuit
/// le jour de livraison (voir core/app_time.dart).
///
/// Les commandes retenues sont classées la plus récemment CRÉÉE en tête.
List<Order> _tourneeDuJour(List<Order> orders) {
  int creeLe(Order o) => o.createdAt?.millisecondsSinceEpoch ?? 0;
  final visibles = orders.where((o) => affichageOuvert(o.dateCommande)).toList();
  visibles.sort((a, b) => creeLe(b).compareTo(creeLe(a)));
  return visibles;
}

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
      initialDate: filter.dateDebut ?? appNow(),
      firstDate: appNow().subtract(const Duration(days: 365)),
      lastDate: appNow().add(const Duration(days: 365)),
    );
    if (date == null) return;
    ref.read(ordersFilterProvider.notifier).set(filter.copyWith(dateDebut: date, dateFin: date));
  }

  // « Effacer » ramène au jour J, la valeur par défaut — pas à « aucun
  // filtre », qui afficherait toute la tournée passée.
  void _clearFilters() =>
      ref.read(ordersFilterProvider.notifier).set(jourJFilter(UserRole.livreur));

  void _setStatut(OrdersFilter filter, String? statut) => ref
      .read(ordersFilterProvider.notifier)
      .set(statut == null ? filter.copyWith(clearStatut: true) : filter.copyWith(statut: statut));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersProvider);
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);

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
                            filter.dateDebut != null
                                ? _tourneeDateFmt.format(filter.dateDebut!)
                                : 'Filtrer par date',
                          ),
                        ),
                      ),
                      if (filter.dateDebut != null || filter.statut != null)
                        IconButton(onPressed: _clearFilters, icon: const Icon(Icons.clear)),
                    ],
                  ),
                ),
                // Filtres de statut : à récupérer, en livraison… (§ demande).
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _tourneeStatutFilters.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final f = _tourneeStatutFilters[i];
                      return ChoiceChip(
                        label: Text(f.label),
                        selected: filter.statut == f.value,
                        onSelected: (_) => _setStatut(filter, f.value),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
                    child: switch (async) {
                      AsyncData(:final value) => Builder(
                        builder: (context) {
                          final ordonnees = _tourneeDuJour(value);
                          if (ordonnees.isEmpty) {
                            return const EmptyState(
                              message: 'Aucune commande en tournée.',
                              icon: Icons.local_shipping_outlined,
                            );
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: ordonnees.length,
                            itemBuilder: (context, i) => _TourneeCard(order: ordonnees[i]),
                          );
                        },
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _actionLabel(OrderStatus target) =>
      target == OrderStatus.enLivraison ? 'Récupérer le colis' : target.label;

  Future<void> _confirm(OrderStatus target) async {
    final result = await showOrderConfirmDialog(
      context,
      title: 'Confirmer : ${_actionLabel(target)}',
      order: widget.order,
      // Déjà payé d'avance : le livreur n'a rien à encaisser, on masque
      // les montants pour éviter toute confusion (§ demande).
      hideAmounts: widget.order.modePaiement == PaymentMode.avant,
    );
    if (result != null) _changeStatus(target, note: result.note);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPrete = order.statutCourant == OrderStatus.prete;
    final isEnPreparation = order.statutCourant == OrderStatus.enPreparation;
    final dueToday = isJourJ(order.dateCommande, UserRole.livreur);

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
            if (order.modePaiement == PaymentMode.avant)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Déjà payé — rien à encaisser',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                ),
              )
            else if (order.totalAPayer != null) ...[
              const SizedBox(height: 4),
              Text(
                'Total à encaisser : ${_ar(order.totalAPayer!)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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
                  Text(
                    'En cours de préparation',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              )
            // Hors jour J, AUCUN bouton n'est rendu — pas même grisé
            // (§ demande) : seule une ligne muette annonce la date. La
            // commande reste visible dans le planning.
            else if (!dueToday)
              _AttenteJourJ(order: order)
            else if (isPrete)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _confirm(OrderStatus.enLivraison),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Récupérer le colis'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _confirm(OrderStatus.livre),
                      icon: const Icon(Icons.check),
                      label: const Text('Livré'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirm(OrderStatus.retour),
                      icon: const Icon(Icons.undo),
                      label: const Text('Retour'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Ligne muette affichée à la place des boutons tant que le jour J n'est pas
/// atteint : le livreur voit la commande dans son planning et sait quand il
/// pourra agir, sans bouton inerte à cliquer.
class _AttenteJourJ extends StatelessWidget {
  const _AttenteJourJ({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final couleur = Theme.of(context).colorScheme.outline;
    return Row(
      children: [
        Icon(Icons.schedule, size: 16, color: couleur),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            order.dateCommande == null
                ? 'Pas encore disponible'
                : 'Disponible le '
                    '${dueDateLabel(order.dateCommande!, UserRole.livreur)}',
            style: TextStyle(color: couleur),
          ),
        ),
      ],
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
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(order.telephone!),
                ],
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
            if (order.modePaiement == PaymentMode.avant)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Déjà payé',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                ),
              )
            else if (order.totalAPayer != null) ...[
              const SizedBox(height: 4),
              Text('Total : ${_ar(order.totalAPayer!)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
