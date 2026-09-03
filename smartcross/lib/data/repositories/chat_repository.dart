import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/chat.dart';

/// `/api/users/chat/` — liste des collègues et historique REST. L'envoi de
/// messages (et édition/suppression) se fait exclusivement via le WebSocket
/// `ws/chat/`, voir `chat_socket_service.dart`.
class ChatRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<ChatUser>> users() async {
    final response = await _dio.get('users/chat/users/');
    return (response.data as List).map((e) => ChatUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Historique d'une conversation privée ([recipientId]) ou du salon
  /// général de la société (par défaut).
  Future<List<ChatMessage>> history({int? recipientId, String roomName = 'general'}) async {
    final response = await _dio.get('users/chat/history/', queryParameters: {
      if (recipientId != null) 'recipient_id': recipientId else 'room_name': roomName,
    });
    return (response.data as List).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }
}
