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
import '../../state/realtime_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/status_badge.dart';
import '../orders/order_create_screen.dart' show OrderFormDropdown;

final _dateFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

/// `fmtAppDate` / `fmtAppDateTime` du web : à l'heure d'Antananarivo quel
/// que soit le fuseau de l'appareil, « — » si la valeur est absente.
String _fmtAppDate(DateTime? d) => d == null ? '—' : _dateFmt.format(appLocal(d));
String _fmtAppDateTime(DateTime? d) => d == null ? '—' : _dateTimeFmt.format(appLocal(d));

/// Les trois onglets du préparateur (`viewMode` × `preparateurTab` de
/// page.tsx) : sa file de livraisons à préparer, ses retraits sur place, et
/// le journal de tout ce qu'il a déjà traité.
enum _DepotView { aPreparer, recuperations, historique }

/// Filtres de statut de l'onglet Historique (`HISTORIQUE_STATUT_FILTERS` du
/// web) : tous les statuts déjà traversés par SES commandes, états
/// terminaux compris. « À récupérer » = PRETE, libellé métier.
const _kTousLesStatuts = 'ALL';
const _historiqueStatutFilters = <({String value, String label})>[
  (value: _kTousLesStatuts, label: 'Tous les statuts'),
  (value: 'LIVRE', label: 'Livrées'),
  (value: 'RETOUR', label: 'Retours'),
  (value: 'ANNULEE', label: 'Annulées'),
  (value: 'EN_LIVRAISON', label: 'En livraison'),
  (value: 'PRETE', label: 'À récupérer'),
  (value: 'EN_PREPARATION', label: 'En préparation'),
  (value: 'NOUVELLE', label: 'Nouvelles'),
];

/// Filtres de l'onglet Historique (§ demande) : bornes date + heure « au
/// mur » (heure d'Antananarivo, converties en instants absolus à l'envoi —
/// `appDatetimeLocalToIso` du web) et statut. Sert de clé au provider de
/// l'historique : deux filtres égaux partagent la même requête.
class DepotHistoriqueFiltre {
  const DepotHistoriqueFiltre({this.from, this.to, this.statut});

  /// Bornes « Du » / « Au », `null` = borne ouverte (champ vidé sur le web).
  final DateTime? from;
  final DateTime? to;

  /// Code de statut serveur, `null` = tous les statuts.
  final String? statut;

  /// Valeur par défaut : le JOUR J, de 00:00 à 23:59 — la journée de
  /// travail en cours à Antananarivo (`${appToday()}T00:00` / `T23:59` du
  /// web). « Réinitialiser » y ramène.
  factory DepotHistoriqueFiltre.jourJ() {
    final j = appToday();
    return DepotHistoriqueFiltre(
      from: DateTime(j.year, j.month, j.day),
      to: DateTime(j.year, j.month, j.day, 23, 59),
    );
  }

  bool get estParDefaut => this == DepotHistoriqueFiltre.jourJ();

