import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../data/repositories/orders_repository.dart';
import '../../models/delivery_zone.dart';
import '../../models/expense.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/expenses_provider.dart';
import '../../state/orders_provider.dart';
import '../../state/realtime_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;
import 'depenses_du_jour.dart';

final _hourFmt = DateFormat('dd/MM HH:mm');
final _dayFmt = DateFormat('dd/MM/yyyy');

/// Clé de regroupement des commandes sans livreur (retrait au comptoir) —
/// `"SANS"` de la vue d'ensemble du gérant côté web.
const String _kSansLivreur = 'SANS';

/// Prix produit seul = total à payer moins les frais de livraison — dérivé
/// sans le prix par article (jamais exposé au livreur, voir
/// orders/serializers.py::OrderItemPublicSerializer).
double _prixProduit(Order o) => (o.totalAPayer ?? 0) - (o.fraisLivraison ?? 0);

/// Le client a-t-il réglé AVANT la livraison ?
bool _estPrepayee(Order o) => o.modePaiement == PaymentMode.avant;

/// Argent réellement encaissé par le livreur sur cette commande (§ demande).
///
/// Une commande déjà payée d'avance ne fait RIEN encaisser au livreur : elle
/// vaut 0 Ar dans le bilan, même si son total est non nul. Sans ça le bilan
/// réclamerait au livreur de l'argent qu'il n'a jamais reçu — et le total du
/// gérant serait faux d'autant.
double _argentEncaisse(Order o) => _estPrepayee(o) ? 0 : (o.totalAPayer ?? 0);

/// Clé de regroupement d'une commande par livreur (`o.livreur == null ?
/// "SANS" : String(o.livreur)` du web).
String _cleLivreur(Order o) => o.livreurId == null ? _kSansLivreur : '${o.livreurId}';

class _Totaux {
  const _Totaux({
    required this.count,
    required this.prix,
    required this.frais,
    required this.argent,
    required this.prepaye,
    required this.prepayeCount,
  });
  final int count;
  final double prix;
  final double frais;

  /// Somme des montants réellement remis par le livreur.
  final double argent;

  /// Montant des commandes prépayées — existe, mais n'a pas transité par le
  /// livreur : affiché à part pour que l'écart soit explicable.
  final double prepaye;
  final int prepayeCount;

  factory _Totaux.of(List<Order> orders) => _Totaux(
    count: orders.length,
    prix: orders.fold<double>(0, (s, o) => s + _prixProduit(o)),
    frais: orders.fold<double>(0, (s, o) => s + (o.fraisLivraison ?? 0)),
    argent: orders.fold<double>(0, (s, o) => s + _argentEncaisse(o)),
    prepaye: orders.where(_estPrepayee).fold<double>(0, (s, o) => s + (o.totalAPayer ?? 0)),
    prepayeCount: orders.where(_estPrepayee).length,
  );
}

/// Bornes absolues (UTC) d'un jour calendaire à Antananarivo — `appDayBounds(jour)`
/// du web. Le jour est ici une date « au mur » (celle choisie ou celle du
/// jour), pas un instant : on passe donc par [appWallClockToUtc] plutôt que
/// par `appDayBounds(DateTime)`, qui réinterpréterait la date dans le fuseau
/// de l'appareil.
({DateTime start, DateTime end}) _bornesDuJour(DateTime jour) => (
  start: appWallClockToUtc(DateTime(jour.year, jour.month, jour.day)),
  end: appWallClockToUtc(DateTime(jour.year, jour.month, jour.day, 23, 59, 59)),
);

/// Périmètre d'un bilan : le jour consulté et le rôle qui le consulte. Sert
/// de clé de famille — deux périmètres égaux partagent le même cache.
class BilanQuery {
  BilanQuery({required DateTime jour, required this.gerant}) : jour = DateTime(jour.year, jour.month, jour.day);

  /// Jour calendaire (minuit, sans fuseau) à Antananarivo.
  final DateTime jour;

  /// Gérant : toutes les commandes du jour de ses magasins ; sinon
  /// l'historique personnel du livreur (déjà limité à lui côté serveur).
  final bool gerant;

