import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../core/permissions.dart';
import '../data/repositories/reports_repository.dart';
import '../models/reports.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

/// État du centre de rapports (tableau de bord du gérant) — portage de
/// `frontend/app/(app)/dashboard/page.tsx` et de
/// `components/reports/use-report.ts` :
///
/// * [reportsFilterProvider] — préréglage / bornes / granularité ;
/// * [activeSectionProvider] — l'onglet affiché (`?tab=` de l'URL) ;
/// * [reportsProvider] — le cache mémoire par (section, paramètres) ;
/// * [reportsAccessProvider] — le garde « réservé au gérant » ;
/// * [reportsRealtimeProvider] — invalidation sur événement temps réel.
final reportsRepositoryProvider = Provider((ref) => ReportsRepository());

// ---------------------------------------------------------------------------
// Accès
// ---------------------------------------------------------------------------

/// Message de la carte « Accès refusé » du web.
const String kReportsAccesRefuseMessage = 'Accès refusé — le tableau de bord est réservé au gérant.';

/// Levée (sans appel réseau) quand le compte connecté n'est pas gérant : le
/// serveur répondrait 403 de toute façon (`IsGerant`, orders/reporting.py).
/// `toString()` renvoie le message du web pour qu'un
/// `ApiClient.messageFromError` l'affiche tel quel.
class ReportsAccesRefuse implements Exception {
  const ReportsAccesRefuse();

  String get message => kReportsAccesRefuseMessage;

  @override
  String toString() => message;
}

/// `const { isGerant, loading: userLoading } = useCurrentUser()` vu par la
/// page : tant que [loading] est vrai rien n'est tranché (squelettes) ;
/// ensuite [isGerant] décide entre le tableau de bord et « Accès refusé ».
final reportsAccessProvider = Provider<({bool loading, bool isGerant})>((ref) {
  final auth = ref.watch(authProvider);
  return (
    loading: auth.status == AuthStatus.loading,
    isGerant: auth.user?.isGerant ?? false,
  );
});

// ---------------------------------------------------------------------------
// Filtres
// ---------------------------------------------------------------------------

/// `Filtres` du web : préréglage, bornes personnalisées (`AAAA-MM-JJ`, vides
/// tant que l'utilisateur n'a rien saisi), granularité (`null` =
/// « Automatique »). [reload] est le compteur `_r` du web : incrémenté par le
/// bouton Actualiser pour forcer une nouvelle clé de cache.
class ReportsFilter {
  const ReportsFilter({
    this.preset = ReportPreset.month,
    this.customFrom = '',
    this.customTo = '',
    this.granularity,
    this.reload = 0,
  });

  final ReportPreset preset;
  final String customFrom;
  final String customTo;
  final ReportGranularity? granularity;
  final int reload;

  /// `periodeDepuisPreset(filtres.preset, filtres.custom)`.
  ReportPeriod get period => periodeDepuisPreset(preset, customFrom: customFrom, customTo: customTo);

  /// Granularité envoyée au serveur : la valeur choisie, sinon l'automatique.
  ReportGranularity get granularityEffective => granularity ?? granulariteAuto(period);

  ReportsFilter copyWith({
    ReportPreset? preset,
    String? customFrom,
    String? customTo,
    ReportGranularity? granularity,
    bool clearGranularity = false,
    int? reload,
  }) =>
      ReportsFilter(
        preset: preset ?? this.preset,
        customFrom: customFrom ?? this.customFrom,
        customTo: customTo ?? this.customTo,
        granularity: clearGranularity ? null : (granularity ?? this.granularity),
        reload: reload ?? this.reload,
      );

  @override
  bool operator ==(Object other) =>
      other is ReportsFilter &&
      other.preset == preset &&
      other.customFrom == customFrom &&
      other.customTo == customTo &&
      other.granularity == granularity &&
      other.reload == reload;

  @override
  int get hashCode => Object.hash(preset, customFrom, customTo, granularity, reload);
}

/// Filtres communs à toutes les sections. NON autoDispose : comme l'onglet,
/// l'état survit à un aller-retour vers un autre écran. Défaut : « Ce mois »,
/// granularité automatique (`useState` de la page web).
class ReportsFilterNotifier extends Notifier<ReportsFilter> {
  @override
  ReportsFilter build() => const ReportsFilter();

  void setPreset(ReportPreset preset) => state = state.copyWith(preset: preset);