  DepotHistoriqueFiltre copyWith({
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    String? statut,
    bool clearStatut = false,
  }) {
    return DepotHistoriqueFiltre(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      statut: clearStatut ? null : (statut ?? this.statut),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DepotHistoriqueFiltre && other.from == from && other.to == to && other.statut == statut);

  @override
  int get hashCode => Object.hash(from, to, statut);
}

/// Historique personnel du préparateur (`historique=1` + `date_from` /
/// `date_to` / `statut` — voir orders/views.py::get_queryset) : toutes les
/// commandes qui lui ont été désignées, tous statuts confondus. Rechargé à
/// chaque événement temps réel comme la liste active ; classé la plus
/// récemment CRÉÉE en tête (même ordre que les trois rôles côté web).
final depotHistoriqueProvider = FutureProvider.autoDispose.family<List<Order>, DepotHistoriqueFiltre>((
  ref,
  filtre,
) async {
  ref.watch(realtimeTickProvider);
  final commandes = await ref.watch(ordersRepositoryProvider).list(
    historique: true,
    dateFrom: filtre.from == null ? null : appWallClockToUtc(filtre.from!),
    dateTo: filtre.to == null ? null : appWallClockToUtc(filtre.to!),
    statut: filtre.statut,
  );
  int creeLe(Order o) => o.createdAt?.millisecondsSinceEpoch ?? 0;
  commandes.sort((a, b) => creeLe(b).compareTo(creeLe(a)));
  return commandes;
});

/// Action du moment du préparateur (`nextAction` de page.tsx) : Nouvelle →
/// « Commencer la préparation », En préparation → « Commande prête », rien
/// au-delà (le retrait sur place prêt est clôturé par le gérant au comptoir).
class _DepotAction {
  const _DepotAction({required this.label, required this.target});
  final String label;
  final OrderStatus target;
}

_DepotAction? _nextAction(Order order) {
  switch (order.statutCourant) {
    case OrderStatus.nouvelle:
      return const _DepotAction(label: 'Commencer la préparation', target: OrderStatus.enPreparation);
    case OrderStatus.enPreparation:
      return const _DepotAction(label: 'Commande prête', target: OrderStatus.prete);
    default:
      return null;
  }
}

/// Recherche texte côté client (`searchableOrders` du web) : numéro, client,
/// adresse, téléphones, zone, préparateur, livreur, statut, articles
/// (référence + couleur) et la date de livraison formatée (avec et sans
/// heure). Insensible à la casse, simple `contains`.
bool _correspond(Order o, String q) {
  final produits = o.items.map((it) => [it.referenceName, it.couleur].where((s) => s.isNotEmpty).join(' ')).join(' ');
  final texte = <String?>[
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
    produits,
    if (o.dateCommande != null) _fmtAppDate(o.dateCommande),
    if (o.dateCommande != null) _fmtAppDateTime(o.dateCommande),
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ').toLowerCase();
  return texte.contains(q);
}

/// Module Dépôt — Préparateur : pendant Flutter de la branche `isPreparateur`
/// de frontend/app/(app)/orders/page.tsx.
///
/// * onglets « À préparer » (livraisons) / « Récupérations » (retraits sur
///   place, qu'il peut créer lui-même) / « Historique » ;
/// * filtre de date sur le jour J — aujourd'hui, plus demain dès 19h00
///   (core/app_time.dart::dernierJourOuvert) — et recherche texte ;
/// * « Commencer la préparation » puis « Commande prête » (note + photo de
///   preuve), bloquées avant l'ouverture du préparateur : 19h00 la veille ;
/// * clic sur une carte = fiche complète (`/orders/:id`).
///
/// Le serveur ne renvoie à ce rôle que ses commandes Nouvelle / En
/// préparation (plus ses retraits sur place déjà prêts), sans prix unitaire
/// ni historique de statut (serializer restreint).
class DepotScreen extends ConsumerStatefulWidget {
  const DepotScreen({super.key});

  @override
  ConsumerState<DepotScreen> createState() => _DepotScreenState();
}

class _DepotScreenState extends ConsumerState<DepotScreen> {
  _DepotView _view = _DepotView.aPreparer;
  final _search = TextEditingController();
  DepotHistoriqueFiltre _historique = DepotHistoriqueFiltre.jourJ();

  /// Vrai pendant un rechargement NON silencieux de la liste active — bouton
  /// « Rafraîchir », tirer-pour-rafraîchir, changement de date — pendant
  /// lequel l'indicateur de chargement remplace la liste (`fetchOrders()` du
  /// web). Le temps réel et les rechargements après action restent
  /// silencieux : la liste reste affichée jusqu'aux nouvelles données
  /// (`fetchOrders(true)`).
  bool _chargementVisible = false;
  bool _recalageEnCours = false;

  @override
  void initState() {
    super.initState();
    // Le filtre de commandes est partagé avec la page Commandes (statut,
    // préparateur…) : le dépôt ne connaît que la date, on repart donc du
    // jour J si autre chose a été posé ailleurs — hors phase de construction.
    Future(() {
      if (!mounted) return;
      if (!_estFiltreDepot(ref.read(ordersFilterProvider))) {
        _setFiltre(jourJFilter(UserRole.preparateur));
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Le filtre ne porte que la fenêtre de dates du dépôt (rien d'un autre écran).
  static bool _estFiltreDepot(OrdersFilter f) =>
      f.statut == null &&
      f.preparateurId == null &&
      f.livraisonZone == null &&
      f.magasinId == null &&
      !f.historique &&
      !f.nonLivree &&
      f.dateFrom == null &&
      f.dateTo == null;

  /// Sur le jour J, la fenêtre va jusqu'au dernier jour déjà ouvert : après
  /// 19h00 elle doit inclure les commandes du lendemain, qui viennent d'être
  /// débloquées. Le web la recalcule à chaque `fetchOrders` ; ici le filtre
  /// stocké est réaligné dès qu'il est en retard sur l'heure.
  static bool _fenetrePerimee(OrdersFilter f) =>
      f.dateDebut != null && f.dateDebut == appToday() && f.dateFin != dernierJourOuvert(UserRole.preparateur);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setFiltre(OrdersFilter filtre) {
    setState(() => _chargementVisible = true);
    ref.read(ordersFilterProvider.notifier).set(filtre);
  }

  /// Une seule date (pas de plage Du/Au) — § demande. Le jour J garde sa
  /// fenêtre étendue (demain dès 19h00) ; toute autre date filtre ce seul
  /// jour ; `null` = champ vidé, tout le planning du préparateur.
  void _setDate(DateTime? date) {
    if (date == null) {
      _setFiltre(const OrdersFilter());
      return;
    }
    _setFiltre(date == appToday() ? jourJFilter(UserRole.preparateur) : OrdersFilter(dateDebut: date, dateFin: date));
  }

  Future<void> _pickDate() async {
    final today = appToday();
    final date = await showDatePicker(
      context: context,
      initialDate: ref.read(ordersFilterProvider).dateDebut ?? today,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    _setDate(date);
  }

  /// « Réinitialiser » de la vue active : retour au jour J et recherche vidée.
  void _reinitialiserActif() {
    _search.clear();
    _setDate(appToday());
  }

  /// Date ET heure, comme les champs « Du » / « Au » du web : sélecteur de
  /// date puis d'heure ; annuler l'heure garde le début / la fin de journée.
  Future<DateTime?> _pickDateTime({required DateTime? current, required bool finDeJournee}) async {
    final now = appNow();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay.fromDateTime(current)
          : (finDeJournee ? const TimeOfDay(hour: 23, minute: 59) : const TimeOfDay(hour: 0, minute: 0)),
    );
    if (time == null) {
      return finDeJournee ? DateTime(date.year, date.month, date.day, 23, 59) : DateTime(date.year, date.month, date.day);
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _setHistorique(DepotHistoriqueFiltre filtre) => setState(() => _historique = filtre);

  Future<void> _pickHistoriqueFrom() async {
    final picked = await _pickDateTime(current: _historique.from, finDeJournee: false);
    if (picked != null) _setHistorique(_historique.copyWith(from: picked));
  }

  Future<void> _pickHistoriqueTo() async {
    final picked = await _pickDateTime(current: _historique.to, finDeJournee: true);
    if (picked != null) _setHistorique(_historique.copyWith(to: picked));
  }

  /// Bouton « Rafraîchir » et tirer-pour-rafraîchir : rechargement NON
  /// silencieux de la vue courante.
  Future<void> _rafraichir() async {
    if (_view == _DepotView.historique) {
      final provider = depotHistoriqueProvider(_historique);
      ref.invalidate(provider);
      try {
        await ref.read(provider.future);
      } catch (_) {
        // L'état d'erreur est porté par le provider (ErrorState / message).
      }
      return;
    }
    final filter = ref.read(ordersFilterProvider);
    if (_fenetrePerimee(filter)) {
      // Le nouveau filtre relance la requête de lui-même.
      _setFiltre(jourJFilter(UserRole.preparateur));
      return;
    }
    setState(() => _chargementVisible = true);
    await ref.read(ordersProvider.notifier).refresh();
  }

  void _onOrdersChanged(AsyncValue<List<Order>>? previous, AsyncValue<List<Order>> next) {
    if (next.isLoading) return;
    if (_chargementVisible) setState(() => _chargementVisible = false);
    // Erreur de chargement : la liste garde son contenu précédent, un
    // message l'annonce (`toast.error(err.message || 'Erreur de chargement
    // des commandes')` du web).
    if (next.hasError) {
      _snack(ApiClient.messageFromError(next.error ?? 'Erreur de chargement des commandes'));
    }
  }

  void _onHistoriqueChanged(AsyncValue<List<Order>>? previous, AsyncValue<List<Order>> next) {
    // Après un premier chargement réussi, un échec de rechargement laisse la
    // liste en place et se signale par un message ; sans données, c'est
    // l'état d'erreur de la liste qui l'affiche.
    if (!next.isLoading && next.hasError && next.hasValue) {
      _snack(ApiClient.messageFromError(next.error ?? 'Erreur de chargement des commandes'));
    }
  }

  /// Recherche texte appliquée à la liste courante.
  List<Order> _filtrer(Iterable<Order> commandes) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return commandes.toList();
    return commandes.where((o) => _correspond(o, q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authProvider).user;
    final isPreparateur = user?.isPreparateur ?? false;
    final isGerant = user?.isGerant ?? false;
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);
    final filter = ref.watch(ordersFilterProvider);
    final historique = _view == _DepotView.historique;

    // Seule la vue affichée est écoutée : l'historique n'est interrogé que
    // sur son onglet (le web ne charge que le mode courant).
    if (historique) {
      ref.listen<AsyncValue<List<Order>>>(depotHistoriqueProvider(_historique), _onHistoriqueChanged);
    } else {
      ref.listen<AsyncValue<List<Order>>>(ordersProvider, _onOrdersChanged);
    }

    // 19h00 passées : la fenêtre du jour J s'étend au lendemain, en silence
    // (comme le refetch temps réel du web) — hors phase de construction.
    if (!historique && !_recalageEnCours && _fenetrePerimee(filter)) {
      _recalageEnCours = true;
      Future(() {
        if (mounted && _fenetrePerimee(ref.read(ordersFilterProvider))) {
          ref.read(ordersFilterProvider.notifier).set(jourJFilter(UserRole.preparateur));
        }
        _recalageEnCours = false;
      });
    }

    final title = historique ? 'Historique' : 'Dépôt — Commandes à préparer';
    final description = historique
        ? 'Vos commandes déjà traitées, tous statuts — filtrables par date et heure.'
        : 'Commandes reçues à préparer, puis à marquer "Prête" pour le livreur.';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
        actions: [
          IconButton(tooltip: 'Rafraîchir', icon: const Icon(Icons.refresh), onPressed: _rafraichir),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(description, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ongletChip(_DepotView.aPreparer, 'À préparer', Icons.local_shipping_outlined),
                _ongletChip(_DepotView.recuperations, 'Récupérations', Icons.inventory_2_outlined),
                _ongletChip(_DepotView.historique, 'Historique', Icons.history),
              ],
            ),
          ),
          if (historique) _filtresHistorique() else _filtresActif(filter),
          Expanded(child: historique ? _listeHistorique(isPreparateur: isPreparateur) : _listeActive(isPreparateur: isPreparateur)),
        ],
      ),
      // Le préparateur ne crée que des retraits sur place (le formulaire
      // force la zone RECUPERATION) ; le gérant, une commande complète.
      floatingActionButton: (isGerant || isPreparateur)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/orders/new'),
              icon: const Icon(Icons.add),
              label: Text(isGerant ? 'Nouvelle commande' : 'Nouvelle récupération'),
            )
          : null,
    );
  }

  Widget _ongletChip(_DepotView view, String label, IconData icon) {
    final selected = _view == view;
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      showCheckmark: false,
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        _view = view;
        // Un rechargement visible entamé sur l'autre onglet n'a plus de
        // sens ici : la liste réapparaît telle quelle, à jour au prochain
        // événement.
        _chargementVisible = false;
      }),
    );
  }