  String get jourIso => formatExpenseDate(jour);

  @override
  bool operator ==(Object other) => other is BilanQuery && other.jourIso == jourIso && other.gerant == gerant;

  @override
  int get hashCode => Object.hash(jourIso, gerant);
}

/// Commandes du jour entrant dans le bilan — `fetchOrders` du web :
///
/// * LIVREUR — `GET /orders/?historique=1&date_from&date_to`, journée bornée
///   à l'heure d'ANTANANARIVO (fuseau du magasin), pas à celle de l'appareil —
///   sinon le « bilan du jour » bascule 3 h trop tôt/trop tard ;
/// * GÉRANT — `GET /orders/?date_debut=jour&date_fin=jour`, toutes les
///   commandes du jour de ses magasins.
///
/// Se recharge SILENCIEUSEMENT à chaque événement temps réel (changement de
/// statut fait ailleurs) — `useRealtimeRefresh(['order',
/// 'order_status_history'], () => fetchOrders(true))` du web.
final bilanOrdersProvider = FutureProvider.autoDispose.family<List<Order>, BilanQuery>((ref, query) {
  ref.watch(realtimeTickProvider);
  final repo = ref.read(ordersRepositoryProvider);
  if (query.gerant) {
    return repo.list(dateDebut: query.jour, dateFin: query.jour);
  }
  final bornes = _bornesDuJour(query.jour);
  return repo.list(historique: true, dateFrom: bornes.start, dateTo: bornes.end);
});

/// Livreurs de la société, pour nommer les lignes de la vue d'ensemble du
/// gérant (`availableStaff('LIVREUR')` du web). Échec silencieux : liste
/// vide, le nom retombe alors sur `livreur_name` de la commande.
final bilanLivreursProvider = FutureProvider.autoDispose<List<StaffOption>>((ref) async {
  try {
    return await ref.read(ordersRepositoryProvider).availableStaff(UserRole.livreur.apiValue);
  } catch (_) {
    return const <StaffOption>[];
  }
});

/// Une ligne de la vue d'ensemble du gérant : un livreur, ses totaux du jour
/// et ses dépenses.
class _LigneLivreur {
  const _LigneLivreur({
    required this.key,
    required this.nom,
    required this.livrees,
    required this.retours,
    required this.depenses,
  });
  final String key;
  final String nom;
  final _Totaux livrees;
  final _Totaux retours;

  /// Dépenses de CE livreur ce jour-là, tous statuts.
  final List<LivreurExpense> depenses;
}

/// Page `/bilan` du web (`frontend/app/(app)/bilan/page.tsx`).
///
/// * LIVREUR — son bilan du jour : livraisons faites et retours, ticket
///   récapitulatif (payé d'avance = 0 Ar, dépenses validées, net à
///   remettre) et déclaration de ses dépenses.
/// * GÉRANT — choisit le jour ; vue d'ensemble (compteurs + une ligne par
///   livreur) ; le clic sur un livreur ouvre son détail complet, avec
///   Accepter / Rejeter sur ses dépenses. Changer de jour revient à la liste.
///
/// Tout autre rôle voit « Accès refusé ». Les retours ne sont jamais
/// additionnés aux livraisons faites (rien n'a été encaissé dessus).
class BilanScreen extends ConsumerStatefulWidget {
  const BilanScreen({super.key});

  @override
  ConsumerState<BilanScreen> createState() => _BilanScreenState();
}

class _BilanScreenState extends ConsumerState<BilanScreen> {
  /// Le gérant choisit le jour ; le livreur reste sur aujourd'hui
  /// (Antananarivo, jamais l'heure de l'appareil).
  DateTime _jour = appToday();

  /// Gérant : `null` = vue d'ensemble (liste des livreurs) ; sinon la clé du
  /// livreur dont on regarde le détail. Le détail ne s'ouvre qu'au clic.
  String? _detailLivreur;

  /// Rechargement NON silencieux (bouton « Rafraîchir ») : le web réaffiche
  /// ses skeletons.
  bool _reloading = false;

