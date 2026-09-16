import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/note_callout.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/order_historique_view.dart';
import '../../widgets/order_card_shell.dart';
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

/// Période de la tournée (`livreurPeriode` de page.tsx) : filtre CLIENT sur
/// le jour de livraison prévu, comparé au jour métier d'Antananarivo. Par
/// défaut « Aujourd'hui (jour J) » ; TOUTES les commandes assignées restent
/// chargées, sans limite d'heure ni de jour (§ demande) — Toutes / Jours
/// suivants / En retard sont à portée de main.
enum _LivreurPeriode {
  aujourdhui("Aujourd'hui (jour J)"),
  toutes('Toutes les commandes'),
  aVenir('Jours suivants'),
  passees('En retard / passées');

  const _LivreurPeriode(this.label);
  final String label;
}

/// Tri de la tournée (`livreurTri` de page.tsx). Par défaut la commande la
/// plus récemment CRÉÉE en tête, dès l'ouverture de l'écran.
enum _LivreurTri {
  recentes("Plus récentes d'abord"),
  anciennes("Plus anciennes d'abord"),
  livraisonProche('Livraison la plus proche'),
  livraisonLointaine('Livraison la plus lointaine');

  const _LivreurTri(this.label);
  final String label;
}

/// Liste affichée de « Ma tournée » (`displayedOrders` du web, vue livreur
/// ACTIF) : SEULES les commandes du JOUR J sont visibles — jour de livraison
/// = aujourd'hui, heure de Madagascar (même ouverture que les boutons
/// d'action, core/app_time.dart::actionOuverte : minuit). Une commande
/// prévue demain à 00:00 apparaît ce soir à minuit pile (§ demande). Les
/// jours suivants ne sont jamais affichés ; les livraisons en retard le sont
/// seulement sur demande (filtre de période). Puis le tri choisi. Son onglet Historique, lui, n'est pas concerné : c'est un
/// journal.
List<Order> _displayedOrders(Iterable<Order> orders, _LivreurPeriode periode, _LivreurTri tri, {bool dateChoisie = false}) {
  final today = appToday();
  int creeLe(Order o) => o.createdAt?.millisecondsSinceEpoch ?? 0;
  int livraisonLe(Order o) => o.dateCommande?.millisecondsSinceEpoch ?? 0;

  bool retenue(Order o) {
    // Une « Date précise » choisie (déjà filtrée par le serveur) affiche
    // tout ce jour-là. Les boutons d'action restent fermés hors jour J.
    if (dateChoisie) return true;
    final jour = o.dateCommande == null ? null : appDay(o.dateCommande!);
    switch (periode) {
      case _LivreurPeriode.toutes:
        return true;
      case _LivreurPeriode.aujourdhui:
        return jour == null || jour.isAtSameMomentAs(today);
      case _LivreurPeriode.aVenir:
        return jour != null && jour.isAfter(today);
      case _LivreurPeriode.passees:
        return jour != null && jour.isBefore(today);
    }
  }

  final visibles = orders.where(retenue).toList();
  switch (tri) {
    case _LivreurTri.recentes:
      visibles.sort((a, b) => creeLe(b).compareTo(creeLe(a)));
    case _LivreurTri.anciennes:
      visibles.sort((a, b) => creeLe(a).compareTo(creeLe(b)));
    case _LivreurTri.livraisonProche:
      visibles.sort((a, b) => livraisonLe(a).compareTo(livraisonLe(b)));
    case _LivreurTri.livraisonLointaine:
      visibles.sort((a, b) => livraisonLe(b).compareTo(livraisonLe(a)));
  }
  return visibles;
}

/// Pastille « quand livrer » d'une commande (`livraisonBadge` du web) :
/// « Aujourd'hui · HH:mm » (vert), « Demain · HH:mm » (bleu), « À venir ·
/// JJ/MM/AAAA HH:mm » (gris) ou « En retard · JJ/MM/AAAA » (rouge) — jour
/// métier d'Antananarivo. `null` sans date de livraison prévue.
({String label, Color color})? _livraisonBadge(Order o) {
  final date = o.dateCommande;
  if (date == null) return null;
  final jour = appDay(date);
  final today = appToday();
  final demain = today.add(const Duration(days: 1));
  final local = appLocal(date);
  if (jour.isAtSameMomentAs(today)) {
    return (label: "Aujourd'hui · ${_heureFmt.format(local)}", color: const Color(0xFF059669));
  }
  if (jour.isBefore(today)) {
    return (label: 'En retard · ${_dayFmt.format(local)}', color: const Color(0xFFDC2626));
  }
  if (jour.isAtSameMomentAs(demain)) {
    return (label: 'Demain · ${_heureFmt.format(local)}', color: const Color(0xFF0284C7));
  }
  return (label: 'À venir · ${_dateTimeFmt.format(local)}', color: const Color(0xFF64748B));
}