  /// Filtres de la vue active : date (un seul jour), recherche, et
  /// « Réinitialiser » dès que l'un des deux s'écarte de sa valeur par défaut.
  Widget _filtresActif(OrdersFilter filter) {
    final today = appToday();
    final dateDebut = filter.dateDebut;
    final fenetreEtendue = dateDebut != null && filter.dateFin != null && filter.dateFin!.isAfter(dateDebut);
    final valeurDate = dateDebut == null
        ? 'Toutes les dates'
        : '${_dateFmt.format(dateDebut)}${fenetreEtendue ? ' (+ demain)' : ''}';
    final peutReinitialiser = dateDebut != today || _search.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _FiltreDateBouton(
                  label: 'Date',
                  value: valeurDate,
                  onTap: _pickDate,
                  onClear: dateDebut == null ? null : () => _setDate(null),
                ),
              ),
              if (peutReinitialiser) ...[
                const SizedBox(width: 4),
                TextButton(onPressed: _reinitialiserActif, child: const Text('Réinitialiser')),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _champRecherche('Code, client, produit, adresse, date...'),
        ],
      ),
    );
  }

  /// Filtres de l'historique : « Du » / « Au » (date et heure), statut, et
  /// « Réinitialiser » dès que l'un des trois s'écarte du jour J.
  Widget _filtresHistorique() {
    final f = _historique;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _FiltreDateBouton(
                  label: 'Du',
                  value: f.from == null ? 'Du…' : _dateTimeFmt.format(f.from!),
                  onTap: _pickHistoriqueFrom,
                  onClear: f.from == null ? null : () => _setHistorique(f.copyWith(clearFrom: true)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FiltreDateBouton(
                  label: 'Au',
                  value: f.to == null ? 'Au…' : _dateTimeFmt.format(f.to!),
                  onTap: _pickHistoriqueTo,
                  onClear: f.to == null ? null : () => _setHistorique(f.copyWith(clearTo: true)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OrderFormDropdown<String>(
                  value: f.statut ?? _kTousLesStatuts,
                  labelText: 'Statut',
                  items: [
                    for (final s in _historiqueStatutFilters) DropdownMenuItem(value: s.value, child: Text(s.label)),
                  ],
                  onChanged: (v) => _setHistorique(
                    v == null || v == _kTousLesStatuts ? f.copyWith(clearStatut: true) : f.copyWith(statut: v),
                  ),
                ),
              ),
              if (!f.estParDefaut) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => _setHistorique(DepotHistoriqueFiltre.jourJ()),
                  child: const Text('Réinitialiser'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _champRecherche('Code, client, produit, adresse, date...'),
        ],
      ),
    );
  }

  Widget _champRecherche(String hint) {
    return TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: 'Recherche',
        hintText: hint,
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                icon: const Icon(Icons.clear),
                onPressed: () => setState(_search.clear),
              ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _liste(List<Order> commandes, {required bool isPreparateur}) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: commandes.length,
      itemBuilder: (context, i) => _DepotOrderCard(order: commandes[i], isPreparateur: isPreparateur),
    );
  }

  /// « À préparer » / « Récupérations » : segmentation côté client par zone
  /// (RECUPERATION ou non — `visibleOrders` du web), puis recherche.
  Widget _listeActive({required bool isPreparateur}) {
    final async = ref.watch(ordersProvider);
    final isRecup = _view == _DepotView.recuperations;

    final Widget contenu;
    if (_chargementVisible || (async.isLoading && !async.hasValue)) {
      contenu = const LoadingState();
    } else if (async.hasValue) {
      final commandes = _filtrer(async.value!.where((o) => o.estRecuperation == isRecup));
      contenu = commandes.isEmpty
          ? const EmptyState(message: 'Aucune commande trouvée pour cette recherche.', icon: Icons.inventory_outlined)
          : _liste(commandes, isPreparateur: isPreparateur);
    } else {
      contenu = ErrorState(
        message: ApiClient.messageFromError(async.error ?? 'Erreur de chargement des commandes'),
        onRetry: _rafraichir,
      );
    }
    return RefreshIndicator(onRefresh: _rafraichir, child: contenu);
  }

  Widget _listeHistorique({required bool isPreparateur}) {
    final async = ref.watch(depotHistoriqueProvider(_historique));
    final contenu = async.when(
      // Temps réel : rechargement silencieux, la liste reste affichée.
      skipLoadingOnReload: true,
      // Bouton « Rafraîchir » / tirer-pour-rafraîchir : indicateur visible.
      skipLoadingOnRefresh: false,
      // Un échec après un premier chargement garde la liste (message à part).
      skipError: true,
      data: (commandes) {
        final visibles = _filtrer(commandes);
        return visibles.isEmpty
            ? const EmptyState(message: 'Aucune commande trouvée pour cette recherche.', icon: Icons.history)
            : _liste(visibles, isPreparateur: isPreparateur);
      },
      error: (error, _) => ErrorState(message: ApiClient.messageFromError(error), onRetry: _rafraichir),
      loading: () => const LoadingState(),
    );
    return RefreshIndicator(onRefresh: _rafraichir, child: contenu);
  }
}