  /// Dernières erreurs déjà signalées par un toast, pour ne pas répéter le
  /// même SnackBar à chaque reconstruction.
  Object? _reportedOrdersError;
  Object? _reportedExpensesError;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Changer de jour renvoie à la vue d'ensemble : le détail affiché ne
  /// correspondrait plus à ce que montre la liste.
  void _setJour(DateTime jour) {
    setState(() {
      _jour = DateTime(jour.year, jour.month, jour.day);
      _detailLivreur = null;
    });
  }

  Future<void> _pickJour() async {
    final today = appToday();
    final picked = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(today.year + 1, 12, 31),
      helpText: 'Jour du bilan',
    );
    if (picked == null || !mounted) return;
    _setJour(picked);
  }

  /// `fetchOrders()` + `fetchDepenses()` du bouton « Rafraîchir » — non
  /// silencieux par défaut ; silencieux pour le tirer-pour-rafraîchir (les
  /// données restent affichées).
  Future<void> _refresh(BilanQuery query, ExpensesFilter filter, {bool silent = false}) async {
    if (!silent) setState(() => _reloading = true);
    try {
      ref.invalidate(bilanOrdersProvider(query));
      if (query.gerant) ref.invalidate(bilanLivreursProvider);
      final Future<void> depenses;
      if (silent) {
        ref.invalidate(expensesProvider(filter));
        depenses = ref.read(expensesProvider(filter).future);
      } else {
        depenses = ref.read(expensesProvider(filter).notifier).refresh();
      }
      await Future.wait<void>([ref.read(bilanOrdersProvider(query).future), depenses]);
    } catch (_) {
      // L'erreur est affichée par ErrorState (rien à montrer) ou par le
      // toast du listener (les données précédentes restent visibles).
    } finally {
      if (mounted && !silent) setState(() => _reloading = false);
    }
  }

  /// Nom d'une ligne : livreur connu, sinon `livreur_name` porté par une de
  /// ses commandes, sinon « Livreur #id » — même cascade que le web.
  String _nomLivreur(String key, List<StaffOption> livreurs, List<Order> traitees) {
    if (key == _kSansLivreur) return 'Retrait au comptoir (sans livreur)';
    for (final l in livreurs) {
      if ('${l.id}' == key && l.fullName.isNotEmpty) return l.fullName;
    }
    for (final o in traitees) {
      if (_cleLivreur(o) == key && (o.livreurName?.isNotEmpty ?? false)) return o.livreurName!;
    }
    return 'Livreur #$key';
  }

  /// Une ligne par livreur ayant travaillé ce jour-là, la plus grosse
  /// recette d'abord.
  List<_LigneLivreur> _lignes(List<Order> traitees, List<LivreurExpense> depenses, List<StaffOption> livreurs) {
    final groupes = <String, List<Order>>{};
    for (final o in traitees) {
      groupes.putIfAbsent(_cleLivreur(o), () => <Order>[]).add(o);
    }
    final lignes = [
      for (final entry in groupes.entries)
        _LigneLivreur(
          key: entry.key,
          nom: _nomLivreur(entry.key, livreurs, traitees),
          livrees: _Totaux.of(entry.value.where((o) => o.statutCourant == OrderStatus.livre).toList()),
          retours: _Totaux.of(entry.value.where((o) => o.statutCourant == OrderStatus.retour).toList()),
          depenses: depenses.where((d) => '${d.livreurId}' == entry.key).toList(),
        ),
    ];
    lignes.sort((a, b) => b.livrees.argent.compareTo(a.livrees.argent));
    return lignes;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    // Web : tant que `userLoading` est vrai, le garde ne s'applique pas et
    // aucune donnée n'est chargée.
    if (auth.status == AuthStatus.loading) {
      return Scaffold(appBar: AppBar(title: const Text('Bilan du jour')), body: const LoadingState());
    }
    if (user == null || !(user.isLivreur || user.isGerant)) return const _AccesRefuse();

    final gerant = user.isGerant;
    final query = BilanQuery(jour: _jour, gerant: gerant);
    final filter = ExpensesFilter.jour(_jour);

    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);
    final ordersAsync = ref.watch(bilanOrdersProvider(query));
    final depensesAsync = ref.watch(expensesProvider(filter));
    final livreurs = gerant ? (ref.watch(bilanLivreursProvider).value ?? const <StaffOption>[]) : const <StaffOption>[];

    // Erreur alors que des données sont déjà affichées (rechargement
    // silencieux) : un toast, la vue précédente reste en place.
    ref.listen<AsyncValue<List<Order>>>(bilanOrdersProvider(query), (previous, next) {
      final error = next.error;
      if (error == null || !next.hasValue || identical(error, _reportedOrdersError)) return;
      _reportedOrdersError = error;
      _snack(ApiClient.messageFromError(error));
    });
    ref.listen<AsyncValue<List<LivreurExpense>>>(expensesProvider(filter), (previous, next) {
      final error = next.error;
      if (error == null || !next.hasValue || identical(error, _reportedExpensesError)) return;
      _reportedExpensesError = error;
      _snack('Dépenses : ${ApiClient.messageFromError(error)}');
    });

    final loading = _reloading || (ordersAsync.isLoading && !ordersAsync.hasValue);
    final Object? erreur = !loading && !ordersAsync.hasValue ? ordersAsync.error : null;
    final orders = ordersAsync.value ?? const <Order>[];
    // Seules les commandes terminées entrent dans un bilan.
    final traitees = orders
        .where((o) => o.statutCourant == OrderStatus.livre || o.statutCourant == OrderStatus.retour)
        .toList();

    final depenses = depensesAsync.value ?? const <LivreurExpense>[];
    final depensesChargement = depensesAsync.isLoading && !depensesAsync.hasValue;
    final Object? depensesErreur = !depensesChargement && !depensesAsync.hasValue ? depensesAsync.error : null;

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final List<Widget> contenu;
    if (!gerant) {
      // Livreur : son propre bilan, directement.
      contenu = [
        _BilanJour(
          orders: traitees,
          loading: loading,
          jour: _jour,
          titreTicket: user.fullName.isNotEmpty ? user.fullName : 'Mon bilan',
          depenses: depenses,
        ),
        const SizedBox(height: 16),
        DepensesDuJour(
          depenses: depenses,
          jour: _jour,
          filter: filter,
          peutDeclarer: true,
          chargement: depensesChargement,
          erreur: depensesErreur,
          onRetry: () => _refresh(query, filter),
        ),
      ];
    } else if (_detailLivreur == null) {
      // Gérant, vue d'ensemble : uniquement la liste des livreurs et leurs totaux.
      final lignes = _lignes(traitees, depenses, livreurs);
      final totalJour = (
        livrees: _Totaux.of(traitees.where((o) => o.statutCourant == OrderStatus.livre).toList()),
        retours: _Totaux.of(traitees.where((o) => o.statutCourant == OrderStatus.retour).toList()),
      );
      contenu = [
        _CompteursJour(livrees: totalJour.livrees, retours: totalJour.retours),
        const SizedBox(height: 16),
        _LivreursCard(
          jour: _jour,
          loading: loading,
          lignes: lignes,
          totalLivrees: totalJour.livrees,
          totalRetours: totalJour.retours,
          totalDepensesValidees: totalDepensesAcceptees(depenses),
          onSelect: (key) => setState(() => _detailLivreur = key),
        ),
      ];
    } else {
      // Gérant, détail d'un livreur : tout le contenu, comme le voit le livreur.
      final key = _detailLivreur!;
      final nom = _nomLivreur(key, livreurs, traitees);
      final ordersDuDetail = traitees.where((o) => _cleLivreur(o) == key).toList();
      final depensesDuDetail = depenses.where((d) => '${d.livreurId}' == key).toList();
      contenu = [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _detailLivreur = null),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Tous les livreurs'),
          ),
        ),
        const SizedBox(height: 8),
        Text(nom, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _BilanJour(
          orders: ordersDuDetail,
          loading: loading,
          jour: _jour,
          titreTicket: nom,
          depenses: depensesDuDetail,
        ),
        const SizedBox(height: 16),
        DepensesDuJour(
          depenses: depensesDuDetail,
          jour: _jour,
          filter: filter,
          peutTrancher: true,
          chargement: depensesChargement,
          erreur: depensesErreur,
          onRetry: () => _refresh(query, filter),
        ),
      ];
    }

    return PopScope(
      // Retour matériel depuis le détail d'un livreur : on revient d'abord à
      // la liste, comme le bouton « Tous les livreurs ».
      canPop: _detailLivreur == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _detailLivreur = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bilan du jour'),
          actions: [
            IconButton(
              tooltip: 'Rafraîchir',
              icon: const Icon(Icons.refresh),
              onPressed: () => _refresh(query, filter),
            ),
          ],
        ),
        body: erreur != null
            ? ErrorState(message: ApiClient.messageFromError(erreur), onRetry: () => _refresh(query, filter))
            : RefreshIndicator(
                onRefresh: () => _refresh(query, filter, silent: true),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(
                      gerant
                          ? 'Montant encaissé par chaque livreur. Cliquez sur un livreur pour voir le détail de ses commandes.'
                          : "Livraisons effectuées et retours d'aujourd'hui — voir le ticket récapitulatif.",
                      style: muted,
                    ),
                    if (gerant) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text('Jour', style: muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _pickJour,
                                icon: const Icon(Icons.event_outlined, size: 18),
                                label: Text(_dayFmt.format(_jour)),
                              ),
                            ),
                          ),
                          // Vider le champ date du web ramène à aujourd'hui.
                          if (_jour != appToday())
                            IconButton(
                              tooltip: "Aujourd'hui",
                              icon: const Icon(Icons.today_outlined),
                              onPressed: () => _setJour(appToday()),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    ...contenu,
                  ],
                ),
              ),
      ),
    );
  }
}

