import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'secure_storage.dart';

/// URL par défaut selon la plateforme : `10.0.2.2` est l'alias que l'émulateur
/// Android utilise pour joindre `localhost` de la machine hôte — un vrai
/// device sur le LAN ou la prod doivent reconfigurer via l'écran serveur.
String get kDefaultServerUrl {
  if (kIsWeb) return 'http://127.0.0.1:8010';
  if (Platform.isAndroid) return 'http://10.0.2.2:8010';
  return 'http://127.0.0.1:8010';
}

enum AuthEventKind { sessionExpired }

class AuthEvent {
  AuthEvent(this.kind);
  final AuthEventKind kind;
}

class AuthEvents {
  AuthEvents._();
  static final AuthEvents instance = AuthEvents._();
  final _controller = StreamController<AuthEvent>.broadcast();
  Stream<AuthEvent> get stream => _controller.stream;
  void emit(AuthEvent event) => _controller.add(event);
}

/// Client HTTP central : base URL configurable, en-tête Authorization
/// automatique, et rafraîchissement JWT transparent sur 401.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStorage.instance.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final response = error.response;
        if (response?.statusCode == 401 && error.requestOptions.extra['retried'] != true) {
          final refreshed = await _tryRefresh();
          if (refreshed != null) {
            final req = error.requestOptions;
            req.extra['retried'] = true;
            req.headers['Authorization'] = 'Bearer $refreshed';
            try {
              final clone = await _dio.fetch(req);
              handler.resolve(clone);
              return;
            } catch (_) {
              // Le refresh a marché mais la requête d'origine échoue encore
              // pour une autre raison : on laisse remonter l'erreur d'origine.
            }
          } else {
            AuthEvents.instance.emit(AuthEvent(AuthEventKind.sessionExpired));
          }
        }
        handler.next(error);
      },
    ));
  }

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  Dio get dio => _dio;
  String _baseUrl = kDefaultServerUrl;
  String get baseUrl => _baseUrl;

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    final saved = await AppPrefs.instance.serverBaseUrl;
    setBaseUrl(saved ?? kDefaultServerUrl);
    _initialized = true;
  }

  void setBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    _baseUrl = normalized;
    _dio.options.baseUrl = '$normalized/api/';
  }

  /// URL WS dérivée de la base HTTP (http->ws, https->wss).
  String get wsBaseUrl {
    final uri = Uri.parse(_baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.authority}';
  }

  Future<String?> _tryRefresh() async {
    final refresh = await TokenStorage.instance.refreshToken;
    if (refresh == null || refresh.isEmpty) return null;
    try {
      final response = await Dio(BaseOptions(baseUrl: _dio.options.baseUrl))
          .post('users/refresh/', data: {'refresh': refresh});
      final access = response.data['access'] as String?;
      if (access != null) {
        await TokenStorage.instance.saveAccess(access);
        return access;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Vrai si [error] traduit une impossibilité de joindre le serveur plutôt
  /// qu'un vrai rejet de la requête (400/401/403/500...).
  static bool isConnectivityError(Object error) {
    if (error is DioException) {
      if (error.response != null) return false;
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return true;
        case DioExceptionType.unknown:
          return error.error is SocketException;
        default:
          return false;
      }
    }
    return error is SocketException;
  }

  /// Message d'erreur lisible extrait d'une DioException, réutilisé partout
  /// pour un affichage utilisateur cohérent.
  static String messageFromError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        for (final key in ['error', 'detail', 'message']) {
          final v = data[key];
          if (v is String && v.isNotEmpty) return v;
        }
        // Erreurs de validation DRF : {"field": ["msg1", "msg2"]} ou
        // {"non_field_errors": [...]}
        final parts = <String>[];
        data.forEach((key, value) {
          if (value is List) {
            parts.add('$key: ${value.join(', ')}');
          } else if (value is String) {
            parts.add('$key: $value');
          }
        });
        if (parts.isNotEmpty) return parts.join(' — ');
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'Impossible de contacter le serveur. Vérifiez votre connexion et l\'URL configurée.';
      }
      return error.message ?? 'Erreur réseau inconnue';
    }
    if (error is SocketException) {
      return 'Impossible de contacter le serveur.';
    }
    return error.toString();
  }
}
