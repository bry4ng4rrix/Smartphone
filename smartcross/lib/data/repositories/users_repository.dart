import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/user.dart';

/// Gestion des comptes préparateur/livreur — réservée au gérant.
/// Le backend multi-tenant n'a pas de CRUD `users/accounts/` simple : la
/// liste vient de `magasins/users/` (regroupée par magasin), la création
/// passe par l'inscription générale (`users/register/`, role=employer), le
/// sous-rôle Commande se change via `users/employers/<id>/commande-role/`
/// et la suppression exige le mot de passe du gérant (§4 Smartreadme.md).
class UsersRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// Les employés du (seul) magasin du gérant connecté.
  Future<List<AppUser>> list() async {
    final response = await _dio.get('users/magasins/users/');
    final magasins = response.data as List;
    if (magasins.isEmpty) return [];
    final employers = (magasins.first as Map<String, dynamic>)['employers'] as List? ?? [];
    return employers.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// [adminEmail] : email du gérant connecté (propriétaire du magasin) —
  /// requis par `register/` pour rattacher le nouvel employé à la bonne
  /// société, même si c'est déjà l'utilisateur courant qui le crée.
  Future<void> create({
    required String fullName,
    required String email,
    required String password,
    required String adminEmail,
    String commandeRole = 'PREPARATEUR', // PREPARATEUR | LIVREUR
    String? phone,
  }) async {
    await _dio.post('users/register/', data: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'role': 'employer',
      'admin_email': adminEmail,
      'commande_role': commandeRole,
      'position': commandeRole == 'LIVREUR' ? 'Livreur' : 'Préparateur',
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
  }

  /// Change le sous-rôle Préparateur/Livreur d'un employé existant.
  Future<void> updateCommandeRole(int userId, String commandeRole) async {
    await _dio.put('users/employers/$userId/commande-role/', data: {'commande_role': commandeRole});
  }

  /// Nécessite le mot de passe du gérant connecté (confirmation, §4 Smartreadme.md).
  Future<void> delete(int userId, String password) async {
    await _dio.delete('users/delete/$userId/', data: {'password': password});
  }

  /// Comptes auto-inscrits en attente d'approbation (employé qui s'inscrit
  /// lui-même avec l'email du gérant — distinct de [create] ci-dessus).
  Future<List<PendingUser>> pending() async {
    final response = await _dio.get('users/pending/');
    return (response.data as List).map((e) => PendingUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> approve(int userId) async {
    await _dio.put('users/approve/$userId/');
  }

  Future<void> reject(int userId) async {
    await _dio.post('users/reject/$userId/');
  }
}