/// Champ « date » cliquable — libellé flottant, valeur, icône calendrier ou
/// croix pour vider la valeur (l'`<input type="date">` du web se vide aussi).
class _FiltreDateBouton extends StatelessWidget {
  const _FiltreDateBouton({required this.label, required this.value, required this.onTap, this.onClear});

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: onClear == null
              ? const Icon(Icons.event_outlined)
              : IconButton(tooltip: 'Vider', icon: const Icon(Icons.clear), onPressed: onClear),
        ),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Carte d'une commande — la ligne du tableau web (statut, produits, client,
/// adresse, action) enrichie de ce que le préparateur doit savoir pour
/// remettre le colis à la bonne personne au bon moment : les deux numéros
/// (appelables), le livreur, « Livraison prévue le » et sa note.
/// Un appui sur la carte ouvre la fiche complète.
class _DepotOrderCard extends ConsumerWidget {
  const _DepotOrderCard({required this.order, required this.isPreparateur});

  final Order order;
  final bool isPreparateur;

  /// Confirmation « note + photo » jouée dans sa propre boîte : en cas
  /// d'échec, la boîte reste ouverte avec la saisie. Le succès est annoncé
  /// même si la carte a déjà quitté la liste (une commande passée « Prête »
  /// sort de la file du préparateur) : le messager est résolu avant.
  Future<void> _agir(BuildContext context, WidgetRef ref, _DepotAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(ordersProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmActionDialog(
        order: order,
        action: action,
        onConfirm: (result) => notifier.changeStatus(
          order.id,
          action.target.apiValue,
          note: result.note,
          photoPath: result.photoPath,
        ),
      ),
    );
    if (ok == true) {
      messenger.showSnackBar(SnackBar(content: Text('Commande ${order.numero} → ${action.target.label}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final action = isPreparateur ? _nextAction(order) : null;
    // Le préparateur voit toutes ses commandes à venir (planning) mais ne
    // peut agir qu'à partir de 19h00 la veille du jour de livraison ; le
    // bouton annonce alors le moment où il se débloquera.
    final bloque = !isJourJ(order.dateCommande, UserRole.preparateur);
    final livree = order.statutCourant == OrderStatus.livre;
    final dateLivraison = livree ? (order.historyAt(OrderStatus.livre) ?? order.dateCommande) : order.dateCommande;
    final adresse = order.adresseLivraison?.trim() ?? '';
    final note = order.notePreparateur?.trim() ?? '';
    final retraitPret = order.estRecuperation && order.statutCourant == OrderStatus.prete;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.numero,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OrderStatusBadge(status: order.statutCourant),
                ],
              ),
              const SizedBox(height: 8),
              for (final item in order.items) _ArticleLigne(item: item),
              const SizedBox(height: 8),
              _InfoLigne(icon: Icons.person_outline, text: order.clientNom, bold: true),
              // Les deux numéros sont appelables : le second sert quand le
              // premier ne répond pas (§ demande).
              for (final tel in [order.telephone, order.telephone2])
                if (tel != null && tel.isNotEmpty)
                  _InfoLigne(
                    icon: Icons.phone_outlined,
                    text: tel,
                    onTap: () => launchUrl(Uri.parse('tel:$tel')),
                  ),
              if (adresse.isNotEmpty) _InfoLigne(icon: Icons.place_outlined, text: adresse),
              _InfoLigne(
                icon: Icons.local_shipping_outlined,
                text: DeliveryZoneCatalog.shortLabelFor(order.livraisonZone),
              ),
              if (order.livreurName != null && order.livreurName!.isNotEmpty)
                _InfoLigne(icon: Icons.moped_outlined, text: 'Livreur : ${order.livreurName}'),
              if (dateLivraison != null)
                _InfoLigne(
                  icon: Icons.event_outlined,
                  text: '${livree ? 'Livrée le' : 'Livraison prévue le'} ${_fmtAppDateTime(dateLivraison)}',
                ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Note pour le préparateur', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(note),
                    ],
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: bloque ? null : () => _agir(context, ref, action),
                    icon: Icon(bloque ? Icons.schedule : Icons.inventory_2_outlined),
                    label: Text(
                      bloque && order.dateCommande != null
                          ? 'Disponible le ${dueDateLabel(order.dateCommande!, UserRole.preparateur)}'
                          : action.label,
                    ),
                  ),
                ),
              ] else if (retraitPret) ...[
                const SizedBox(height: 8),
                _InfoLigne(
                  icon: Icons.storefront_outlined,
                  text: 'Prête — retrait au comptoir, à valider comme livrée par le gérant.',
                  muted: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Un article : référence + quantité, puis marque / sous-type et pastille de
/// couleur (colonne « Produit » du tableau web). Un article rapporté lors
/// d'une livraison partielle est barré.
class _ArticleLigne extends StatelessWidget {
  const _ArticleLigne({required this.item});
  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [item.brandName, item.typeName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.referenceName.isEmpty ? 'Article' : item.referenceName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: item.retourne ? TextDecoration.lineThrough : null,
                    color: item.retourne ? scheme.onSurfaceVariant : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('x${item.quantite}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          if (meta.isNotEmpty || item.couleur.isNotEmpty)
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (meta.isNotEmpty) Text(meta, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                if (item.couleur.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(item.couleur, style: const TextStyle(fontSize: 10)),
                  ),
                if (item.retourne) const StatusChip(label: 'Rapporté', color: Color(0xFFEF4444)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Ligne « icône + texte » de la carte ; appelable (couleur primaire,
/// souligné) quand [onTap] est fourni.
class _InfoLigne extends StatelessWidget {
  const _InfoLigne({required this.icon, required this.text, this.onTap, this.bold = false, this.muted = false});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = onTap != null
        ? scheme.primary
        : muted
            ? scheme.outline
            : null;
    final ligne = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: couleur ?? scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: couleur,
                fontWeight: bold ? FontWeight.w600 : null,
                decoration: onTap != null ? TextDecoration.underline : null,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return ligne;
    return InkWell(onTap: onTap, child: ligne);
  }
}

/// Boîte « Confirmer : {action} » (dialogue `actionNote` du web) : résumé de
/// la commande à vérifier, puis le formulaire note + photo (photo proposée
/// au seul passage « Prête », par l'appareil photo ou un fichier).
///
/// La transition est jouée SANS fermer la boîte : en cas d'échec, note et
/// photo saisies restent en place et l'erreur est affichée ; la boîte ne se
/// ferme (avec `true`) qu'une fois la commande passée au nouveau statut.
class _ConfirmActionDialog extends StatefulWidget {
  const _ConfirmActionDialog({required this.order, required this.action, required this.onConfirm});

  final Order order;
  final _DepotAction action;

  /// Exécute la transition ; lève en cas d'échec.
  final Future<void> Function(OrderConfirmResult result) onConfirm;

  @override
  State<_ConfirmActionDialog> createState() => _ConfirmActionDialogState();
}

class _ConfirmActionDialogState extends State<_ConfirmActionDialog> {
  bool _submitting = false;

  Future<void> _submit(OrderConfirmResult result) async {
    setState(() => _submitting = true);
    try {
      await widget.onConfirm(result);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final target = widget.action.target;
    final avecPhoto = photoPourStatut(target);

    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: Text('Confirmer : ${widget.action.label}'),
        content: SizedBox(
          width: dialogWidth(MediaQuery.sizeOf(context).width, 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Commande ${widget.order.numero} — vérifiez le résumé avant de confirmer.', style: muted),
                const SizedBox(height: 10),
                _ResumeCommande(order: widget.order),
                if (avecPhoto) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Ajoutez si besoin une note et une photo prouvant que la préparation est faite — le livreur les verra.',
                    style: muted.copyWith(fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                OrderConfirmForm(
                  showPhoto: avecPhoto,
                  confirmWord: kMotsConfirmation[target],
                  submitting: _submitting,
                  onCancel: () => Navigator.of(context).pop(false),
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

/// Encadré récapitulatif de la confirmation : client, téléphones, zone,
/// adresse, paiement (hors retrait sur place), articles, puis les montants
/// exposés au préparateur (prix de vente, frais, total).
class _ResumeCommande extends StatelessWidget {
  const _ResumeCommande({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final recup = order.estRecuperation;
    final adresse = order.adresseLivraison?.trim() ?? '';

    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Client', order.clientNom),
          if (order.telephone != null && order.telephone!.isNotEmpty) row('Téléphone', order.telephone!),
          if (order.telephone2 != null) row('Autre téléphone', order.telephone2!),
          row('Zone', DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
          if (adresse.isNotEmpty) row('Adresse', adresse),
          if (!recup) row('Paiement', order.modePaiement.label),
          const Divider(height: 16),
          Text('Articles', style: muted),
          for (final item in order.items) row(item.libelle, 'x${item.quantite}'),
          if (order.totalAPayer != null) ...[
            const Divider(height: 16),
            if (!recup && order.fraisLivraison != null) ...[
              row('Prix de vente', arFmt(order.totalAPayer! - order.fraisLivraison!)),
              row('Frais de livraison', arFmt(order.fraisLivraison!)),
            ],
            row('Total', arFmt(order.totalAPayer!), bold: true),
          ],
        ],
      ),
    );
  }
}
