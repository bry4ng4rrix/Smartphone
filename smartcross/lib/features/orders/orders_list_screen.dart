import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../data/repositories/orders_repository.dart' show StaffOption;
import '../../models/catalog.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/orders_provider.dart';
import '../../widgets/assign_staff_dialog.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/status_badge.dart';
import '../depot/depot_screen.dart';
import '../tournee/tournee_screen.dart';
import 'order_create_screen.dart'
    show
        CartLine,
        OrderDateTimeField,
        OrderFormDropdown,
        OrderItemsEditor,
        OrderTypeToggle,
        kTelephoneRegExp,
        modePaiementLabel,
        orderToast;

// Tous les horodatages sont affichés à l'heure d'Antananarivo (fuseau du
// magasin), quel que soit le réglage de l'appareil — cohérent avec la règle
// du jour J et avec le serveur (voir core/app_time.dart).
final _dayFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
final _shortDateTimeFmt = DateFormat('dd/MM HH:mm');

String _fmtDT(DateTime? d) => d == null ? '' : _shortDateTimeFmt.format(appLocal(d));

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Valeur « virtuelle » du sélecteur de statut du gérant : « Pas encore
/// livrée » n'est pas un statut serveur (filtre client `statut !== 'LIVRE'`).
const String _kFiltreAll = 'ALL';
const String _kFiltreNonLivree = 'NON_LIVREE';

// ---------------------------------------------------------------------------
// Actions proposées au gérant — miroir de page.tsx::gerantActionOptions.
// ---------------------------------------------------------------------------

enum _ActionKind { status, assign }

/// Une entrée du sélecteur « Action » d'une commande (gérant) : soit une
/// transition de statut, soit la désignation d'un préparateur/livreur.
class _GerantAction {
  const _GerantAction({
    required this.value,
    required this.label,
    required this.target,
    required this.kind,
    required this.icon,
    this.role,
  });

  final String value;
  final String label;
  final OrderStatus target;
  final _ActionKind kind;
  final IconData icon;

  /// `PREPARATEUR` | `LIVREUR` pour une assignation.
  final String? role;
}

const _assignerPreparateur = _GerantAction(
  value: 'assign-preparateur',
  label: 'Assigner un préparateur',
  target: OrderStatus.enPreparation,
  kind: _ActionKind.assign,
  role: 'PREPARATEUR',
  icon: Icons.person_add_alt_outlined,
);

const _assignerLivreur = _GerantAction(
  value: 'assign-livreur',
  label: 'Assigner un livreur',
  target: OrderStatus.enLivraison,
  kind: _ActionKind.assign,
  role: 'LIVREUR',
  icon: Icons.person_add_alt_outlined,
);

/// Uniquement les transitions réellement possibles depuis le statut
/// courant — le workflow ne revient jamais en arrière, et une commande
/// terminée (Livrée / Retour / Annulée) n'en propose aucune. Mêmes règles que
/// orders/services.py::TRANSITIONS.
///
/// Les boutons d'assignation ne sont proposés que tant que le poste est
/// vacant (§ demande) : une fois quelqu'un désigné, le bouton disparaît —
/// pour changer de personne, on passe par « Modifier ». Le livreur peut être
/// désigné à l'avance, dès que le préparateur l'est, sans attendre que la
/// commande soit prête. Un retrait sur place n'a jamais de livreur.
List<_GerantAction> _gerantActionOptions(Order order) {
  final isRecuperation = order.estRecuperation;
  final sansPreparateur = order.preparateurId == null;
  final sansLivreur = order.livreurId == null && !isRecuperation;

  switch (order.statutCourant) {
    case OrderStatus.nouvelle:
      return [
        if (sansPreparateur) _assignerPreparateur,
        // Préparateur déjà en place : c'est le tour du livreur.
        if (!sansPreparateur && sansLivreur) _assignerLivreur,
        const _GerantAction(
          value: 'commencer-preparation',
          label: 'Commencer la préparation',
          target: OrderStatus.enPreparation,
          kind: _ActionKind.status,
          icon: Icons.inventory_2_outlined,
        ),
      ];
    case OrderStatus.enPreparation:
      return [
        if (sansLivreur) _assignerLivreur,
        const _GerantAction(
          value: 'commande-prete',
          label: 'Commande prête',
          target: OrderStatus.prete,
          kind: _ActionKind.status,
          icon: Icons.inventory_2_outlined,
        ),
      ];
    case OrderStatus.prete:
      // Retrait sur place : pas de livreur, le gérant clôture directement au
      // comptoir (voir services.py::change_order_status).
      if (isRecuperation) {
        return const [
          _GerantAction(
            value: 'livre',
            label: 'Récupérée par le client',
            target: OrderStatus.livre,
            kind: _ActionKind.status,
            icon: Icons.inventory_2_outlined,
          ),
        ];
      }
      return [
        if (sansLivreur) _assignerLivreur,
        const _GerantAction(
          value: 'rendre-en-livraison',
          label: 'Récupérer / En livraison',
          target: OrderStatus.enLivraison,
          kind: _ActionKind.status,
          icon: Icons.local_shipping_outlined,
        ),
      ];
    case OrderStatus.enLivraison:
      return const [
        _GerantAction(
          value: 'livre',
          label: 'Livrée',
          target: OrderStatus.livre,
          kind: _ActionKind.status,
          icon: Icons.local_shipping_outlined,
        ),
        _GerantAction(
          value: 'retour',
          label: 'Retour',
          target: OrderStatus.retour,
          kind: _ActionKind.status,
          icon: Icons.undo,
        ),
      ];
    case OrderStatus.livre:
    case OrderStatus.retour:
    case OrderStatus.annulee:
      return const [];
  }
}

