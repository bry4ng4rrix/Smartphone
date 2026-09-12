import 'json_utils.dart';

/// Libellé d'un rôle Django brut, tel que l'affiche la messagerie web
/// (`getRoleLabel()` dans chats/page.tsx) : le sous-rôle Préparateur /
/// Livreur n'y apparaît jamais.
String chatRoleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Admin';
    case 'magasin':
      return 'Gérant';
    case 'employer':
      return 'Employé';
    default:
      return role;
  }
}

/// Initiales d'un nom complet — `getInitials()` du web : première lettre de
/// chaque mot, deux au maximum, en majuscules ; `U` si le nom est vide.
String chatInitials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
  final initials = parts.map((p) => p[0]).join().toUpperCase();
  return initials.isEmpty ? 'U' : initials;
}

/// Clé de tri alphabétique insensible à la casse et aux accents — approche
/// le `localeCompare(..., 'fr')` du web (« Élise » se range avec les E).
String _collationKey(String s) {
  const from = 'àâäáãåéèêëíìîïóòôöõúùûüçñýÿ';
  const to = 'aaaaaaeeeeiiiiooooouuuucnyy';
  final buffer = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final idx = from.indexOf(ch);
    buffer.write(idx == -1 ? ch : to[idx]);
  }
  return buffer.toString();
}

/// Un collègue de la société (autre gérant/préparateur/livreur) avec qui
/// discuter — `GET /api/users/chat/users/`.
class ChatUser {
  ChatUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.shopName,
    this.isOnline = false,
    this.lastSeenAt,
    this.unreadCount = 0,
    this.lastMessageAt,
  });

  final int id;
  final String fullName;
  final String email;
  final String role; // rôle Django brut (admin/magasin/employer)
  final String? shopName;
  // Présence recalculée côté serveur à CHAQUE appel de cet endpoint (pas de
  // push) : is_online = activité WS il y a moins de 40s — voir
  // users/views.py::ChatUsersListView. Rafraîchir périodiquement pour rester
  // à jour (chatUsersProvider, toutes les 20s côté chat_list_screen.dart).
  final bool isOnline;
  final DateTime? lastSeenAt;

  /// Messages reçus de CE contact et pas encore lus — badge par contact de la
  /// liste (§ demande). Même comptage que le badge global du menu
  /// (`chatUnreadProvider`), détaillé par expéditeur.
  final int unreadCount;

  /// Dernier message échangé avec ce contact, quel qu'en soit l'auteur — sert
  /// au classement de la liste ([compareForList]). null = jamais échangé.
  final DateTime? lastMessageAt;

  bool get hasUnread => unreadCount > 0;

  /// Texte du badge de non-lus — plafonné à « 99+ » comme sur le web.
  String get unreadBadgeLabel => unreadCount > 99 ? '99+' : '$unreadCount';

  /// `getRoleLabel()` du web : Admin / Gérant / Employé.
  String get roleLabel => chatRoleLabel(role);

  /// `getInitials()` du web (avatar).
  String get initials => chatInitials(fullName);

  /// Filtre de la barre « Rechercher un collaborateur... » (web) : insensible
  /// à la casse, sur le nom complet, l'e-mail OU le nom du magasin.
  bool matchesSearch(String query) {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return true;
    return fullName.toLowerCase().contains(term) ||
        email.toLowerCase().contains(term) ||
        (shopName?.toLowerCase().contains(term) ?? false);
  }

  /// Ordre de la liste des contacts, « comme une messagerie » (web,
  /// `filteredUsers.sort`) :
  ///
  /// 1. les conversations avec des messages NON LUS d'abord ;
  /// 2. à l'intérieur de chaque groupe, la plus récemment active en tête ;
  /// 3. les contacts avec qui on n'a jamais échangé ferment la marche, par
  ///    ordre alphabétique.
  static int compareForList(ChatUser a, ChatUser b) {
    final rangA = a.hasUnread ? 0 : 1;
    final rangB = b.hasUnread ? 0 : 1;
    if (rangA != rangB) return rangA - rangB;
    final quandA = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
    final quandB = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
    if (quandA != quandB) return quandB.compareTo(quandA);
    return _collationKey(a.fullName).compareTo(_collationKey(b.fullName));
  }

  /// Copie triée selon [compareForList] (l'original n'est pas modifié).
  static List<ChatUser> sortedForList(Iterable<ChatUser> users) => [...users]..sort(compareForList);

  ChatUser copyWith({
    String? shopName,
    bool? isOnline,
    DateTime? lastSeenAt,
    int? unreadCount,
    DateTime? lastMessageAt,
  }) {
    return ChatUser(
      id: id,
      fullName: fullName,
      email: email,
      role: role,
      shopName: shopName ?? this.shopName,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: asInt(json['id']),
      fullName: asString(json['full_name']),
      email: asString(json['email']),
      role: asString(json['role']),
      shopName: asStringOrNull(json['shop_name']),
      isOnline: asBool(json['is_online']),
      lastSeenAt: asDateOrNull(json['last_seen_at']),
      unreadCount: asInt(json['unread_count']),
      lastMessageAt: asDateOrNull(json['last_message_at']),
    );
  }
}

