import 'json_utils.dart';

/// Campagne marketing — `MarketingCampaignSerializer` (orders/serializers.py)
/// : `GET/POST/PATCH/DELETE /api/orders/campaigns/`. Lecture pour tout
/// utilisateur du magasin (le formulaire de commande propose la campagne
/// d'origine), écriture réservée au gérant.
class MarketingCampaign {
  const MarketingCampaign({
    required this.id,
    required this.magasin,
    required this.nom,
    required this.plateforme,
    required this.plateformeLabel,
    required this.montant,
    required this.dateDebut,
    required this.dateFin,
    required this.note,
    required this.actif,
    required this.createdAt,
    this.nbCommandes = 0,
    this.nbLivrees = 0,
    this.ca = 0,
    this.coutParCommande,
    this.coutParArticle = 0,
    this.articlesVendus = 0,
    this.periodeEffectiveTo,
    this.enCours = false,
  });

  final int id;
  final int? magasin;
  final String nom;

  /// Code de [kPlateformes] (`FACEBOOK`, `INSTAGRAM`…).
  final String plateforme;
  final String plateformeLabel;
  final num montant;

  /// `AAAA-MM-JJ`.
  final String dateDebut;

  /// `AAAA-MM-JJ`, `null` = campagne sans fin.
  final String? dateFin;
  final String note;
  final bool actif;
  final String? createdAt;

  /// Affectation AUTOMATIQUE par période, calculée par le serveur
  /// (`nb_commandes`, `nb_livrees`, `ca`, `cout_par_commande`,
  /// `periode_effective`) : rien n'est recalculé côté app.
  final int nbCommandes;
  final int nbLivrees;
  final num ca;
  final num? coutParCommande;
  final num coutParArticle;
  final int articlesVendus;

  /// Dernier jour couvert (`AAAA-MM-JJ`) — aujourd'hui pour un boost en cours.
  final String? periodeEffectiveTo;
  final bool enCours;

  factory MarketingCampaign.fromJson(Map<String, dynamic> json) => MarketingCampaign(
        id: asInt(json['id']),
        magasin: asIntOrNull(json['magasin']),
        nom: asString(json['nom']),
        plateforme: asString(json['plateforme']),
        plateformeLabel: asString(json['plateforme_label']),
        montant: asDouble(json['montant']),
        dateDebut: asString(json['date_debut']),
        dateFin: asStringOrNull(json['date_fin']),
        note: asString(json['note']),
        actif: asBool(json['actif']),
        createdAt: asStringOrNull(json['created_at']),
        nbCommandes: asInt(json['nb_commandes']),
        nbLivrees: asInt(json['nb_livrees']),
        ca: asDouble(json['ca']),
        coutParCommande: asDoubleOrNull(json['cout_par_commande']),
        coutParArticle: asDouble(json['cout_par_article']),
        articlesVendus: asInt(json['articles_vendus']),
        periodeEffectiveTo: asStringOrNull((json['periode_effective'] as Map?)?['to']),
        enCours: asBool((json['periode_effective'] as Map?)?['en_cours']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'magasin': magasin,
        'nom': nom,
        'plateforme': plateforme,
        'plateforme_label': plateformeLabel,
        'montant': montant,
        'date_debut': dateDebut,
        'date_fin': dateFin,
        'note': note,
        'actif': actif,
        'created_at': createdAt,
      };
}

/// `MarketingCampaign.PLATEFORME_CHOICES` (orders/models.py).
class Plateforme {
  const Plateforme(this.code, this.label);

  final String code;
  final String label;
}

const List<Plateforme> kPlateformes = [
  Plateforme('FACEBOOK', 'Facebook'),
  Plateforme('INSTAGRAM', 'Instagram'),
  Plateforme('TIKTOK', 'TikTok'),
  Plateforme('GOOGLE', 'Google'),
  Plateforme('AUTRE', 'Autre'),
];
