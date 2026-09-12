import 'dart:async';
import 'dart:convert';

import '../models/chat.dart';
import '../models/json_utils.dart';
import 'api_client.dart';
import 'secure_storage.dart';
import 'ws_manager.dart';

/// État de la connexion `ws/chat/` — les trois badges du web
/// (« Connexion... » ambre, « En ligne » émeraude, « Hors ligne » rose).
enum ChatSocketStatus { connecting, connected, disconnected }

/// Trame reçue sur `ws/chat/`, décodée — voir `users/consumers.py`.
sealed class ChatSocketEvent {
  const ChatSocketEvent();

  /// Décode une trame JSON du serveur ; null si elle n'est pas reconnue.
  static ChatSocketEvent? parse(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'message_edited':
        final id = asIntOrNull(data['id']);
        if (id == null) return null;
        return ChatMessageEdited(
          id: id,
          content: asString(data['content']),
          isEdited: asBool(data['is_edited'], true),
          editedAt: asDateOrNull(data['edited_at']),
        );
      case 'message_deleted':
        final id = asIntOrNull(data['id']);
        if (id == null) return null;
        return ChatMessageDeleted(id);
      case 'message_read':
        final ids = (data['ids'] as List?)?.map(asIntOrNull).whereType<int>().toSet() ?? const <int>{};
        return ChatMessagesRead(ids: ids, readAt: asDateOrNull(data['read_at']));
      default:
        // Tout le reste est un nouveau message (`type: "message"`, ou une
        // charge utile sans type) — comme `ws.onmessage` côté web.
        if (data['id'] == null || data['sender'] == null) return null;
        return ChatMessageReceived(ChatMessage.fromJson(data));
    }
  }
}

/// Nouveau message dans la conversation (texte envoyé par le socket, ou image
/// envoyée par HTTP puis diffusée par le serveur). Le serveur renvoie AUSSI
/// nos propres messages : c'est cet événement qui les fait apparaître (pas
/// d'ajout optimiste), en dédoublonnant par `id`.
class ChatMessageReceived extends ChatSocketEvent {
  const ChatMessageReceived(this.message);
  final ChatMessage message;
}

class ChatMessageEdited extends ChatSocketEvent {
  const ChatMessageEdited({required this.id, required this.content, required this.isEdited, this.editedAt});
  final int id;
  final String content;
  final bool isEdited;
  final DateTime? editedAt;
}

class ChatMessageDeleted extends ChatSocketEvent {
  const ChatMessageDeleted(this.id);
  final int id;
}

/// Accusé de lecture diffusé par le serveur après une action « read » (la
/// nôtre ou celle de l'autre partie) : les messages [ids] sont « vus ».
class ChatMessagesRead extends ChatSocketEvent {
  const ChatMessagesRead({required this.ids, this.readAt});
  final Set<int> ids;
  final DateTime? readAt;
}

/// Connexion `ws/chat/` pour UNE conversation — instance jetable
/// créée/fermée par l'écran de conversation, contrairement à
/// `NotificationsSocketService` qui est un singleton global. L'envoi,
/// l'édition, la suppression et l'accusé de lecture d'un message passent
/// uniquement par cette socket ; SEULE l'image passe par HTTP
/// (`ChatRepository.sendImage`) puis revient ici comme un message ordinaire.
///
/// Comportements repris de `chats/page.tsx` :
/// * heartbeat de présence toutes les 20 s ;
/// * reconnexion 3 s après une coupure non voulue (WsManager), reflétée par
///   [status] = [ChatSocketStatus.connecting] ;
/// * ouvrir une conversation DIRECTE (et chaque reconnexion) marque « vu »
///   les messages reçus non lus, de même qu'un message reçu de
///   l'interlocuteur pendant que la conversation est affichée.
class ChatSocketService extends WsManager {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// Trames brutes, telles que reçues (conservé pour les écrans existants ;
  /// préférer [events]).
  Stream<Map<String, dynamic>> get incoming => _controller.stream;

  final _eventsController = StreamController<ChatSocketEvent>.broadcast();

  /// Trames décodées — voir [ChatSocketEvent].
  Stream<ChatSocketEvent> get events => _eventsController.stream;

  final _statusController = StreamController<bool>.broadcast();

  /// Connecté / déconnecté (conservé pour les écrans existants ; [status]
  /// distingue en plus « Connexion... »).
  Stream<bool> get connectionStatus => _statusController.stream;

  final _stateController = StreamController<ChatSocketStatus>.broadcast();

  /// État à trois valeurs, pour le badge de l'en-tête de conversation.
  Stream<ChatSocketStatus> get status => _stateController.stream;

  ChatSocketStatus _status = ChatSocketStatus.disconnected;
  ChatSocketStatus get currentStatus => _status;

  int? _recipientId;

  /// Interlocuteur de la conversation directe ; null = ancien salon général.
  int? get recipientId => _recipientId;
  bool get isDirect => _recipientId != null;

  /// Marquer automatiquement « vu » à la connexion et à la réception d'un
  /// message de l'interlocuteur (conversation directe seulement).
  bool autoMarkRead = true;

