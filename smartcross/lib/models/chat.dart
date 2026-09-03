import 'json_utils.dart';

/// Un collègue de la société (autre gérant/préparateur/livreur) avec qui
/// discuter — `GET /api/users/chat/users/`.
class ChatUser {
  ChatUser({required this.id, required this.fullName, required this.email, required this.role, this.shopName});

  final int id;
  final String fullName;
  final String email;
  final String role; // rôle Django brut (admin/magasin/employer)
  final String? shopName;

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: asInt(json['id']),
      fullName: asString(json['full_name']),
      email: asString(json['email']),
      role: asString(json['role']),
      shopName: asStringOrNull(json['shop_name']),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    this.senderName,
    this.recipientId,
    this.recipientName,
    required this.roomName,
    required this.content,
    this.isEdited = false,
    this.isDeleted = false,
    this.timestamp,
  });

  final int id;
  final int senderId;
  final String? senderName;
  final int? recipientId;
  final String? recipientName;
  final String roomName;
  final String content;
  final bool isEdited;
  final bool isDeleted;
  final DateTime? timestamp;

  ChatMessage copyWith({String? content, bool? isEdited, bool? isDeleted}) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      recipientId: recipientId,
      recipientName: recipientName,
      roomName: roomName,
      content: content ?? this.content,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      timestamp: timestamp,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: asInt(json['id']),
      senderId: asInt(json['sender']),
      senderName: asStringOrNull(json['sender_name']),
      recipientId: asIntOrNull(json['recipient']),
      recipientName: asStringOrNull(json['recipient_name']),
      roomName: asString(json['room_name']),
      content: asString(json['content']),
      isEdited: asBool(json['is_edited']),
      isDeleted: asBool(json['is_deleted']),
      timestamp: asDateOrNull(json['timestamp']),
    );
  }
}
