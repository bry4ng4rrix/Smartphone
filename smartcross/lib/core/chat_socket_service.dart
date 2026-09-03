import 'dart:async';
import 'dart:convert';

import 'api_client.dart';
import 'secure_storage.dart';
import 'ws_manager.dart';

/// Connexion `ws/chat/` pour UNE conversation (salon général ou message
/// privé) — instance jetable créée/fermée par l'écran de conversation,
/// contrairement à `NotificationsSocketService` qui est un singleton
/// global. L'envoi/édition/suppression de message se fait uniquement via
/// cette socket (pas de POST REST, §9 README côté chat).
class ChatSocketService extends WsManager {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incoming => _controller.stream;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _statusController.stream;

  @override
  void onMessage(Map<String, dynamic> data) => _controller.add(data);

  @override
  void onStatusChange(bool connected) => _statusController.add(connected);

  /// [recipientId] pour une conversation privée, sinon salon général.
  void connectToConversation({int? recipientId}) {
    connect(() async {
      await ApiClient.instance.ensureInitialized();
      final token = await TokenStorage.instance.accessToken;
      final params = {'token': token ?? '', if (recipientId != null) 'recipient_id': recipientId.toString()};
      return Uri.parse('${ApiClient.instance.wsBaseUrl}/ws/chat/').replace(queryParameters: params);
    });
  }

  void sendMessage(String content) {
    _emit({'action': 'send', 'content': content});
  }

  void editMessage(int messageId, String content) {
    _emit({'action': 'edit', 'message_id': messageId, 'content': content});
  }

  void deleteMessage(int messageId) {
    _emit({'action': 'delete', 'message_id': messageId});
  }

  void _emit(Map<String, dynamic> payload) {
    if (!isConnected) return;
    send(jsonEncode(payload));
  }

  void disposeService() {
    disconnect();
    _controller.close();
    _statusController.close();
  }
}