// ---------------------------------------------------------------------------
// Écran
// ---------------------------------------------------------------------------

/// Page Commandes (§7.1 README) — `/orders` du web, déclinée par rôle :
/// le préparateur y retrouve son Dépôt et le livreur sa Tournée (mêmes
/// écrans que leurs entrées de menu dédiées) ; le gérant a le suivi complet :
/// filtres date (jour J par défaut) / statut / préparateur / recherche,
/// cartes détaillées et toutes les actions (sélecteur d'action, Modifier,
/// Annuler, Supprimer, Corriger). Un autre rôle voit la liste en lecture
/// seule, comme sur le web.
class OrdersListScreen extends ConsumerStatefulWidget {
  const OrdersListScreen({super.key});

  @override
  ConsumerState<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends ConsumerState<OrdersListScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilter(OrdersFilter filter) => ref.read(ordersFilterProvider.notifier).set(filter);

  /// Une seule date (pas de plage Du/Au) — § demande : date_debut = date_fin.
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

  /// Champ date vidé (comme l'input du web) : toutes les dates.
  void _clearDate(OrdersFilter filter) => _setFilter(
        OrdersFilter(
          statut: filter.statut,
          preparateurId: filter.preparateurId,
          livraisonZone: filter.livraisonZone,
          magasinId: filter.magasinId,
          nonLivree: filter.nonLivree,
        ),
      );

  void _setStatut(OrdersFilter filter, String value) {
    switch (value) {
      case _kFiltreAll:
        _setFilter(filter.copyWith(clearStatut: true, nonLivree: false));
      case _kFiltreNonLivree:
        _setFilter(filter.copyWith(clearStatut: true, nonLivree: true));
      default:
        _setFilter(filter.copyWith(statut: value, nonLivree: false));
    }
  }

  String _statutValue(OrdersFilter filter) =>
      filter.nonLivree ? _kFiltreNonLivree : (filter.statut ?? _kFiltreAll);

  /// « Réinitialiser » : retour au jour J, sans statut ni préparateur, et
  /// recherche vidée.
  void _reset() {
    _setFilter(jourJFilter(UserRole.gerant));
    _searchController.clear();
    setState(() => _search = '');
  }

  /// Recherche texte GLOBALE côté client (`searchableOrders` du web) :
  /// numéro, client, adresse, téléphones, zone, préparateur, livreur, statut,
  /// articles et date de livraison formatée. Insensible à la casse.
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    // Page unique déclinée en 3 expériences par rôle, comme /orders côté
    // web : Dépôt pour le préparateur, Tournée pour le livreur.
    if (user != null && user.isPreparateur) return const DepotScreen();
    if (user != null && user.isLivreur) return const TourneeScreen();
    final isGerant = user != null && user.isGerant;

    final async = ref.watch(ordersProvider);
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);
    final filter = ref.watch(ordersFilterProvider);

    // Erreur d'un rechargement silencieux (temps réel, après action) : la
    // liste garde son contenu précédent et l'erreur est annoncée par un
    // toast, comme `toast.error(err.message || 'Erreur de chargement des
    // commandes')` côté web.
    ref.listen<AsyncValue<List<Order>>>(ordersProvider, (previous, next) {
      if (next.hasError && next.hasValue && !next.isLoading) {
        orderToast(context, ApiClient.messageFromError(next.error!));
      }
    });

    final q = _search.trim().toLowerCase();
    final orders = async.value;
    // Tri commun aux trois rôles (§ demande) : la commande la plus
    // récemment CRÉÉE en haut — déjà appliqué par le provider, réaffirmé ici
    // après le filtre de recherche.
    final displayed = <Order>[if (orders != null) ...orders.where((o) => _matches(o, q))];
    displayed.sort((a, b) {
      final ac = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bc = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bc.compareTo(ac);
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Commandes'),
            Text(
              'Suivi complet des commandes clients.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            // Rechargement NON silencieux (repasse par l'état de chargement).
            onPressed: () => ref.read(ordersProvider.notifier).refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ordersProvider.notifier).refreshSilencieux(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (isGerant)
              SliverToBoxAdapter(
                child: _GerantFilters(
                  filter: filter,
                  searchController: _searchController,
                  search: _search,
                  onSearch: (v) => setState(() => _search = v),
                  onPickDate: () => _pickDate(filter),
                  onClearDate: () => _clearDate(filter),
                  statutValue: _statutValue(filter),
                  onStatut: (v) => _setStatut(filter, v),
                  onPreparateur: (id) => _setFilter(filter.copyWith(preparateurId: id, clearPreparateurId: id == null)),
                  onReset: _reset,
                ),
              ),
            if (async.isLoading && orders != null)
              const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
            if (orders != null)
              displayed.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        message: 'Aucune commande trouvée pour cette recherche.',
                        icon: Icons.receipt_long_outlined,
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      sliver: SliverList.builder(
                        itemCount: displayed.length,
                        itemBuilder: (context, i) =>
                            _OrderCard(key: ValueKey(displayed[i].id), order: displayed[i], canManage: isGerant),
                      ),
                    )
            else if (async.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(
                  message: ApiClient.messageFromError(async.error!),
                  onRetry: () => ref.read(ordersProvider.notifier).refresh(),
                ),
              )
            else
              const SliverFillRemaining(hasScrollBody: false, child: LoadingState()),
          ],
        ),
      ),
      floatingActionButton: isGerant
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/orders/new'),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle commande'),
            )
          : null,
    );
  }
}

