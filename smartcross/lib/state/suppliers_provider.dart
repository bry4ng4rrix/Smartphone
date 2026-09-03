import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/suppliers_repository.dart';
import '../models/supplier.dart';
import 'realtime_provider.dart';

final suppliersRepositoryProvider = Provider((ref) => SuppliersRepository());

class SupplierOrdersNotifier extends AsyncNotifier<List<SupplierOrder>> {
  late final _repo = ref.read(suppliersRepositoryProvider);

  @override
  Future<List<SupplierOrder>> build() {
    ref.watch(realtimeTickProvider);
    return _repo.list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.list);
  }

  Future<SupplierOrder> create({
    String description = '',
    required double prixFournisseur,
    required double fretImport,
    required double douane,
    required double metaAds,
    required List<SupplierOrderLineDraft> lines,
  }) async {
    final order = await _repo.create(
      description: description,
      prixFournisseur: prixFournisseur,
      fretImport: fretImport,
      douane: douane,
      metaAds: metaAds,
      lines: lines,
    );
    await refresh();
    return order;
  }

  Future<SupplierOrder> receive(int id) async {
    final order = await _repo.receive(id);
    await refresh();
    return order;
  }
}

final supplierOrdersProvider = AsyncNotifierProvider<SupplierOrdersNotifier, List<SupplierOrder>>(SupplierOrdersNotifier.new);

final supplierOrderDetailProvider = FutureProvider.autoDispose.family<SupplierOrder, int>((ref, id) {
  ref.watch(realtimeTickProvider);
  return ref.read(suppliersRepositoryProvider).detail(id);
});