// Tous les horodatages sont affichés à l'heure d'Antananarivo (fuseau du
// magasin), quel que soit le réglage de l'appareil — cohérent avec la règle
// du jour J et avec le serveur (voir core/app_time.dart).
final _dayFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
final _heureFmt = DateFormat('HH:mm');

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

  /// Période et tri de la tournée (filtres CLIENT, comme sur le web) — le
  /// tri « plus récentes d'abord » s'applique dès l'ouverture.
  _LivreurPeriode _periode = _LivreurPeriode.aujourdhui;
  _LivreurTri _tri = _LivreurTri.recentes;

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
  /// du livreur — tout son planning), recherche vidée, période « Toutes »
  /// et tri « plus récentes d'abord ».
  void _reset() {
    _setFilter(jourJFilter(UserRole.livreur));
    _searchController.clear();
    setState(() {
      _search = '';
      _periode = _LivreurPeriode.aujourdhui;
      _tri = _LivreurTri.recentes;
    });
  }

  /// Un filtre s'écarte-t-il de la vue par défaut ? (affiche « Réinitialiser »)
  bool _filtresActifs(OrdersFilter filter) =>
      filter.statut != null ||
      filter.dateDebut != null ||
      _search.isNotEmpty ||
      _periode != _LivreurPeriode.aujourdhui ||
      _tri != _LivreurTri.recentes;

  /// Nombre de filtres écartés de la vue par défaut, affiché sur le bouton
  /// « Filtres » (la recherche a sa propre croix).
  int _nbFiltresActifs(OrdersFilter filter) =>
      (filter.statut != null ? 1 : 0) +
      (filter.dateDebut != null ? 1 : 0) +
      (_periode != _LivreurPeriode.aujourdhui ? 1 : 0) +
      (_tri != _LivreurTri.recentes ? 1 : 0);

  /// Feuille « Filtres » (période, tri, date précise) : les choix
  /// s'appliquent immédiatement à la liste derrière la feuille.
  Future<void> _ouvrirFiltres() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filter = ref.read(ordersFilterProvider);
          final theme = Theme.of(ctx);
          Widget titre(String t) => Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(t, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Filtres', style: theme.textTheme.titleMedium)),
                      if (_filtresActifs(filter))
                        TextButton(
                          onPressed: () {
                            _reset();
                            setSheet(() {});
                          },
                          child: const Text('Réinitialiser'),
                        ),
                    ],
                  ),
                  titre('Période'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final p in _LivreurPeriode.values)
                        ChoiceChip(
                          label: Text(p.label),
                          selected: _periode == p,
                          onSelected: (_) {
                            setState(() => _periode = p);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  titre('Trier par'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in _LivreurTri.values)
                        ChoiceChip(
                          label: Text(t.label),
                          selected: _tri == t,
                          onSelected: (_) {
                            setState(() => _tri = t);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  titre('Date précise'),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await _pickDate(filter);
                            setSheet(() {});
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            filter.dateDebut != null ? _dayFmt.format(filter.dateDebut!) : 'Choisir une date',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (filter.dateDebut != null)
                        IconButton(
                          tooltip: 'Effacer la date',
                          onPressed: () {
                            _clearDate(filter);
                            setSheet(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Voir les commandes')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

    return Scaffold(
      appBar: AppBar(
        // Titre seul : le sous-titre encombrait l'écran mobile ; la règle du
        // jour J est rappelée sur chaque carte (« Disponible le … »).
        title: Text(historique ? 'Historique' : 'Ma tournée'),
        actions: [IconButton(tooltip: 'Rafraîchir', icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      // Toute la page défile avec les commandes (onglets et filtres compris),
      // pas seulement la liste (§ demande) : l'en-tête est passé au
      // défilement de chaque vue.
      body: Builder(
        builder: (context) {
          // En-tête compact (§ demande « très encombrant en vue mobile ») :
          // 1. onglets Ma tournée / Historique (bouton segmenté) ;
          // 2. recherche + bouton « Filtres » (période, tri, date précise)
          //    qui ouvre une feuille en bas de l'écran ;
          // 3. pastilles de statut ;
          // 4. seulement si des filtres sont actifs : leurs puces, effaçables
          //    une à une, et « Réinitialiser ».
          final nbFiltres = _nbFiltresActifs(filter);
          final header = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_TourneeView>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                        value: _TourneeView.active,
                        icon: Icon(Icons.local_shipping_outlined, size: 18),
                        label: Text('Ma tournée'),
                      ),
                      ButtonSegment(
                        value: _TourneeView.historique,
                        icon: Icon(Icons.history, size: 18),
                        label: Text('Historique'),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (v) => setState(() => _view = v.first),
                  ),
                ),
              ),
              if (!historique) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _search = v),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Rechercher (code, client, produit…)',
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
                      const SizedBox(width: 8),
                      _BoutonFiltres(nbActifs: nbFiltres, onPressed: _ouvrirFiltres),
                    ],
                  ),
                ),
                // Filtre de statut : tous / à récupérer / livrées (§ demande).
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _tourneeStatutFilters.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final f = _tourneeStatutFilters[i];
                      return ChoiceChip(
                        label: Text(f.label),
                        visualDensity: VisualDensity.compact,
                        selected: filter.statut == f.value,
                        onSelected: (_) => _setStatut(filter, f.value),
                      );
                    },
                  ),
                ),
                if (_filtresActifs(filter))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (_periode != _LivreurPeriode.aujourdhui)
                                _PuceFiltre(
                                  icon: Icons.date_range_outlined,
                                  label: _periode.label,
                                  onDeleted: () => setState(() => _periode = _LivreurPeriode.aujourdhui),
                                ),
                              if (_tri != _LivreurTri.recentes)
                                _PuceFiltre(
                                  icon: Icons.sort,
                                  label: _tri.label,
                                  onDeleted: () => setState(() => _tri = _LivreurTri.recentes),
                                ),
                              if (filter.dateDebut != null)
                                _PuceFiltre(
                                  icon: Icons.event_outlined,
                                  label: _dayFmt.format(filter.dateDebut!),
                                  onDeleted: () => _clearDate(filter),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _reset,
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: const Text('Réinitialiser'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
              ],
            ],
          );
          return historique
              // Même carte que la tournée : le tableau du web est identique
              // dans les deux onglets (téléphones cliquables, boutons
              // d'action quand le statut et le jour J s'y prêtent).
              ? OrderHistoriqueView(header: header, cardBuilder: (context, order) => _TourneeCard(order: order))
              : _TourneeActiveList(header: header, search: _search, periode: _periode, tri: _tri, refreshing: _refreshing);
        },
      ),
    );
  }
}

