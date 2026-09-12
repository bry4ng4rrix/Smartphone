import 'json_utils.dart';

/// Réponse de `GET /api/orders/reports/?date_from=YYYY-MM-DD&date_to=YYYY-MM-DD`
/// — rapports du gérant, portage de `djangoClient.reports.get(dateFrom, dateTo)`
/// et de la page `frontend/app/(app)/reports/page.tsx`.
///
/// TOUT est agrégé côté serveur (orders/reports.py) : le bénéfice a besoin du
/// prix d'achat, qui ne transite jamais par un compte livreur ou préparateur.
/// L'endpoint est réservé au gérant (403 sinon). La période est bornée en
/// date de livraison prévue (`date_commande`), bornes comprises — la même
/// référence que la page Commandes et les bilans.
///
/// Les montants sont des `Decimal` côté serveur (rendus en nombre ou en
/// chaîne selon l'encodeur) : tout passe par [asDouble].
class ReportsData {
  const ReportsData({
    required this.periode,
    required this.totaux,
    required this.parJour,
    required this.topProduits,
    required this.produitsMoinsVendus,
    required this.livreurs,
    required this.preparateurs,
    required this.mouvementsParJour,
  });

  /// Bornes effectivement retenues par le serveur (`periode.from` / `to`) —
  /// affichées dans le sous-titre « Du JJ/MM au JJ/MM ».
  final ReportPeriode periode;

  /// Les chiffres de la période (8 cartes KPI).
  final ReportTotaux totaux;

  /// Une ligne PAR JOUR de la période, jours sans activité compris — le
  /// graphique « Recettes et dépenses par jour » et le tableau « Activité par
  /// jour ».
  final List<ReportJour> parJour;

  /// « Produits les plus vendus » — 10 au plus, par quantité décroissante.
  final List<ReportProduit> topProduits;

  /// « Produits les moins vendus » — 10 au plus, par quantité croissante,
  /// PARMI ceux qui se sont vendus (un produit jamais vendu n'y figure pas).
  final List<ReportProduit> produitsMoinsVendus;

  /// « Performance des livreurs » — par livraisons réussies décroissantes.
  final List<ReportLivreur> livreurs;

  /// « Commandes préparées » — par total décroissant, avec le détail par jour.
  final List<ReportPreparateur> preparateurs;

  /// « Mouvements de stock par jour » — UNIQUEMENT les jours ayant au moins
  /// un mouvement (le serveur ne comble pas les trous ici, contrairement à
  /// [parJour]), par date croissante.
  final List<ReportMouvementsJour> mouvementsParJour;

  factory ReportsData.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    Map<String, dynamic> obj(String key) {
      final v = json[key];
      return v is Map ? v.cast<String, dynamic>() : const {};
    }

    return ReportsData(
      periode: ReportPeriode.fromJson(obj('periode')),
      totaux: ReportTotaux.fromJson(obj('totaux')),
      parJour: rows('par_jour').map(ReportJour.fromJson).toList(),
      topProduits: rows('top_produits').map(ReportProduit.fromJson).toList(),
      produitsMoinsVendus: rows('produits_moins_vendus').map(ReportProduit.fromJson).toList(),
      livreurs: rows('livreurs').map(ReportLivreur.fromJson).toList(),
      preparateurs: rows('preparateurs').map(ReportPreparateur.fromJson).toList(),
      mouvementsParJour: rows('mouvements_par_jour').map(ReportMouvementsJour.fromJson).toList(),
    );
  }
}