/// Écran « Accès refusé » du web : rendu à la place de tout le reste dès que
/// l'utilisateur n'est ni livreur ni gérant (aucune donnée n'est chargée).
class _AccesRefuse extends StatelessWidget {
  const _AccesRefuse();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bilan du jour')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_maybe_outlined, size: 48, color: Color(0xFFEF4444)),
                  const SizedBox(height: 16),
                  Text(
                    'Accès refusé',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cette page est réservée au livreur et au gérant.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bilan d'un jour pour un périmètre donné (un livreur, ou tous) —
/// `BilanJour` du web : le ticket récapitulatif, puis les livraisons
/// effectuées et les retours. Sur un écran large, le ticket prend la colonne
/// de droite (300 px) ; sur mobile il passe en tête.
class _BilanJour extends StatelessWidget {
  const _BilanJour({
    required this.orders,
    required this.loading,
    required this.jour,
    required this.titreTicket,
    required this.depenses,
  });

  final List<Order> orders;
  final bool loading;
  final DateTime jour;
  final String titreTicket;

  /// Dépenses du livreur pour ce jour, tous statuts confondus.
  final List<LivreurExpense> depenses;

  @override
  Widget build(BuildContext context) {
    // Seules les dépenses ACCEPTÉES par le gérant viennent diminuer l'argent
    // remis (§ demande) : une dépense en attente ou refusée ne doit pas
    // fausser le compte.
    final depensesAcceptees = depenses.where((d) => d.estAcceptee).toList();
    final totalDepenses = totalDepensesAcceptees(depenses);
    // Les retours ne sont volontairement pas additionnés aux livrées (§
    // demande) — un colis retourné n'a rien fait encaisser au livreur.
    final livrees = orders.where((o) => o.statutCourant == OrderStatus.livre).toList();
    final retours = orders.where((o) => o.statutCourant == OrderStatus.retour).toList();

    // Le ticket est toujours rendu, même pendant le chargement (0 / 0 Ar).
    final ticket = _TicketCard(
      jour: jour,
      titre: titreTicket,
      livrees: _Totaux.of(livrees),
      retours: _Totaux.of(retours),
      depensesAcceptees: depensesAcceptees,
      totalDepenses: totalDepenses,
    );
    final scheme = Theme.of(context).colorScheme;
    final listes = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ListeCard(
          icon: Icons.check_circle_outline,
          titre: 'Livraisons effectuées (${livrees.length})',
          loading: loading,
          orders: livrees,
          vide: 'Aucune livraison effectuée ce jour-là.',
        ),
        const SizedBox(height: 16),
        _ListeCard(
          icon: Icons.undo,
          iconColor: scheme.error,
          titre: 'Retours (${retours.length})',
          description: "Colis rapportés — rien n'a été encaissé, ces montants ne sont pas comptés dans le total du ticket.",
          loading: loading,
          orders: retours,
          vide: 'Aucun retour ce jour-là.',
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: listes),
              const SizedBox(width: 16),
              SizedBox(width: 300, child: ticket),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [ticket, const SizedBox(height: 16), listes],
        );
      },
    );
  }
}

