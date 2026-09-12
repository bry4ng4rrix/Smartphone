import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/data_sync_socket_service.dart';
import '../core/notifications_socket_service.dart';
import '../core/secure_storage.dart';
import 'auth_provider.dart';

/// Compteur incrémenté à chaque événement temps réel reçu — notification
/// (`ws/notifications/`, §9 README) OU événement de données (`ws/data/` :
/// commande, historique de statut, variante, mouvement de stock, commande
/// fournisseur, session et mouvement de caisse — les modèles du
/// `useRealtimeRefresh` web). Les providers de données le `watch`ent pour se
/// rafraîchir automatiquement, sans dupliquer la logique de reconnexion dans
/// chaque écran.
class RealtimeTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final realtimeTickProvider = NotifierProvider<RealtimeTickNotifier, int>(RealtimeTickNotifier.new);

/// Établit/ferme la connexion WebSocket en fonction de l'état d'auth, et
/// relaie chaque message vers [realtimeTickProvider]. À instancier une seule
/// fois à la racine de l'app (voir `main.dart`).
class RealtimeBootstrap with WidgetsBindingObserver {
  RealtimeBootstrap(this.ref) {
    WidgetsBinding.instance.addObserver(this);
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated && previous?.status != AuthStatus.authenticated) {
        _connect();
      } else if (next.status != AuthStatus.authenticated) {
        NotificationsSocketService.instance.disconnect();
        DataSyncSocketService.instance.disconnect();
      }
    }, fireImmediately: true);

    _sub = NotificationsSocketService.instance.incoming.listen((_) {
      ref.read(realtimeTickProvider.notifier).bump();
    });
    // Événements de données : regroupés (400 ms, comme le debounce de
    // useRealtimeRefresh) — une commande livrée enchaîne commande + historique
    // + mouvements de stock en rafale.
    _dataSub = DataSyncSocketService.instance.events.listen((_) {
      _dataDebounce?.cancel();
      _dataDebounce = Timer(const Duration(milliseconds: 400), () {
        ref.read(realtimeTickProvider.notifier).bump();
      });
    });
  }

  final Ref ref;
  StreamSubscription? _sub;
  StreamSubscription? _dataSub;
  Timer? _dataDebounce;

  Future<Uri> _uri(String path) async {
    await ApiClient.instance.ensureInitialized();
    final token = await TokenStorage.instance.accessToken;
    return Uri.parse('${ApiClient.instance.wsBaseUrl}$path?token=$token');
  }

  void _connect() {
    NotificationsSocketService.instance.connect(() => _uri('/ws/notifications/'));
    DataSyncSocketService.instance.connect(() => _uri('/ws/data/'));
  }

  /// Retour au premier plan : la connexion est rouverte sans délai si le
  /// système l'a coupée en arrière-plan, et les données temps réel
  /// (notifications, messages non lus, commandes) sont relues — les
  /// événements manqués pendant la coupure n'ont pas pu être poussés.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (ref.read(authProvider).status != AuthStatus.authenticated) return;
    NotificationsSocketService.instance.ensureConnected();
    DataSyncSocketService.instance.ensureConnected();
    ref.read(realtimeTickProvider.notifier).bump();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _dataSub?.cancel();
    _dataDebounce?.cancel();
    NotificationsSocketService.instance.disconnect();
    DataSyncSocketService.instance.disconnect();
  }
}

final realtimeBootstrapProvider = Provider<RealtimeBootstrap>((ref) {
  final bootstrap = RealtimeBootstrap(ref);
  ref.onDispose(bootstrap.dispose);
  return bootstrap;
});

/// État de la connexion WebSocket temps réel — piloté par la topbar.
final wsConnectionStatusProvider = StreamProvider<bool>((ref) => NotificationsSocketService.instance.connectionStatus);
