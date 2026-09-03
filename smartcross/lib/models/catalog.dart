import 'json_utils.dart';

/// HOUSSE, CACHE ÉCRAN, CHARGEUR… (§8.1/8.2 README).
class ProductCategory {
  ProductCategory({required this.id, required this.nom, required this.ordre});

  final int id;
  final String nom;
  final int ordre;

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(id: asInt(json['id']), nom: asString(json['nom']), ordre: asInt(json['ordre']));
  }

  Map<String, dynamic> toJson() => {'nom': nom, 'ordre': ordre};
}

/// Sous-type : FLIP COVER, Z-FOLD, Z-FLIP, PRIVACY…
class ProductType {
  ProductType({required this.id, required this.categoryId, required this.nom});

  final int id;
  final int categoryId;
  final String nom;

  factory ProductType.fromJson(Map<String, dynamic> json) {
    return ProductType(id: asInt(json['id']), categoryId: asInt(json['category']), nom: asString(json['nom']));
  }

  Map<String, dynamic> toJson() => {'category': categoryId, 'nom': nom};
}

class Brand {
  Brand({required this.id, required this.nom});

  final int id;
  final String nom;

  factory Brand.fromJson(Map<String, dynamic> json) => Brand(id: asInt(json['id']), nom: asString(json['nom']));

  Map<String, dynamic> toJson() => {'nom': nom};
}

/// Une déclinaison couleur d'une référence — niveau où le stock est
/// réellement suivi (§8.1 README).
class ProductVariant {
  ProductVariant({
    required this.id,
    required this.productReferenceId,
    required this.referenceName,
    required this.brandName,
    required this.prixVente,
    required this.couleur,
    required this.stockActuel,
    required this.seuilAlerte,
    required this.isRupture,
    required this.isStockBas,
  });

  final int id;
  final int productReferenceId;
  final String referenceName;
  final String brandName;
  final double prixVente;
  final String couleur;
  final int stockActuel;
  final int seuilAlerte;
  final bool isRupture;
  final bool isStockBas;

  String get label => '$brandName $referenceName — $couleur';

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: asInt(json['id']),
      productReferenceId: asInt(json['product_reference']),
      referenceName: asString(json['reference_name']),
      brandName: asString(json['brand_name']),
      prixVente: asDouble(json['prix_vente']),
      couleur: asString(json['couleur']),
      stockActuel: asInt(json['stock_actuel']),
      seuilAlerte: asInt(json['seuil_alerte']),
      isRupture: asBool(json['is_rupture']),
      isStockBas: asBool(json['is_stock_bas']),
    );
  }
}

/// Référence de téléphone pour une marque donnée (ex: Samsung A15).
class ProductReference {
  ProductReference({
    required this.id,
    required this.typeId,
    required this.typeName,
    required this.categoryName,
    required this.brandId,
    required this.brandName,
    required this.referenceName,
    required this.prixVente,
    required this.actif,
    required this.variants,
  });

  final int id;
  final int typeId;
  final String typeName;
  final String categoryName;
  final int brandId;
  final String brandName;
  final String referenceName;
  final double prixVente;
  final bool actif;
  final List<ProductVariant> variants;

  factory ProductReference.fromJson(Map<String, dynamic> json) {
    return ProductReference(
      id: asInt(json['id']),
      typeId: asInt(json['type']),
      typeName: asString(json['type_name']),
      categoryName: asString(json['category_name']),
      brandId: asInt(json['brand']),
      brandName: asString(json['brand_name']),
      referenceName: asString(json['reference_name']),
      prixVente: asDouble(json['prix_vente']),
      actif: asBool(json['actif'], true),
      variants: (json['variants'] as List? ?? []).map((e) => ProductVariant.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': typeId,
        'brand': brandId,
        'reference_name': referenceName,
        'prix_vente': prixVente,
        'actif': actif,
      };
}

/// Résultat de recherche autocomplete pour le formulaire Nouvelle commande
/// (§6 README) — inclut les couleurs disponibles avec leur variant_id.
class ReferenceOption {
  ReferenceOption({
    required this.id,
    required this.typeId,
    required this.typeName,
    required this.brandId,
    required this.brandName,
    required this.referenceName,
    required this.prixVente,
    required this.couleurs,
  });

  final int id;
  final int typeId;
  final String typeName;
  final int brandId;
  final String brandName;
  final String referenceName;
  final double prixVente;
  final List<ColorOption> couleurs;

  factory ReferenceOption.fromJson(Map<String, dynamic> json) {
    return ReferenceOption(
      id: asInt(json['id']),
      typeId: asInt(json['type']),
      typeName: asString(json['type_name']),
      brandId: asInt(json['brand']),
      brandName: asString(json['brand_name']),
      referenceName: asString(json['reference_name']),
      prixVente: asDouble(json['prix_vente']),
      couleurs: (json['couleurs'] as List? ?? []).map((e) => ColorOption.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ColorOption {
  ColorOption({required this.variantId, required this.couleur, required this.stockActuel});

  final int variantId;
  final String couleur;
  final int stockActuel;

  factory ColorOption.fromJson(Map<String, dynamic> json) {
    return ColorOption(
      variantId: asInt(json['variant_id']),
      couleur: asString(json['couleur']),
      stockActuel: asInt(json['stock_actuel']),
    );
  }
}
