import 'json_utils.dart';

/// Sous-type métier d'une notification « commande » (§9 README) : nouvelle
/// commande -> Préparateur, commande prête -> Livreur.
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

/// Libellé d'un `notif_type` — `typeLabel()` de
/// frontend/lib/notifications-utils.tsx (sale/product/user/chat/transfer/
/// movement, défaut « Autre »), complété par les types que le serveur émet
/// réellement (users/models.py::Notification.NOTIF_TYPES : order,
/// supplier_order, user, chat, caisse, other) et que le web laisse retomber
/// sur « Autre ».
String notificationTypeLabel(String type) {
  switch (type) {
    case 'sale':
      return 'Vente';
    case 'product':
      return 'Produit';
    case 'user':
      return 'Utilisateur';
    case 'chat':
      return 'Chat';
    case 'transfer':
      return 'Transfert';
    case 'movement':
      return 'Mouvement';
    case 'order':
      return 'Commande';
    case 'supplier_order':
      return 'Commande fournisseur';
    case 'caisse':
      return 'Caisse';
    default:
      return 'Autre';
  }
}

/// Numéro de commande tel que généré par le serveur
/// (orders/models.py::Order.generate_numero) : `CMD-{magasin}-{AAAAMMJJ}-{seq}`.
/// Les messages de notification commande l'incluent toujours (§9
/// Smartreadme.md) — c'est le seul lien exploitable vers la commande, le
/// modèle Notification n'ayant pas de clé étrangère `order`.
final RegExp kOrderNumeroRegExp = RegExp(r'CMD-\d+-\d{8}-\d{4}');

/// Notification in-app (users/models.py::Notification), reçue en REST
/// (`NotificationSerializer` : id, notif_type, message, magasin,
/// magasin_name, caisse_session, user, user_name, is_read, created_at) et en
/// temps réel via WebSocket — où `id` peut être absent (diffusion des
/// notifications créées en masse, voir orders/services.py::
/// _broadcast_notification_ws) : [isPersisted] le signale.
class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.message,
    this.orderNumero,
    this.magasinId,
    this.magasinName,
    this.caisseSessionId,
    this.userId,
    this.userName,
    this.isRead = false,
    this.createdAt,
  });

  final int id;

  /// `notif_type` brut du serveur (order, supplier_order, user, chat, caisse,
  /// other…). Voir [typeLabel].
  final String type;
  final String message;

  /// Numéro de commande extrait du message (deep-link), `null` si le message
  /// n'en contient pas.
  final String? orderNumero;

  final int? magasinId;
  final String? magasinName;
  final int? caisseSessionId;
  final int? userId;
  final String? userName;
  final bool isRead;
  final DateTime? createdAt;

  /// Sous-type commande (icône dédiée nouvelle commande / commande prête).
  NotifType get notifType => NotifTypeX.fromApi(type, message);

  String get typeLabel => notificationTypeLabel(type);

  /// Faux pour une notification reçue par WebSocket sans identifiant — elle
  /// ne peut être ni marquée lue ni supprimée tant que la liste REST n'a
  /// pas été relue.
  bool get isPersisted => id > 0;

  /// Première partie de la ligne de métadonnées du web (page
  /// /notifications) : `Utilisateur : {user_name}` si présent — les branches
  /// `Produit :` / `Vente #` du web s'appuient sur des champs que le
  /// sérialiseur n'expose pas, elles ne s'affichent jamais.
  String? get subjectLabel {
    final name = userName?.trim();
    if (name != null && name.isNotEmpty) return 'Utilisateur : $name';
    return null;
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      message: message,
      orderNumero: orderNumero,
      magasinId: magasinId,
      magasinName: magasinName,
      caisseSessionId: caisseSessionId,
      userId: userId,
      userName: userName,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final message = asString(json['message']);
    return AppNotification(
      // `id` absent/null dans les trames WebSocket des notifications créées
      // en masse -> 0 (voir [isPersisted]).
      id: asIntOrNull(json['id']) ?? 0,
      type: asStringOrNull(json['notif_type']) ?? 'other',
      message: message,
      orderNumero: kOrderNumeroRegExp.firstMatch(message)?.group(0),
      magasinId: asIntOrNull(json['magasin']),
      magasinName: asStringOrNull(json['magasin_name']),
      caisseSessionId: asIntOrNull(json['caisse_session']),
      userId: asIntOrNull(json['user']),
      userName: asStringOrNull(json['user_name']),
      isRead: asBool(json['is_read']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}
