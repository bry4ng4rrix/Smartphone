import 'json_utils.dart';

/// Mouvement d'espèces (apport, retrait, dépense…) au sein d'une session de
/// caisse — distinct des mouvements de stock (`StockMovement`).
class CaisseMovement {
  CaisseMovement({
    required this.id,
    required this.session,
    required this.movementType, // in | out
    required this.amount,
    required this.reason,
    this.createdByName,
    this.createdAt,
  });

  final int id;
  final int session;
  final String movementType;
  final double amount;
  final String reason;
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
  final List<CaisseMovement> movements;

  bool get isOpen => status == 'open';

  /// Solde courant estimé (fond + entrées − sorties), pour affichage avant
  /// fermeture — le serveur recalcule `expectedBalance` à la fermeture.
  double get soldeCourant {
    var total = openingBalance;
    for (final m in movements) {
      total += m.isIn ? m.amount : -m.amount;
    }
    return total;
  }

  factory CaisseSession.fromJson(Map<String, dynamic> json) {
    return CaisseSession(
      id: asInt(json['id']),
      magasinId: asInt(json['magasin']),
      status: asString(json['status']),
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
