import 'json_utils.dart';

/// Module Fournisseur — approvisionnements (`/api/suppliers/`).
///
/// Un approvisionnement = 1 fournisseur + 1 produit + 1 quantité + N
/// paiements (taux du jour figé) + 1 expédition + 1 Frais + Douane + 1 coût
/// total rendu Madagascar + 1 coût de revient par pièce. Tous les montants
/// calculés viennent du serveur (suppliers/services.py) : rien n'est
/// recalculé dans l'app.

/// Statuts (§ 15), dans l'ordre du cycle.
enum SupplierOrderStatus {
  brouillon,
  commande,
  acomptePaye,
  preparation,
  paye,
  expedie,
  enTransit,
  arrive,
  coutFinalise,
}

extension SupplierOrderStatusX on SupplierOrderStatus {
  String get apiValue => switch (this) {
        SupplierOrderStatus.brouillon => 'BROUILLON',
        SupplierOrderStatus.commande => 'COMMANDE',
        SupplierOrderStatus.acomptePaye => 'ACOMPTE_PAYE',
        SupplierOrderStatus.preparation => 'PREPARATION',
        SupplierOrderStatus.paye => 'PAYE',
        SupplierOrderStatus.expedie => 'EXPEDIE',
        SupplierOrderStatus.enTransit => 'EN_TRANSIT',
        SupplierOrderStatus.arrive => 'ARRIVE',
        SupplierOrderStatus.coutFinalise => 'COUT_FINALISE',
      };

  String get label => switch (this) {
        SupplierOrderStatus.brouillon => 'Brouillon',
        SupplierOrderStatus.commande => 'Commande',
        SupplierOrderStatus.acomptePaye => 'Acompte payé',
        SupplierOrderStatus.preparation => 'Préparation',
        SupplierOrderStatus.paye => 'Entièrement payé',
        SupplierOrderStatus.expedie => 'Expédié',
        SupplierOrderStatus.enTransit => 'En transit',
        SupplierOrderStatus.arrive => 'Arrivé à Madagascar',
        SupplierOrderStatus.coutFinalise => 'Coût finalisé',
      };

  static SupplierOrderStatus fromApi(String value) =>
      SupplierOrderStatus.values.firstWhere((s) => s.apiValue == value, orElse: () => SupplierOrderStatus.brouillon);
}

/// Fiche fournisseur (`SupplierSerializer`) avec son résumé financier.
class Supplier {
  const Supplier({
    required this.id,
    required this.nom,
    required this.pays,
    required this.contact,
    required this.telephone,
    required this.email,
    required this.adresse,
    required this.notes,
    required this.devise,
    required this.actif,
    required this.nbApprovisionnements,
    required this.nbEnCours,
    required this.nbFinalises,
    required this.totalPayeMga,
    required this.totalFraisDouaneMga,
    required this.coutTotalMga,
    required this.resteAPayerDevise,
    this.dernierNumero,
    this.dernierStatut,
  });

  final int id;
  final String nom;
  final String pays;
  final String contact;
  final String telephone;
  final String email;
  final String adresse;
  final String notes;
  final String devise;
  final bool actif;
  final int nbApprovisionnements;
  final int nbEnCours;
  final int nbFinalises;
  final double totalPayeMga;
  final double totalFraisDouaneMga;
  final double coutTotalMga;
  final double resteAPayerDevise;
  final String? dernierNumero;
  final String? dernierStatut;

  factory Supplier.fromJson(Map<String, dynamic> json) {
    final dernier = json['dernier_approvisionnement'] as Map?;
    return Supplier(
      id: asInt(json['id']),
      nom: asString(json['nom']),
      pays: asString(json['pays']),
      contact: asString(json['contact']),
      telephone: asString(json['telephone']),
      email: asString(json['email']),
      adresse: asString(json['adresse']),
      notes: asString(json['notes']),
      devise: asString(json['devise'], 'USD'),
      actif: asBool(json['actif'], true),
      nbApprovisionnements: asInt(json['nb_approvisionnements']),
      nbEnCours: asInt(json['nb_en_cours']),
      nbFinalises: asInt(json['nb_finalises']),
      totalPayeMga: asDouble(json['total_paye_mga']),
      totalFraisDouaneMga: asDouble(json['total_frais_douane_mga']),
      coutTotalMga: asDouble(json['cout_total_mga']),
      resteAPayerDevise: asDouble(json['reste_a_payer_devise']),
      dernierNumero: dernier == null ? null : asStringOrNull(dernier['numero']),
      dernierStatut: dernier == null ? null : asStringOrNull(dernier['statut']),
    );
  }
}