  // Heartbeat de présence — toute trame reçue par le serveur met à jour
  // last_seen_at (ChatConsumer.receive() -> touch_last_seen()) ; un ping
  // sans "content" suffit et n'est jamais traité comme un message. Tant que
  // ce device reste sur cet écran, il compte donc comme "en ligne" pour les
  // autres (la présence n'est jamais poussée par le serveur, seulement
  // recalculée à chaque GET /chat/users/, cf. chat_list_screen.dart).
  Timer? _pingTimer;

  // WsManager retente 3 s après une coupure non voulue, sans le signaler :
  // ce minuteur fait passer [status] à « connecting » au même moment.
  Timer? _reconnectHint;
  bool _userClosed = false;
  bool _disposed = false;

  @override
  void onMessage(Map<String, dynamic> data) {
    if (_disposed) return;
    _controller.add(data);
    final event = ChatSocketEvent.parse(data);
    if (event == null) return;
    _eventsController.add(event);
    // Message reçu de l'interlocuteur pendant que la conversation DIRECTE
    // est affichée -> le marquer « vu » tout de suite (miroir web :
    // ws.onmessage). "Général" n'a pas de statut « vu » : rien à envoyer.
    if (autoMarkRead && isDirect && event is ChatMessageReceived && event.message.senderId == _recipientId) {
      markRead();
    }
  }

  @override
  void onStatusChange(bool connected) {
    if (connected && (_userClosed || _disposed)) {
      // Tentative de connexion (WsManager) aboutie APRÈS une fermeture
      // volontaire : refermer aussitôt plutôt que laisser une socket
      // orpheline pinger le serveur.
      super.disconnect();
      return;
    }
    if (_disposed) return;
    _statusController.add(connected);
    _pingTimer?.cancel();
    _reconnectHint?.cancel();
    if (connected) {
      _setStatus(ChatSocketStatus.connected);
      // Ouvrir une conversation directe = la consulter -> marquer les
      // messages reçus non lus comme « vu » côté serveur (miroir web :
      // ws.onopen). Rejoué à chaque reconnexion.
      if (autoMarkRead && isDirect) markRead();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => _emit({'action': 'ping'}));
    } else {
      _setStatus(ChatSocketStatus.disconnected);
      if (!_userClosed) {
        _reconnectHint = Timer(const Duration(seconds: 3), () {
          if (!_disposed && !_userClosed && !isConnected) _setStatus(ChatSocketStatus.connecting);
        });
      }
    }
  }

  void _setStatus(ChatSocketStatus value) {
    if (_disposed || _status == value) return;
    _status = value;
    _stateController.add(value);
  }

  /// [recipientId] pour une conversation privée, sinon l'ancien salon
  /// général (plus proposé par le web — conservé pour les écrans existants).
  void connectToConversation({int? recipientId}) {
    if (_disposed) return;
    _recipientId = recipientId;
    _userClosed = false;
    _setStatus(ChatSocketStatus.connecting);
    connect(() async {
      await ApiClient.instance.ensureInitialized();
      final token = await TokenStorage.instance.accessToken;
      final params = {
        'token': token ?? '',
        if (recipientId != null) 'recipient_id': recipientId.toString() else 'room': 'general',
      };
      return Uri.parse('${ApiClient.instance.wsBaseUrl}/ws/chat/').replace(queryParameters: params);
    });
  }

  /// Envoie un message texte ; renvoie false (sans rien envoyer) si le texte
  /// est vide ou si la socket n'est pas connectée — même garde silencieuse
  /// que `handleSendMessage` côté web. Pas d'ajout optimiste : le message
  /// apparaît quand le serveur le renvoie ([ChatMessageReceived]).
  bool sendMessage(String content) {
    final text = content.trim();
    if (text.isEmpty) return false;
    return _emit({'action': 'send', 'content': text});
  }

  /// Modifie un de SES messages ; refusé côté serveur sinon (ou s'il est
  /// supprimé). Le nouveau contenu arrive par [ChatMessageEdited].
  bool editMessage(int messageId, String content) {
    final text = content.trim();
    if (text.isEmpty) return false;
    return _emit({'action': 'edit', 'message_id': messageId, 'content': text});
  }

  /// Supprime un de SES messages (soft delete) — confirmation « Supprimer ce
  /// message ? » à la charge de l'écran. Reflété par [ChatMessageDeleted].
  bool deleteMessage(int messageId) {
    return _emit({'action': 'delete', 'message_id': messageId});
  }

  /// Marque comme lus tous les messages reçus non lus de CETTE conversation
  /// (no-op serveur si ce n'est pas une conversation directe, voir
  /// ChatConsumer.mark_read()) — le serveur répond en broadcastant
  /// `{"type": "message_read", "ids": [...], "read_at": ...}` sur le salon.
  bool markRead() {
    return _emit({'action': 'read'});
  }

  bool _emit(Map<String, dynamic> payload) {
    if (_disposed || !isConnected) return false;
    send(jsonEncode(payload));
    return true;
  }

  @override
  void disconnect() {
    _userClosed = true;
    _reconnectHint?.cancel();
    _pingTimer?.cancel();
    super.disconnect();
  }

  void disposeService() {
    if (_disposed) return;
    disconnect();
    _disposed = true;
    _controller.close();
    _eventsController.close();
    _statusController.close();
    _stateController.close();
  }
}
