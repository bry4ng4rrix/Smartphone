import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/stock_repository.dart';
import '../models/stock.dart';
import 'realtime_provider.dart';

final stockRepositoryProvider = Provider((ref) => StockRepository());

/// Alertes de stock (ruptures + stock bas) — page `/alerts` du web.
///
/// Deux rechargements, comme `fetchData(silent)` côté web :
///
/// * [refresh] — NON silencieux (bouton « Actualiser ») ;
/// * [refreshSilencieux] — la liste courante reste affichée pendant l'appel
///   (tirer-pour-rafraîchir).
///
/// Le rafraîchissement temps réel (`useRealtimeRefresh(['product_variant',
/// 'order'])`) est assuré par le `watch` de [realtimeTickProvider] : la
/// reconstruction conserve la valeur précédente (Riverpod 3), donc aucun
/// clignotement.
///
/// NB Riverpod 3 : `state = AsyncLoading()` conserve la valeur précédente
/// (`hasValue` reste vrai). Les écrans distinguent donc eux-mêmes le
/// rechargement non silencieux (indicateur + boutons désactivés) du
/// rechargement silencieux — le notifier ne peut pas « vider » l'état.
class RupturesNotifier extends AsyncNotifier<List<RuptureItem>> {
  late final _repo = ref.read(stockRepositoryProvider);

  @override
  Future<List<RuptureItem>> build() {
    ref.watch(realtimeTickProvider);
    return _repo.ruptures();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.ruptures);
  }

  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(_repo.ruptures);
  }
}

final rupturesProvider = AsyncNotifierProvider<RupturesNotifier, List<RuptureItem>>(RupturesNotifier.new);

/// Historique des mouvements de stock (`GET /catalog/movements/`), pour
/// toute la société (`variantId == null`) ou une seule variante.
///
/// Mêmes deux rechargements que [RupturesNotifier] ; le temps réel
/// (`useRealtimeRefresh(['stock_movement','product_variant','order'])`) passe
/// par le `watch` de [realtimeTickProvider].
class MovementsNotifier extends AsyncNotifier<List<StockMovement>> {
  MovementsNotifier(this.variantId);

  final int? variantId;
  late final _repo = ref.read(stockRepositoryProvider);

  @override
  Future<List<StockMovement>> build() {
    ref.watch(realtimeTickProvider);
    return _repo.movements(variantId: variantId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.movements(variantId: variantId));
  }

  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(() => _repo.movements(variantId: variantId));
  }
}

final movementsProvider = AsyncNotifierProvider.family<MovementsNotifier, List<StockMovement>, int?>(
  (arg) => MovementsNotifier(arg),
);
