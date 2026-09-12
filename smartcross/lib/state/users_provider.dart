import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/repositories/users_repository.dart';
import '../models/company.dart';
import '../models/user.dart';
import 'auth_provider.dart';
import 'company_provider.dart';

final usersRepositoryProvider = Provider((ref) => UsersRepository());

/// Résultat de `handleAddUser` (web) : l'id du compte créé (s'il est renvoyé
/// par le serveur) et le rôle demandé, pour choisir le toast et l'insertion
/// optimiste côté écran.
class CreatedAccount {
  const CreatedAccount({required this.role, this.id});
  final String role;
  final int? id;
}

/// Onglet « Utilisateurs actifs » de la page Super Administration : tous les
/// comptes de la société (admins, gérants, employés) de TOUS les magasins
/// accessibles, aplatis et dédoublonnés comme sur le web ([flattenTeamUsers]).
///
/// Les actions (création, rôle, suppression) ne rechargent PAS la liste
/// elles-mêmes : l'écran appelle [reloadAll] après avoir fermé sa modale et
/// affiché son toast, exactement dans l'ordre de `fetchUsers()` sur le web
/// (qui repasse les deux onglets en chargement).
class AccountsNotifier extends AsyncNotifier<List<AppUser>> {
  late final _repo = ref.read(usersRepositoryProvider);

  @override
  Future<List<AppUser>> build() => _repo.list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.list);
  }

  /// `fetchUsers()` du web : recharge l'équipe active ET les comptes en
  /// attente (une approbation, un rejet ou une création touche les deux).
  Future<void> reloadAll() async {
    await Future.wait([refresh(), ref.read(pendingUsersProvider.notifier).refresh()]);
  }

  /// Création d'un compte selon le rôle Django choisi :
  /// - `admin` -> `POST /users/add-admin/` (fondateur uniquement) ;
  /// - `magasin` / `employer` -> `POST /users/register/` avec `admin_email` =
  ///   email de l'utilisateur courant (rattachement à la société / au
  ///   magasin), plus `shop_name` (gérant) ou `position` + sous-rôle Commande
  ///   (employé).
  ///
  /// Comme sur le web, un administrateur créé est inséré EN TÊTE de la liste
  /// de façon optimiste (rattaché à « Société », confirmé) avant le
  /// rechargement complet demandé par l'écran.
  Future<CreatedAccount> create({
    required String fullName,
    required String email,
    required String password,
    required String role,
    String? position,
    String? shopName,
    String? commandeRole,
    String? phone,
  }) async {
    final current = ref.read(authProvider).user;
    if (current == null) throw StateError('Utilisateur non connecté');

    final int? id;
    if (role == DjangoRole.admin) {
      id = await _repo.addAdmin(fullName: fullName, email: email, password: password);
      if (id != null) {
        final previous = state.value ?? const <AppUser>[];
        state = AsyncData([
          AppUser(
            id: id,
            fullName: fullName,
            email: email,
            role: UserRole.gerant,
            isActive: true,
            shopName: 'Société',
            position: '',
            rawRole: DjangoRole.admin,
          ),
          ...previous,
        ]);
      }
    } else {
      id = await _repo.register(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
        adminEmail: current.email,
        position: position,
        shopName: shopName,
        commandeRole: commandeRole,
        phone: phone,
      );
    }
    return CreatedAccount(role: role, id: id);
  }

  /// `PUT /users/role/<id>/` — laisse remonter l'erreur : le dialog
  /// l'affiche et reste ouvert, comme sur le web.
  Future<void> updateRole(int userId, String role) => _repo.updateRole(userId, role);

  /// Sous-rôle module Commande d'un employé (PREPARATEUR / LIVREUR / aucun).
  Future<void> updateCommandeRole(int userId, String? commandeRole) => _repo.updateCommandeRole(userId, commandeRole);

  /// Suppression confirmée par le mot de passe de l'opérateur ; l'erreur
  /// remonte à la modale (affichée en ligne, modale maintenue ouverte).
  Future<void> delete(int userId, String password) => _repo.delete(userId, password);
}

final accountsProvider = AsyncNotifierProvider<AccountsNotifier, List<AppUser>>(AccountsNotifier.new);

/// Onglet « En attente » : comptes créés mais non encore approuvés.
class PendingUsersNotifier extends AsyncNotifier<List<PendingUser>> {
  late final _repo = ref.read(usersRepositoryProvider);

  @override
  Future<List<PendingUser>> build() => _repo.pending();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.pending);
  }

  /// `PUT /users/approve/<id>/` — l'écran recharge ensuite les deux listes.
  Future<void> approve(int userId) => _repo.approve(userId);

  /// `POST /users/reject/<id>/` — rejette ET supprime le compte.
  Future<void> reject(int userId) => _repo.reject(userId);
}

final pendingUsersProvider = AsyncNotifierProvider<PendingUsersNotifier, List<PendingUser>>(PendingUsersNotifier.new);

// =============================================================================
// Onglet « Réinit. mots de passe » (admin uniquement)
// =============================================================================

/// Valeurs du Select de filtre du web, dans l'ordre : `pending` (défaut),
/// `approved`, `rejected`, `all` (paramètre `status` omis).
const kPasswordRequestFilters = <String, String>{
  'pending': 'En attente',
  'approved': 'Approuvées',
  'rejected': 'Rejetées',
  'all': 'Toutes',
};

/// Filtre SERVEUR de l'onglet : chaque changement relance
/// `GET /users/password-reset-requests/?status=...` (via [passwordRequestsProvider]
/// qui l'observe).
class PasswordRequestFilterNotifier extends Notifier<String> {
  @override
  String build() => 'pending';

  void set(String value) => state = value;
}

final passwordRequestFilterProvider = NotifierProvider<PasswordRequestFilterNotifier, String>(
  PasswordRequestFilterNotifier.new,
);

/// Demandes de réinitialisation de mot de passe adressées à l'admin courant
/// (`EmployeePasswordResetListView`, `[IsAuthenticated, IsAdmin]`), filtrées
/// côté serveur par [passwordRequestFilterProvider]. Réutilise
/// [CompanyRepository] (`company_repository.dart`).
///
/// Dépend de l'id de l'utilisateur connecté pour repartir d'un état propre à
/// chaque changement de compte sur le même appareil.
class PasswordRequestsNotifier extends AsyncNotifier<List<PasswordResetRequest>> {
  late final _repo = ref.read(companyRepositoryProvider);

  @override
  Future<List<PasswordResetRequest>> build() {
    ref.watch(authProvider.select((a) => a.user?.id));
    final status = ref.watch(passwordRequestFilterProvider);
    return _repo.passwordResetRequests(status: status);
  }

  Future<void> refresh() async {
    final status = ref.read(passwordRequestFilterProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.passwordResetRequests(status: status));
  }

  /// `PATCH /users/password-reset-requests/<id>/ { action }` puis
  /// rechargement (`await fetchPasswordRequests()` du web). L'erreur de
  /// l'action remonte à l'écran (toast) ; celle du rechargement va dans l'état.
  Future<void> resolve(int id, String action) async {
    await _repo.resolvePasswordReset(id, action);
    await refresh();
  }
}

final passwordRequestsProvider = AsyncNotifierProvider<PasswordRequestsNotifier, List<PasswordResetRequest>>(
  PasswordRequestsNotifier.new,
);
