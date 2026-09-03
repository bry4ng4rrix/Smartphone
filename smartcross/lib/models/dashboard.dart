import 'json_utils.dart';

class DashboardKpis {
  DashboardKpis({
    required this.nbVentes,
    required this.caPeriode,
    required this.caMoisEnCours,
    this.tauxLivraisonReussiePct,
    required this.nbRetours,
  });

  final int nbVentes;
  final double caPeriode;
  final double caMoisEnCours;
  final double? tauxLivraisonReussiePct;
  final int nbRetours;

  factory DashboardKpis.fromJson(Map<String, dynamic> json) {
    return DashboardKpis(
      nbVentes: asInt(json['nb_ventes']),
      caPeriode: asDouble(json['ca_periode']),
      caMoisEnCours: asDouble(json['ca_mois_en_cours']),
      tauxLivraisonReussiePct: asDoubleOrNull(json['taux_livraison_reussie_pct']),
      nbRetours: asInt(json['nb_retours']),
    );
  }
}

class DashboardFinance {
  DashboardFinance({
    required this.caProduitsVendus,
    required this.fraisLivraisonEncaisses,
    required this.totalInvestiFournisseurs,
    required this.totalPubMetaAds,
    required this.beneficeEstime,
  });

  final double caProduitsVendus;
  final double fraisLivraisonEncaisses;
  final double totalInvestiFournisseurs;
  final double totalPubMetaAds;
  final double beneficeEstime;

  factory DashboardFinance.fromJson(Map<String, dynamic> json) {
    return DashboardFinance(
      caProduitsVendus: asDouble(json['ca_produits_vendus']),
      fraisLivraisonEncaisses: asDouble(json['frais_livraison_encaisses']),
      totalInvestiFournisseurs: asDouble(json['total_investi_fournisseurs']),
      totalPubMetaAds: asDouble(json['total_pub_meta_ads']),
      beneficeEstime: asDouble(json['benefice_estime']),
    );
  }
}

class TopEntry {
  TopEntry({required this.label, required this.quantiteVendue});

  final String label;
  final int quantiteVendue;

  factory TopEntry.fromJson(Map<String, dynamic> json) {
    return TopEntry(label: asString(json['label']), quantiteVendue: asInt(json['quantite_vendue']));
  }
}

class StockRapide {
  StockRapide({required this.totalEnStock, required this.ruptures, required this.stockBas});

  final int totalEnStock;
  final int ruptures;
  final int stockBas;

  factory StockRapide.fromJson(Map<String, dynamic> json) {
    return StockRapide(
      totalEnStock: asInt(json['total_en_stock']),
      ruptures: asInt(json['ruptures']),
      stockBas: asInt(json['stock_bas']),
    );
  }
}

/// Réponse complète de `GET /api/orders/dashboard/` (§7.7 README).
class DashboardData {
  DashboardData({
    required this.dateDebut,
    required this.dateFin,
    required this.kpis,
    required this.suiviCommandesTempsReel,
    required this.financiere,
    required this.topParSousType,
    required this.topMarques,
    required this.topReferences,
    required this.topCouleurs,
    required this.stockRapide,
  });

  final DateTime? dateDebut;
  final DateTime? dateFin;
  final DashboardKpis kpis;
  final Map<String, int> suiviCommandesTempsReel;
  final DashboardFinance financiere;
  final List<TopEntry> topParSousType;
  final List<TopEntry> topMarques;
  final List<TopEntry> topReferences;
  final List<TopEntry> topCouleurs;
  final StockRapide stockRapide;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final periode = json['periode'] as Map<String, dynamic>? ?? {};
    final suivi = json['suivi_commandes_temps_reel'] as Map<String, dynamic>? ?? {};
    final top = json['top_produits'] as Map<String, dynamic>? ?? {};

    List<TopEntry> parseTop(String key) =>
        (top[key] as List? ?? []).map((e) => TopEntry.fromJson(e as Map<String, dynamic>)).toList();

    return DashboardData(
      dateDebut: asDateOrNull(periode['date_debut']),
      dateFin: asDateOrNull(periode['date_fin']),
      kpis: DashboardKpis.fromJson(json['kpis'] as Map<String, dynamic>? ?? {}),
      suiviCommandesTempsReel: suivi.map((k, v) => MapEntry(k, asInt(v))),
      financiere: DashboardFinance.fromJson(json['analyse_financiere'] as Map<String, dynamic>? ?? {}),
      topParSousType: parseTop('par_sous_type'),
      topMarques: parseTop('marques'),
      topReferences: parseTop('references'),
      topCouleurs: parseTop('couleurs'),
      stockRapide: StockRapide.fromJson(json['stock_rapide'] as Map<String, dynamic>? ?? {}),
    );
  }
}
