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