/// Un message de la messagerie — forme commune à l'historique REST
/// (`users/chat/history/`), à l'envoi d'image (`users/chat/upload/`) et aux
/// trames `{"type": "message", ...}` du WebSocket : toutes trois passent par
/// `ChatMessageSerializer` (ou en reproduisent exactement les champs).
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    this.senderName,
    this.senderEmail,
    this.senderRole,
    this.recipientId,
    this.recipientName,
    this.recipientEmail,
    required this.roomName,
    required this.content,
    this.image,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
    this.timestamp,
    this.readAt,
  });

  final int id;
  final int senderId;
  final String? senderName;
  final String? senderEmail;
  // Rôle Django brut de l'expéditeur (admin/magasin/employer) — mini-badge
  // de rôle sous le nom, voir [senderRoleLabel].
  final String? senderRole;
  final int? recipientId;
  final String? recipientName;
  final String? recipientEmail;
  final String roomName;
  // Facultatif depuis l'arrivée des images : un message peut n'être QU'une
  // image (le serveur exige au moins l'un des deux).
  final String content;

  /// URL absolue de l'image jointe (§ demande — bouton « + » du chat), ou
  /// null. Toujours null pour un message texte envoyé par le WebSocket : les
  /// images passent par HTTP (`ChatRepository.sendImage`) et reviennent
  /// ensuite par le socket avec l'URL renseignée.
  final String? image;
  final bool isEdited;
  final DateTime? editedAt;
  final bool isDeleted;
  final DateTime? timestamp;
  // Accusé de lecture — DM uniquement ("Général" a plusieurs destinataires,
  // pas de "vu" unique : le serveur ignore l'action "read" pour ce salon,
  // voir ChatConsumer.mark_read()). null = envoyé mais pas encore lu.
  final DateTime? readAt;

  bool get hasImage => image != null && image!.isNotEmpty;

  /// Message privé (destinataire unique) — par opposition à l'ancien salon
  /// Général, dont les messages n'ont pas de destinataire.
  bool get isDirect => recipientId != null;

  /// `getRoleLabel(msg.sender_role)` du web, ou null si le rôle est inconnu.
  String? get senderRoleLabel => senderRole == null ? null : chatRoleLabel(senderRole!);

  ChatMessage copyWith({
    String? content,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
    DateTime? readAt,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      senderEmail: senderEmail,
      senderRole: senderRole,
      recipientId: recipientId,
      recipientName: recipientName,
      recipientEmail: recipientEmail,
      roomName: roomName,
      content: content ?? this.content,
      image: image,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      timestamp: timestamp,
      readAt: readAt ?? this.readAt,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: asInt(json['id']),
      senderId: asInt(json['sender']),
      senderName: asStringOrNull(json['sender_name']),
      senderEmail: asStringOrNull(json['sender_email']),
      senderRole: asStringOrNull(json['sender_role']),
      recipientId: asIntOrNull(json['recipient']),
      recipientName: asStringOrNull(json['recipient_name']),
      recipientEmail: asStringOrNull(json['recipient_email']),
      roomName: asString(json['room_name']),
      content: asString(json['content']),
      image: asStringOrNull(json['image']),
      isEdited: asBool(json['is_edited']),
      editedAt: asDateOrNull(json['edited_at']),
      isDeleted: asBool(json['is_deleted']),
      timestamp: asDateOrNull(json['timestamp']),
      readAt: asDateOrNull(json['read_at']),
    );
  }
}
