import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/json_utils.dart';

/// Type de compte choisi par l'utilisateur au moment de l'auto-inscription.
///
/// Le formulaire web (`frontend/components/auth/register-form.tsx`) manipule
/// les valeurs `'admin' | 'store_manager' | 'employee'` et c'est
/// `djangoClient.auth.register` qui les traduit vers les rôles Django juste
/// avant l'appel (`store_manager -> magasin`, `employee -> employer`). On
/// reproduit la même séparation ici : l'écran parle en `RegisterAccountType`,
/// le repository est le SEUL endroit qui connaît le nom backend.
enum RegisterAccountType { admin, storeManager, employee }

extension RegisterAccountTypeX on RegisterAccountType {
  /// Valeur envoyée dans le champ `role` de `POST users/register/`.
  String get apiRole => switch (this) {
        RegisterAccountType.admin => 'admin',
        RegisterAccountType.storeManager => 'magasin',
        RegisterAccountType.employee => 'employer',
      };

  /// Libellé du RadioGroup web ('Admin' / 'Manager' / 'Employé').
  String get label => switch (this) {
        RegisterAccountType.admin => 'Admin',
        RegisterAccountType.storeManager => 'Manager',
        RegisterAccountType.employee => 'Employé',
      };

  /// Message de succès du toast après inscription.
  ///
  /// Manager / Employé : libellé EXACT du web (`handleRegister`), le compte
  /// part en attente d'approbation (`is_confirmed=False`).
  ///
  /// Admin : le web affiche « Compte créé ! En attente d'approbation. » et
  /// envoie sur la page d'attente, alors que `RegisterSerializer` crée
  /// l'admin avec `is_confirmed=True` (et son magasin « Stock Local ») : il
  /// peut se connecter tout de suite, personne n'a à l'approuver. La doc de
  /// migration (règle métier cachée n°1) demande de corriger ce message
  /// trompeur et de renvoyer l'admin directement vers la connexion.
  String get successMessage => this == RegisterAccountType.admin
      ? 'Compte créé ! Vous pouvez vous connecter.'
      : "Compte créé ! En attente d'approbation par un administrateur.";

  /// Vrai quand le serializer confirme le compte d'office (aucune étape
  /// d'approbation) — voir [successMessage].
  bool get isAutoConfirmed => this == RegisterAccountType.admin;
}

/// Réponse de `POST users/register/` : `{"message": "Inscription réussie",
/// "id": 42}` (users/views.py::RegisterView).
class RegisterResult {
  const RegisterResult({required this.message, this.id});

  final String message;
  final int? id;

  factory RegisterResult.fromJson(Map<String, dynamic> json) => RegisterResult(
        message: asString(json['message']),
        id: asIntOrNull(json['id']),
      );
}

/// Cycle de vie d'un compte AVANT qu'il n'ait de session : auto-inscription
/// publique (`/register` côté web). Endpoint `AllowAny` — aucun token n'est
/// posé, aucune connexion automatique n'a lieu après la création : le compte
/// reste `is_confirmed=False` jusqu'à l'approbation par l'administrateur
/// (sauf `role='admin'`, confirmé d'office par le serializer).
class AccountRepository {
  /// `users/register/` est PUBLIC et appelé alors que personne n'est
  /// connecté. On ne passe donc PAS par `ApiClient.instance.dio` : son
  /// intercepteur collerait un `Authorization: Bearer <jeton périmé>` laissé
  /// par une session précédente (expirée sans déconnexion explicite), que
  /// `JWTAuthentication` rejetterait en 401 AVANT d'atteindre la vue — et
  /// l'intercepteur émettrait un `sessionExpired` parasite. Même technique
  /// que `PasswordRepository` et `ApiClient._tryRefresh` : un Dio nu sur la
  /// même base URL (relue à chaque appel, l'URL serveur étant configurable).
  Dio get _publicDio => Dio(BaseOptions(
        baseUrl: ApiClient.instance.dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'Accept': 'application/json'},
      ));

  /// Crée un compte. [username] vide -> partie locale de l'email, exactement
  /// comme le web (`username || email.split('@')[0]`).
  ///
  /// Les champs conditionnels absents ne sont PAS envoyés (le web les passe à
  /// `undefined`, donc ils disparaissent du JSON) : le serializer Django les
  /// déclare tous `required=False` et se sert du `role` pour savoir lesquels
  /// il attend.
  Future<RegisterResult> register({
    required RegisterAccountType type,
    required String fullName,
    required String email,
    required String password,
    String? username,
    String? companyName,
    String? shopName,
    String? adminEmail,
    String? position,
  }) async {
    // L'inscription peut être la toute première requête de l'app (écran
    // public atteint depuis /login) : on garantit que l'URL serveur
    // enregistrée a bien été appliquée à Dio.
    await ApiClient.instance.ensureInitialized();

    final trimmedUsername = username?.trim() ?? '';
    final trimmedEmail = email.trim();
    final resolvedUsername =
        trimmedUsername.isNotEmpty ? trimmedUsername : trimmedEmail.split('@').first;

    final response = await _publicDio.post('users/register/', data: {
      'email': trimmedEmail,
      'username': resolvedUsername,
      'password': password,
      'role': type.apiRole,
      'full_name': fullName.trim(),
      if (type == RegisterAccountType.admin && (companyName?.trim().isNotEmpty ?? false))
        'company_name': companyName!.trim(),
      if (type == RegisterAccountType.storeManager && (shopName?.trim().isNotEmpty ?? false))
        'shop_name': shopName!.trim(),
      if (type != RegisterAccountType.admin && (adminEmail?.trim().isNotEmpty ?? false))
        'admin_email': adminEmail!.trim(),
      if (type == RegisterAccountType.employee && (position?.trim().isNotEmpty ?? false))
        'position': position!.trim(),
    });

    final data = response.data;
    if (data is Map<String, dynamic>) return RegisterResult.fromJson(data);
    return const RegisterResult(message: 'Inscription réussie');
  }
}

/// Les providers du projet vivent dans `lib/state/` ; aucun
/// `state/account_provider.dart` n'existe encore et le portage ne doit créer
/// que les fichiers listés — le provider est donc déclaré ici, avec la même
/// forme que `authRepositoryProvider` & co.
final accountRepositoryProvider = Provider((ref) => AccountRepository());
