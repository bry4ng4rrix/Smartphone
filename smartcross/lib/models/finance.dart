import 'json_utils.dart';

/// Trésorerie (`/api/finance/*`) — miroir des blocs consommés par
/// frontend/app/(app)/caisse/page.tsx. Tous les montants sont calculés par
/// le serveur (finance/services.py) : rien n'est recalculé dans l'app.

class FinanceIndicateurs {
  const FinanceIndicateurs({
    required this.especeDisponible,
    required this.soldeCaisse,
    required this.sessionOuverte,
    required this.epargneCouverte,
    required this.valeurStock,
    required this.valeurStockVente,
    required this.quantiteStock,
    required this.argentEnAttente,
    required this.attenteLivreurs,
    required this.attenteAEnregistrer,
    required this.epargne,
  });

  final double especeDisponible;
  final double soldeCaisse;
  final bool sessionOuverte;
  final bool epargneCouverte;
  final double valeurStock;
  final double valeurStockVente;
  final int quantiteStock;
  final double argentEnAttente;
  final double attenteLivreurs;
  final double attenteAEnregistrer;
  final double epargne;

  factory FinanceIndicateurs.fromJson(Map<String, dynamic> j) => FinanceIndicateurs(
        especeDisponible: asDouble(j['espece_disponible']),
        soldeCaisse: asDouble(j['solde_caisse']),
        sessionOuverte: asBool(j['session_ouverte'], false),
        epargneCouverte: asBool(j['epargne_couverte'], true),
        valeurStock: asDouble(j['valeur_stock']),
        valeurStockVente: asDouble(j['valeur_stock_vente']),
        quantiteStock: asInt(j['quantite_stock']),
        argentEnAttente: asDouble(j['argent_en_attente']),
        attenteLivreurs: asDouble(j['attente_livreurs']),
        attenteAEnregistrer: asDouble(j['attente_a_enregistrer']),
        epargne: asDouble(j['epargne']),
      );
}

/// Gain réel de la période : (prix de vente + livraison client) − prix
/// d'achat − frais de livraison acceptés − part de boost.
class FinanceGain {
  const FinanceGain({
    required this.nbVentes,
    required this.nbArticles,
    required this.nbPertes,
    required this.caProduits,
    required this.livraisonClient,
    required this.totalEncaisse,
    required this.coutAchat,
    required this.fraisAgence,
    required this.partBoost,
    required this.gainReel,
    required this.etat,
    required this.reappro,
    required this.epargne,
    required this.depenses,
  });

  final int nbVentes;
  final int nbArticles;
  final int nbPertes;
  final double caProduits;
  final double livraisonClient;
  final double totalEncaisse;
  final double coutAchat;
  final double fraisAgence;
  final double partBoost;
  final double gainReel;
  final String etat;
  final double reappro;
  final double epargne;
  final double depenses;

  factory FinanceGain.fromJson(Map<String, dynamic> j) {
    final r = (j['repartition'] as Map?) ?? const {};
    return FinanceGain(
      nbVentes: asInt(j['nb_ventes']),
      nbArticles: asInt(j['nb_articles']),
      nbPertes: asInt(j['nb_pertes']),
      caProduits: asDouble(j['ca_produits']),
      livraisonClient: asDouble(j['livraison_client']),
      totalEncaisse: asDouble(j['total_encaisse']),
      coutAchat: asDouble(j['cout_achat']),
      fraisAgence: asDouble(j['frais_agence']),
      partBoost: asDouble(j['part_boost']),
      gainReel: asDouble(j['gain_reel']),
      etat: asString(j['etat']),
      reappro: asDouble(r['reappro']),
      epargne: asDouble(r['epargne']),
      depenses: asDouble(r['depenses']),
    );
  }
}

class StatsLivraison {
  const StatsLivraison({required this.from, required this.to, required this.nb, required this.facturee, required this.agence, required this.resultat, required this.etat});
  final String from;
  final String to;
  final int nb;
  final double facturee;
  final double agence;
  final double resultat;
  final String etat;