/// Filtres du gérant : boutons de statut, date (un seul jour, jour J par
/// défaut), sélecteur de statut (même état que les boutons), préparateur,
/// recherche et « Réinitialiser ».
class _GerantFilters extends ConsumerWidget {
  const _GerantFilters({
    required this.filter,
    required this.searchController,
    required this.search,
    required this.onSearch,
    required this.onPickDate,
    required this.onClearDate,
    required this.statutValue,
    required this.onStatut,
    required this.onPreparateur,
    required this.onReset,
  });

  final OrdersFilter filter;
  final TextEditingController searchController;
  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final String statutValue;
  final ValueChanged<String> onStatut;
  final ValueChanged<int?> onPreparateur;
  final VoidCallback onReset;

  static const _statutOptions = <({String value, String label})>[
    (value: _kFiltreAll, label: 'Toutes'),
    (value: _kFiltreNonLivree, label: 'Pas encore livrée'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = appToday();
    final dateJourJ = filter.dateDebut != null &&
        _sameDay(filter.dateDebut!, today) &&
        (filter.dateFin == null || _sameDay(filter.dateFin!, today));
    final aDesFiltres =
        !dateJourJ || filter.preparateurId != null || filter.statut != null || filter.nonLivree || search.isNotEmpty;
    final preparateurs = ref.watch(preparateurFilterListProvider).asData?.value ?? const <StaffOption>[];
    final wide = MediaQuery.sizeOf(context).width >= 700;

    final dateField = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPickDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          isDense: true,
          prefixIcon: const Icon(Icons.event_outlined, size: 20),
          suffixIcon: filter.dateDebut == null
              ? null
              : IconButton(
                  tooltip: 'Toutes les dates',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClearDate,
                ),
        ),
        isEmpty: filter.dateDebut == null,
        child: Text(
          filter.dateDebut == null ? 'Toutes les dates' : _dayFmt.format(filter.dateDebut!),
          style: filter.dateDebut == null ? TextStyle(color: scheme.onSurfaceVariant) : null,
        ),
      ),
    );

    final statutField = OrderFormDropdown<String>(
      value: statutValue,
      labelText: 'Statut',
      items: [
        const DropdownMenuItem(value: _kFiltreAll, child: Text('Tous')),
        const DropdownMenuItem(value: _kFiltreNonLivree, child: Text('Pas encore livrée')),
        for (final s in OrderStatus.values) DropdownMenuItem(value: s.apiValue, child: Text(s.label)),
      ],
      onChanged: (v) => onStatut(v ?? _kFiltreAll),
    );

    final preparateurField = OrderFormDropdown<int>(
      value: filter.preparateurId,
      labelText: 'Préparateur',
      hintText: 'Tous',
      items: [
        const DropdownMenuItem<int>(value: null, child: Text('Tous')),
        for (final p in preparateurs) DropdownMenuItem(value: p.id, child: Text(p.fullName)),
        // Liste pas encore chargée (ou préparateur absent de celle-ci) : le
        // filtre appliqué reste visible.
        if (filter.preparateurId != null && !preparateurs.any((p) => p.id == filter.preparateurId))
          DropdownMenuItem(value: filter.preparateurId, child: const Text('Préparateur sélectionné')),
      ],
      onChanged: onPreparateur,
    );

    final searchField = TextField(
      controller: searchController,
      decoration: InputDecoration(
        labelText: 'Recherche',
        hintText: 'Code, client, produit, adresse, livreur, préparateur, date...',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: search.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  searchController.clear();
                  onSearch('');
                },
              ),
      ),
      onChanged: onSearch,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barre de boutons statut : Toutes / Pas encore livrée / un bouton
          // par statut — le bouton actif est mis en avant.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final o in [
                  ..._statutOptions,
                  for (final s in OrderStatus.values) (value: s.apiValue, label: s.label),
                ]) ...[
                  ChoiceChip(
                    label: Text(o.label),
                    selected: statutValue == o.value,
                    onSelected: (_) => onStatut(o.value),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (wide)
            Row(
              children: [
                Expanded(child: dateField),
                const SizedBox(width: 8),
                Expanded(child: statutField),
                const SizedBox(width: 8),
                Expanded(child: preparateurField),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: searchField),
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(child: dateField),
                const SizedBox(width: 8),
                Expanded(child: statutField),
              ],
            ),
            const SizedBox(height: 8),
            preparateurField,
            const SizedBox(height: 8),
            searchField,
          ],
          if (aDesFiltres)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Réinitialiser'),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carte d'une commande (une ligne du tableau web) + actions du gérant
