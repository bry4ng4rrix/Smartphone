import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/chat.dart';

/// `/api/users/chat/` — liste des collègues, historique REST, compteur de
/// non-lus et envoi d'image. L'envoi de messages TEXTE (et édition,
/// suppression, accusé de lecture) se fait exclusivement via le WebSocket
/// `ws/chat/`, voir `chat_socket_service.dart`.
///
/// Miroir de `djangoClient.chat` (frontend/lib/django-client.ts).
class ChatRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// Contacts de la société, DÉJÀ classés comme sur le web : conversations
  /// avec des non-lus d'abord, puis la plus récemment active, puis les
  /// contacts jamais contactés par ordre alphabétique
  /// ([ChatUser.compareForList]). Chaque contact porte `unreadCount` et
  /// `lastMessageAt` (ChatUsersListView).
  Future<List<ChatUser>> users() async {
    final response = await _dio.get('users/chat/users/');
    final users = (response.data as List).map((e) => ChatUser.fromJson(e as Map<String, dynamic>));
    return ChatUser.sortedForList(users);
  }

  /// Nombre total de messages directs non lus du compte connecté — badge de
  /// l'entrée « Discussions » du menu (`GET users/chat/unread-count/`, même
  /// COUNT léger que le sidebar web). Voir `chatUnreadProvider`.
  Future<int> unreadCount() async {
    final response = await _dio.get('users/chat/unread-count/');
    final data = response.data;
    final count = data is Map ? data['count'] : null;
    if (count is num) return count.toInt();
    return int.tryParse(count?.toString() ?? '') ?? 0;
  }

  /// Historique d'une conversation privée ([recipientId]) — les 100 derniers
  /// messages, dans l'ordre chronologique.
  ///
  /// Sans [recipientId], renvoie l'ancien salon général de la société
  /// (`room_name`) : ce salon N'EXISTE PLUS côté web (conversations directes
  /// uniquement), le serveur le sert encore et les écrans Flutter actuels
  /// (`/chats/room/general`) s'en servent — la branche est conservée tant
  /// qu'ils ne sont pas migrés.
  Future<List<ChatMessage>> history({int? recipientId, String roomName = 'general'}) async {
    final response = await _dio.get('users/chat/history/', queryParameters: {
      if (recipientId != null) 'recipient_id': recipientId else 'room_name': roomName,
    });
    return (response.data as List).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Envoi d'une image dans le chat (bouton « + » : fichier ou photo prise à
  /// l'appareil) — `POST users/chat/upload/` en multipart.
  ///
  /// Le WebSocket ne transporte que du JSON : l'image passe donc par HTTP.
  /// Le serveur crée le message PUIS le diffuse au même groupe temps réel :
  /// il revient par le socket comme un message texte
  /// (`{"type": "message", ...}`) — l'écran ne doit donc PAS l'ajouter
  /// lui-même à la liste (ou dédoublonner par `id`), exactement comme sur
  /// le web. La réponse est tout de même renvoyée (même forme que le socket).
  ///
  /// [content] : légende facultative, envoyée seulement si non vide.
  /// [recipientId] : conversation privée ; null = ancien salon général.
  ///
  /// Erreurs serveur (à afficher via `ApiClient.messageFromError`) :
  /// « Aucune image reçue. » (400), « Destinataire introuvable » (404),
  /// « Permission refusée » / « Deux livreurs ne peuvent pas se contacter
  /// entre eux » (403).
  Future<ChatMessage> sendImage(File image, {String? content, int? recipientId}) async {
    final caption = content?.trim() ?? '';
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(image.path, contentType: _imageMediaType(image.path)),
      if (caption.isNotEmpty) 'content': caption,
      'recipient_id': ?recipientId,
    });
    final response = await _dio.post('users/chat/upload/', data: formData);
    return ChatMessage.fromJson(response.data as Map<String, dynamic>);
  }

  /// Type MIME déduit de l'extension du fichier choisi (image_picker /
  /// appareil photo) — l'`accept="image/*"` de l'input web. Inconnue ->
  /// `image/jpeg`, le format que produit image_picker avec `imageQuality`.
  static DioMediaType _imageMediaType(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'png':
        return DioMediaType('image', 'png');
      case 'gif':
        return DioMediaType('image', 'gif');
      case 'webp':
        return DioMediaType('image', 'webp');
      case 'bmp':
        return DioMediaType('image', 'bmp');
      case 'heic':
        return DioMediaType('image', 'heic');
      case 'heif':
        return DioMediaType('image', 'heif');
      default:
        return DioMediaType('image', 'jpeg');
    }
  }
}
