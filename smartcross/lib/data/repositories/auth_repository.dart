import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/secure_storage.dart';
import '../../models/user.dart';

/// Résultat de `djangoClient.auth.login()` côté web : les deux jetons ET le
/// profil `GET users/me/` lu dans la foulée (le backend ne renvoie que
/// `{access, refresh}` sur `users/login/`, jamais le rôle ni le nom).
class LoginResult {
  LoginResult({required this.access, required this.refresh, required this.user});

  final String access;
  final String refresh;
  final AppUser user;
}

/// Compte dont la connexion a abouti mais dont `is_confirmed` vaut `false`
/// sur `users/me/`. C'est la seconde barrière du formulaire web
/// (`if (!response.user.is_confirmed)` dans `login-form.tsx`), en pratique
/// inatteignable puisque `CustomTokenObtainPairSerializer` refuse déjà
/// d'émettre un jeton dans ce cas — mais si elle se déclenchait, le web
/// laissait les jetons en localStorage. La doc de migration demande de les
/// purger ici : [AuthRepository.login] le fait avant de lever cette erreur.
class AccountNotApprovedException implements Exception {
  const AccountNotApprovedException();

  /// Libellé EXACT du toast web (`ERRORS['Account pending approval']`).
  static const String message = "Compte en attente d'approbation. Contactez votre manager.";

  @override
  String toString() => message;
}

/// Cycle de vie de la session : connexion, profil courant, déconnexion,
/// profil (mise à jour + photo) et changement de mot de passe — réplique de
/// `djangoClient.auth` (frontend/lib/django-client.ts).
class AuthRepository {
  AuthRepository() {
    // Web : `refreshAccessToken()` PURGE les jetons quand le rafraîchissement
    // échoue (puis `window.location.href = '/login'`). Côté app, l'ApiClient
    // se contente d'émettre `sessionExpired` (et `AuthNotifier` renvoie sur
    // /login) : on complète ici avec la purge, sinon un jeton périmé
    // resterait dans le stockage sécurisé et serait collé en `Authorization`
    // sur des appels publics ultérieurs (inscription, mot de passe oublié),
    // que DRF rejetterait en 401 avant même d'atteindre la vue.
    _expirySubscription ??= AuthEvents.instance.stream.listen((event) {
      if (event.kind != AuthEventKind.sessionExpired) return;
      _justLoggedIn = null;
      unawaited(TokenStorage.instance.clear().catchError((_) {}));
    });
  }

  /// Un seul abonnement pour tout le processus, quel que soit le nombre
  /// d'instances (le provider n'en crée qu'une, mais on se protège).
  static StreamSubscription<AuthEvent>? _expirySubscription;

  /// Délai maximal accordé aux appels « best effort » de la déconnexion :
  /// hors ligne, l'utilisateur ne doit pas attendre 20 s avant de voir
  /// l'écran de connexion.
  static const Duration _bestEffortTimeout = Duration(seconds: 6);

  Dio get _dio => ApiClient.instance.dio;