  /// Champ « Du » : passe en période personnalisée en reprenant l'autre borne
  /// de la période courante (`custom.to = preset === 'custom' ? custom.to :
  /// period.to`).
  void setCustomFrom(String from) {
    final to = state.preset == ReportPreset.custom ? state.customTo : state.period.to;
    state = state.copyWith(preset: ReportPreset.custom, customFrom: from, customTo: to);
  }

  /// Champ « Au » : idem.
  void setCustomTo(String to) {
    final from = state.preset == ReportPreset.custom ? state.customFrom : state.period.from;
    state = state.copyWith(preset: ReportPreset.custom, customFrom: from, customTo: to);
  }

  /// Select « Granularité » — `null` = « Automatique ».
  void setGranularity(ReportGranularity? g) =>
      state = g == null ? state.copyWith(clearGranularity: true) : state.copyWith(granularity: g);

  /// `setRechargement((n) => n + 1)` : nouvelle clé de cache.
  void bumpReload() => state = state.copyWith(reload: state.reload + 1);
}

final reportsFilterProvider = NotifierProvider<ReportsFilterNotifier, ReportsFilter>(ReportsFilterNotifier.new);

/// L'onglet affiché — équivalent du `?tab=` de l'URL web, conservé entre
/// deux visites de l'écran.
class ActiveSectionNotifier extends Notifier<ReportSection> {
  @override
  ReportSection build() => ReportSection.overview;

  void set(ReportSection s) => state = s;
}

final activeSectionProvider = NotifierProvider<ActiveSectionNotifier, ReportSection>(ActiveSectionNotifier.new);

/// Paramètres de requête propres à une section (`dormant_days` du rapport
/// Stock, `platform` du rapport Marketing…), tenus ici plutôt que dans
/// l'état local de la section : le tableau de bord reconstruit ainsi la
/// requête exacte de l'onglet affiché (impression, indicateur de
/// chargement). Une section les lit avec `ref.watch(reportExtrasProvider(
/// ReportSection.x))` et les modifie avec `ref.read(reportExtrasProvider(
/// ReportSection.x).notifier).set(...)`. Conservés entre deux visites.
class ReportExtrasNotifier extends Notifier<Map<String, String>> {
  ReportExtrasNotifier(this.section);

  final ReportSection section;

  /// Valeurs initiales : la section Stock envoie toujours `dormant_days`
  /// (`useState(30)` de section-stock.tsx, `{ ...params, dormant_days: jours }`),
  /// les autres n'ont pas de paramètre propre au départ (`platform` du
  /// Marketing est absent pour « Toutes plateformes »).
  @override
  Map<String, String> build() => switch (section) {
        ReportSection.stock => const {'dormant_days': '30'},
        _ => const {},
      };

  void set(String cle, String? valeur) {
    final next = Map<String, String>.from(state);
    if (valeur == null || valeur.isEmpty) {
      next.remove(cle);
    } else {
      next[cle] = valeur;
    }
    state = Map.unmodifiable(next);
  }
}

final reportExtrasProvider =
    NotifierProvider.family<ReportExtrasNotifier, Map<String, String>, ReportSection>(ReportExtrasNotifier.new);

// ---------------------------------------------------------------------------
// Requêtes et cache par section
// ---------------------------------------------------------------------------

/// Clé du cache mémoire du web (`${section}:${JSON.stringify(params)}`) :
/// une section et ses paramètres de requête, comparés par valeur.
class ReportRequest {
  ReportRequest({required this.section, required Map<String, String> params})
      : params = Map.unmodifiable(Map.fromEntries(params.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));

  /// Paramètres communs (`date_from`, `date_to`, `prev_from`, `prev_to`,
  /// `granularity`, `_r` s'il y a eu un rechargement manuel) + [extra]
  /// propres à la section (`dormant_days`, `platform`…).
  factory ReportRequest.pour(ReportSection section, ReportsFilter filter, {Map<String, String> extra = const {}}) {
    final p = filter.period;
    return ReportRequest(section: section, params: {
      'date_from': p.from,
      'date_to': p.to,
      'prev_from': p.prevFrom,
      'prev_to': p.prevTo,
      'granularity': filter.granularityEffective.key,
      if (filter.reload > 0) '_r': '${filter.reload}',
      ...extra,
    });
  }

  final ReportSection section;
  final Map<String, String> params;

  String get _cle => '${section.key}:${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';

  @override
  bool operator ==(Object other) => other is ReportRequest && other._cle == _cle;

  @override
  int get hashCode => _cle.hashCode;

