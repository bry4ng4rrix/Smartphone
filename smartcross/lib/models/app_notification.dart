import 'json_utils.dart';

enum NotifType { nouvelleCommande, commandePrete, unknown }

// Le backend multi-tenant regroupe toute notification commande sous un seul
// notif_type="order" (pas de distinction NOUVELLE_COMMANDE/COMMANDE_PRETE
// côté modèle, §9 Smartreadme.md) — on affine via le texte du message.
extension NotifTypeX on NotifType {
  static NotifType fromApi(String? notifType, [String? message]) {
    if (notifType != 'order') return NotifType.unknown;
    final text = (message ?? '').toLowerCase();
    if (text.contains('prête') || text.contains('prete')) return NotifType.commandePrete;
    if (text.contains('nouvelle commande')) return NotifType.nouvelleCommande;
    return NotifType.unknown;
  }
}

final _numeroRe = RegExp(r'CMD-\S+');

/// Notification métier (§9 README) : nouvelle commande -> Préparateur,
/// commande prête -> Livreur. Reçue en REST et en temps réel via WebSocket.
class AppNotification {
  AppNotification({
    required this.id,
    required this.notifType,
    required this.message,
    this.orderId,
    this.orderNumero,
    this.isRead = false,
    this.createdAt,
  });

  final int id;
  final NotifType notifType;
  final String message;
  final int? orderId;
  final String? orderNumero;
  final bool isRead;
  final DateTime? createdAt;

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      notifType: notifType,
      message: message,
      orderId: orderId,
      orderNumero: orderNumero,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final message = asString(json['message']);
    return AppNotification(
      id: asInt(json['id']),
      notifType: NotifTypeX.fromApi(asStringOrNull(json['notif_type']), message),
      message: message,
      // Pas de FK order sur ce modèle de notification — on récupère le
      // numéro depuis le message (toujours inclus, §9 Smartreadme.md) pour
      // permettre le deep-link ; il n'y a pas d'id direct disponible.
      orderId: null,
      orderNumero: _numeroRe.firstMatch(message)?.group(0),
      isRead: asBool(json['is_read']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}
