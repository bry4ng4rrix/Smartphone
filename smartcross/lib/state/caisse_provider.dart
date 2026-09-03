import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/caisse_repository.dart';
import '../models/caisse.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

final caisseRepositoryProvider = Provider((ref) => CaisseRepository());

/// Session de caisse en cours pour le magasin du gérant connecté.
class CurrentCaisseNotifier extends AsyncNotifier<CaisseSession?> {
  late final _repo = ref.read(caisseRepositoryProvider);

  int? get _magasinId => ref.read(authProvider).user?.magasinId;

  @override
  Future<CaisseSession?> build() {
    ref.watch(realtimeTickProvider);
    final magasinId = _magasinId;
    if (magasinId == null) return Future.value(null);
    return _repo.current(magasinId);
  }

  Future<void> refresh() async {
    final magasinId = _magasinId;
    if (magasinId == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.current(magasinId));
  }

  Future<void> open({required double openingBalance, String? openingNote}) async {
    final magasinId = _magasinId;
    if (magasinId == null) throw StateError('Aucun magasin associé à ce compte.');
    await _repo.open(magasinId: magasinId, openingBalance: openingBalance, openingNote: openingNote);
    await refresh();
  }

  Future<void> close({required double closingBalance, String? closingNote}) async {
    final session = state.value;
    if (session == null) return;
    await _repo.close(session.id, closingBalance: closingBalance, closingNote: closingNote);
    await refresh();
  }

  Future<void> addMovement({required String movementType, required double amount, required String reason}) async {
    final session = state.value;
    if (session == null) throw StateError('Aucune session de caisse ouverte.');
    await _repo.addMovement(sessionId: session.id, movementType: movementType, amount: amount, reason: reason);
    await refresh();
  }
}

final currentCaisseProvider = AsyncNotifierProvider<CurrentCaisseNotifier, CaisseSession?>(CurrentCaisseNotifier.new);

final caisseHistoryProvider = FutureProvider.autoDispose<List<CaisseSession>>((ref) {
  ref.watch(realtimeTickProvider);
  final magasinId = ref.watch(authProvider).user?.magasinId;
  if (magasinId == null) return Future.value(<CaisseSession>[]);
  return ref.read(caisseRepositoryProvider).history(magasinId);
});