// ---------------------------------------------------------------------------

class _OrderCard extends ConsumerWidget {
  const _OrderCard({super.key, required this.order, required this.canManage});

  final Order order;

  /// Gérant : sélecteur d'action, Modifier, Annuler, Supprimer, Corriger.
  final bool canManage;

  Future<void> _runAction(BuildContext context, WidgetRef ref, _GerantAction action) async {
    if (action.kind == _ActionKind.assign) {
      await _assign(context, ref, action.role ?? 'PREPARATEUR');
      return;
    }
    await _changeStatus(context, ref, action);
  }

  /// Transition de statut jouée par le gérant lui-même — confirmation avec
  /// résumé, note, photo (passage « Prête »), pointage des articles
  /// (« Livré ») et mot à retaper (« Retour »).
  Future<void> _changeStatus(BuildContext context, WidgetRef ref, _GerantAction action) async {
    final result = await showOrderConfirmDialog(
      context,
      title: 'Confirmer : ${action.label}',
      order: order,
      target: action.target,
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(ordersProvider.notifier)
          .changeStatus(
            order.id,
            action.target.apiValue,
            note: result.note,
            photoPath: result.photoPath,
            itemsLivres: result.itemsLivres,
          );
      messenger.showSnackBar(SnackBar(content: Text('Commande ${order.numero} → ${updated.statutCourant.label}')));
    } catch (e) {
      // `toast.error(err.message || 'Action impossible')` — c'est ainsi que
      // remontent les refus serveur (transition impossible, préparateur à
      // choisir, commande assignée à quelqu'un d'autre…).
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  /// Assigne un préparateur ou un livreur SANS faire avancer la commande
  /// (§ demande) : le statut reste « Nouvelle » ou « Prête » jusqu'à ce que
  /// quelqu'un clique explicitement sur l'étape suivante.
  Future<void> _assign(BuildContext context, WidgetRef ref, String role) async {
    final result = await showAssignStaffDialog(
      context,
      role: role,
      orderNumero: order.numero,
      loadStaff: () => ref.read(ordersProvider.notifier).availableStaff(role, magasinId: order.magasinId),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (role == 'PREPARATEUR') {
        await ref.read(ordersProvider.notifier).assignPreparateur(order.id, result.staffId);
      } else {
        await ref.read(ordersProvider.notifier).assignLivreur(order.id, result.staffId);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Commande ${order.numero} — ${role == 'PREPARATEUR' ? 'préparateur' : 'livreur'} assigné'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _edit(BuildContext context) async {
    await showDialog<bool>(context: context, builder: (_) => EditOrderDialog(order: order));
  }

  Future<void> _cancel(BuildContext context) async {
    await showDialog<bool>(context: context, builder: (_) => _CancelOrderDialog(order: order));
  }

  Future<void> _delete(BuildContext context) async {
    await showDialog<bool>(context: context, builder: (_) => _DeleteOrderDialog(order: order));
  }

  Future<void> _corriger(BuildContext context) async {
    await showDialog<bool>(context: context, builder: (_) => _CorrectionDialog(order: order));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);

    final preparedAt = order.historyAt(OrderStatus.enPreparation);
    // Tant que la commande n'est pas Livrée, on affiche la date de livraison
    // prévue (dateCommande) — une fois Livrée, l'heure réellement atteinte.
    final livreurAt = order.statutCourant == OrderStatus.livre ? order.historyAt(OrderStatus.livre) : order.dateCommande;
    // « Livrée le » une fois livrée, sinon la livraison prévue (colonne
    // « Date » retirée du tableau web, reprise dans son détail).
    final dateLigne = order.statutCourant == OrderStatus.livre
        ? (order.historyAt(OrderStatus.livre) ?? order.dateCommande)
        : order.dateCommande;
    final actions = canManage ? _gerantActionOptions(order) : const <_GerantAction>[];
    // « Modifier » reste proposé tant que la commande n'est pas terminée :
    // régime complet jusqu'à « En préparation », régime livraison (zone,
    // adresse, paiement, note livreur) au-delà — même fenêtre que le détail
    // du web (le bouton de ligne n'y couvrait que le régime complet).
    final canEdit = canManage && !order.estTerminee;
    final canDelete = canManage && order.suppressionPossible;
    final canCancel = canManage && order.annulationPossible;
    final correctionCible = canManage ? order.correctionCible : null;
    final adresse = order.adresseLivraison;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
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
                  if (order.totalAPayer != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(arFmt(order.totalAPayer!), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (order.estPrepayee && !order.estRecuperation)
                          const Text(
                            'Déjà payé',
                            style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // Produit : tous les articles, référence + quantité, puis
              // sous-type / marque et pastille de couleur.
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
              _IconLine(
                icon: Icons.place_outlined,
                // Adresse de livraison, sinon le libellé de zone (sans prix),
                // sinon le code brut.
                text: adresse != null && adresse.isNotEmpty ? adresse : DeliveryZoneCatalog.shortLabelFor(order.livraisonZone),
              ),
              if (dateLigne != null)
                _IconLine(
                  icon: Icons.event_outlined,
                  text: '${order.statutCourant == OrderStatus.livre ? 'Livrée le' : 'Livraison prévue le'} '
                      '${_dateTimeFmt.format(appLocal(dateLigne))}',
                ),
              // Assigné à — préparateur (avec l'heure de début de préparation)
              // et/ou livreur (« Livré le » / « Prévu le »), sinon « - ».
              if (order.preparateurName == null && order.livreurName == null)
                _IconLine(icon: Icons.group_outlined, text: 'Assigné à : -')
              else ...[
                if (order.preparateurName != null)
                  _IconLine(
                    icon: Icons.inventory_2_outlined,
                    text: '${order.preparateurName}${preparedAt != null ? ' · ${_fmtDT(preparedAt)}' : ''}',
                  ),
                if (order.livreurName != null)
                  _IconLine(
                    icon: Icons.local_shipping_outlined,
                    text: '${order.livreurName}'
                        '${livreurAt != null ? ' · ${order.statutCourant == OrderStatus.livre ? 'Livré le ' : 'Prévu le '}${_fmtDT(livreurAt)}' : ''}',
                  ),
              ],
              if (actions.isNotEmpty || correctionCible != null || canEdit || canCancel || canDelete) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (actions.isNotEmpty)
                      PopupMenuButton<_GerantAction>(
                        tooltip: 'Action',
                        onSelected: (a) => _runAction(context, ref, a),
                        itemBuilder: (context) => [
                          for (final a in actions)
                            PopupMenuItem(
                              value: a,
                              child: Row(
                                children: [
                                  Icon(a.icon, size: 18),
                                  const SizedBox(width: 8),
                                  Text(a.label),
                                ],
                              ),
                            ),
                        ],
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.only(left: 12, right: 6),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Action', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                              Icon(Icons.arrow_drop_down, color: scheme.onPrimary),
                            ],
                          ),
                        ),
                      ),
                    // Commande close : le gérant peut corriger un état saisi
                    // par erreur (§ demande), directement depuis la ligne.
                    if (correctionCible != null)
                      _SmallAction(
                        icon: Icons.undo,
                        label: 'Corriger → ${correctionCible.label}',
                        onPressed: () => _corriger(context),
                      ),
                    if (canEdit)
                      _SmallAction(icon: Icons.edit_outlined, label: 'Modifier', onPressed: () => _edit(context)),
                    if (canCancel)
                      _SmallAction(
                        icon: Icons.block_outlined,
                        label: 'Annuler',
                        color: Colors.red,
                        onPressed: () => _cancel(context),
                      ),
                    if (canDelete)
                      _SmallAction(
                        icon: Icons.delete_outline,
                        label: 'Supprimer',
                        color: Colors.red,
                        onPressed: () => _delete(context),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
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

/// Bouton d'action compact avec icône + libellé (`IconAction showLabel` du web).
class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.onPressed, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogues : annulation (mot ANNULER), suppression, correction d'état
// ---------------------------------------------------------------------------

/// Annulation d'une commande (gérant) — restitue le stock si déjà déduit.
/// Annuler est irréversible : on fait retaper le mot pour rendre le geste
/// délibéré (§ demande).
class _CancelOrderDialog extends ConsumerStatefulWidget {
  const _CancelOrderDialog({required this.order});
  final Order order;

  @override
  ConsumerState<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends ConsumerState<_CancelOrderDialog> {
  final _word = TextEditingController();
  bool _cancelling = false;
  String? _error;

  bool get _motValide => motConfirmationValide(kMotConfirmationAnnulation, _word.text);

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _cancelling = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ordersProvider.notifier).cancel(widget.order.id);
      messenger.showSnackBar(SnackBar(content: Text('Commande ${widget.order.numero} annulée')));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiClient.messageFromError(e);
          _cancelling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Annuler la commande ${order.numero} ?'),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La commande de ${order.clientNom} sera annulée.'
              '${order.annulationRestitueStock ? ' Le stock déjà déduit pour cette commande sera automatiquement restitué.' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Pour confirmer, tapez '),
                  TextSpan(text: kMotConfirmationAnnulation, style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _word,
              decoration: const InputDecoration(hintText: kMotConfirmationAnnulation),
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              enabled: !_cancelling,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _cancelling ? null : () => Navigator.of(context).pop(false), child: const Text('Retour')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: (_cancelling || !_motValide) ? null : _submit,
          child: Text(_cancelling ? 'Annulation...' : 'Annuler la commande'),
        ),
      ],
    );
  }
}

/// Suppression (gérant, uniquement tant que « Nouvelle » — rien d'engagé).
class _DeleteOrderDialog extends ConsumerStatefulWidget {
  const _DeleteOrderDialog({required this.order});
  final Order order;

  @override
  ConsumerState<_DeleteOrderDialog> createState() => _DeleteOrderDialogState();
}

class _DeleteOrderDialogState extends ConsumerState<_DeleteOrderDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ordersProvider.notifier).delete(widget.order.id);
      messenger.showSnackBar(SnackBar(content: Text('Commande ${widget.order.numero} supprimée')));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiClient.messageFromError(e);
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Supprimer la commande ${widget.order.numero} ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cette action est définitive — la commande de ${widget.order.clientNom} sera supprimée.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        OutlinedButton(onPressed: _deleting ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: _deleting ? null : _submit,
          child: Text(_deleting ? 'Suppression...' : 'Supprimer'),
        ),
      ],
    );
  }
}

