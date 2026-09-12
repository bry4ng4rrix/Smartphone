import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/app_time.dart';
import '../core/permissions.dart';
import '../data/repositories/reports_repository.dart';
import '../models/reports.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

/// État de l'écran Rapports — portage de `frontend/app/(app)/reports/page.tsx`.
///
/// La page web tient trois états locaux (`periode`, `dateFrom`, `dateTo`) et
/// recharge `GET /api/orders/reports/` à chaque changement de bornes ; ici :
///
/// * [reportsFilterProvider] — le sélecteur (7 / 30 / 90 jours ou bornes
///   libres) ;
/// * [reportsProvider] — le rapport d'une période, famille paramétrée par
///   [ReportsRange] (`date_from`, `date_to`) : changer de bornes instancie un
///   nouveau chargement, comme `charger()` côté web ;
/// * [reportsAccessProvider] — le garde « réservé au gérant ».
final reportsRepositoryProvider = Provider((ref) => ReportsRepository());

// ---------------------------------------------------------------------------
// Accès
// ---------------------------------------------------------------------------

/// Message de la carte « Accès refusé » du web.
const String kReportsAccesRefuseMessage = 'Les rapports sont réservés au gérant.';

/// Levée (sans appel réseau) quand le compte connecté n'est pas gérant : le
/// serveur répondrait 403 de toute façon (`IsGerant`, orders/reports.py).
/// `toString()` renvoie le message du web pour qu'un
/// `ApiClient.messageFromError` l'affiche tel quel.
class ReportsAccesRefuseException implements Exception {
  const ReportsAccesRefuseException();

  String get message => kReportsAccesRefuseMessage;

  @override
  String toString() => message;
}

/// `const { isGerant, loading: userLoading } = useCurrentUser()` vu par la
/// page : tant que [loading] est vrai rien n'est tranché (le web affiche les
/// squelettes) ; ensuite [isGerant] décide entre le rapport et la carte
/// « Accès refusé — Les rapports sont réservés au gérant. ».
final reportsAccessProvider = Provider<({bool loading, bool isGerant})>((ref) {
  final auth = ref.watch(authProvider);
  return (
    loading: auth.status == AuthStatus.loading,
    isGerant: auth.user?.isGerant ?? false,
  );
});

// ---------------------------------------------------------------------------
// Sélecteur de période
// ---------------------------------------------------------------------------

/// `PERIODES` du web : 7 / 30 / 90 jours, libellés « 7 jours »…
const List<int> kReportsPeriods = [7, 30, 90];

/// Libellé du bouton de période : « 7 jours », « 30 jours », « 90 jours ».
String reportsPeriodeLabel(int jours) => '$jours jours';

/// `depuis(jours)` du web : recule de `jours` jours depuis aujourd'hui, en
/// date d'Antananarivo, aujourd'hui compris (30 jours = J−29 … J).
DateTime reportsDepuis(int jours) {
  final today = appToday();
  return DateTime(today.year, today.month, today.day - (jours - 1));
}

/// Bornes envoyées au serveur — clé de famille de [reportsProvider]. Deux
/// bornes qui tombent le même jour calendaire sont la même clé (l'heure est
/// ignorée).
class ReportsRange {
  ReportsRange({required DateTime from, required DateTime to})
      : from = DateTime(from.year, from.month, from.day),
        to = DateTime(to.year, to.month, to.day);

  /// `ReportsRange` des `jours` derniers jours, aujourd'hui compris.
  factory ReportsRange.derniersJours(int jours) => ReportsRange(from: reportsDepuis(jours), to: appToday());

  final DateTime from;
  final DateTime to;

  /// `date_from` / `date_to` tels qu'envoyés (`YYYY-MM-DD`).
  String get fromParam => formatReportsDate(from);
  String get toParam => formatReportsDate(to);

  @override
  bool operator ==(Object other) =>
      other is ReportsRange && other.fromParam == fromParam && other.toParam == toParam;

  @override
  int get hashCode => Object.hash(fromParam, toParam);

  @override
  String toString() => 'ReportsRange($fromParam → $toParam)';
}

/// Le sélecteur de la page : `periode` (7 | 30 | 90, ou 0 = bornes libres
/// après saisie manuelle d'une date), `dateFrom`, `dateTo`.
class ReportsFilter {
  ReportsFilter({required this.periode, required DateTime dateFrom, required DateTime dateTo})
      : dateFrom = DateTime(dateFrom.year, dateFrom.month, dateFrom.day),
        dateTo = DateTime(dateTo.year, dateTo.month, dateTo.day);

  /// `choisirPeriode(jours)` : bouton de période — bornes recalculées
  /// depuis aujourd'hui.
  factory ReportsFilter.derniersJours(int jours) =>
      ReportsFilter(periode: jours, dateFrom: reportsDepuis(jours), dateTo: appToday());

  /// Bouton de période actif (variant `default` sur le web), 0 quand
  /// l'utilisateur a touché une borne à la main (aucun bouton actif).
  final int periode;
  final DateTime dateFrom;
  final DateTime dateTo;

  /// Aucun des trois boutons n'est actif : les bornes viennent des champs
  /// « Du » / « Au ».
  bool get bornesLibres => periode == 0;

  /// `periode === p.jours` — le bouton à dessiner en plein.
  bool periodeActive(int jours) => periode == jours;

  /// Clé du rapport à charger pour ces bornes.
  ReportsRange get range => ReportsRange(from: dateFrom, to: dateTo);

  @override
  bool operator ==(Object other) =>
      other is ReportsFilter && other.periode == periode && other.range == range;