/// Carte « Livraisons effectuées (n) » / « Retours (n) » : en-tête, état de
/// chargement, état vide, ou une carte par commande.
class _ListeCard extends StatelessWidget {
  const _ListeCard({
    required this.icon,
    this.iconColor,
    required this.titre,
    this.description,
    required this.loading,
    required this.orders,
    required this.vide,
  });

  final IconData icon;
  final Color? iconColor;
  final String titre;
  final String? description;
  final bool loading;
  final List<Order> orders;
  final String vide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(titre, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(description!, style: muted),
            ],
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (orders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(vide, style: muted)),
              )
            else
              for (final o in orders) _BilanOrderCard(order: o),
          ],
        ),
      ),
    );
  }
}

/// Une ligne du tableau web (`OrdersTable`) : type / sous-type du premier
/// article, tous les produits, date, client, adresse, prix, frais et argent
/// encaissé (0 Ar + « déjà payé » pour une commande réglée d'avance).
class _BilanOrderCard extends StatelessWidget {
  const _BilanOrderCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final typeLabel = [
      firstItem?.categoryName,
      firstItem?.typeName,
    ].where((e) => e != null && e.isNotEmpty).join(' • ');
    final adresse = order.adresseLivraison;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w700))),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(arFmt(_argentEncaisse(order)), style: const TextStyle(fontWeight: FontWeight.w700)),
                    // Payée d'avance -> 0 Ar : le livreur n'a rien encaissé.
                    if (_estPrepayee(order))
                      const Text('déjà payé', style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(typeLabel.isEmpty ? '-' : typeLabel, style: muted),
            for (final item in order.items)
              Text(
                '• ${item.libelle} x${item.quantite}',
                style: item.retourne
                    ? TextStyle(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant)
                    : null,
              ),
            const SizedBox(height: 4),
            Text(
              '${order.clientNom} · ${adresse != null && adresse.isNotEmpty ? adresse : DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)}',
              style: muted,
            ),
            Text(
              order.dateCommande != null ? _hourFmt.format(appLocal(order.dateCommande!)) : '-',
              style: muted,
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Prix ${arFmt(_prixProduit(order))}', style: muted),
                Text('Frais ${arFmt(order.fraisLivraison ?? 0)}', style: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ticket de caisse récapitulatif — police à chasse fixe, sections
/// séparées par des pointillés : LIVRAISONS EFFECTUÉES, DÉPENSES VALIDÉES
/// (si le gérant en a accepté) avec NET À REMETTRE, puis RETOURS.
class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.jour,
    required this.titre,
    required this.livrees,
    required this.retours,
    required this.depensesAcceptees,
    required this.totalDepenses,
  });

  final DateTime jour;
  final String titre;
  final _Totaux livrees;
  final _Totaux retours;
  final List<LivreurExpense> depensesAcceptees;
  final double totalDepenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const mono = TextStyle(fontFamily: 'monospace');
    final sectionStyle = theme.textTheme.labelMedium?.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );

    Widget ligne(String label, String valeur, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: mono.copyWith(fontWeight: bold ? FontWeight.w700 : null, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            valeur,
            style: mono.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color),
          ),
        ],
      ),
    );

    Widget pointilles() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -',
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: mono.copyWith(color: scheme.outlineVariant),
      ),
    );

    const vert = Color(0xFF059669);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 4),
                  Text(
                    'BILAN DU JOUR',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(_dayFmt.format(jour), style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                  Text(
                    titre,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            pointilles(),
            Text('LIVRAISONS EFFECTUÉES', style: sectionStyle),
            const SizedBox(height: 4),
            ligne('Nombre', '${livrees.count}'),
            ligne('Total produits', arFmt(livrees.prix)),
            ligne('Total frais livraison', arFmt(livrees.frais)),
            if (livrees.prepayeCount > 0)
              ligne("Dont payé d'avance (${livrees.prepayeCount})", '-${arFmt(livrees.prepaye)}', color: vert),
            pointilles(),
            ligne('TOTAL ARGENT', arFmt(livrees.argent), bold: true),
            if (depensesAcceptees.isNotEmpty) ...[
              pointilles(),
              Text('DÉPENSES VALIDÉES', style: sectionStyle),
              const SizedBox(height: 4),
              for (final d in depensesAcceptees) ligne(d.libelleAvecQuantite, '-${arFmt(d.montant)}'),
              pointilles(),
              ligne('NET À REMETTRE', arFmt(livrees.argent - totalDepenses), bold: true),
            ],
            pointilles(),
            Text('RETOURS (hors total ci-dessus)', style: sectionStyle),
            const SizedBox(height: 4),
            ligne('Nombre', '${retours.count}'),
            ligne('Total produits', arFmt(retours.prix)),
            ligne('Total frais livraison', arFmt(retours.frais)),
            if (retours.prepayeCount > 0)
              ligne("Dont payé d'avance (${retours.prepayeCount})", '-${arFmt(retours.prepaye)}', color: vert),
            pointilles(),
            ligne('TOTAL NON ENCAISSÉ', arFmt(retours.argent), bold: true, color: scheme.error),
          ],
        ),
      ),
    );
  }
}

