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
import '../orders/order_create_screen.dart' show modePaiementLabel, orderToast;

/// Filtres de statut de la tournée active (`LIVREUR_STATUT_ACTIF` de
/// page.tsx — § demande) : le livreur ne filtre que sur les deux états qui le
/// concernent — celles qu'il doit aller chercher, et celles qu'il a livrées.
/// « À récupérer » = commande prête au dépôt (statut PRETE), libellé métier
/// du livreur, plus parlant que « Prête ». Les autres états (en
/// préparation, en livraison, retour) restent visibles dans la liste via
/// « Tous les statuts » : on retire l'option de filtre, pas les commandes.
/// `null` = tous les statuts.
const _tourneeStatutFilters = <({String? value, String label})>[
  (value: null, label: 'Tous les statuts'),
  (value: 'PRETE', label: 'À récupérer'),
  (value: 'LIVRE', label: 'Livrées'),
];

/// Tournée du jour (§ demande) : le livreur ne voit QUE les commandes dont
/// la fenêtre d'affichage est ouverte — le jour de livraison, et 5 h avant.
/// Une commande du lundi n'apparaît donc qu'à partir du dimanche 19h00, heure
/// de Madagascar ; les suivantes restent invisibles tant que leur fenêtre
/// n'est pas ouverte : sa tournée ne montre que ce qui le concerne
/// maintenant. Son onglet Historique, lui, n'est pas filtré : c'est un
/// journal.
///
/// Le bouton d'action reste soumis à sa propre règle, plus stricte : minuit
/// le jour de livraison (voir core/app_time.dart).
///
/// Les commandes retenues sont classées la plus récemment CRÉÉE en tête.
List<Order> _tourneeDuJour(Iterable<Order> orders) {
  int creeLe(Order o) => o.createdAt?.millisecondsSinceEpoch ?? 0;
  final visibles = orders.where((o) => affichageOuvert(o.dateCommande)).toList();
  visibles.sort((a, b) => creeLe(b).compareTo(creeLe(a)));
  return visibles;
}

// Tous les horodatages sont affichés à l'heure d'Antananarivo (fuseau du
// magasin), quel que soit le réglage de l'appareil — cohérent avec la règle
// du jour J et avec le serveur (voir core/app_time.dart).
final _dayFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Recherche texte GLOBALE côté client (`searchableOrders` du web) : numéro,
/// client, adresse, téléphones, zone, préparateur, livreur, statut, articles
/// et date de livraison formatée (jour, et jour + heure). Insensible à la
/// casse, `includes` simple.
bool _matches(Order o, String q) {
  if (q.isEmpty) return true;
  final date = o.dateCommande == null ? null : appLocal(o.dateCommande!);
  final parts = <String?>[
    o.numero,
    o.clientNom,
    o.adresseLivraison,
    o.telephone,
    o.telephone2,
    o.livraisonZone,
    DeliveryZoneCatalog.shortLabelFor(o.livraisonZone),
    o.preparateurName,
    o.livreurName,
    o.statutCourant.apiValue,
    o.statutCourant.label,
    for (final it in o.items) ...[it.referenceName, it.brandName, it.typeName, it.couleur],
    if (date != null) ...[_dayFmt.format(date), _dateTimeFmt.format(date)],
  ];
  return parts.whereType<String>().join(' ').toLowerCase().contains(q);
}

/// Compose le numéro (`<a href="tel:…">` du web). Sans application capable
/// de téléphoner (tablette, émulateur), on le dit plutôt que d'échouer en
/// silence.
Future<void> _appeler(BuildContext context, String numero) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ok = await launchUrl(Uri.parse('tel:$numero'));
    if (!ok) messenger.showSnackBar(SnackBar(content: Text("Impossible d'appeler le $numero sur cet appareil.")));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text("Impossible d'appeler le $numero sur cet appareil.")));
  }
}

enum _TourneeView { active, historique }

