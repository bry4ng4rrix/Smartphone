import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage chiffré des tokens JWT (access/refresh).
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  final _secure = const FlutterSecureStorage();

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  Future<void> save({required String access, required String refresh}) async {
    await _secure.write(key: _kAccess, value: access);
    await _secure.write(key: _kRefresh, value: refresh);
  }

  Future<void> saveAccess(String access) async {
    await _secure.write(key: _kAccess, value: access);
  }

  Future<String?> get accessToken => _secure.read(key: _kAccess);
  Future<String?> get refreshToken => _secure.read(key: _kRefresh);

  Future<void> clear() async {
    await _secure.delete(key: _kAccess);
    await _secure.delete(key: _kRefresh);
  }
}

/// Préférences non sensibles (URL serveur configurable — utile pour pointer
/// vers le poste de dev, un appareil réel sur le LAN, ou la prod plus tard).
class AppPrefs {
  AppPrefs._();
  static final AppPrefs instance = AppPrefs._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async => _prefs ??= await SharedPreferences.getInstance();

  static const _kServerUrl = 'server_base_url';

  Future<String?> get serverBaseUrl async => (await _sp).getString(_kServerUrl);

  Future<void> setServerBaseUrl(String url) async {
    (await _sp).setString(_kServerUrl, url);
  }
}