  @override
  String toString() => 'ReportRequest($_cle)';
}

/// `CACHE_MAX = 60` de use-report.ts : nombre maximal de réponses gardées en
/// mémoire ; au-delà, la plus ancienne est libérée.
const int kReportsCacheMax = 60;

/// Entrées du cache, de la plus ancienne à la plus récente (ordre d'insertion
/// d'un `LinkedHashMap`) : chaque lien maintient en vie un membre de
/// [reportsProvider] qui n'est plus observé.
final Map<ReportRequest, KeepAliveLink> _cacheLinks = <ReportRequest, KeepAliveLink>{};

void _retenir(ReportRequest request, KeepAliveLink link) {
  _cacheLinks.remove(request);
  _cacheLinks[request] = link;
  while (_cacheLinks.length > kReportsCacheMax) {
    final plusAncienne = _cacheLinks.keys.first;
    _cacheLinks.remove(plusAncienne)?.close();
  }
}

/// Réponse brute d'une section pour une requête donnée — le cache mémoire du
/// web (`cache.set(k, res)` seulement en cas de succès, 60 entrées au plus) :
/// un membre non observé reste en vie tant qu'il est dans le cache, donc
/// revenir sur un onglet déjà consulté est instantané ; une erreur n'est pas
/// conservée (nouvelle tentative à la prochaine ouverture, comme le web).
///
/// * Pas d'appel réseau pour un compte qui n'est pas gérant :
///   [ReportsAccesRefuse] immédiate.
/// * [refresh] : rechargement NON silencieux (l'état repasse en chargement).
/// * [refreshSilencieux] : garde la valeur affichée pendant le rechargement.
class ReportSectionNotifier extends AsyncNotifier<Map<String, dynamic>> {
  ReportSectionNotifier(this.request);

  final ReportRequest request;

  Future<Map<String, dynamic>> _charger() async {
    final user = ref.read(authProvider).user;
    if (user != null && !user.isGerant) throw const ReportsAccesRefuse();
    return ref.read(reportsRepositoryProvider).section(request.section, request.params);
  }

  @override
  Future<Map<String, dynamic>> build() async {
    // Invalidation ou libération : l'entrée quitte le cache.
    ref.onDispose(() => _cacheLinks.remove(request));
    final data = await _charger();
    if (ref.mounted) _retenir(request, ref.keepAlive());
    return data;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_charger);
  }

  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(_charger);
  }
}

/// `reportsProvider(ReportRequest.pour(section, filter))` — une entrée de
/// cache par (section, paramètres). Pas de nouvel essai automatique : un refus
/// (403, accès réservé) ou une coupure s'affichent tout de suite avec le
/// bouton Actualiser pour relancer.
final reportsProvider =
    AsyncNotifierProvider.autoDispose.family<ReportSectionNotifier, Map<String, dynamic>, ReportRequest>(
  ReportSectionNotifier.new,
  retry: (_, _) => null,
);

/// `invalidateReports()` du web : vide tout le cache. Les entrées observées
/// se rechargent silencieusement (valeur conservée pendant le rechargement),
/// les autres sont libérées (rechargées à leur prochaine ouverture).
void invalidateReports(Ref ref) => ref.invalidate(reportsProvider);

/// Variante pour les widgets.
void invalidateReportsFromWidget(WidgetRef ref) => ref.invalidate(reportsProvider);

/// Bouton « Actualiser » (`recharger()` du web) : cache vidé + nouvelle clé
/// (`_r`), donc chargement NON silencieux de la section affichée.
void rechargerReports(WidgetRef ref) {
  ref.invalidate(reportsProvider);
  ref.read(reportsFilterProvider.notifier).bumpReload();
}

// ---------------------------------------------------------------------------
// Temps réel
// ---------------------------------------------------------------------------

/// `useRealtimeRefresh(['order', 'order_status_history', 'stock_movement',
/// 'caisse_movement'], …)` de use-report.ts : une commande ou un mouvement
/// modifié ailleurs vide le cache et recharge SILENCIEUSEMENT la section
/// affichée (les autres à leur prochaine ouverture). Débordement de 400 ms
/// pour grouper les rafales d'événements. À `watch`er tant que le tableau de
/// bord est affiché.
final reportsRealtimeProvider = Provider.autoDispose<void>((ref) {
  Timer? timer;
  ref.listen(realtimeTickProvider, (previous, next) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 400), () => ref.invalidate(reportsProvider));
  });
  ref.onDispose(() => timer?.cancel());
});