/// Module Livreur — vue livreur de /orders côté web (§7.3 README) : « Ma
/// tournée » (commandes prêtes à récupérer, puis « Livré » ou « Retour ») et
/// « Historique » (journal de toutes ses commandes, tous statuts). Le serveur
/// renvoie aussi les commandes « Nouvelle » / « En préparation » qui lui sont
/// déjà assignées (planning, pas encore actionnables pour ce rôle).
class TourneeScreen extends ConsumerStatefulWidget {
  const TourneeScreen({super.key});

  @override
  ConsumerState<TourneeScreen> createState() => _TourneeScreenState();
}

class _TourneeScreenState extends ConsumerState<TourneeScreen> {
  _TourneeView _view = _TourneeView.active;
  final _searchController = TextEditingController();
  String _search = '';

  /// Bouton « Rafraîchir » : rechargement NON silencieux (repasse par l'état
  /// de chargement, comme le skeleton du web) — contrairement au temps réel
  /// et aux rechargements d'après action, silencieux.
  bool _refreshing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilter(OrdersFilter filter) => ref.read(ordersFilterProvider.notifier).set(filter);

  // Filtre "Ma tournée" : une seule date (pas de plage Du/Au) — § demande.
  // Réutilise le même `ordersFilterProvider` que la page Commandes du gérant
  // (date_debut = date_fin côté serveur). Sans date choisie, le serveur
  // renvoie tout le planning du livreur.
  Future<void> _pickDate(OrdersFilter filter) async {
    final today = appToday();
    final first = today.subtract(const Duration(days: 365));
    final last = today.add(const Duration(days: 365));
    var initial = filter.dateDebut ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
    if (date == null) return;
    _setFilter(filter.copyWith(dateDebut: date, dateFin: date));
  }

  /// Champ date vidé (comme l'input du web) : tout le planning.
  void _clearDate(OrdersFilter filter) => _setFilter(OrdersFilter(statut: filter.statut));

  void _setStatut(OrdersFilter filter, String? statut) =>
      _setFilter(statut == null ? filter.copyWith(clearStatut: true) : filter.copyWith(statut: statut));

  /// « Réinitialiser » : tous les statuts, aucune date (le filtre par défaut
  /// du livreur — tout son planning), recherche vidée.
  void _reset() {
    _setFilter(jourJFilter(UserRole.livreur));
    _searchController.clear();
    setState(() => _search = '');
  }

  Future<void> _refresh() async {
    if (_view == _TourneeView.historique) {
      ref.invalidate(orderHistoriqueProvider);
      return;
    }
    setState(() => _refreshing = true);
    try {
      await ref.read(ordersProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);
    final filter = ref.watch(ordersFilterProvider);
    final historique = _view == _TourneeView.historique;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(historique ? 'Historique' : 'Ma tournée'),
            Text(
              historique
                  ? 'Vos commandes déjà traitées, tous statuts — filtrables par date et heure.'
                  : 'Commandes prêtes à récupérer, puis "Livré" ou "Retour" une fois la tournée faite.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [IconButton(tooltip: 'Rafraîchir', icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: Column(
        children: [
          // Onglets du livreur : « Ma tournée » / « Historique ».
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('Ma tournée'),
                    selected: !historique,
                    onSelected: (_) => setState(() => _view = _TourneeView.active),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.history, size: 18),
                    label: const Text('Historique'),
                    selected: historique,
                    onSelected: (_) => setState(() => _view = _TourneeView.historique),
                  ),
                ),
              ],
            ),
          ),
          if (!historique) ...[
            // Filtre de statut : tous / à récupérer / livrées (§ demande).
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(filter),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        filter.dateDebut != null ? _dayFmt.format(filter.dateDebut!) : 'Date',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (filter.dateDebut != null)
                    IconButton(
                      tooltip: 'Effacer la date',
                      onPressed: () => _clearDate(filter),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Code, client, produit, adresse, livreur, préparateur, date...',
                        suffixIcon: _search.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                },
                              ),
                      ),
                    ),
                  ),
                  if (filter.statut != null || filter.dateDebut != null || _search.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    TextButton(onPressed: _reset, child: const Text('Réinitialiser')),
                  ],
                ],
              ),
            ),
          ],
          Expanded(
            child: historique
                // Même carte que la tournée : le tableau du web est identique
                // dans les deux onglets (téléphones cliquables, boutons
                // d'action quand le statut et le jour J s'y prêtent).
                ? OrderHistoriqueView(cardBuilder: (context, order) => _TourneeCard(order: order))
                : _TourneeActiveList(search: _search, refreshing: _refreshing),
          ),
        ],
      ),
    );
  }
}

