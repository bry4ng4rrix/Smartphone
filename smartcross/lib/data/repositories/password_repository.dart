import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Message EXACT renvoyé par le backend (403) quand un compte qui n'est ni
/// `admin` ni `magasin` tente `POST /users/change-password/`
/// (users/views.py::ChangePasswordView). Repris tel quel dans l'UI pour
/// prévenir l'utilisateur AVANT l'appel, comme le fait la page Paramètres du
/// web pour la même règle.
const String kChangePasswordForbiddenMessage =
    'Seul le gérant peut modifier ces informations. Contactez votre gérant.';

/// Statut d'une demande « mot de passe oublié », tel que renvoyé par
/// `GET /users/public/forgot-password/status/`.
///
/// `none` couvre trois cas côté serveur (email inconnu, compte `admin`, ou
/// aucune demande non consommée) : le web les traite tous pareil — bandeau
/// masqué + message « Aucune demande trouvée pour cet email. ».
enum PasswordResetStatus {
  none('none'),
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const PasswordResetStatus(this.apiValue);

  final String apiValue;

  static PasswordResetStatus fromApi(Object? value) {
    final raw = value is String ? value : '';
    for (final status in values) {
      if (status.apiValue == raw) return status;
    }
    return PasswordResetStatus.none;
  }
}

/// Réponse 201 de `POST /users/public/forgot-password/` :
/// `{queue: 'admin', message: '...'}`. Le web affiche le message DU SERVEUR
/// (pas une constante) — on le remonte donc tel quel.
class ForgotPasswordRequestResult {
  const ForgotPasswordRequestResult({required this.message, required this.queue});

  final String message;

  /// File d'attente qui traitera la demande — toujours `admin` aujourd'hui
  /// (l'administrateur de la société valide ou rejette).
  final String queue;
}

/// Flux « mot de passe oublié » (public, sans authentification) + changement
/// de mot de passe d'un compte connecté.
///
/// Aucun email n'est envoyé par le backend (aucun backend mail configuré) :
/// la demande est routée vers l'administrateur de la société, qui l'approuve
/// ou la rejette depuis `/users` ; le demandeur revient vérifier lui-même le
/// statut, puis définit son mot de passe.
class PasswordRepository {
  /// Les 3 endpoints `users/public/forgot-password/*` sont `AllowAny` et sont
  /// appelés alors que personne n'est connecté. On ne passe donc PAS par
  /// `ApiClient.instance.dio` : son intercepteur collerait un
  /// `Authorization: Bearer <token périmé>` laissé par une session
  /// précédente, DRF répondrait 401 avant même d'atteindre la vue, et
  /// l'intercepteur émettrait un `sessionExpired` parasite. Même technique
  /// que `ApiClient._tryRefresh` : un Dio nu sur la même base URL (relue à
  /// chaque appel, car l'URL du serveur est configurable à l'exécution).
  Dio get _publicDio => Dio(BaseOptions(
        baseUrl: ApiClient.instance.dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'Accept': 'application/json'},
      ));

  Dio get _authDio => ApiClient.instance.dio;

  static String _messageOf(Object? data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    return fallback;
  }

  /// Étape 1 — `POST /users/public/forgot-password/` body `{email}`.
  ///
  /// Erreurs backend remontées telles quelles par
  /// [ApiClient.messageFromError] : 400 « Email requis. », 404 « Aucun compte
  /// avec cet email. », 400 « La réinitialisation automatique n'est pas
  /// disponible pour les comptes administrateur… », 404 « Aucun
  /// administrateur associé à ce compte. », 400 « Une demande est déjà en
  /// attente. ».
  Future<ForgotPasswordRequestResult> forgotPasswordRequest(String email) async {
    final response = await _publicDio.post(
      'users/public/forgot-password/',
      data: {'email': email},
    );
    final data = response.data;
    return ForgotPasswordRequestResult(
      message: _messageOf(
        data,
        'Votre demande a été transmise à votre administrateur pour validation.',
      ),
      queue: (data is Map && data['queue'] is String) ? data['queue'] as String : '',
    );
  }

  /// Étape 2 — `GET /users/public/forgot-password/status/?email=…`.
  Future<PasswordResetStatus> forgotPasswordStatus(String email) async {
    final response = await _publicDio.get(
      'users/public/forgot-password/status/',
      queryParameters: {'email': email},
    );
    final data = response.data;
    return PasswordResetStatus.fromApi(data is Map ? data['status'] : null);
  }

  /// Étape 3 — `POST /users/public/forgot-password/confirm/` body
  /// `{email, new_password}`. La demande approuvée est marquée `consumed_at`
  /// côté serveur : usage UNIQUE, non rejouable.
  Future<String> forgotPasswordConfirm({
    required String email,
    required String newPassword,
  }) async {
    final response = await _publicDio.post(
      'users/public/forgot-password/confirm/',
      data: {'email': email, 'new_password': newPassword},
    );
    return _messageOf(response.data, 'Mot de passe mis à jour avec succès.');
  }

  /// `POST /users/change-password/` body `{old_password, new_password}` —
  /// compte CONNECTÉ, et réservé côté backend aux rôles `admin` / `magasin`
  /// (403 [kChangePasswordForbiddenMessage] sinon).
  Future<String> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final response = await _authDio.post(
      'users/change-password/',
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
    return _messageOf(response.data, 'Mot de passe changé avec succès');
  }
}

/// Déclaré ici (et non dans `lib/state/`) parce que ce repository n'a pas de
/// provider d'état associé : les deux écrans mots de passe pilotent des
/// formulaires, pas un cache de données. Même schéma que
/// `chatRepositoryProvider` (features/chats/chat_list_screen.dart).
final passwordRepositoryProvider = Provider((ref) => PasswordRepository());