  factory StatsLivraison.fromJson(Map<String, dynamic> j) => StatsLivraison(
        from: asString(j['from']),
        to: asString(j['to']),
        nb: asInt(j['nb']),
        facturee: asDouble(j['facturee']),
        agence: asDouble(j['agence']),
        resultat: asDouble(j['resultat']),
        etat: asString(j['etat']),
      );
}

class FinanceBoost {
  const FinanceBoost({
    required this.id,
    required this.nom,
    required this.plateformeLabel,
    required this.dateDebut,
    required this.dateFin,
    required this.montant,
    required this.articlesVendus,
    required this.coutParArticle,
    required this.actif,
    required this.enCaisse,
    required this.nbCommandes,
    required this.nbLivrees,
    required this.ca,
    required this.coutParCommande,
  });

  final int id;
  final String nom;
  final String plateformeLabel;
  final String dateDebut;
  final String? dateFin;
  final double montant;
  final int articlesVendus;
  final double coutParArticle;
  final bool actif;
  final bool enCaisse;
  final int nbCommandes;
  final int nbLivrees;
  final double ca;
  final double? coutParCommande;

  factory FinanceBoost.fromJson(Map<String, dynamic> j) => FinanceBoost(
        id: asInt(j['id']),
        nom: asString(j['nom']),
        plateformeLabel: asString(j['plateforme_label']),
        dateDebut: asString(j['date_debut']),
        dateFin: asStringOrNull(j['date_fin']),
        montant: asDouble(j['montant']),
        articlesVendus: asInt(j['articles_vendus']),
        coutParArticle: asDouble(j['cout_par_article']),
        actif: asBool(j['actif'], true),
        enCaisse: asBool(j['en_caisse'], false),
        nbCommandes: asInt(j['nb_commandes']),
        nbLivrees: asInt(j['nb_livrees']),
        ca: asDouble(j['ca']),
        coutParCommande: asDoubleOrNull(j['cout_par_commande']),
      );
}

class EncaissementLigne {
  const EncaissementLigne({required this.id, required this.orderId, required this.numero, required this.client, required this.montant, required this.source, required this.sourceLabel, required this.livreurId, required this.livreur, required this.dateCommande});
  final int id;
  final int orderId;
  final String numero;
  final String client;
  final double montant;
  final String source;
  final String sourceLabel;
  final int? livreurId;
  final String livreur;
  final String dateCommande;

  factory EncaissementLigne.fromJson(Map<String, dynamic> j) => EncaissementLigne(
        id: asInt(j['id']),
        orderId: asInt(j['order_id']),
        numero: asString(j['numero']),
        client: asString(j['client']),
        montant: asDouble(j['montant']),
        source: asString(j['source']),
        sourceLabel: asString(j['source_label']),
        livreurId: asIntOrNull(j['livreur_id']),
        livreur: asString(j['livreur']),
        dateCommande: asString(j['date_commande']),
      );
}

class EncaissementParLivreur {
  const EncaissementParLivreur({required this.livreurId, required this.nom, required this.nb, required this.brut, required this.depenses, required this.net});
  final int? livreurId;
  final String nom;
  final int nb;
  final double brut;
  final double depenses;
  final double net;

  factory EncaissementParLivreur.fromJson(Map<String, dynamic> j) => EncaissementParLivreur(
        livreurId: asIntOrNull(j['livreur_id']),
        nom: asString(j['nom']),
        nb: asInt(j['nb']),
        brut: asDouble(j['brut']),
        depenses: asDouble(j['depenses']),
        net: asDouble(j['net']),
      );
}

class FinanceEncaissements {
  const FinanceEncaissements({required this.lignes, required this.parLivreur, required this.total, required this.chezLivreurs, required this.aEnregistrer});
  final List<EncaissementLigne> lignes;
  final List<EncaissementParLivreur> parLivreur;
  final double total;
  final double chezLivreurs;
  final double aEnregistrer;

