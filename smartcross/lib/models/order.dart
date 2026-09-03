import '../core/constants.dart';
import 'json_utils.dart';

/// Article d'une commande. `prixUnitaire` est `null` pour le
/// préparateur/livreur (serializers restreints, §4/§7.2/§7.3 README).
class OrderItem {
  OrderItem({
    required this.id,
    this.productVariantId,
    required this.referenceName,
    required this.couleur,
    this.prixUnitaire,
    required this.quantite,
  });

  final int id;
  final int? productVariantId;
  final String referenceName;
  final String couleur;
  final double? prixUnitaire;
  final int quantite;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: asInt(json['id']),
      productVariantId: asIntOrNull(json['product_variant']),
      referenceName: asString(json['reference_name']),
      couleur: asString(json['couleur']),
      prixUnitaire: asDoubleOrNull(json['prix_unitaire']),
      quantite: asInt(json['quantite'], 1),
    );
  }
}

class OrderStatusHistoryEntry {
  OrderStatusHistoryEntry({
    required this.id,
    this.ancienStatut,
    required this.nouveauStatut,
    this.changedByName,
    this.note,
    required this.timestamp,
  });

  final int id;
  final OrderStatus? ancienStatut;
  final OrderStatus nouveauStatut;
  final String? changedByName;
  final String? note;
  final DateTime? timestamp;

  factory OrderStatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryEntry(
      id: asInt(json['id']),
      ancienStatut: json['ancien_statut'] != null ? OrderStatusX.fromApi(asString(json['ancien_statut'])) : null,
      nouveauStatut: OrderStatusX.fromApi(asString(json['nouveau_statut'])),
      changedByName: asStringOrNull(json['changed_by_name']),
      note: asStringOrNull(json['note']),
      timestamp: asDateOrNull(json['timestamp']),
    );
  }
}

/// Commande client (§6, §11 README). Les champs financiers
/// (`fraisLivraison`, `totalAPayer` pour le préparateur ; tout sauf total
/// pour le gérant/livreur) dépendent du rôle du viewer côté API — laissés
/// nullable ici plutôt que dupliqués en 3 classes, pour rester simple.
class Order {
  Order({
    required this.id,
    required this.numero,
    this.dateCommande,
    required this.clientNom,
    this.telephone,
    required this.livraisonZone,
    this.adresseLivraison,
    this.fraisLivraison,
    this.totalAPayer,
    this.note,
    required this.statutCourant,
    required this.items,
    this.statusHistory = const [],
    this.createdAt,
  });

  final int id;
  final String numero;
  final DateTime? dateCommande;
  final String clientNom;
  final String? telephone;
  final DeliveryZone livraisonZone;
  final String? adresseLivraison;
  final double? fraisLivraison;
  final double? totalAPayer;
  final String? note;
  final OrderStatus statutCourant;
  final List<OrderItem> items;
  final List<OrderStatusHistoryEntry> statusHistory;
  final DateTime? createdAt;

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: asInt(json['id']),
      numero: asString(json['numero']),
      dateCommande: asDateOrNull(json['date_commande']),
      clientNom: asString(json['client_nom']),
      telephone: asStringOrNull(json['telephone']),
      livraisonZone: DeliveryZoneX.fromApi(asStringOrNull(json['livraison_zone'])),
      adresseLivraison: asStringOrNull(json['adresse_livraison']),
      fraisLivraison: asDoubleOrNull(json['frais_livraison']),
      totalAPayer: asDoubleOrNull(json['total_a_payer']),
      note: asStringOrNull(json['note']),
      statutCourant: OrderStatusX.fromApi(asString(json['statut_courant'])),
      items: (json['items'] as List? ?? []).map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList(),
      statusHistory: (json['status_history'] as List? ?? [])
          .map((e) => OrderStatusHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}

/// Un article du formulaire "Nouvelle commande" (§6 README), avant envoi.
class OrderItemDraft {
  OrderItemDraft({required this.productVariant, required this.quantite});

  final int productVariant;
  final int quantite;

  Map<String, dynamic> toJson() => {'product_variant': productVariant, 'quantite': quantite};
}