/// Les trois compteurs du gérant : livraisons effectuées, total encaissé,
/// retours (en rouge).
class _CompteursJour extends StatelessWidget {
  const _CompteursJour({required this.livrees, required this.retours});
  final _Totaux livrees;
  final _Totaux retours;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final livraisons = _CompteurCard(label: 'Livraisons effectuées', valeur: '${livrees.count}');
    final encaisse = _CompteurCard(label: 'Total encaissé', valeur: arFmt(livrees.argent));
    final nbRetours = _CompteurCard(label: 'Retours', valeur: '${retours.count}', color: scheme.error);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 480) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: livraisons),
                const SizedBox(width: 8),
                Expanded(child: encaisse),
                const SizedBox(width: 8),
                Expanded(child: nbRetours),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: livraisons),
                  const SizedBox(width: 8),
                  Expanded(child: nbRetours),
                ],
              ),
            ),
            const SizedBox(height: 8),
            encaisse,
          ],
        );
      },
    );
  }
}

class _CompteurCard extends StatelessWidget {
  const _CompteurCard({required this.label, required this.valeur, this.color});
  final String label;
  final String valeur;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valeur,
                maxLines: 1,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte « Livreurs du jj/mm/aaaa » du gérant : une ligne par livreur
/// (livraisons, retours, produits, frais, dépenses, encaissé), la ligne
/// « Total du jour », et le clic qui ouvre le détail.
class _LivreursCard extends StatelessWidget {
  const _LivreursCard({
    required this.jour,
    required this.loading,
    required this.lignes,
    required this.totalLivrees,
    required this.totalRetours,
    required this.totalDepensesValidees,
    required this.onSelect,
  });