/// Correction d'un état final saisi par erreur (gérant) — un « Retour »
/// touché par accident alors que la livraison était faite, et l'inverse. Le
/// serveur rétablit le stock : les articles ressortent (ou rentrent) selon le
/// sens. Le mot à retaper est le statut cible (RETOUR / LIVRE).
class _CorrectionDialog extends ConsumerStatefulWidget {
  const _CorrectionDialog({required this.order});
  final Order order;

  @override
  ConsumerState<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends ConsumerState<_CorrectionDialog> {
  bool _submitting = false;

  Future<void> _submit(OrderStatus cible, OrderConfirmResult result) async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ordersProvider.notifier).corrigerStatut(widget.order.id, cible.apiValue, note: result.note);
      messenger.showSnackBar(SnackBar(content: Text('Commande ${widget.order.numero} corrigée → ${cible.label}')));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // En cas d'échec on reste sur le formulaire : la note n'est pas perdue.
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final cible = order.correctionCible ?? OrderStatus.retour;
    final scheme = Theme.of(context).colorScheme;
    final bold = TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface);
    return AlertDialog(
      title: Text('Corriger la commande ${order.numero}'),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  children: [
                    const TextSpan(text: 'Son état passera de '),
                    TextSpan(text: order.statutCourant.label, style: bold),
                    const TextSpan(text: ' à '),
                    TextSpan(text: cible.label, style: bold),
                    TextSpan(
                      text: '. Le stock est rétabli en conséquence : '
                          '${cible == OrderStatus.livre ? "les articles ressortent du stock, puisqu'ils n'ont jamais été rapportés." : 'les articles rentrent en stock, puisque le colis est revenu.'}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OrderConfirmForm(
                confirmWord: cible.apiValue,
                submitting: _submitting,
                onCancel: () => Navigator.of(context).pop(false),
                onSubmit: (result) => _submit(cible, result),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modification d'une commande (gérant) — EditOrderDialog du web
// ---------------------------------------------------------------------------

/// Modification d'une commande — réservée au gérant (voir
/// orders/views.py::partial_update). Deux régimes, mêmes règles que
/// orders/services.py::update_order :
///
/// * « Nouvelle » / « En préparation » — tout est modifiable (client,
///   téléphones, date, type, zone, adresse, paiement, notes, articles,
///   pré-assignation du préparateur/livreur) ;
/// * « Prête » / « En livraison » — la commande est trop engagée pour tout
///   modifier, mais les données de LIVRAISON restent ajustables : zone,
///   adresse, paiement et note du livreur. Changer la zone met à jour les
///   frais et le total, donc le bilan du livreur (§ demande).
///
/// Se referme avec `true` après enregistrement ; la liste se recharge
/// silencieusement via [OrdersNotifier].
class EditOrderDialog extends ConsumerStatefulWidget {
  const EditOrderDialog({super.key, required this.order});
  final Order order;

  @override
  ConsumerState<EditOrderDialog> createState() => _EditOrderDialogState();
}

class _EditOrderDialogState extends ConsumerState<EditOrderDialog> {
  late final _clientController = TextEditingController(text: widget.order.clientNom);
  late final _phoneController = TextEditingController(text: widget.order.telephone ?? '+261');
  late final _phone2Controller = TextEditingController(text: widget.order.telephone2 ?? '');
  late final _adresseController = TextEditingController(text: widget.order.adresseLivraison ?? '');
  late final _notePreparateurController = TextEditingController(text: widget.order.notePreparateur ?? '');
  late final _noteLivreurController = TextEditingController(text: widget.order.noteLivreur ?? '');
  late String _zone = widget.order.livraisonZone;
  late PaymentMode _modePaiement = widget.order.modePaiement;
  // Heure « au mur » d'Antananarivo : ce que l'utilisateur voit et saisit
  // est l'heure du magasin, renvoyée telle quelle au serveur via
  // appWallClockToUtc (voir core/app_time.dart). `null` = non renseignée ->
  // non envoyée.
  late DateTime? _dateCommande = widget.order.dateCommande == null ? null : appLocal(widget.order.dateCommande!);
  late int? _preparateurId = widget.order.preparateurId;
  late int? _livreurId = widget.order.livreurId;
  List<StaffOption> _preparateurs = const [];
  List<StaffOption> _livreurs = const [];
  // Articles existants pré-chargés : plus de contrôle de stock sur eux
  // (`stock_actuel: Infinity` côté web).
  late List<CartLine> _lines = [
    for (final it in widget.order.items)
      if (it.productVariantId != null)
        CartLine(
          key: 'existing-${it.id}',
          reference: ReferenceOption(
            id: 0,
            typeId: 0,
            typeName: it.typeName ?? '',
            brandId: 0,
            brandName: it.brandName ?? '',
            referenceName: it.referenceName,
            prixVente: it.prixUnitaire ?? 0,
            couleurs: [ColorOption(variantId: it.productVariantId!, couleur: it.couleur, stockActuel: 1 << 30)],
          ),
          couleur: it.couleur,
          variantId: it.productVariantId!,
          quantite: it.quantite,
          stockActuel: 1 << 30,
        ),
  ];
  bool _submitting = false;
  String? _error;

  /// Au-delà de « En préparation » : régime livraison (`livraisonSeule`).
  bool get _livraisonSeule => !widget.order.modificationComplete;

  bool get _isPickup => _zone == kRecuperationCode;

  @override
  void initState() {
    super.initState();
    if (!_livraisonSeule) {
      _loadStaff();
    }
  }

  Future<void> _loadStaff() async {
    final notifier = ref.read(ordersProvider.notifier);
    final magasinId = widget.order.magasinId;
    try {
      final staff = await notifier.availableStaff('PREPARATEUR', magasinId: magasinId);
      if (mounted) setState(() => _preparateurs = staff);
    } catch (_) {
      if (mounted) setState(() => _preparateurs = const []);
    }
    try {
      final staff = await notifier.availableStaff('LIVREUR', magasinId: magasinId, dateCommande: widget.order.dateCommande);
      if (mounted) setState(() => _livreurs = staff);
    } catch (_) {
      if (mounted) setState(() => _livreurs = const []);
    }
  }

  @override
  void dispose() {
    _clientController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    _adresseController.dispose();
    _notePreparateurController.dispose();
    _noteLivreurController.dispose();
    super.dispose();
  }

  /// Liste du sélecteur de personnel : le personnel disponible, plus la
  /// personne déjà désignée si elle n'y figure pas (compte désactivé, autre
  /// magasin…) pour que le champ reflète toujours la commande.
  List<DropdownMenuItem<int>> _staffItems(List<StaffOption> staff, int? currentId, String? currentName) {
    final items = <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(value: null, child: Text('Non assigné')),
      for (final s in staff) DropdownMenuItem(value: s.id, child: Text('${s.fullName}${s.available ? '' : ' (occupé)'}')),
    ];
    if (currentId != null && !staff.any((s) => s.id == currentId)) {
      items.add(DropdownMenuItem(value: currentId, child: Text(currentName ?? 'Assigné')));
    }
    return items;
  }

  void _fail(String message) {
    setState(() => _error = message);
    orderToast(context, message);
  }

  Future<void> _submit() async {
    final order = widget.order;
    final clientNom = _clientController.text.trim();
    final telephone = _phoneController.text.trim();
    final telephone2 = _phone2Controller.text.trim();
    // En régime livraison on ne valide rien d'autre : seules les données de
    // livraison partent.
    if (!_livraisonSeule) {
      if (clientNom.isEmpty) {
        _fail('Nom du client requis');
        return;
      }
      if (!kTelephoneRegExp.hasMatch(telephone)) {
        _fail('Téléphone au format +261XXXXXXXXX');
        return;
      }
      if (telephone2.isNotEmpty && !kTelephoneRegExp.hasMatch(telephone2)) {
        _fail('Autre téléphone au format +261XXXXXXXXX');
        return;
      }
      if (_lines.isEmpty) {
        _fail('Ajoutez au moins un article');
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(ordersProvider.notifier);
    try {
      if (_livraisonSeule) {
        await notifier.updateLivraison(
          order.id,
          modePaiement: _modePaiement.apiValue,
          livraisonZone: _zone,
          adresseLivraison: _isPickup ? '' : _adresseController.text.trim(),
          noteLivreur: _isPickup ? '' : _noteLivreurController.text.trim(),
        );
        messenger.showSnackBar(SnackBar(content: Text('Commande ${order.numero} — livraison mise à jour')));
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await notifier.updateOrder(
        order.id,
        clientNom: clientNom,
        telephone: telephone,
        telephone2: telephone2,
        livraisonZone: _zone,
        adresseLivraison: _isPickup ? '' : _adresseController.text.trim(),
        modePaiement: _modePaiement.apiValue,
        dateCommande: _dateCommande == null ? null : appWallClockToUtc(_dateCommande!),
        notePreparateur: _notePreparateurController.text.trim(),
        noteLivreur: _isPickup ? '' : _noteLivreurController.text.trim(),
        items: [for (final l in _lines) OrderItemDraft(productVariant: l.variantId, quantite: l.quantite)],
      );
      // Pré-assignation du préparateur/livreur — endpoints indépendants du
      // statut, comme à la création. Rien à envoyer si rien n'a changé.
      if (_preparateurId != null && _preparateurId != order.preparateurId) {
        try {
          await notifier.assignPreparateur(order.id, _preparateurId!);
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                "Commande mise à jour, mais l'assignation du préparateur a échoué : ${ApiClient.messageFromError(e)}",
              ),
            ),
          );
        }
      }
      if (!_isPickup && _livreurId != null && _livreurId != order.livreurId) {
        try {
          await notifier.assignLivreur(order.id, _livreurId!);
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                "Commande mise à jour, mais l'assignation du livreur a échoué : ${ApiClient.messageFromError(e)}",
              ),
            ),
          );
        }
      }
      messenger.showSnackBar(const SnackBar(content: Text('Commande mise à jour')));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiClient.messageFromError(e);
          _submitting = false;
        });
      }
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final livraisonSeule = _livraisonSeule;
    // Zones configurables (CRUD Paramètres) — une zone désactivée reste
    // proposée si c'est celle de la commande.
    final zones = ref.watch(deliveryZonesProvider).asData?.value ?? const <DeliveryZoneOption>[];
    final zonesPayantes = zones.where((z) => z.actif || z.code == _zone).toList();
    final wide = MediaQuery.sizeOf(context).width >= 600;

    Widget twoCols(Widget a, Widget b) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, b]);

    return AlertDialog(
      title: Text('Modifier la commande ${order.numero}'),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                livraisonSeule
                    ? "Commande déjà engagée : seules la zone, l'adresse, le paiement et la note du livreur restent "
                        'modifiables. Changer la zone met à jour les frais et le bilan du livreur.'
                    : 'Possible tant que la commande n\'est pas encore "Prête".',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                ),
              ],
              // Régime complet : articles, type, date, client, téléphones.
              if (!livraisonSeule) ...[
                const SizedBox(height: 12),
                OrderItemsEditor(lines: _lines, onChanged: (l) => setState(() => _lines = l), showPrices: true),
                _label('Type de commande'),
                OrderTypeToggle(
                  pickup: _isPickup,
                  onChanged: (pickup) => setState(() {
                    final payantes = zones.where((z) => z.actif).toList();
                    _zone = pickup ? kRecuperationCode : (payantes.isNotEmpty ? payantes.first.code : '');
                  }),
                ),
                _label('Date et heure de livraison'),
                OrderDateTimeField(
                  value: _dateCommande,
                  hintText: 'Choisir la date',
                  onChanged: (d) => setState(() => _dateCommande = d),
                ),
                twoCols(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('Nom client'),
                      TextField(
                        controller: _clientController,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('Téléphone'),
                      TextField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.phone_outlined),
                          hintText: '+261340000000',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
                _label('Autre téléphone (optionnel)'),
                TextField(
                  controller: _phone2Controller,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined), hintText: '+261340000000'),
                  keyboardType: TextInputType.phone,
                ),
              ],
              // Zone + adresse : les deux régimes, hors retrait sur place.
              if (!_isPickup)
                twoCols(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('Zone de livraison'),
                      OrderFormDropdown<String>(
                        value: _zone,
                        hintText: 'Zone de livraison',
                        prefixIcon: Icons.local_shipping_outlined,
                        items: [for (final z in zonesPayantes) DropdownMenuItem(value: z.code, child: Text(z.label))],
                        onChanged: (v) => setState(() => _zone = v ?? _zone),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('Adresse de livraison'),
                      TextField(
                        controller: _adresseController,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.place_outlined)),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ),
                ),
              if (livraisonSeule || !_isPickup) ...[
                _label('Paiement'),
                OrderFormDropdown<PaymentMode>(
                  value: _modePaiement,
                  prefixIcon: Icons.payments_outlined,
                  items: [
                    for (final m in PaymentMode.values) DropdownMenuItem(value: m, child: Text(modePaiementLabel(m))),
                  ],
                  onChanged: (v) => setState(() => _modePaiement = v ?? _modePaiement),
                ),
              ],
              if (!livraisonSeule) ...[
                twoCols(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('Préparateur'),
                      OrderFormDropdown<int>(
                        value: _preparateurId,
                        hintText: 'Non assigné',
                        prefixIcon: Icons.inventory_2_outlined,
                        items: _staffItems(_preparateurs, _preparateurId, order.preparateurName),
                        onChanged: (v) => setState(() => _preparateurId = v),
                      ),
                    ],
                  ),
                  _isPickup
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('Livreur'),
                            OrderFormDropdown<int>(
                              value: _livreurId,
                              hintText: 'Non assigné',
                              prefixIcon: Icons.moped_outlined,
                              items: _staffItems(_livreurs, _livreurId, order.livreurName),
                              onChanged: (v) => setState(() => _livreurId = v),
                            ),
                          ],
                        ),
                ),
                _label('Note pour le préparateur (optionnel)'),
                TextField(
                  controller: _notePreparateurController,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.notes_outlined)),
                  maxLines: 2,
                ),
              ],
              // La note du livreur reste utile en cours de tournée : c'est par
              // elle qu'on lui transmet une consigne de dernière minute.
              if (!_isPickup) ...[
                _label('Note pour le livreur (optionnel)'),
                TextField(
                  controller: _noteLivreurController,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.moped_outlined)),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Enregistrement...' : 'Enregistrer'),
        ),
      ],
    );
  }
}
