import '../core/constants.dart';
import 'json_utils.dart';

class SupplierOrderLine {
  SupplierOrderLine({
    required this.id,
    required this.productVariantId,
    required this.referenceName,
    required this.couleur,
    required this.quantite,
    required this.coutUnitaireCalcule,
    required this.totalLigne,
    required this.margeUnitaire,
  });

  final int id;
  final int productVariantId;
  final String referenceName;
  final String couleur;
  final int quantite;

  /// Coût unitaire de la commande, réparti sur chaque ligne côté serveur
  /// (`suppliers/services.py::recompute_costs`).
  final double coutUnitaireCalcule;
  final double totalLigne;

  /// `prix_vente` de la référence − coût unitaire calculé (backend).
  final double margeUnitaire;

  factory SupplierOrderLine.fromJson(Map<String, dynamic> json) {
    return SupplierOrderLine(
      id: asInt(json['id']),
      productVariantId: asInt(json['product_variant']),
      referenceName: asString(json['reference_name']),
      couleur: asString(json['couleur']),
      quantite: asInt(json['quantite']),
      coutUnitaireCalcule: asDouble(json['cout_unitaire_calcule']),
      totalLigne: asDouble(json['total_ligne']),
      margeUnitaire: asDouble(json['marge_unitaire']),
    );
  }
}

/// Commande fournisseur (§7.6 README) : coût de revient réel = marchandise
/// + fret/import + douane, réparti sur chaque ligne — miroir de
/// `suppliers/serializers.py::SupplierOrderSerializer`.
class SupplierOrder {
  SupplierOrder({
    required this.id,
    required this.magasinId,
    required this.numero,
    this.date,
    this.description,
    required this.statut,
    required this.prixFournisseur,
    required this.fretImport,
    required this.douane,
    required this.totalQty,
    required this.coutTotal,
    required this.coutUnitaire,
    required this.lines,
    this.createdAt,
    this.receivedAt,
  });

  final int id;

  /// Magasin destinataire de la marchandise (un admin multi-magasins voit
  /// les commandes de tous ses magasins).
  final int magasinId;

  /// `SUP-<magasinId>-<YYYYMMDD>-<0001>` — généré par le serveur, unique.
  final String numero;
  final DateTime? date;
  final String? description;
  final SupplierOrderStatus statut;
  final double prixFournisseur;
  final double fretImport;
  final double douane;
  final int totalQty;
  final double coutTotal;
  final double coutUnitaire;
  final List<SupplierOrderLine> lines;
  final DateTime? createdAt;
  final DateTime? receivedAt;

  bool get isReceived => statut == SupplierOrderStatus.recu;

  factory SupplierOrder.fromJson(Map<String, dynamic> json) {
    return SupplierOrder(
      id: asInt(json['id']),
      magasinId: asInt(json['magasin']),
      numero: asString(json['numero']),
      date: asDateOrNull(json['date']),
      description: asStringOrNull(json['description']),
      statut: SupplierOrderStatusX.fromApi(asString(json['statut'])),
      prixFournisseur: asDouble(json['prix_fournisseur']),
      fretImport: asDouble(json['fret_import']),
      douane: asDouble(json['douane']),
      totalQty: asInt(json['total_qty']),
      coutTotal: asDouble(json['cout_total']),
      coutUnitaire: asDouble(json['cout_unitaire']),
      lines: (json['lines'] as List? ?? []).map((e) => SupplierOrderLine.fromJson(e as Map<String, dynamic>)).toList(),
      createdAt: asDateOrNull(json['created_at']),
      receivedAt: asDateOrNull(json['received_at']),
    );
  }
}

/// Ligne saisie dans le formulaire « Nouvelle commande fournisseur »
/// (`{product_variant, quantite}` — `SupplierOrderLineInputSerializer`).
class SupplierOrderLineDraft {
  SupplierOrderLineDraft({required this.productVariant, required this.quantite});

  final int productVariant;
  final int quantite;

  Map<String, dynamic> toJson() => {'product_variant': productVariant, 'quantite': quantite};
}
