import 'dart:async';

import 'ws_manager.dart';

/// Client de `ws/notifications/` (§9 README) : le serveur y pousse chaque
/// [Notification] créée en temps réel (nouvelle commande -> groupe
/// Préparateur, commande prête -> groupe Livreur).
class NotificationsSocketService extends WsManager {
  NotificationsSocketService._();
  static final NotificationsSocketService instance = NotificationsSocketService._();

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incoming => _controller.stream;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _statusController.stream;

  @override
  void onMessage(Map<String, dynamic> data) {
    _controller.add(data);
  }

  @override
  void onStatusChange(bool connected) {
    _statusController.add(connected);
  }
}