  /// Dio SANS intercepteur pour les endpoints publics (`users/login/` est un
  /// `TokenViewBase` sans authentification). Même technique que
  /// `ApiClient._tryRefresh` et `PasswordRepository` : on évite qu'un jeton
  /// périmé d'une session précédente ne parte en `Authorization`, et qu'un
  /// 401 « identifiants invalides » ne déclenche un rafraîchissement suivi
  /// d'un `sessionExpired` parasite.
  Dio get _publicDio => Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'Accept': 'application/json'},
      ));

  /// Profil lu par [login] et consommé par le `me()` qui suit immédiatement
  /// (`AuthNotifier.login` enchaîne `login()` puis `me()`) : on garde ainsi
  /// exactement les deux requêtes du web (login + /users/me/) au lieu de
  /// trois, sans changer le contrat de `me()`.
  AppUser? _justLoggedIn;

  /// `djangoClient.auth.login(email, password)` : POST `users/login/`
  /// (champ `email`, pas `username`), jetons persistés IMMÉDIATEMENT, puis
  /// `GET users/me/` pour le profil.
  ///
  /// Erreurs remontées telles quelles par [ApiClient.messageFromError] (401
  /// « No active account found with the given credentials », 401 « Compte
  /// non approuvé. Contactez votre administrateur. », 400 champs vides…) —
  /// c'est l'écran qui applique la table de traduction du web.
  Future<LoginResult> login(String email, String password) async {
    await ApiClient.instance.ensureInitialized();
    _justLoggedIn = null;

    final response = await _publicDio.post(
      'users/login/',
      data: {'email': email, 'password': password},
    );
    final data = response.data as Map<String, dynamic>;
    final access = data['access'] as String;
    final refresh = data['refresh'] as String;
    await TokenStorage.instance.save(access: access, refresh: refresh);

    final user = await _fetchMe();
    if (!user.isActive) {
      // Seconde barrière `is_confirmed` du formulaire web — avec, en plus,
      // la purge des jetons (voir [AccountNotApprovedException]).
      await TokenStorage.instance.clear();
      throw const AccountNotApprovedException();
    }
    _justLoggedIn = user;
    return LoginResult(access: access, refresh: refresh, user: user);
  }

  /// `djangoClient.auth.logout()`, dans le même ordre que le web :
  /// 1. `POST users/logout-event/` — horodatage de déconnexion sur le dernier
  ///    LoginEvent (best effort : l'échec est ignoré, comme le `console.warn`
  ///    du web) ; si l'access token vient d'expirer, un rafraîchissement puis
  ///    UNE relance, comme l'intercepteur du web ;
  /// 2. `POST users/refresh/` avec le refresh token (best effort, sans effet
  ///    serveur : le jeton n'est pas mis en liste noire — reproduit tel quel) ;
  /// 3. purge du stockage local. Le web fait `localStorage.clear()` ; ici les
  ///    jetons sont la seule donnée de session — l'URL du serveur
  ///    (`AppPrefs`) est une configuration d'installation, pas une donnée de
  ///    compte, et la vider obligerait à la ressaisir à chaque connexion.
  ///
  /// Tout passe par le Dio nu, volontairement : une déconnexion VOLONTAIRE
  /// avec des jetons périmés ne doit pas faire émettre `sessionExpired` par
  /// l'intercepteur (l'écran de connexion annoncerait à tort une session
  /// expirée). Ne lève jamais : la déconnexion locale doit toujours aboutir,
  /// même hors ligne ou avec des jetons déjà périmés.
  Future<void> logout() async {
    _justLoggedIn = null;
    final access = await TokenStorage.instance.accessToken;
    final refresh = await TokenStorage.instance.refreshToken;
    final dio = _publicDio;

    if (access != null && access.isNotEmpty) {
      await _recordLogoutEvent(dio, access: access, refresh: refresh);
    }

    if (refresh != null && refresh.isNotEmpty) {
      try {
        await dio.post('users/refresh/', data: {'refresh': refresh}).timeout(_bestEffortTimeout);
      } catch (_) {
        // Best effort — « [v0] Logout refresh request failed » côté web.
      }
    }

    await TokenStorage.instance.clear();
  }

  Future<void> _recordLogoutEvent(Dio dio, {required String access, required String? refresh}) async {
    Future<void> post(String token) => dio
        .post('users/logout-event/', options: Options(headers: {'Authorization': 'Bearer $token'}))
        .timeout(_bestEffortTimeout);
    try {
      await post(access);
    } on DioException catch (e) {
      // Access token périmé : rafraîchir puis relancer une seule fois.
      if (e.response?.statusCode != 401 || refresh == null || refresh.isEmpty) return;
      try {
        final refreshed = await dio.post('users/refresh/', data: {'refresh': refresh}).timeout(_bestEffortTimeout);
        final newAccess = (refreshed.data is Map) ? refreshed.data['access'] as String? : null;
        if (newAccess != null && newAccess.isNotEmpty) await post(newAccess);
      } catch (_) {
        // Best effort — « [v0] Logout event recording failed » côté web.
      }
    } catch (_) {
      // Best effort (délai dépassé, hors ligne…).
    }
  }

  /// `djangoClient.auth.getCurrentUser()` — `GET users/me/`.
  Future<AppUser> me() async {
    final cached = _justLoggedIn;
    if (cached != null) {
      _justLoggedIn = null;
      return cached;
    }
    return _fetchMe();
  }

  Future<AppUser> _fetchMe() async {
    final response = await _dio.get('users/me/');
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AppUser> updateProfile({String? fullName, String? phone, String? adresse}) async {
    final response = await _dio.patch('users/me/', data: {
      'full_name': ?fullName,
      'phone': ?phone,
      'adresse': ?adresse,
    });
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AppUser> uploadProfilePhoto(String filePath) async {
    final formData = FormData.fromMap({'photo': await MultipartFile.fromFile(filePath)});
    final response = await _dio.patch('users/me/', data: formData);
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    await _dio.post('users/change-password/', data: {'old_password': oldPassword, 'new_password': newPassword});
  }
}
