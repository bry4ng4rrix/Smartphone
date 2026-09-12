import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/permissions.dart';
import '../data/repositories/caisse_repository.dart';
import '../models/caisse.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

final caisseRepositoryProvider = Provider((ref) => CaisseRepository());

/// Erreur métier locale (validation avant appel réseau) — `toString()` rend
/// le message nu pour que `ApiClient.messageFromError` l'affiche tel quel.
class CaisseError implements Exception {
  const CaisseError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Magasin choisi par un ADMIN dans la barre « Magasin : » de la page —
/// `selectedMagasinId` du web : aucune présélection au chargement (l'admin
/// n'a pas de magasin propre et doit en choisir un). Remis à `null` à chaque
/// changement de compte pour ne jamais rejouer le choix d'un autre
/// utilisateur.
class CaisseSelectedMagasinNotifier extends Notifier<int?> {
  @override
  int? build() {
    ref.watch(authProvider.select((a) => a.user?.id));
    return null;
  }

  void select(int? magasinId) => state = magasinId;
}

final caisseSelectedMagasinProvider =
    NotifierProvider<CaisseSelectedMagasinNotifier, int?>(CaisseSelectedMagasinNotifier.new);

/// Règle centrale de la page web :
/// `magasinId = isAdmin ? selectedMagasinId : (user?.magasin_id ?? null)`.
/// Pilote TOUTES les requêtes (session courante, historique, résumé,
/// mouvements de période, valeur de stock).
final caisseMagasinIdProvider = Provider<int?>((ref) {
  final user = ref.watch(authProvider).user;
  if (user == null) return null;
  if (user.isAdmin) return ref.watch(caisseSelectedMagasinProvider);
  return user.magasinId;
});

/// Session de caisse en cours du magasin [magasinId] (`null` = aucune
/// session ouverte, ou aucun magasin résolu).
///
/// Famille par magasin : un admin qui change de magasin repart d'un état
/// propre (pas de session d'un autre magasin affichée pendant le
/// chargement). Le temps réel (`useRealtimeRefresh(['caisse_session',
/// 'caisse_movement'])` du web) passe par le `watch` de
/// [realtimeTickProvider] — Riverpod 3 conserve la valeur précédente pendant
/// la reconstruction, donc rafraîchissement silencieux.
class CurrentCaisseNotifier extends AsyncNotifier<CaisseSession?> {
  CurrentCaisseNotifier(this.magasinId);

  final int? magasinId;
  late final _repo = ref.read(caisseRepositoryProvider);

  @override
  Future<CaisseSession?> build() {
    ref.watch(realtimeTickProvider);
    return _load();
  }

  Future<CaisseSession?> _load() {
    final id = magasinId;
    if (id == null) return Future.value(null);
    return _repo.current(id);
  }

  /// Rechargement NON silencieux (bouton « Actualiser », `fetchCaisse()` du
  /// web avec `setLoading(true)`).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// Rechargement silencieux (après une action, tirer-pour-rafraîchir).
  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(_load);
  }

  /// `fetchCaisse()` du web après une action : session courante ET
  /// historique des sessions (les deux appels de `Promise.all`).
  Future<void> _afterAction() async {
    ref.invalidate(caisseHistoryProvider(magasinId));
    await refreshSilencieux();
  }

  /// `djangoClient.caisse.open(...)` puis `fetchCaisse()`.
  Future<void> open({required double openingBalance, String? openingNote, DateTime? openedAt}) async {
    final id = magasinId;
    if (id == null) throw const CaisseError('Sélectionnez un magasin');
    await _repo.open(magasinId: id, openingBalance: openingBalance, openingNote: openingNote, openedAt: openedAt);
    await _afterAction();
  }

  /// `djangoClient.caisse.close(session.id, ...)` puis `fetchCaisse()` SEUL
  /// (le résumé de période n'est pas rafraîchi, comme sur le web).
  Future<void> close({required double closingBalance, String? closingNote, DateTime? closedAt}) async {
    final session = state.value;
    if (session == null) throw const CaisseError('Aucune session de caisse ouverte.');
    await _repo.close(session.id, closingBalance: closingBalance, closingNote: closingNote, closedAt: closedAt);
    await _afterAction();
  }

  /// `djangoClient.caisse.addMovement(...)` puis `fetchCaisse()` ET
  /// `fetchSummary()` (le mouvement entre aussi dans la période).
  Future<void> addMovement({
    required String movementType,
    required double amount,
    required String reason,
    int? categoryId,
  }) async {
    final session = state.value;
    if (session == null) throw const CaisseError('Aucune session de caisse ouverte.');
    await _repo.addMovement(
      sessionId: session.id,
      movementType: movementType,
      amount: amount,
      reason: reason,
      categoryId: movementType == 'out' ? categoryId : null,
    );
    ref.invalidate(caissePeriodProvider);
    await _afterAction();
  }
}

final currentCaisseProvider = AsyncNotifierProvider.family<CurrentCaisseNotifier, CaisseSession?, int?>(
  (magasinId) => CurrentCaisseNotifier(magasinId),
);

/// Historique : sessions du magasin filtrées côté client sur
/// `status === 'closed'` (ordre serveur `-opened_at`), comme le web.
final caisseHistoryProvider = FutureProvider.autoDispose.family<List<CaisseSession>, int?>((ref, magasinId) async {
  ref.watch(realtimeTickProvider);
  if (magasinId == null) return const <CaisseSession>[];
  final sessions = await ref.read(caisseRepositoryProvider).listSessions(magasinId);
  return sessions.where((s) => s.isClosed).toList();
});

/// Filtre de la carte « Résumé de la caisse » : magasin + bornes `YYYY-MM-DD`
/// (`summaryFrom` / `summaryTo` du web). Tout changement relance les deux
/// appels (résumé + mouvements de la période).
typedef CaissePeriodQuery = ({int magasinId, String dateFrom, String dateTo});

/// `fetchSummary()` du web : `GET /users/caisse/summary/` et
/// `GET /users/caisse/movements/` lancés ensemble pour la période.
final caissePeriodProvider = FutureProvider.autoDispose.family<CaissePeriodData, CaissePeriodQuery>((ref, query) async {
  ref.watch(realtimeTickProvider);
  final repo = ref.read(caisseRepositoryProvider);
  final (summary, movements) = await (
    repo.summary(magasinId: query.magasinId, dateFrom: query.dateFrom, dateTo: query.dateTo),
    repo.listMovements(magasinId: query.magasinId, dateFrom: query.dateFrom, dateTo: query.dateTo),
  ).wait;
  return CaissePeriodData(summary: summary, movements: movements);
});

/// Catégories de dépense pour le Select « Catégorie » d'une sortie
/// (`GET /users/caisse/categories/`, lecture ouverte à tout authentifié).
final caisseCategoriesProvider = FutureProvider.autoDispose<List<CaisseCategory>>((ref) {
  return ref.read(caisseRepositoryProvider).categories();
});

/// Valeur de stock actuelle du magasin, pour pré-remplir les montants
/// d'ouverture et de fermeture — `autoDispose` : recalculée à chaque
/// ouverture de dialog (le stock bouge avec les ventes pendant la session).
final caisseStockValueProvider = FutureProvider.autoDispose.family<double?, int>((ref, magasinId) {
  return ref.read(caisseRepositoryProvider).stockValue(magasinId);
});