/// Liste « Ma tournée » : les commandes du provider partagé, filtrées par la
/// recherche et la fenêtre d'affichage, la plus récente en tête.
class _TourneeActiveList extends ConsumerWidget {
  const _TourneeActiveList({required this.search, required this.refreshing});
  final String search;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider);
    // Erreur d'un rechargement silencieux (temps réel, après action) : la
    // liste garde son contenu précédent et l'erreur est annoncée par un
    // toast, comme `toast.error(err.message || 'Erreur de chargement des
    // commandes')` côté web.
    ref.listen<AsyncValue<List<Order>>>(ordersProvider, (previous, next) {
      if (next.hasError && next.hasValue && !next.isLoading) {
        orderToast(context, ApiClient.messageFromError(next.error!));
      }
    });

    // Dernière liste connue, y compris pendant un rechargement silencieux.
    final orders = async.value;
    if (refreshing || orders == null) {
      if (!refreshing && async.hasError) {
        return ErrorState(
          message: ApiClient.messageFromError(async.error!),
          onRetry: () => ref.read(ordersProvider.notifier).refresh(),
        );
      }
      return const LoadingState();
    }

    final q = search.trim().toLowerCase();
    final displayed = _tourneeDuJour(orders.where((o) => _matches(o, q)));

    return Column(
      children: [
        if (async.isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(ordersProvider.notifier).refreshSilencieux(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (displayed.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      message: 'Aucune commande trouvée pour cette recherche.',
                      icon: Icons.local_shipping_outlined,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    sliver: SliverList.builder(
                      itemCount: displayed.length,
                      itemBuilder: (context, i) => _TourneeCard(key: ValueKey(displayed[i].id), order: displayed[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Une ligne du tableau du livreur, en carte : statut, produits, client,
/// adresse, les deux téléphones cliquables, zone, total (ou « Déjà payé »),
/// et l'action du moment. Le clic sur la carte ouvre la fiche.
class _TourneeCard extends ConsumerWidget {
  const _TourneeCard({super.key, required this.order});
  final Order order;

  /// Confirmation avant toute action de statut — résumé de la commande,
  /// note, pointage des articles (« Livré ») ou mot à retaper (« Retour »).
  /// Le formulaire reste ouvert en cas d'échec ; en cas de succès la liste
  /// active est rechargée silencieusement par le provider, et l'historique
  /// (s'il est affiché) est invalidé — `fetchOrders(true)` du web.
  Future<void> _confirm(BuildContext context, WidgetRef ref, OrderStatus target, String label) async {
    final updated = await showDialog<Order>(
      context: context,
      builder: (_) => _TourneeConfirmDialog(order: order, target: target, label: label),
    );
    if (updated == null || !context.mounted) return;
    orderToast(context, 'Commande ${order.numero} → ${updated.statutCourant.label}');
    ref.invalidate(orderHistoriqueProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    final adresse = order.adresseLivraison;
    // « Livrée le » une fois livrée, sinon la livraison prévue (colonne
    // « Date » du tableau web, reprise dans son détail).
    final dateLigne = order.statutCourant == OrderStatus.livre
        ? (order.historyAt(OrderStatus.livre) ?? order.dateCommande)
        : order.dateCommande;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OrderStatusBadge(status: order.statutCourant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.numero,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Produit : tous les articles, référence + quantité, puis
              // sous-type / marque et pastille de couleur. Un article rapporté
              // lors d'une livraison partielle est barré.
              for (final it in order.items) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        it.referenceName.isEmpty ? 'Article' : it.referenceName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: it.retourne ? TextDecoration.lineThrough : null,
                          color: it.retourne ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('x${it.quantite}', style: muted),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (it.typeName != null && it.typeName!.isNotEmpty) Text(it.typeName!, style: muted),
                    if (it.brandName != null && it.brandName!.isNotEmpty) Text(it.brandName!, style: muted),
                    if (it.couleur.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(it.couleur, style: const TextStyle(fontSize: 10)),
                      ),
                    if (it.retourne) Text('rapporté', style: muted.copyWith(color: Colors.red)),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              const Divider(height: 12),
              _IconLine(icon: Icons.person_outline, text: order.clientNom),
              _IconLine(icon: Icons.place_outlined, text: adresse != null && adresse.isNotEmpty ? adresse : '-'),
              // Les deux numéros sont cliquables : le livreur appelle le
              // second quand le premier ne répond pas (§ demande).
              if (order.telephone != null) _PhoneLink(numero: order.telephone!),
              if (order.telephone2 != null) _PhoneLink(numero: order.telephone2!),
              _IconLine(icon: Icons.local_shipping_outlined, text: DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
              if (dateLigne != null)
                _IconLine(
                  icon: Icons.event_outlined,
                  text: '${order.statutCourant == OrderStatus.livre ? 'Livrée le' : 'Livraison prévue le'} '
                      '${_dateTimeFmt.format(appLocal(dateLigne))}',
                ),
              // Rien à encaisser : le client a déjà payé d'avance, on masque
              // le montant au livreur pour éviter toute confusion (§ demande).
              if (order.estPrepayee)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Déjà payé — rien à encaisser',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Total à encaisser : ${arFmt(order.totalAPayer ?? 0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ..._actions(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  /// Action du moment (`nextAction` + bouton « Retour » du web) : Prête →
  /// « Récupérer (en livraison) » ; En livraison → « Livré » et « Retour »,
  /// deux issues possibles. Hors jour J, AUCUN bouton n'est rendu — pas même
  /// grisé (§ demande) : seule une ligne muette annonce la date, la commande
  /// restant visible dans le planning. Les autres statuts n'ont pas d'action.
  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    switch (order.statutCourant) {
      case OrderStatus.enPreparation:
        // Visible pour planning uniquement — pas encore prête, rien à faire
        // ici pour le livreur.
        return [
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.hourglass_empty, size: 16, color: scheme.outline),
              const SizedBox(width: 6),
              Text('En cours de préparation', style: TextStyle(color: scheme.outline)),
            ],
          ),
        ];
      case OrderStatus.prete:
        if (!isJourJ(order.dateCommande, UserRole.livreur)) {
          return [const SizedBox(height: 10), _AttenteJourJ(order: order)];
        }
        return [
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _confirm(context, ref, OrderStatus.enLivraison, 'Récupérer (en livraison)'),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Récupérer (en livraison)'),
            ),
          ),
        ];
      case OrderStatus.enLivraison:
        if (!isJourJ(order.dateCommande, UserRole.livreur)) {
          return [const SizedBox(height: 10), _AttenteJourJ(order: order)];
        }
        return [
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _confirm(context, ref, OrderStatus.livre, 'Livré'),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Livré'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirm(context, ref, OrderStatus.retour, 'Retour'),
                  icon: const Icon(Icons.undo),
                  label: const Text('Retour'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ];
      case OrderStatus.nouvelle:
      case OrderStatus.livre:
      case OrderStatus.retour:
      case OrderStatus.annulee:
        return const [];
    }
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// Numéro de téléphone cliquable (`<a href="tel:…">` bleu du web). Son
/// propre InkWell absorbe le tap : appeler n'ouvre pas la fiche.
class _PhoneLink extends StatelessWidget {
  const _PhoneLink({required this.numero});
  final String numero;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => _appeler(context, numero),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(Icons.phone_outlined, size: 16, color: primary),
            const SizedBox(width: 8),
            Text(numero, style: TextStyle(fontSize: 13, color: primary, decoration: TextDecoration.underline)),
          ],
        ),
      ),
    );
  }
}

/// Ligne muette affichée à la place des boutons tant que le jour J n'est pas
/// atteint : le livreur voit la commande dans son planning et sait quand il
/// pourra agir, sans bouton inerte à cliquer. Ce que la ligne annonce, c'est
/// le moment où l'action se débloquera — pas la date de livraison.
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
                : 'Disponible le ${dueDateLabel(order.dateCommande!, UserRole.livreur)}',
            style: TextStyle(color: couleur),
          ),
        ),
      ],
    );
  }
}

