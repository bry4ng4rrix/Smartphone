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

  // Heartbeat de présence — toute trame reçue par le serveur met à jour
  // last_seen_at (ChatConsumer.receive() -> touch_last_seen()) ; un ping
  // sans "content" suffit et n'est jamais traité comme un message. Tant que
  // ce device reste sur cet écran, il compte donc comme "en ligne" pour les
  // autres (la présence n'est jamais poussée par le serveur, seulement
  // recalculée à chaque GET /chat/users/, cf. chat_list_screen.dart).
  Timer? _pingTimer;

  @override
  void onMessage(Map<String, dynamic> data) => _controller.add(data);

  @override
  void onStatusChange(bool connected) {
    _statusController.add(connected);
    _pingTimer?.cancel();
    if (connected) {
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => _emit({'action': 'ping'}));
    }
  }

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

  /// Marque comme lus tous les messages reçus non lus de CETTE conversation
  /// (no-op serveur si ce n'est pas une conversation directe, voir
  /// ChatConsumer.mark_read()) — le serveur répond en broadcastant
  /// `{"type": "message_read", "ids": [...], "read_at": ...}` sur le salon.
  void markRead() {
    _emit({'action': 'read'});
  }

  void _emit(Map<String, dynamic> payload) {
    if (!isConnected) return;
    send(jsonEncode(payload));
  }

  void disposeService() {
    _pingTimer?.cancel();
    disconnect();
    _controller.close();
    _statusController.close();
  }
}
