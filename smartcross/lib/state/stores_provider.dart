import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/stores_repository.dart';
import '../models/magasin.dart';

final storesRepositoryProvider = Provider((ref) => StoresRepository());

class StoresNotifier extends AsyncNotifier<List<Magasin>> {
  late final _repo = ref.read(storesRepositoryProvider);

  @override
  Future<List<Magasin>> build() => _repo.list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.list());
  }

  Future<void> create({
    required String shopName,
    required String managerFullName,
    required String managerEmail,
    required String managerPassword,
  }) async {
    await _repo.create(
      shopName: shopName,
      managerFullName: managerFullName,
      managerEmail: managerEmail,
      managerPassword: managerPassword,
    );
    await refresh();
  }

  Future<void> rename(int magasinId, String shopName) async {
    await _repo.rename(magasinId, shopName);
    await refresh();
  }

  Future<void> delete(int magasinId, String password) async {
    await _repo.delete(magasinId, password);
    await refresh();
  }
}

final storesProvider = AsyncNotifierProvider<StoresNotifier, List<Magasin>>(StoresNotifier.new);