/// `periode: {from, to}` — jours calendaires, sans fuseau.
class ReportPeriode {
  const ReportPeriode({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  /// « 09/09 » — `jourCourt(data.periode.from)` du web.
  String get fromCourt => formatJourCourt(from);
  String get toCourt => formatJourCourt(to);

  factory ReportPeriode.fromJson(Map<String, dynamic> json) {
    return ReportPeriode(
      from: parseReportsDate(json['from']),
      to: parseReportsDate(json['to']),
    );
  }
}

/// `totaux` — les chiffres de la période. Formules (orders/reports.py) :
///
/// * chiffre_affaires = ca_produits + frais_livraison ;
/// * marge_produits   = ca_produits − cout_produits ;
/// * depenses_totales = depenses_caisse + depenses_livreur ;
/// * resultat         = marge_produits + frais_livraison − depenses_totales.
///
/// `ca_produits` ne compte que les articles RÉELLEMENT remis (commandes
/// livrées, hors articles rapportés lors d'une livraison partielle) ;
/// `depenses_livreur` ne compte que les dépenses ACCEPTÉES.
class ReportTotaux {
  const ReportTotaux({
    required this.chiffreAffaires,
    required this.caProduits,
    required this.coutProduits,
    required this.margeProduits,
    required this.fraisLivraison,
    required this.depensesCaisse,
    required this.depensesLivreur,
    required this.depensesTotales,
    required this.resultat,
    required this.nbCommandes,
    required this.nbLivrees,
    required this.nbRetours,
    required this.montantRetours,
    required this.tauxLivraison,
  });

  /// KPI « Chiffre d'affaires » — détail « Produits X + frais Y ».
  final double chiffreAffaires;
  final double caProduits;

  /// Coût d'achat des produits vendus — n'est visible que du gérant.
  final double coutProduits;

  /// KPI « Marge sur produits » — détail « Vendus X − coût Y ».
  final double margeProduits;

  /// KPI « Frais de livraison » — détail « N livraison(s) ».
  final double fraisLivraison;

  /// Sorties de caisse de la période.
  final double depensesCaisse;

  /// KPI « Dépenses livreurs » — « Frais de tournée validés ».
  final double depensesLivreur;

  /// KPI « Total dépenses » — détail « Caisse X + livreurs Y ».
  final double depensesTotales;

  /// KPI « Résultat » — « Marge + frais − dépenses ». Vert si ≥ 0, rouge
  /// sinon ([resultatPositif]).
  final double resultat;

  final int nbCommandes;
  final int nbLivrees;

  /// KPI « Retours » — détail « X non encaissés » ([montantRetours]).
  final int nbRetours;
  final double montantRetours;

  /// KPI « Taux de livraison » en % (une décimale) — détail « N livrées sur
  /// M ». 0 quand aucune commande.
  final double tauxLivraison;

  /// `Number(t.resultat) >= 0` du web : icône TrendingUp + vert, sinon
  /// TrendingDown + rouge.
  bool get resultatPositif => resultat >= 0;

  /// « 66.7 » / « 100 » — rendu web `${t.taux_livraison}` (voir
  /// [formatPourcentage]).
  String get tauxLivraisonLabel => formatPourcentage(tauxLivraison);

  factory ReportTotaux.fromJson(Map<String, dynamic> json) {
    return ReportTotaux(
      chiffreAffaires: asDouble(json['chiffre_affaires']),
      caProduits: asDouble(json['ca_produits']),
      coutProduits: asDouble(json['cout_produits']),
      margeProduits: asDouble(json['marge_produits']),
      fraisLivraison: asDouble(json['frais_livraison']),
      depensesCaisse: asDouble(json['depenses_caisse']),
      depensesLivreur: asDouble(json['depenses_livreur']),
      depensesTotales: asDouble(json['depenses_totales']),
      resultat: asDouble(json['resultat']),
      nbCommandes: asInt(json['nb_commandes']),
      nbLivrees: asInt(json['nb_livrees']),
      nbRetours: asInt(json['nb_retours']),
      montantRetours: asDouble(json['montant_retours']),
      tauxLivraison: asDouble(json['taux_livraison']),
    );
  }
}

/// Une ligne de `par_jour` — un jour de la période.
class ReportJour {
  const ReportJour({
    required this.date,
    required this.commandes,
    required this.livrees,
    required this.retours,
    required this.ca,
    required this.fraisLivraison,
    required this.depenses,
    required this.difference,
    required this.mouvements,
    required this.partMouvements,
  });

  final DateTime date;

  /// Colonnes « Commandes » / « Livrées » / « Retours » du tableau
  /// « Activité par jour » (retours affiché « - » quand 0).
  final int commandes;
  final int livrees;
  final int retours;

  /// « Recettes » du graphique : produits vendus + frais de livraison du jour.
  final double ca;
  final double fraisLivraison;

  /// « Dépenses » du graphique : sorties de caisse + dépenses livreur
  /// acceptées du jour.
  final double depenses;

  /// « Écart » (courbe) : ce que la journée a réellement laissé une fois les
  /// dépenses retirées — `ca − depenses`.
  final double difference;

  /// Nombre de mouvements de stock du jour et sa part (%) dans le total de
  /// la période — colonnes « Mouvements » / « Part ».
  final int mouvements;
  final double partMouvements;

  /// « 09/09 » — étiquette d'axe et première colonne du tableau.
  String get jourCourt => formatJourCourt(date);

  /// Rendu web `{j.part_mouvements} %` sans le « % ».
  String get partMouvementsLabel => formatPourcentage(partMouvements);

  factory ReportJour.fromJson(Map<String, dynamic> json) {
    return ReportJour(
      date: parseReportsDate(json['date']),
      commandes: asInt(json['commandes']),
      livrees: asInt(json['livrees']),
      retours: asInt(json['retours']),
      ca: asDouble(json['ca']),
      fraisLivraison: asDouble(json['frais_livraison']),
      depenses: asDouble(json['depenses']),
      difference: asDouble(json['difference']),
      mouvements: asInt(json['mouvements']),
      partMouvements: asDouble(json['part_mouvements']),
    );
  }
}

/// Une ligne des classements produits (`top_produits` /
/// `produits_moins_vendus`) — colonnes « Produit », « Marque », « Vendus »,
/// « CA ».
class ReportProduit {
  const ReportProduit({
    required this.label,
    required this.marque,
    required this.quantite,
    required this.ca,
  });

  /// Nom de la référence (« - » si inconnu, comme le serveur).
  final String label;

  /// Vide si la référence n'a pas de marque — le web affiche « - ».
  final String marque;
  final int quantite;
  final double ca;

  factory ReportProduit.fromJson(Map<String, dynamic> json) {
    return ReportProduit(
      label: asString(json['label'], '-'),
      marque: asString(json['marque']),
      quantite: asInt(json['quantite']),
      ca: asDouble(json['ca']),
    );
  }
}

/// Une ligne de `livreurs` — « Performance des livreurs ».
class ReportLivreur {
  const ReportLivreur({
    required this.id,
    required this.nom,
    required this.livrees,
    required this.retours,
    required this.assignees,
    required this.ca,
    required this.fraisLivraison,
    required this.depenses,
    required this.tauxReussite,
  });

  final int id;
  final String nom;

  /// Colonnes « Livrées », « Retours » (« - » si 0), « Assignées ».
  final int livrees;
  final int retours;
  final int assignees;

  /// « Encaissé » : total à payer des commandes livrées.
  final double ca;

  /// « Frais » : frais de livraison des commandes livrées.
  final double fraisLivraison;

  /// « Dépenses » : frais de tournée ACCEPTÉS — affiché « -X Ar » si > 0,
  /// « - » sinon.
  final double depenses;

  /// « Réussite » en % : livrées / (livrées + retours), une décimale.
  final double tauxReussite;

  String get tauxReussiteLabel => formatPourcentage(tauxReussite);

  factory ReportLivreur.fromJson(Map<String, dynamic> json) {
    return ReportLivreur(
      id: asInt(json['id']),
      nom: asString(json['nom'], '-'),
      livrees: asInt(json['livrees']),
      retours: asInt(json['retours']),
      assignees: asInt(json['assignees']),
      ca: asDouble(json['ca']),
      fraisLivraison: asDouble(json['frais_livraison']),
      depenses: asDouble(json['depenses']),
      tauxReussite: asDouble(json['taux_reussite']),
    );
  }
}

/// Une ligne de `preparateurs` — « Commandes préparées », avec les pastilles
/// « JJ/MM · n » par jour.
class ReportPreparateur {
  const ReportPreparateur({
    required this.id,
    required this.nom,
    required this.total,
    required this.parJour,
  });

  final int id;
  final String nom;

  /// « N commande(s) » : commandes préparées par lui sur la période
  /// (statut Prête ou au-delà).
  final int total;

  /// Détail par jour, par date croissante.
  final List<ReportPreparateurJour> parJour;

  factory ReportPreparateur.fromJson(Map<String, dynamic> json) {
    return ReportPreparateur(
      id: asInt(json['id']),
      nom: asString(json['nom'], '-'),
      total: asInt(json['total']),
      parJour: (json['par_jour'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ReportPreparateurJour.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// `preparateurs[].par_jour[]` — « JJ/MM · nb ».
class ReportPreparateurJour {
  const ReportPreparateurJour({required this.date, required this.nb});

  final DateTime date;
  final int nb;

  String get jourCourt => formatJourCourt(date);

  factory ReportPreparateurJour.fromJson(Map<String, dynamic> json) {
    return ReportPreparateurJour(
      date: parseReportsDate(json['date']),
      nb: asInt(json['nb']),
    );
  }
}

/// Une ligne de `mouvements_par_jour` — barres « Entrées » / « Sorties ».
class ReportMouvementsJour {
  const ReportMouvementsJour({
    required this.date,
    required this.entrees,
    required this.sorties,
  });

  final DateTime date;
  final int entrees;
  final int sorties;

  String get jourCourt => formatJourCourt(date);

  factory ReportMouvementsJour.fromJson(Map<String, dynamic> json) {
    return ReportMouvementsJour(
      date: parseReportsDate(json['date']),
      entrees: asInt(json['entrees']),
      sorties: asInt(json['sorties']),
    );
  }
}

// ---------------------------------------------------------------------------
// Dates et formats partagés par le module Rapports
// ---------------------------------------------------------------------------

/// `YYYY-MM-DD` d'un jour calendaire — format des paramètres `date_from` /
/// `date_to` envoyés au serveur.
String formatReportsDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// « JJ/MM » — `jourCourt(iso)` du web, pour les axes, les pastilles et le
/// sous-titre « Du … au … ».
String formatJourCourt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Rendu d'un pourcentage tel que JS l'affiche (`${t.taux_livraison}`) :
/// « 66.7 », mais « 100 » et « 0 » sans décimale inutile — Dart écrirait
/// sinon « 100.0 ».
String formatPourcentage(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

/// `"2026-09-12"` -> `DateTime(2026, 9, 12)` (jour calendaire, sans fuseau).
/// Une date absente ou illisible retombe sur l'epoch plutôt que de planter
/// l'écran : le serveur renvoie toujours ces champs.
DateTime parseReportsDate(dynamic v) {
  final parsed = asDateOrNull(v);
  if (parsed == null) return DateTime(1970);
  return DateTime(parsed.year, parsed.month, parsed.day);
}
