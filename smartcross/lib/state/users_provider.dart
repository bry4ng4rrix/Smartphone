import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/users_repository.dart';
import '../models/user.dart';
import 'auth_provider.dart';

final usersRepositoryProvider = Provider((ref) => UsersRepository());

/// Gestion des comptes préparateur/livreur (§4 Smartreadme.md, réservée au gérant).
class AccountsNotifier extends AsyncNotifier<List<AppUser>> {
  late final _repo = ref.read(usersRepositoryProvider);

  @override
  Future<List<AppUser>> build() => _repo.list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.list);
  }

  Future<void> create({
    required String fullName,
    required String email,
    required String password,
    required String commandeRole,
    String? phone,
  }) async {
    final adminEmail = ref.read(authProvider).user?.email;
    if (adminEmail == null) throw StateError('Utilisateur non connecté');
    await _repo.create(
      fullName: fullName,
      email: email,
      password: password,
      adminEmail: adminEmail,
      commandeRole: commandeRole,
      phone: phone,
    );
    await refresh();
  }

  Future<void> updateCommandeRole(int userId, String commandeRole) async {
    await _repo.updateCommandeRole(userId, commandeRole);
    await refresh();
  }

  Future<void> delete(int userId, String password) async {
    await _repo.delete(userId, password);
    await refresh();
  }
}

final accountsProvider = AsyncNotifierProvider<AccountsNotifier, List<AppUser>>(AccountsNotifier.new);
