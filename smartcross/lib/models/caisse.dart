import 'json_utils.dart';

/// Catégorie de dépense (`GET /users/caisse/categories/`) proposée lors de
/// la saisie d'une SORTIE de caisse — gérée dans Paramètres > Dépenses.
/// Défaut serveur : Salaire, Pub, Commande stock, Autre.
class CaisseCategory {
  CaisseCategory({required this.id, required this.nom, this.createdAt});

  final int id;
  final String nom;
  final DateTime? createdAt;

  factory CaisseCategory.fromJson(Map<String, dynamic> json) {
    return CaisseCategory(
      id: asInt(json['id']),
      nom: asString(json['nom']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}

/// Mouvement d'espèces (apport, retrait, dépense…) au sein d'une session de
/// caisse — distinct des mouvements de stock (`StockMovement`).
class CaisseMovement {
  CaisseMovement({
    required this.id,
    required this.session,
    required this.movementType, // in | out
    required this.amount,
    required this.reason,
    this.magasinId,
    this.magasinName,
    this.categoryId,
    this.categoryName,
    this.createdByName,
    this.createdAt,
  });

  final int id;
  final int session;
  final String movementType;
  final double amount;
  final String reason;
  final int? magasinId;
  final String? magasinName;

  /// Catégorie de dépense — uniquement pour une sortie (le serializer
  /// refuse une catégorie sur une entrée).
  final int? categoryId;
  final String? categoryName;
  final String? createdByName;
  final DateTime? createdAt;

  bool get isIn => movementType == 'in';

  factory CaisseMovement.fromJson(Map<String, dynamic> json) {
    return CaisseMovement(
      id: asInt(json['id']),
      session: asInt(json['session']),
      movementType: asString(json['movement_type']),
      amount: asDouble(json['amount']),
      reason: asString(json['reason']),
      magasinId: asIntOrNull(json['magasin']),
      magasinName: asStringOrNull(json['magasin_name']),
      categoryId: asIntOrNull(json['category']),
      categoryName: asStringOrNull(json['category_name']),
      createdByName: asStringOrNull(json['created_by_name']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}

/// Session de caisse : ouverte avec un fond de départ, fermée avec un
/// montant compté — un magasin n'a qu'une session `open` à la fois.
class CaisseSession {
  CaisseSession({
    required this.id,
    required this.magasinId,
    required this.status, // open | closed
    this.magasinName,
    this.openedByName,
    this.closedByName,
    required this.openingBalance,
    this.closingBalance,
    this.expectedBalance,
    this.difference,
    this.openingNote,
    this.closingNote,
    this.openedAt,
    this.closedAt,
    this.movements = const [],
  });

  final int id;
  final int magasinId;
  final String status;
  final String? magasinName;
  final String? openedByName;
  final String? closedByName;
  final double openingBalance;
  final double? closingBalance;
  final double? expectedBalance;
  final double? difference;
  final String? openingNote;
  final String? closingNote;
  final DateTime? openedAt;
  final DateTime? closedAt;

  /// Ordre de l'API : `-created_at` (le plus récent en premier).
  final List<CaisseMovement> movements;

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';

  /// `movementTotals.in` du web : somme des entrées de la session.
  double get totalEntrees {
    var total = 0.0;
    for (final m in movements) {
      if (m.isIn) total += m.amount;
    }
    return total;
  }

  /// `movementTotals.out` du web : somme des sorties de la session.
  double get totalSorties {
    var total = 0.0;
    for (final m in movements) {
      if (!m.isIn) total += m.amount;
    }
    return total;
  }

  /// `expectedBalance` calculé côté client (fond + entrées − sorties), pour
  /// affichage avant fermeture — le serveur recalcule `expectedBalance` à
  /// la fermeture.
  double get soldeCourant => openingBalance + totalEntrees - totalSorties;

  factory CaisseSession.fromJson(Map<String, dynamic> json) {
    return CaisseSession(
      id: asInt(json['id']),
      magasinId: asInt(json['magasin']),
      status: asString(json['status']),
      magasinName: asStringOrNull(json['magasin_name']),
      openedByName: asStringOrNull(json['opened_by_name']),
      closedByName: asStringOrNull(json['closed_by_name']),
      openingBalance: asDouble(json['opening_balance']),
      closingBalance: asDoubleOrNull(json['closing_balance']),
      expectedBalance: asDoubleOrNull(json['expected_balance']),
      difference: asDoubleOrNull(json['difference']),
      openingNote: asStringOrNull(json['opening_note']),
      closingNote: asStringOrNull(json['closing_note']),
      openedAt: asDateOrNull(json['opened_at']),
      closedAt: asDateOrNull(json['closed_at']),
      movements: (json['movements'] as List? ?? []).map((e) => CaisseMovement.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// Ligne « Sorties par catégorie » du résumé — le backend remplace une
/// catégorie nulle par « Sans catégorie » et trie par total décroissant.
class CaisseCategoryTotal {
  CaisseCategoryTotal({required this.categorie, required this.total});

  final String categorie;
  final double total;

  factory CaisseCategoryTotal.fromJson(Map<String, dynamic> json) {
    return CaisseCategoryTotal(
      categorie: asString(json['categorie'], 'Sans catégorie'),
      total: asDouble(json['total']),
    );
  }
}

/// `GET /users/caisse/summary/` — entrées/sorties de caisse de la période,
/// toutes sessions confondues, plus CA / coût / bénéfice des produits
/// vendus (commandes LIVRÉES de la période).
class CaisseSummary {
  CaisseSummary({
    required this.dateFrom,
    required this.dateTo,
    required this.totalEntrees,
    required this.totalSorties,
    required this.solde,
    required this.sortiesParCategorie,
    required this.caProduitsVendus,
    required this.coutProduitsVendus,
    required this.beneficeProduitsVendus,
  });

  final String dateFrom;
  final String dateTo;
  final double totalEntrees;
  final double totalSorties;
  final double solde;
  final List<CaisseCategoryTotal> sortiesParCategorie;
  final double caProduitsVendus;
  final double coutProduitsVendus;
  final double beneficeProduitsVendus;

  factory CaisseSummary.fromJson(Map<String, dynamic> json) {
    return CaisseSummary(
      dateFrom: asString(json['date_from']),
      dateTo: asString(json['date_to']),
      totalEntrees: asDouble(json['total_entrees']),
      totalSorties: asDouble(json['total_sorties']),
      solde: asDouble(json['solde']),
      sortiesParCategorie: (json['sorties_par_categorie'] as List? ?? [])
          .map((e) => CaisseCategoryTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
      caProduitsVendus: asDouble(json['ca_produits_vendus']),
      coutProduitsVendus: asDouble(json['cout_produits_vendus']),
      beneficeProduitsVendus: asDouble(json['benefice_produits_vendus']),
    );
  }
}

/// Carte « Résumé de la caisse » : le résumé chiffré ET les mouvements de la
/// période (deux appels lancés ensemble, `fetchSummary()` du web).
class CaissePeriodData {
  const CaissePeriodData({required this.summary, required this.movements});

  final CaisseSummary summary;

  /// Ordre de l'API (`-created_at`, le plus récent en premier) — pas
  /// d'inversion, contrairement aux mouvements de la session en cours.
  final List<CaisseMovement> movements;
}