/// Bouton « Filtres » de l'en-tête : ouvre la feuille période / tri / date
/// et porte le nombre de filtres actifs en pastille.
class _BoutonFiltres extends StatelessWidget {
  const _BoutonFiltres({required this.nbActifs, required this.onPressed});
  final int nbActifs;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actif = nbActifs > 0;
    return Badge(
      isLabelVisible: actif,
      label: Text('$nbActifs'),
      child: actif
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Filtres'),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Filtres'),
              style: OutlinedButton.styleFrom(foregroundColor: scheme.onSurface),
            ),
    );
  }
}

/// Puce d'un filtre actif, effaçable d'un geste.
class _PuceFiltre extends StatelessWidget {
  const _PuceFiltre({required this.icon, required this.label, required this.onDeleted});
  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onDeleted: onDeleted,
    );
  }
}

/// Liste « Ma tournée » : les commandes du provider partagé (tout le planning
/// assigné), filtrées par la recherche et la période, dans l'ordre choisi.
class _TourneeActiveList extends ConsumerWidget {
  const _TourneeActiveList({
    required this.header,
    required this.search,
    required this.periode,
    required this.tri,
    required this.refreshing,
  });

  /// Onglets + filtres de l'écran, rendus en tête du défilement.
  final Widget header;
  final String search;
  final _LivreurPeriode periode;
  final _LivreurTri tri;
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
      final etat = !refreshing && async.hasError
          ? ErrorState(
              message: ApiClient.messageFromError(async.error!),
              onRetry: () => ref.read(ordersProvider.notifier).refresh(),
            )
          : const LoadingState();
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverFillRemaining(hasScrollBody: false, child: etat),
        ],
      );
    }

    final q = search.trim().toLowerCase();
    final dateChoisie = ref.watch(ordersFilterProvider.select((f) => f.dateDebut != null));
    final displayed = _displayedOrders(orders.where((o) => _matches(o, q)), periode, tri, dateChoisie: dateChoisie);

    return Column(
      children: [
        if (async.isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(ordersProvider.notifier).refreshSilencieux(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Onglets et filtres défilent avec les commandes (§ demande).
                SliverToBoxAdapter(child: header),
                if (displayed.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      message: dateChoisie
                          ? 'Aucune commande assignée pour cette date.'
                          : periode == _LivreurPeriode.aujourdhui
                              ? "Aucune commande pour aujourd'hui. Période « Toutes les commandes » ou « Jours suivants » pour voir le reste de votre planning."
                              : 'Aucune commande pour ces filtres.',
                      icon: Icons.local_shipping_outlined,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
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
    final isLivreur = ref.watch(authProvider.select((a) => a.user?.isLivreur ?? false));
    // « Livrée le » une fois livrée, sinon la livraison prévue (colonne
    // « Date » du tableau web, reprise dans son détail).
    final dateLigne = order.statutCourant == OrderStatus.livre
        ? (order.historyAt(OrderStatus.livre) ?? order.dateCommande)
        : order.dateCommande;
    final livraison = _livraisonBadge(order);

    final actions = _actions(context, ref);
    final totalStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onSurface);

    return OrderCardShell(
      status: order.statutCourant,
      onTap: () => context.push('/orders/${order.id}'),
      // En-tête teinté : statut, numéro et — d'un coup d'œil — quand livrer.
      header: Row(
        children: [
          OrderStatusBadge(status: order.statutCourant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              order.numero,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // « En retard » sur une commande livrée n'aurait aucun sens.
          if (!order.estTerminee && livraison != null) ...[
            const SizedBox(width: 8),
            _LivraisonBadge(label: livraison.label, color: livraison.color),
          ],
        ],
      ),
      // 5. L'action du moment, isolée en pied de carte.
      footer: actions.isEmpty
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: actions),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Ce qu'il y a dans le colis — tous les articles, référence +
          // quantité, sous-type / marque et pastille de couleur. Un article
          // rapporté lors d'une livraison partielle est barré.
          OrderCardSection(
            label: 'Articles',
            icon: Icons.inventory_2_outlined,
            trailing: Text(
              '${order.items.fold<int>(0, (n, it) => n + it.quantite)} pièce(s)',
              style: muted.copyWith(fontWeight: FontWeight.w600),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      Text('x${it.quantite}', style: muted.copyWith(fontWeight: FontWeight.w700)),
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
                  if (it != order.items.last) const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          // 2. Qui, où, comment joindre — les deux numéros sont cliquables :
          // le livreur appelle le second quand le premier ne répond pas.
          OrderCardSection(
            label: 'Client',
            icon: Icons.person_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.clientNom, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                _IconLine(icon: Icons.place_outlined, text: adresse != null && adresse.isNotEmpty ? adresse : '-'),
                if (order.telephone != null) _PhoneLink(numero: order.telephone!),
                if (order.telephone2 != null) _PhoneLink(numero: order.telephone2!),
                _IconLine(icon: Icons.local_shipping_outlined, text: DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
              ],
            ),
          ),
          // 3. Consigne du gérant, impossible à manquer depuis la liste
          // (§ demande) — cellule « Client » du tableau web, réservée au
          // livreur (`isLivreur &&`).
          if (isLivreur)
            NoteCallout(
              role: NoteRole.livreur,
              text: order.noteLivreur,
              compact: true,
              margin: const EdgeInsets.only(bottom: 10),
            ),
          // 4. Argent et date : bandeau à part. Rien à encaisser quand le
          // client a déjà payé d'avance — on masque le montant au livreur
          // pour éviter toute confusion (§ demande).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: order.estPrepayee
                  ? const Color(0xFF059669).withValues(alpha: 0.12)
                  : scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (order.estPrepayee ? const Color(0xFF059669) : scheme.primary).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.estPrepayee)
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF059669)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Déjà payé — rien à encaisser',
                          style: totalStyle.copyWith(color: const Color(0xFF059669)),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(Icons.payments_outlined, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Total à encaisser', style: muted.copyWith(fontWeight: FontWeight.w600))),
                      Text(arFmt(order.totalAPayer ?? 0), style: totalStyle),
                    ],
                  ),
                if (dateLigne != null) ...[
                  const SizedBox(height: 4),
                  _IconLine(
                    icon: Icons.event_outlined,
                    text: '${order.statutCourant == OrderStatus.livre ? 'Livrée le' : 'Livraison prévue le'} '
                        '${_dateTimeFmt.format(appLocal(dateLigne))}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Action du moment (`nextAction` + bouton « Retour » du web) : Prête →
  /// « Récupérer (en livraison) » ; En livraison → « Livré » et « Retour »,
  /// deux issues possibles. Hors jour J (minuit le jour de livraison —
  /// `actionOuverte`), les boutons restent VISIBLES mais DÉSACTIVÉS et
  /// annoncent « Disponible le … » : le livreur voit toute sa tournée à venir
  /// et sait quand il pourra agir. Le serveur reste seul juge. Les autres
  /// statuts n'ont pas d'action.
  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bloque = !actionOuverte(order.dateCommande, UserRole.livreur);
    switch (order.statutCourant) {
      case OrderStatus.enPreparation:
        // Visible pour planning uniquement — pas encore prête, rien à faire
        // ici pour le livreur.
        return [
          Row(
            children: [
              Icon(Icons.hourglass_empty, size: 16, color: scheme.outline),
              const SizedBox(width: 6),
              Text('En cours de préparation', style: TextStyle(color: scheme.outline)),
            ],
          ),
        ];
      case OrderStatus.prete:
        // Bouton unique, pleine largeur : hors jour J il porte lui-même
        // « Disponible le … » (comme la carte du dépôt et le web).
        return [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: bloque
                  ? null
                  : () => _confirm(context, ref, OrderStatus.enLivraison, 'Récupérer (en livraison)'),
              icon: Icon(bloque ? Icons.schedule : Icons.local_shipping_outlined),
              label: Text(
                bloque ? _disponibleLabel(order) : 'Récupérer (en livraison)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ];
      case OrderStatus.enLivraison:
        // Deux boutons côte à côte : trop étroits pour porter chacun
        // « Disponible le JJ/MM/AAAA à HHhMM » — ils gardent leur libellé,
        // désactivés, et une ligne dessous annonce l'ouverture.
        return [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: bloque ? null : () => _confirm(context, ref, OrderStatus.livre, 'Livré'),
                  icon: Icon(bloque ? Icons.schedule : Icons.local_shipping_outlined),
                  label: const Text('Livré'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: bloque ? null : () => _confirm(context, ref, OrderStatus.retour, 'Retour'),
                  icon: const Icon(Icons.undo),
                  label: const Text('Retour'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
          if (bloque) ...[const SizedBox(height: 8), _AttenteJourJ(order: order)],
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

/// Pastille « quand livrer » (badge `outline` coloré du web) : fond teinté,
/// liseré et texte de la même couleur — lisible en clair comme en sombre.
class _LivraisonBadge extends StatelessWidget {
  const _LivraisonBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ce que le bouton désactivé annonce : le moment où l'action se débloquera
/// (`fmtOuverture` du web) — pas la date de livraison.
String _disponibleLabel(Order order) => order.dateCommande == null
    ? 'Pas encore disponible'
    : 'Disponible le ${dueDateLabel(order.dateCommande!, UserRole.livreur)}';

/// Ligne muette sous les boutons désactivés tant que le jour J n'est pas
/// atteint : le livreur voit la commande dans son planning et sait quand il
/// pourra agir. Ce que la ligne annonce, c'est le moment où l'action se
/// débloquera — pas la date de livraison.
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
        Expanded(child: Text(_disponibleLabel(order), style: TextStyle(color: couleur))),
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
    // Vert des remises (`text-emerald-700` / `dark:text-emerald-300` du web).
    final remiseColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF047857);

    Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: bold
                ? TextStyle(fontWeight: FontWeight.w700, color: color)
                : (color == null ? muted : TextStyle(fontWeight: FontWeight.w500, color: color)),
          ),
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
                // La consigne du gérant, bien en vue au moment d'agir.
                NoteCallout(role: NoteRole.livreur, text: order.noteLivreur, margin: const EdgeInsets.only(top: 8)),
                // Remise du gérant, déjà déduite du total : annoncée au client
                // même quand il a déjà réglé (même place que le résumé web,
                // après la note, avant les articles).
                if (order.aRemise)
                  row('Remise accordée au client', '−${arFmt(order.remiseTotal)}', color: remiseColor),
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