  final DateTime jour;
  final bool loading;
  final List<_LigneLivreur> lignes;
  final _Totaux totalLivrees;
  final _Totaux totalRetours;

  /// Somme des dépenses ACCEPTÉES de tous les livreurs ce jour-là.
  final double totalDepensesValidees;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_outline, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Livreurs du ${_dayFmt.format(jour)}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Cliquez sur une ligne pour ouvrir le détail : toutes les commandes, tous les produits et tous les totaux.',
                  style: muted,
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (lignes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Aucune livraison ni retour ce jour-là.', style: muted)),
            )
          else ...[
            const Divider(height: 1),
            for (final l in lignes) ...[
              _LigneLivreurTile(ligne: l, onTap: () => onSelect(l.key)),
              const Divider(height: 1),
            ],
            _TotalJourTile(
              livrees: totalLivrees,
              retours: totalRetours,
              depensesValidees: totalDepensesValidees,
            ),
          ],
        ],
      ),
    );
  }
}

/// Une statistique d'une ligne livreur : libellé, valeur, et un
/// complément facultatif (« n à valider », « dont … déjà payé »).
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.valeur, this.color, this.bold = false, this.sub, this.subColor});
  final String label;
  final String valeur;
  final Color? color;
  final bool bold;
  final String? sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        Text(valeur, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
        if (sub != null) Text(sub!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: subColor)),
      ],
    );
  }
}

