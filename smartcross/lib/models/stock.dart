import '../core/constants.dart';
import 'json_utils.dart';

class StockMovement {
  StockMovement({
    required this.id,
    required this.productVariantId,
    required this.variantLabel,
    required this.type,
    required this.quantite,
    required this.origine,
    this.reference,
    this.note,
    this.userName,
    this.timestamp,
  });

  final int id;
  final int productVariantId;
  final String variantLabel;
  final StockMovementType type;
  final int quantite;
  final String origine;
  final String? reference;
  final String? note;
  final String? userName;
  final DateTime? timestamp;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final referenceName = asString(json['reference_name']);
    final couleur = asString(json['couleur']);
    return StockMovement(
      id: asInt(json['id']),
      productVariantId: asInt(json['product_variant']),
      variantLabel: couleur.isNotEmpty ? '$referenceName — $couleur' : referenceName,
      type: StockMovementTypeX.fromApi(asString(json['type'])),
      quantite: asInt(json['quantite']),
      origine: asString(json['origine']),
      reference: asStringOrNull(json['reference']),
      note: asStringOrNull(json['note']),
      userName: asStringOrNull(json['user_name']),
      timestamp: asDateOrNull(json['timestamp']),
    );
  }
}

/// Ligne de la liste ruptures/stock bas (§7.5 README).
class RuptureItem {
  RuptureItem({
    required this.id,
    required this.referenceName,
    required this.brandName,
    required this.typeName,
    required this.categoryName,
    required this.couleur,
    required this.stockActuel,
    required this.seuilAlerte,
    required this.statut,
  });

  final int id;
  final String referenceName;
  final String brandName;
  final String typeName;
  final String categoryName;
  final String couleur;
  final int stockActuel;
  final int seuilAlerte;
  final String statut; // RUPTURE | STOCK_BAS

  bool get isRupture => statut == 'RUPTURE';

  /// Quantité suggérée à commander (même règle que l'export PDF serveur).
  int get quantiteACommander => (seuilAlerte - stockActuel).clamp(1, 1 << 30);

  factory RuptureItem.fromJson(Map<String, dynamic> json) {
    return RuptureItem(
      id: asInt(json['id']),
      referenceName: asString(json['reference_name']),
      brandName: asString(json['brand_name']),
      typeName: asString(json['type_name']),
      categoryName: asString(json['category_name']),
      couleur: asString(json['couleur']),
      stockActuel: asInt(json['stock_actuel']),
      seuilAlerte: asInt(json['seuil_alerte']),
      statut: asString(json['statut']),
    );
  }
}