/// Dialogue « Confirmer : {action} » du livreur (`actionNote` + `NoteForm`
/// de page.tsx) : récapitulatif de la commande (client, téléphones, zone,
/// adresse, paiement, articles, montants — ou « Rien — déjà payé »), puis
/// le formulaire de confirmation : note, pointage des articles remis au
/// passage « Livré » (livraison partielle — rien de coché = Retour), mot
/// RETOUR à retaper pour « Retour ».
///
/// La transition est jouée ICI : en cas d'échec le formulaire reste ouvert
/// avec l'erreur en toast (la note et le pointage ne sont pas perdus) ; en
/// cas de succès le dialogue se ferme en renvoyant la commande mise à jour.
class _TourneeConfirmDialog extends ConsumerStatefulWidget {
  const _TourneeConfirmDialog({required this.order, required this.target, required this.label});
  final Order order;
  final OrderStatus target;
  final String label;

  @override
  ConsumerState<_TourneeConfirmDialog> createState() => _TourneeConfirmDialogState();
}

class _TourneeConfirmDialogState extends ConsumerState<_TourneeConfirmDialog> {
  bool _busy = false;

  Future<void> _submit(OrderConfirmResult result) async {
    final order = widget.order;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(ordersProvider.notifier)
          .changeStatus(
            order.id,
            widget.target.apiValue,
            note: result.note,
            photoPath: result.photoPath,
            itemsLivres: result.itemsLivres,
          );
      if (!mounted) return;
      navigator.pop(updated);
    } catch (e) {
      // `toast.error(err.message || 'Action impossible')` — c'est ainsi que
      // remontent les refus serveur (transition impossible, jour J, commande
      // assignée à quelqu'un d'autre…). On reste sur le formulaire.
      if (mounted) orderToast(context, ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final target = widget.target;
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final isRecuperation = order.estRecuperation;

    Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: bold ? TextStyle(fontWeight: FontWeight.w700, color: color) : muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('Confirmer : ${widget.label}'),
        content: SizedBox(
          width: dialogWidth(MediaQuery.sizeOf(context).width, 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Commande ${order.numero} — vérifiez le résumé avant de confirmer.', style: muted),
                const SizedBox(height: 10),
                row('Client', order.clientNom),
                if (order.telephone != null) row('Téléphone', order.telephone!),
                if (order.telephone2 != null) row('Autre téléphone', order.telephone2!),
                row('Zone', DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
                if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
                  row('Adresse', order.adresseLivraison!),
                if (!isRecuperation) row('Paiement', modePaiementLabel(order.modePaiement)),
                const Divider(height: 20),
                Text('Articles', style: muted),
                for (final item in order.items) row(item.libelle, 'x${item.quantite}'),
                const Divider(height: 20),
                // Commande déjà réglée : le livreur n'a rien à encaisser, on
                // masque tous les montants et on l'annonce clairement
                // (§ demande).
                if (order.estPrepayee)
                  row('À encaisser', 'Rien — déjà payé', bold: true, color: const Color(0xFF059669))
                else if (order.totalAPayer != null) ...[
                  if (!isRecuperation && order.fraisLivraison != null) ...[
                    row('Prix de vente', arFmt(order.totalAPayer! - order.fraisLivraison!)),
                    row('Frais de livraison', arFmt(order.fraisLivraison!)),
                  ],
                  row('Total', arFmt(order.totalAPayer!), bold: true),
                ],
                const SizedBox(height: 12),
                OrderConfirmForm(
                  showPhoto: photoPourStatut(target),
                  confirmWord: kMotsConfirmation[target],
                  // Pointage des articles au moment de livrer.
                  items: pointagePourStatut(target) && order.items.isNotEmpty ? order.items : null,
                  submitting: _busy,
                  onCancel: () => Navigator.of(context).pop(),
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
