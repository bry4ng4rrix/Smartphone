import '../core/constants.dart';
import 'delivery_zone.dart';
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
    this.brandName,
    this.typeName,
    this.categoryName,
    this.retourne = false,
  });

  final int id;
  final int? productVariantId;
  final String referenceName;
  final String couleur;
  final double? prixUnitaire;
  final int quantite;
  // Marque, sous-type (ProductType) et type (ProductCategory) — exposés par
  // les deux serializers (gérant/préparateur-livreur), voir
  // orders/serializers.py::OrderItemSerializer/OrderItemPublicSerializer.
  final String? brandName;
  final String? typeName;
  final String? categoryName;

  /// Article rapporté par le livreur lors d'une livraison partielle
  /// (§ demande) : le client n'en a pas voulu, il est reparti en stock et
  /// sorti du total à payer — voir OrderItem.retourne côté serveur et
  /// `OrdersRepository.changeStatus(itemsLivres: ...)`.
  final bool retourne;

  /// "Galaxy A15 (Noir)" — libellé commun aux listes, résumés et pointage
  /// des articles (même forme que `{reference_name} ({couleur})` du web).
  String get libelle => couleur.isNotEmpty ? '$referenceName ($couleur)' : referenceName;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: asInt(json['id']),
      productVariantId: asIntOrNull(json['product_variant']),
      referenceName: asString(json['reference_name']),
      couleur: asString(json['couleur']),
      prixUnitaire: asDoubleOrNull(json['prix_unitaire']),
      quantite: asInt(json['quantite'], 1),
      brandName: asStringOrNull(json['brand_name']),
      typeName: asStringOrNull(json['type_name']),
      categoryName: asStringOrNull(json['category_name']),
      retourne: asBool(json['retourne'], false),
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
    this.photo,
    required this.timestamp,
  });

  final int id;
  final OrderStatus? ancienStatut;
  final OrderStatus nouveauStatut;
  final String? changedByName;
  final String? note;
  // Preuve que la préparation est faite — jointe au passage "Prête"
  // (§ demande), voir OrderStatusHistory.photo côté serveur.
  final String? photo;
  final DateTime? timestamp;

  /// Vrai si une photo est réellement jointe (le serveur peut renvoyer une
  /// chaîne vide plutôt que `null`).
  bool get aPhoto => photo != null && photo!.isNotEmpty;

  factory OrderStatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    final photo = asStringOrNull(json['photo']);
    return OrderStatusHistoryEntry(
      id: asInt(json['id']),
      ancienStatut: json['ancien_statut'] != null ? OrderStatusX.fromApi(asString(json['ancien_statut'])) : null,
      nouveauStatut: OrderStatusX.fromApi(asString(json['nouveau_statut'])),
      changedByName: asStringOrNull(json['changed_by_name']),
      note: asStringOrNull(json['note']),
      photo: photo == null || photo.isEmpty ? null : photo,
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
    this.telephone2,
    required this.livraisonZone,
    this.adresseLivraison,
    this.modePaiement = PaymentMode.livraison,
    this.fraisLivraison,
    this.totalAPayer,
    this.notePreparateur,
    this.noteLivreur,
    required this.statutCourant,
    required this.items,
    this.statusHistory = const [],
    this.createdAt,
    this.updatedAt,
    this.magasinId,
    this.preparateurId,
    this.preparateurName,
    this.livreurId,
    this.livreurName,
    this.campagneId,
    this.campagneNom = '',
  });

  final int id;
  final String numero;
  final DateTime? dateCommande;
  final String clientNom;
  final String? telephone;

  /// Second numéro, facultatif (§ demande) — même format +261XXXXXXXXX. Le
  /// livreur l'appelle quand le premier ne répond pas. `null` si vide.
  final String? telephone2;
  // Code de zone : soit le `code` d'une DeliveryZoneOption (CRUD Paramètres),
  // soit le littéral kRecuperationCode — voir models/delivery_zone.dart.
  final String livraisonZone;
  final String? adresseLivraison;
  final PaymentMode modePaiement;
  final double? fraisLivraison;
  final double? totalAPayer;
  // Deux notes distinctes, chacune destinée à un seul rôle (§ demande) — le
  // préparateur ne voit jamais celle du livreur, et inversement.
  final String? notePreparateur;
  final String? noteLivreur;
  final OrderStatus statutCourant;
  final List<OrderItem> items;
  final List<OrderStatusHistoryEntry> statusHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Magasin de la commande — exposé au gérant seulement (serializer
  /// complet) ; sert à cibler `available-staff` sur le bon magasin.
  final int? magasinId;
  // Préparateur/livreur désigné pour cette commande (voir orders/services.py
  // — un seul à la fois par personne).
  final int? preparateurId;
  final String? preparateurName;
  final int? livreurId;
  final String? livreurName;

  /// Campagne marketing d'origine (facultative, choisie à la création de la
  /// commande — alimente le rapport Marketing). Exposée au gérant seulement
  /// (`campagne` / `campagne_nom` du serializer complet,
  /// orders/serializers.py) ; `null` / vide pour les autres rôles ou sans
  /// campagne.
  final int? campagneId;
  final String campagneNom;

  // ---------------------------------------------------------------------
  // Règles métier partagées par les écrans — mêmes conditions que
  // frontend/app/(app)/orders/page.tsx.
  // ---------------------------------------------------------------------

  /// Retrait sur place : pas de livreur, pas de frais.
  bool get estRecuperation => livraisonZone == kRecuperationCode;

  /// Le client a réglé AVANT la livraison : rien à encaisser pour le
  /// livreur, les montants lui sont masqués.
  bool get estPrepayee => modePaiement == PaymentMode.avant;

  /// Livrée / Retour / Annulée — plus aucune transition, ni modification,
  /// ni annulation possible (`!['LIVRE','RETOUR','ANNULEE'].includes(...)`).
  bool get estTerminee =>
      statutCourant == OrderStatus.livre ||
      statutCourant == OrderStatus.retour ||
      statutCourant == OrderStatus.annulee;

  /// Close (Livrée ou Retour) : le gérant peut encore CORRIGER l'état
  /// (§ demande — voir [correctionCible] et `corrigerStatut`).
  bool get estClose => statutCourant == OrderStatus.livre || statutCourant == OrderStatus.retour;

  /// État vers lequel une commande close peut être corrigée (LIVRE <-> RETOUR),
  /// `null` si la commande n'est pas close.
  OrderStatus? get correctionCible {
    switch (statutCourant) {
      case OrderStatus.livre:
        return OrderStatus.retour;
      case OrderStatus.retour:
        return OrderStatus.livre;
      default:
        return null;
    }
  }

  /// Modification complète possible (client, téléphone, date, articles…) —
  /// `canEdit` du web : Nouvelle ou En préparation.
  bool get modificationComplete =>
      statutCourant == OrderStatus.nouvelle || statutCourant == OrderStatus.enPreparation;

  /// Au-delà de "En préparation" et avant la clôture, seules les données de
  /// LIVRAISON restent modifiables : mode de paiement, zone, adresse et note
  /// du livreur (`livraisonSeule` du web, même règle que
  /// orders/services.py::update_order).
  bool get modificationLivraisonSeule => !modificationComplete && !estTerminee;

  /// Suppression réservée à une commande "Nouvelle" (rien d'engagé).
  bool get suppressionPossible => statutCourant == OrderStatus.nouvelle;

  /// Annulation possible tant que la commande n'est pas terminée.
  bool get annulationPossible => !estTerminee;

  /// L'annulation restituera du stock déjà déduit (message du dialogue web).
  bool get annulationRestitueStock =>
      statutCourant == OrderStatus.enPreparation ||
      statutCourant == OrderStatus.prete ||
      statutCourant == OrderStatus.enLivraison;

  /// Première entrée d'historique ayant atteint [statut] (`historyAt` du
  /// web) — pour la chronologie et la colonne « Assigné à ».
  OrderStatusHistoryEntry? historyEntry(OrderStatus statut) {
    for (final h in statusHistory) {
      if (h.nouveauStatut == statut) return h;
    }
    return null;
  }

  /// Horodatage du premier passage par [statut], `null` s'il n'a jamais été
  /// atteint.
  DateTime? historyAt(OrderStatus statut) => historyEntry(statut)?.timestamp;

  /// Photo de préparation la plus récente de l'historique, `null` s'il n'y
  /// en a aucune. Le partage dans la messagerie n'est proposé que si elle
  /// existe (§ demande).
  String? get photoPreparation {
    String? photo;
    for (final h in statusHistory) {
      if (h.aPhoto) photo = h.photo;
    }
    return photo;
  }

  bool get aPhotoPreparation => photoPreparation != null;

  /// Articles réellement remis au client (non rapportés).
  List<OrderItem> get itemsRemis => items.where((i) => !i.retourne).toList();

  /// Articles rapportés lors d'une livraison partielle.
  List<OrderItem> get itemsRapportes => items.where((i) => i.retourne).toList();

  /// Vrai si au moins un article a été rapporté (livraison partielle).
  bool get livraisonPartielle => items.any((i) => i.retourne);

  factory Order.fromJson(Map<String, dynamic> json) {
    final telephone2 = asStringOrNull(json['telephone_2'])?.trim();
    return Order(
      id: asInt(json['id']),
      numero: asString(json['numero']),
      dateCommande: asDateOrNull(json['date_commande']),
      clientNom: asString(json['client_nom']),
      telephone: asStringOrNull(json['telephone']),
      telephone2: telephone2 == null || telephone2.isEmpty ? null : telephone2,
      livraisonZone: asString(json['livraison_zone'], kRecuperationCode),
      adresseLivraison: asStringOrNull(json['adresse_livraison']),
      modePaiement: PaymentModeX.fromApi(asStringOrNull(json['mode_paiement'])),
      fraisLivraison: asDoubleOrNull(json['frais_livraison']),
      totalAPayer: asDoubleOrNull(json['total_a_payer']),
      notePreparateur: asStringOrNull(json['note_preparateur']),
      noteLivreur: asStringOrNull(json['note_livreur']),
      statutCourant: OrderStatusX.fromApi(asString(json['statut_courant'])),
      items: (json['items'] as List? ?? []).map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList(),
      statusHistory: (json['status_history'] as List? ?? [])
          .map((e) => OrderStatusHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: asDateOrNull(json['created_at']),
      updatedAt: asDateOrNull(json['updated_at']),
      magasinId: asIntOrNull(json['magasin']),
      preparateurId: asIntOrNull(json['preparateur']),
      preparateurName: asStringOrNull(json['preparateur_name']),
      livreurId: asIntOrNull(json['livreur']),
      livreurName: asStringOrNull(json['livreur_name']),
      campagneId: asIntOrNull(json['campagne']),
      campagneNom: asString(json['campagne_nom']),
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