  @override
  int get hashCode => Object.hash(periode, range);
}

/// Sélecteur de période. Défaut : 30 jours, comme `useState(30)` du web ;
/// autoDispose pour repartir des 30 jours à chaque retour sur l'écran (état
/// de composant côté web, non persisté).
///
/// Aucune validation de bornes, comme sur le web : une période inversée
/// (« Du » après « Au ») donne simplement un rapport vide côté serveur.
class ReportsFilterNotifier extends Notifier<ReportsFilter> {
  @override
  ReportsFilter build() => ReportsFilter.derniersJours(30);

  /// Boutons « 7 jours » / « 30 jours » / « 90 jours ».
  void choisirPeriode(int jours) => state = ReportsFilter.derniersJours(jours);

  /// Champ « Du » : la période passe en bornes libres (`setPeriode(0)`).
  void setDateFrom(DateTime dateFrom) =>
      state = ReportsFilter(periode: 0, dateFrom: dateFrom, dateTo: state.dateTo);

  /// Champ « Au » : idem.
  void setDateTo(DateTime dateTo) =>
      state = ReportsFilter(periode: 0, dateFrom: state.dateFrom, dateTo: dateTo);
}

final reportsFilterProvider =
    NotifierProvider.autoDispose<ReportsFilterNotifier, ReportsFilter>(ReportsFilterNotifier.new);

// ---------------------------------------------------------------------------
// Rapport d'une période
// ---------------------------------------------------------------------------

/// Politique de nouvel essai de [reportsProvider].
///
/// Riverpod 3 rejoue par défaut TOUTE exception levée par `build` dix fois
/// avec attente exponentielle : l'écran resterait en chargement près de
/// 40 s avant de montrer quoi que ce soit. Ici un refus est définitif et
/// s'affiche tout de suite — accès réservé au gérant, 403 du serveur, bornes
/// illisibles (400)… — et seule une coupure réseau est retentée, deux fois
/// et vite (200 ms puis 400 ms), avant de rendre la main au bouton
/// « Réessayer ».
Duration? reportsRetry(int retryCount, Object error) {
  if (error is ReportsAccesRefuseException) return null;
  if (!ApiClient.isConnectivityError(error)) return null;
  return ProviderContainer.defaultRetry(retryCount, error, maxRetries: 2);
}

/// Rapport de la période [range] — `djangoClient.reports.get(dateFrom, dateTo)`.
///
/// * Chargé UNIQUEMENT pour un gérant (`if (!userLoading && isGerant)
///   charger()` côté web) : un autre compte reçoit
///   [ReportsAccesRefuseException] sans appel réseau ; un compte encore
///   inconnu (auth en cours) laisse le serveur trancher. Le rôle qui devient
///   connu, ou qui change, relance le chargement.
/// * Événement temps réel (`useRealtimeRefresh(['order',
///   'order_status_history'], () => charger(true))`) : rechargement
///   SILENCIEUX — l'état reste un `AsyncData` (avec `isRefreshing`), l'écran
///   continue d'afficher le rapport courant, puis reçoit le nouveau.
/// * [refresh] (bouton « Actualiser », tirer pour rafraîchir) : rechargement
///   NON silencieux, comme `charger()` sans argument — l'état devient un
///   `AsyncLoading` (l'ancienne valeur reste lisible dans `value` pour qui la
///   veut, mais `when()` par défaut et un `switch` sur `AsyncData` affichent
///   le chargement).
/// * Changer de bornes instancie un autre membre de la famille : chargement
///   puis nouveau rapport, comme le web.
class ReportsNotifier extends AsyncNotifier<ReportsData> {
  ReportsNotifier(this.range);

  final ReportsRange range;
  late final _repo = ref.read(reportsRepositoryProvider);

  Future<ReportsData> _charger() async {
    final user = ref.read(authProvider).user;
    if (user != null && !user.isGerant) throw const ReportsAccesRefuseException();
    return _repo.fetch(dateFrom: range.from, dateTo: range.to);
  }

  @override
  Future<ReportsData> build() {
    // Temps réel : `invalidateSelf` (et non `watch`) pour que le rechargement
    // soit un rafraîchissement transparent — la valeur affichée ne bouge pas
    // tant que la nouvelle n'est pas arrivée.
    ref.listen(realtimeTickProvider, (previous, next) => ref.invalidateSelf());
    // Rôle connu / changé : rechargement, sans réagir aux autres mises à jour
    // du profil.
    ref.watch(authProvider.select((a) => a.user?.isGerant));
    return _charger();
  }

  /// Bouton « Actualiser » (et tirer pour rafraîchir) : rechargement NON
  /// silencieux.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_charger);
  }
}

/// `reportsProvider(filter.range)` — un rapport par période. autoDispose : le
/// rapport est un instantané, jeté dès que plus aucun écran ne le regarde.
final reportsProvider = AsyncNotifierProvider.autoDispose.family<ReportsNotifier, ReportsData, ReportsRange>(
  ReportsNotifier.new,
  retry: reportsRetry,
);

/// Rapport de la période SÉLECTIONNÉE — `reportsProvider(filter.range)` en
/// un seul `watch` pour l'écran. Pour recharger :
/// `ref.read(reportsProvider(ref.read(reportsFilterProvider).range).notifier).refresh()`.
final currentReportsProvider = Provider.autoDispose<AsyncValue<ReportsData>>((ref) {
  final range = ref.watch(reportsFilterProvider.select((f) => f.range));
  return ref.watch(reportsProvider(range));
});