/// Un versement au fournisseur — montant, devise, taux DU JOUR, MGA figé.
class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.date,
    required this.typePaiement,
    required this.typeLabel,
    required this.methode,
    required this.methodeLabel,
    required this.montant,
    required this.devise,
    required this.tauxChange,
    required this.montantMga,
    required this.reference,
    required this.commentaire,
    required this.createdByName,
  });

  final int id;
  final String date;
  final String typePaiement;
  final String typeLabel;
  final String methode;
  final String methodeLabel;
  final double montant;
  final String devise;
  final double tauxChange;
  final double montantMga;
  final String reference;
  final String commentaire;
  final String createdByName;

  factory SupplierPayment.fromJson(Map<String, dynamic> json) => SupplierPayment(
        id: asInt(json['id']),
        date: asString(json['date']),
        typePaiement: asString(json['type_paiement']),
        typeLabel: asString(json['type_label']),
        methode: asString(json['methode']),
        methodeLabel: asString(json['methode_label']),
        montant: asDouble(json['montant']),
        devise: asString(json['devise'], 'MGA'),
        tauxChange: asDouble(json['taux_change']),
        montantMga: asDouble(json['montant_mga']),
        reference: asString(json['reference']),
        commentaire: asString(json['commentaire']),
        createdByName: asString(json['created_by_name']),
      );
}

/// LE produit d'un approvisionnement = un sous-type du catalogue.
class SupplierSousType {
  const SupplierSousType({required this.id, required this.libelle, required this.nom, required this.categoryId, required this.categoryName});
  final int id;
  final String libelle;
  final String nom;
  final int categoryId;
  final String categoryName;

  factory SupplierSousType.fromJson(Map<String, dynamic> json) => SupplierSousType(
        id: asInt(json['id']),
        libelle: asString(json['libelle']),
        nom: asString(json['nom']),
        categoryId: asInt(json['category']),
        categoryName: asString(json['category_name']),
      );
}

/// Variante précise (anciens approvisionnements uniquement).
class SupplierProduit {
  const SupplierProduit({
    required this.variantId,
    required this.libelle,
    required this.referenceName,
    required this.brandName,
    required this.typeName,
    required this.couleur,
    required this.stockActuel,
    required this.prixVente,
    required this.prixAchat,
  });

  final int variantId;
  final String libelle;
  final String referenceName;
  final String brandName;
  final String typeName;
  final String couleur;
  final int stockActuel;
  final double prixVente;
  final double prixAchat;

  factory SupplierProduit.fromJson(Map<String, dynamic> json) => SupplierProduit(
        variantId: asInt(json['id']),
        libelle: asString(json['libelle']),
        referenceName: asString(json['reference_name']),
        brandName: asString(json['brand_name']),
        typeName: asString(json['type_name']),
        couleur: asString(json['couleur']),
        stockActuel: asInt(json['stock_actuel']),
        prixVente: asDouble(json['prix_vente']),
        prixAchat: asDouble(json['prix_achat']),
      );
}

/// Approvisionnement (`SupplierOrderSerializer`).
class SupplierOrder {
  const SupplierOrder({
    required this.id,
    required this.numero,
    required this.date,
    required this.description,
    required this.statut,
    required this.statutLabel,
    required this.magasinId,
    required this.magasinName,
    required this.supplierId,
    required this.supplierNom,
    required this.supplierPays,
    required this.sousType,
    required this.produit,
    required this.produitLibelle,
    required this.quantite,
    required this.quantiteRecue,
    required this.devise,
    required this.montantPrevu,
    required this.totalPayeDevise,
    required this.resteAPayerDevise,
    required this.pourcentagePaye,
    required this.dateExpedition,
    required this.transporteur,
    required this.modeTransport,
    required this.modeTransportLabel,
    required this.tracking,
    required this.numeroColis,
    required this.lieuDepart,
    required this.destination,
    required this.dateArrivee,
    required this.commentaireTransport,
    required this.fraisDouaneMga,
    required this.totalPaiementsMga,
    required this.coutTotalMga,
    required this.coutUnitaireMga,
    required this.prixVenteUnitaire,
    required this.margeUnitaire,
    required this.payments,
    required this.caissePaiements,
    required this.caisseFraisDouane,
    required this.finaliseAt,
    required this.createdByName,
    required this.createdAt,
  });

  final int id;
  final String numero;
  final String date;
  final String? description;
  final SupplierOrderStatus statut;
  final String statutLabel;
  final int magasinId;
  final String magasinName;
  final int? supplierId;
  final String supplierNom;
  final String supplierPays;
  final SupplierSousType? sousType;
  final SupplierProduit? produit;

  /// Libellé du sous-type (ou de la variante d'un ancien appro).
  final String produitLibelle;
  final int quantite;
  final int quantiteRecue;
  final String devise;
  final double montantPrevu;
  final double totalPayeDevise;
  final double resteAPayerDevise;
  final double pourcentagePaye;
  final String? dateExpedition;
  final String transporteur;
  final String modeTransport;
  final String modeTransportLabel;
  final String tracking;
  final String numeroColis;
  final String lieuDepart;
  final String destination;
  final String? dateArrivee;
  final String commentaireTransport;
  final double fraisDouaneMga;
  final double totalPaiementsMga;
  final double coutTotalMga;
  final double coutUnitaireMga;
  final double prixVenteUnitaire;
  final double margeUnitaire;
  final List<SupplierPayment> payments;
  final List<int> caissePaiements;
  final bool caisseFraisDouane;
  final DateTime? finaliseAt;
  final String createdByName;
  final DateTime? createdAt;

