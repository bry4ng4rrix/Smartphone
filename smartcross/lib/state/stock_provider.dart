import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/stock_repository.dart';
import '../models/stock.dart';
import 'realtime_provider.dart';

final stockRepositoryProvider = Provider((ref) => StockRepository());

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
}

final rupturesProvider = AsyncNotifierProvider<RupturesNotifier, List<RuptureItem>>(RupturesNotifier.new);

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
}

final movementsProvider = AsyncNotifierProvider.family<MovementsNotifier, List<StockMovement>, int?>(
  (arg) => MovementsNotifier(arg),
);