  factory FinanceEncaissements.fromJson(Map<String, dynamic> j) => FinanceEncaissements(
        lignes: (j['lignes'] as List? ?? []).map((e) => EncaissementLigne.fromJson((e as Map).cast<String, dynamic>())).toList(),
        parLivreur: (j['par_livreur'] as List? ?? []).map((e) => EncaissementParLivreur.fromJson((e as Map).cast<String, dynamic>())).toList(),
        total: asDouble(j['total']),
        chezLivreurs: asDouble(j['chez_livreurs']),
        aEnregistrer: asDouble(j['a_enregistrer']),
      );
}

class FinanceDashboard {
  const FinanceDashboard({
    required this.indicateurs,
    required this.periodeFrom,
    required this.periodeTo,
    required this.gain,
    required this.pctReappro,
    required this.pctEpargne,
    required this.pctDepenses,
    required this.livraisonPeriode,
    required this.livraisonJour,
    required this.livraisonSemaine,
    required this.livraisonMois,
    required this.boosts,
    required this.encaissements,
    required this.epargneSolde,
    required this.epargneVersePeriode,
    required this.epargneRetirePeriode,
  });

  final FinanceIndicateurs indicateurs;
  final String periodeFrom;
  final String periodeTo;
  final FinanceGain gain;
  final double pctReappro;
  final double pctEpargne;
  final double pctDepenses;
  final StatsLivraison livraisonPeriode;
  final StatsLivraison livraisonJour;
  final StatsLivraison livraisonSemaine;
  final StatsLivraison livraisonMois;
  final List<FinanceBoost> boosts;
  final FinanceEncaissements encaissements;
  final double epargneSolde;
  final double epargneVersePeriode;
  final double epargneRetirePeriode;

  factory FinanceDashboard.fromJson(Map<String, dynamic> j) {
    final periode = (j['periode'] as Map?) ?? const {};
    final pct = (j['repartition_pct'] as Map?) ?? const {};
    final liv = (j['livraison'] as Map?) ?? const {};
    final ep = (j['epargne'] as Map?) ?? const {};
    StatsLivraison sl(String k) => StatsLivraison.fromJson(((liv[k] as Map?) ?? const {}).cast<String, dynamic>());
    return FinanceDashboard(
      indicateurs: FinanceIndicateurs.fromJson(((j['indicateurs'] as Map?) ?? const {}).cast<String, dynamic>()),
      periodeFrom: asString(periode['from']),
      periodeTo: asString(periode['to']),
      gain: FinanceGain.fromJson(((j['gain'] as Map?) ?? const {}).cast<String, dynamic>()),
      pctReappro: asDouble(pct['reappro'], 60),
      pctEpargne: asDouble(pct['epargne'], 25),
      pctDepenses: asDouble(pct['depenses'], 15),
      livraisonPeriode: sl('periode'),
      livraisonJour: sl('jour'),
      livraisonSemaine: sl('semaine'),
      livraisonMois: sl('mois'),
      boosts: (j['boosts'] as List? ?? []).map((e) => FinanceBoost.fromJson((e as Map).cast<String, dynamic>())).toList(),
      encaissements: FinanceEncaissements.fromJson(((j['encaissements'] as Map?) ?? const {}).cast<String, dynamic>()),
      epargneSolde: asDouble(ep['solde']),
      epargneVersePeriode: asDouble(ep['verse_periode']),
      epargneRetirePeriode: asDouble(ep['retire_periode']),
    );
  }
}

/// Ligne du journal de caisse (`GET finance/journal/`).
class JournalLigne {
  const JournalLigne({
    required this.id,
    required this.date,
    required this.sessionId,
    required this.type,
    required this.origine,
    required this.origineLabel,
    required this.entree,
    required this.sortie,
    required this.montant,
    required this.libelle,
    required this.categorie,
    required this.reference,
    required this.soldeApres,
    required this.auteur,
    required this.automatique,
  });

  final int id;
  final DateTime? date;
  final int sessionId;
  final String type;
  final String origine;
  final String origineLabel;
  final double entree;
  final double sortie;
  final double montant;
  final String libelle;
  final String categorie;
  final String reference;
  final double soldeApres;
  final String auteur;
  final bool automatique;

