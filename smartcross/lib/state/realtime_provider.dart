import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/notifications_socket_service.dart';
import '../core/secure_storage.dart';
import 'auth_provider.dart';

/// Compteur incrémenté à chaque notification WebSocket reçue (§9 README).
/// Les providers de données (commandes, notifications) le `watch`ent pour se
/// rafraîchir automatiquement dès qu'un événement temps réel arrive, sans
/// dupliquer la logique de reconnexion dans chaque écran.
class RealtimeTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final realtimeTickProvider = NotifierProvider<RealtimeTickNotifier, int>(RealtimeTickNotifier.new);

/// Établit/ferme la connexion WebSocket en fonction de l'état d'auth, et
/// relaie chaque message vers [realtimeTickProvider]. À instancier une seule
/// fois à la racine de l'app (voir `main.dart`).
class RealtimeBootstrap {
  RealtimeBootstrap(this.ref) {
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated && previous?.status != AuthStatus.authenticated) {
        _connect();
      } else if (next.status != AuthStatus.authenticated) {
        NotificationsSocketService.instance.disconnect();
      }
    }, fireImmediately: true);

    _sub = NotificationsSocketService.instance.incoming.listen((_) {
      ref.read(realtimeTickProvider.notifier).bump();
    });
  }

  final Ref ref;
  StreamSubscription? _sub;

  void _connect() {
    NotificationsSocketService.instance.connect(() async {
      await ApiClient.instance.ensureInitialized();
      final token = await TokenStorage.instance.accessToken;
      return Uri.parse('${ApiClient.instance.wsBaseUrl}/ws/notifications/?token=$token');
    });
  }

  void dispose() {
    _sub?.cancel();
    NotificationsSocketService.instance.disconnect();
  }
}

final realtimeBootstrapProvider = Provider<RealtimeBootstrap>((ref) {
  final bootstrap = RealtimeBootstrap(ref);
  ref.onDispose(bootstrap.dispose);
  return bootstrap;
});

/// État de la connexion WebSocket temps réel — piloté par la topbar.
final wsConnectionStatusProvider = StreamProvider<bool>((ref) => NotificationsSocketService.instance.connectionStatus);
