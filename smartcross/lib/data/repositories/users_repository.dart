import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/json_utils.dart';
import '../../models/user.dart';

/// Rôle Django à créer / attribuer depuis la page Super Administration
/// (`frontend/app/(app)/users/page.tsx`) : `employer` | `magasin` | `admin`.
class DjangoRole {
  DjangoRole._();
  static const employer = 'employer';
  static const magasin = 'magasin';
  static const admin = 'admin';
}

/// Gestion des comptes de la société — portage des appels de
/// `frontend/app/(app)/users/page.tsx`.
///
/// Le backend multi-tenant n'a pas de CRUD `users/accounts/` simple :
/// - la liste vient de `magasins/users/` (regroupée par magasin — TOUS les
///   magasins de l'admin, pas seulement le premier) ;
/// - la création passe par l'inscription générale (`users/register/`) pour un
///   employé ou un gérant, et par `users/add-admin/` pour un co-admin
///   (fondateur uniquement) ;
/// - le rôle Django se change via `users/role/<id>/` (admin), le sous-rôle
///   Commande via `users/employers/<id>/commande-role/` (gérant) ;
/// - la suppression exige le mot de passe de l'opérateur (§4 Smartreadme.md).
class UsersRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// `GET /users/magasins/users/` — toutes les équipes accessibles
  /// (users/views.py::UsersByMagasinView : admin -> tous ses magasins,
  /// gérant -> le sien, employé -> le sien).
  Future<List<MagasinTeam>> teams() async {
    final response = await _dio.get('users/magasins/users/');
    return (response.data as List).map((e) => MagasinTeam.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Tous les comptes de la société, aplatis et dédoublonnés comme sur le web
  /// (voir [flattenTeamUsers]).
  Future<List<AppUser>> list() async => flattenTeamUsers(await teams());

  /// `POST /users/register/` — création d'un employé ou d'un gérant de
  /// magasin par l'utilisateur courant (`handleAddUser` du web).
  ///
  /// [adminEmail] est TOUJOURS l'email de l'utilisateur courant : le
  /// serializer s'en sert pour rattacher le compte à la société (admin) ou
  /// au magasin (gérant). Quand c'est l'admin lui-même qui crée, le compte
  /// est confirmé d'office ; sinon il reste en attente d'approbation.
  ///
  /// L'email est envoyé À LA FOIS comme `email` et comme `username`, comme
  /// sur le web. [commandeRole] (PREPARATEUR | LIVREUR) est un ajout mobile :
  /// le sous-rôle module Commande d'un employé, sinon attribué plus tard par
  /// le gérant via [updateCommandeRole].
  ///
  /// Renvoie l'id du compte créé (`{"message", "id"}`).
  Future<int?> register({
    required String fullName,
    required String email,
    required String password,
    required String role, // employer | magasin
    required String adminEmail,
    String? position,
    String? shopName,
    String? commandeRole,
    String? phone,
  }) async {
    final response = await _dio.post(
      'users/register/',
      data: {
        'email': email,
        'username': email,
        'password': password,
        'role': role,
        'full_name': fullName,
        'admin_email': adminEmail,
        if (role == DjangoRole.employer) 'position': position ?? '',
        if (role == DjangoRole.employer && commandeRole != null && commandeRole.isNotEmpty)
          'commande_role': commandeRole,
        if (role == DjangoRole.magasin) 'shop_name': shopName ?? '',
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
    return _createdId(response.data);
  }

  /// `POST /users/add-admin/` — ajoute un co-administrateur (permission
  /// `IsCompanyOwner` : fondateur uniquement). Réponse `{message, id}`.
  Future<int?> addAdmin({required String fullName, required String email, required String password}) async {
    final response = await _dio.post(
      'users/add-admin/',
      data: {'email': email, 'username': email, 'password': password, 'role': DjangoRole.admin, 'full_name': fullName},
    );
    return _createdId(response.data);
  }

  int? _createdId(dynamic data) => data is Map ? asIntOrNull(data['id']) : null;

  /// `handleAddUser` (web) : vrai si le serveur a refusé la création parce
  /// qu'un compte porte déjà ce `username` / cet `email` (message d'unicité
  /// DRF « already exists ») — l'écran affiche alors le libellé dédié.
  static bool isDuplicateAccountError(Object error) {
    if (error is! DioException) return false;
    final data = error.response?.data;
    if (data is! Map) return false;
    for (final key in const ['username', 'email']) {
      final v = data[key];
      final text = (v is List ? v.join(' ') : v?.toString() ?? '').toLowerCase();
      if (text.contains('already exists') || text.contains('existe déjà')) return true;
    }
    return false;
  }

  /// Compatibilité avec l'ancien flux mobile (création d'un préparateur /
  /// livreur) : délègue à [register] avec `role=employer`.
  Future<void> create({
    required String fullName,
    required String email,
    required String password,
    required String adminEmail,
    String commandeRole = 'PREPARATEUR', // PREPARATEUR | LIVREUR
    String? phone,
  }) async {
    await register(
      fullName: fullName,
      email: email,
      password: password,
      role: DjangoRole.employer,
      adminEmail: adminEmail,
      commandeRole: commandeRole,
      position: commandeRole == 'LIVREUR' ? 'Livreur' : 'Préparateur',
      phone: phone,
    );
  }

  /// `PUT /users/role/<id>/ { role }` — change le rôle Django
  /// (users/views.py::RoleManagementView, `[IsAuthenticated, IsAdmin]`).
  /// Refus serveur remontés tels quels : rôle invalide (400), « Vous ne
  /// pouvez pas modifier votre propre rôle » (400), « Seul le fondateur de la
  /// société peut gérer les administrateurs. » (403), « Action impossible sur
  /// le fondateur de la société. » (403), hors entreprise (403), 404.
  Future<void> updateRole(int userId, String role) async {
    await _dio.put('users/role/$userId/', data: {'role': role});
  }

  /// Change le sous-rôle Préparateur/Livreur d'un employé existant
  /// (`null`/vide = aucun sous-rôle). Réservé au gérant (admin ou magasin).
  Future<void> updateCommandeRole(int userId, String? commandeRole) async {
    await _dio.put(
      'users/employers/$userId/commande-role/',
      data: {'commande_role': (commandeRole == null || commandeRole.isEmpty) ? null : commandeRole},
    );
  }

  /// `DELETE /users/delete/<id>/ { password }` — nécessite le mot de passe
  /// de l'opérateur connecté (ré-authentification, §4 Smartreadme.md).
  Future<void> delete(int userId, String password) async {
    await _dio.delete('users/delete/$userId/', data: {'password': password});
  }

  /// `GET /users/pending/` — comptes non confirmés de la société (admin) ou
  /// du magasin (gérant) : employés ET gérants de magasin en attente.
  Future<List<PendingUser>> pending() async {
    final response = await _dio.get('users/pending/');
    return (response.data as List).map((e) => PendingUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `PUT /users/approve/<id>/` — passe `is_confirmed` à vrai.
  Future<void> approve(int userId) async {
    await _dio.put('users/approve/$userId/');
  }

  /// `POST /users/reject/<id>/` — REJETTE ET SUPPRIME définitivement le compte.
  Future<void> reject(int userId) async {
    await _dio.post('users/reject/$userId/');
  }
}