  bool get isIn => type == 'in';

  factory JournalLigne.fromJson(Map<String, dynamic> j) => JournalLigne(
        id: asInt(j['id']),
        date: asDateOrNull(j['date']),
        sessionId: asInt(j['session_id']),
        type: asString(j['type']),
        origine: asString(j['origine']),
        origineLabel: asString(j['origine_label']),
        entree: asDouble(j['entree']),
        sortie: asDouble(j['sortie']),
        montant: asDouble(j['montant']),
        libelle: asString(j['libelle']),
        categorie: asString(j['categorie']),
        reference: asString(j['reference']),
        soldeApres: asDouble(j['solde_apres']),
        auteur: asString(j['auteur']),
        automatique: asBool(j['automatique'], false),
      );
}

/// Résultat d'une vente livrée (`GET finance/ventes/`).
class VenteLigne {
  const VenteLigne({
    required this.id,
    required this.orderId,
    required this.numero,
    required this.client,
    required this.dateVente,
    required this.livreur,
    required this.zone,
    required this.nbArticles,
    required this.caProduits,
    required this.livraisonClient,
    required this.totalClient,
    required this.coutAchat,
    required this.fraisAgence,
    required this.partBoost,
    required this.gainReel,
    required this.etat,
    required this.partReappro,
    required this.partEpargne,
    required this.partDepenses,
    required this.annule,
    required this.encaissement,
  });

  final int id;
  final int orderId;
  final String numero;
  final String client;
  final String dateVente;
  final String livreur;
  final String zone;
  final int nbArticles;
  final double caProduits;
  final double livraisonClient;
  final double totalClient;
  final double coutAchat;
  final double fraisAgence;
  final double partBoost;
  final double gainReel;
  final String etat;
  final double partReappro;
  final double partEpargne;
  final double partDepenses;
  final bool annule;
  final String encaissement;

  factory VenteLigne.fromJson(Map<String, dynamic> j) => VenteLigne(
        id: asInt(j['id']),
        orderId: asInt(j['order_id']),
        numero: asString(j['numero']),
        client: asString(j['client']),
        dateVente: asString(j['date_vente']),
        livreur: asString(j['livreur']),
        zone: asString(j['zone']),
        nbArticles: asInt(j['nb_articles']),
        caProduits: asDouble(j['ca_produits']),
        livraisonClient: asDouble(j['livraison_client']),
        totalClient: asDouble(j['total_client']),
        coutAchat: asDouble(j['cout_achat']),
        fraisAgence: asDouble(j['frais_agence']),
        partBoost: asDouble(j['part_boost']),
        gainReel: asDouble(j['gain_reel']),
        etat: asString(j['etat']),
        partReappro: asDouble(j['part_reappro']),
        partEpargne: asDouble(j['part_epargne']),
        partDepenses: asDouble(j['part_depenses']),
        annule: asBool(j['annule'], false),
        encaissement: asString(j['encaissement']),
      );
}

/// Mouvement d'épargne (`GET finance/epargne/ → historique`).
class EpargneMouvement {
  const EpargneMouvement({required this.id, required this.type, required this.typeLabel, required this.montant, required this.soldeApres, required this.motif, required this.orderNumero, required this.reference, required this.createdByName, required this.createdAt});
  final int id;
  final String type;
  final String typeLabel;
  final double montant;
  final double soldeApres;
  final String motif;
  final String orderNumero;
  final String reference;
  final String createdByName;
  final DateTime? createdAt;

  factory EpargneMouvement.fromJson(Map<String, dynamic> j) => EpargneMouvement(
        id: asInt(j['id']),
        type: asString(j['type']),
        typeLabel: asString(j['type_label']),
        montant: asDouble(j['montant']),
        soldeApres: asDouble(j['solde_apres']),
        motif: asString(j['motif']),
        orderNumero: asString(j['order_numero']),
        reference: asString(j['reference']),
        createdByName: asString(j['created_by_name']),
        createdAt: asDateOrNull(j['created_at']),
      );
}