const Color _kAmbre = Color(0xFFD97706);
const Color _kVert = Color(0xFF059669);

/// Ligne « Dépenses » d'un livreur : « - montant validé » et/ou « n à
/// valider », « - » s'il n'a rien déclaré.
({String valeur, String? sub}) _depensesCellule(List<LivreurExpense> sien) {
  if (sien.isEmpty) return (valeur: '-', sub: null);
  final valide = totalDepensesAcceptees(sien);
  final attente = nbDepensesEnAttente(sien);
  return (
    valeur: valide > 0 ? '-${arFmt(valide)}' : '-',
    sub: attente > 0 ? '$attente à valider' : null,
  );
}

class _LigneLivreurTile extends StatelessWidget {
  const _LigneLivreurTile({required this.ligne, required this.onTap});
  final _LigneLivreur ligne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = ligne;
    final depenses = _depensesCellule(l.depenses);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.nom, style: const TextStyle(fontWeight: FontWeight.w600))),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Stat(label: 'Livraisons', valeur: '${l.livrees.count}')),
                Expanded(
                  child: _Stat(
                    label: 'Retours',
                    valeur: l.retours.count > 0 ? '${l.retours.count}' : '-',
                    color: scheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Stat(label: 'Total produits', valeur: arFmt(l.livrees.prix))),
                Expanded(child: _Stat(label: 'Total frais', valeur: arFmt(l.livrees.frais))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Dépenses',
                    valeur: depenses.valeur,
                    sub: depenses.sub,
                    subColor: _kAmbre,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Total encaissé',
                    valeur: arFmt(l.livrees.argent),
                    bold: true,
                    sub: l.livrees.prepayeCount > 0 ? 'dont ${arFmt(l.livrees.prepaye)} déjà payé' : null,
                    subColor: _kVert,
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

/// Ligne « Total du jour » de la vue d'ensemble.
class _TotalJourTile extends StatelessWidget {
  const _TotalJourTile({required this.livrees, required this.retours, required this.depensesValidees});
  final _Totaux livrees;
  final _Totaux retours;
  final double depensesValidees;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total du jour', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Stat(label: 'Livraisons', valeur: '${livrees.count}', bold: true)),
              Expanded(
                child: _Stat(
                  label: 'Retours',
                  valeur: retours.count > 0 ? '${retours.count}' : '-',
                  color: scheme.error,
                  bold: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Stat(label: 'Total produits', valeur: arFmt(livrees.prix), bold: true)),
              Expanded(child: _Stat(label: 'Total frais', valeur: arFmt(livrees.frais), bold: true)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  label: 'Dépenses',
                  valeur: depensesValidees > 0 ? '-${arFmt(depensesValidees)}' : '-',
                  bold: true,
                ),
              ),
              Expanded(child: _Stat(label: 'Total encaissé', valeur: arFmt(livrees.argent), bold: true)),
            ],
          ),
        ],
      ),
    );
  }
}