  bool get estFinalise => statut == SupplierOrderStatus.coutFinalise;
  bool get modifiable => !estFinalise;

  factory SupplierOrder.fromJson(Map<String, dynamic> json) {
    final caisse = json['caisse'] as Map?;
    return SupplierOrder(
      id: asInt(json['id']),
      numero: asString(json['numero']),
      date: asString(json['date']),
      description: asStringOrNull(json['description']),
      statut: SupplierOrderStatusX.fromApi(asString(json['statut'])),
      statutLabel: asString(json['statut_label']),
      magasinId: asInt(json['magasin']),
      magasinName: asString(json['magasin_name']),
      supplierId: asIntOrNull(json['supplier']),
      supplierNom: asString(json['supplier_nom']),
      supplierPays: asString(json['supplier_pays']),
      sousType: json['sous_type'] is Map ? SupplierSousType.fromJson((json['sous_type'] as Map).cast<String, dynamic>()) : null,
      produit: json['produit'] is Map ? SupplierProduit.fromJson((json['produit'] as Map).cast<String, dynamic>()) : null,
      produitLibelle: asString(json['produit_libelle']),
      quantite: asInt(json['quantite']),
      quantiteRecue: asInt(json['quantite_recue']),
      devise: asString(json['devise'], 'USD'),
      montantPrevu: asDouble(json['montant_prevu']),
      totalPayeDevise: asDouble(json['total_paye_devise']),
      resteAPayerDevise: asDouble(json['reste_a_payer_devise']),
      pourcentagePaye: asDouble(json['pourcentage_paye']),
      dateExpedition: asStringOrNull(json['date_expedition']),
      transporteur: asString(json['transporteur']),
      modeTransport: asString(json['mode_transport']),
      modeTransportLabel: asString(json['mode_transport_label']),
      tracking: asString(json['tracking']),
      numeroColis: asString(json['numero_colis']),
      lieuDepart: asString(json['lieu_depart']),
      destination: asString(json['destination']),
      dateArrivee: asStringOrNull(json['date_arrivee']),
      commentaireTransport: asString(json['commentaire_transport']),
      fraisDouaneMga: asDouble(json['frais_douane_mga']),
      totalPaiementsMga: asDouble(json['total_paiements_mga']),
      coutTotalMga: asDouble(json['cout_total_mga']),
      coutUnitaireMga: asDouble(json['cout_unitaire_mga']),
      prixVenteUnitaire: asDouble(json['prix_vente_unitaire']),
      margeUnitaire: asDouble(json['marge_unitaire']),
      payments: (json['payments'] as List? ?? []).map((e) => SupplierPayment.fromJson((e as Map).cast<String, dynamic>())).toList(),
      caissePaiements: ((caisse?['paiements'] as List?) ?? const []).map((e) => asInt(e)).toList(),
      caisseFraisDouane: asBool(caisse?['frais_douane'], false),
      finaliseAt: asDateOrNull(json['finalise_at']),
      createdByName: asString(json['created_by_name']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}

/// Indicateurs de la page (`GET suppliers/orders/kpis/`).
class SupplierKpis {
  const SupplierKpis({
    required this.nbApprovisionnements,
    required this.nbEnCours,
    required this.nbFinalises,
    required this.totalPayeMga,
    required this.totalFraisDouaneMga,
    required this.coutTotalMga,
    required this.nbFournisseursActifs,
    required this.enTransitNb,
    required this.enTransitValeurMga,
    required this.aFinaliser,
    required this.coutMoyenParPieceMga,
  });

  final int nbApprovisionnements;
  final int nbEnCours;
  final int nbFinalises;
  final double totalPayeMga;
  final double totalFraisDouaneMga;
  final double coutTotalMga;
  final int nbFournisseursActifs;
  final int enTransitNb;
  final double enTransitValeurMga;
  final int aFinaliser;
  final double? coutMoyenParPieceMga;

  factory SupplierKpis.fromJson(Map<String, dynamic> json) {
    final transit = json['en_transit'] as Map?;
    return SupplierKpis(
      nbApprovisionnements: asInt(json['nb_approvisionnements']),
      nbEnCours: asInt(json['nb_en_cours']),
      nbFinalises: asInt(json['nb_finalises']),
      totalPayeMga: asDouble(json['total_paye_mga']),
      totalFraisDouaneMga: asDouble(json['total_frais_douane_mga']),
      coutTotalMga: asDouble(json['cout_total_mga']),
      nbFournisseursActifs: asInt(json['nb_fournisseurs_actifs']),
      enTransitNb: asInt(transit?['nb']),
      enTransitValeurMga: asDouble(transit?['valeur_mga']),
      aFinaliser: asInt(json['a_finaliser']),
      coutMoyenParPieceMga: asDoubleOrNull(json['cout_moyen_par_piece_mga']),
    );
  }
}
