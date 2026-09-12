import '../core/app_time.dart';
import 'json_utils.dart';

/// Statut d'une dépense déclarée par un livreur — `LivreurExpense.statut`
/// côté serveur (EN_ATTENTE | ACCEPTE | REJETE). Une dépense n'entre dans
/// aucun bilan tant qu'elle n'est pas ACCEPTÉE.
enum ExpenseStatus { enAttente, accepte, rejete }

extension ExpenseStatusX on ExpenseStatus {
  static ExpenseStatus fromApi(String? value) {
    switch (value) {
      case 'ACCEPTE':
        return ExpenseStatus.accepte;
      case 'REJETE':
        return ExpenseStatus.rejete;
      default:
        return ExpenseStatus.enAttente;
    }
  }

  String get apiValue {
    switch (this) {
      case ExpenseStatus.enAttente:
        return 'EN_ATTENTE';
      case ExpenseStatus.accepte:
        return 'ACCEPTE';
      case ExpenseStatus.rejete:
        return 'REJETE';
    }
  }

  /// Mêmes libellés que `STATUT_DEPENSE` de la page /bilan du web.
  String get label {
    switch (this) {
      case ExpenseStatus.enAttente:
        return 'En attente';
      case ExpenseStatus.accepte:
        return 'Acceptée';
      case ExpenseStatus.rejete:
        return 'Rejetée';
    }
  }
}

/// Type de dépense du livreur, configurable dans Paramètres (§ demande) —
/// repas, carburant, enveloppe… Le catalogue appartient à la société, pas à
/// un magasin (voir orders/models.py::ExpenseType).
///
/// [prixUnitaire] n'est qu'une valeur par défaut proposée à la saisie : le
/// montant réellement retenu est figé sur la dépense, pour qu'une révision
/// de tarif ne réécrive pas les bilans déjà validés.
class ExpenseType {
  const ExpenseType({
    required this.id,
    required this.nom,
    required this.prixUnitaire,
    required this.parUnite,
    required this.actif,
    this.createdAt,
  });

  final int id;
  final String nom;
  final double prixUnitaire;

  /// Vrai pour une dépense qui se compte (enveloppes…) : la saisie propose
  /// alors une quantité, et le montant vaut prix_unitaire × quantité.
  final bool parUnite;

  /// Un type inactif n'est plus proposé à la saisie mais reste attaché aux
  /// dépenses passées (DELETE d'un type déjà utilisé = désactivation).
  final bool actif;
  final DateTime? createdAt;

  factory ExpenseType.fromJson(Map<String, dynamic> json) {
    return ExpenseType(
      id: asInt(json['id']),
      nom: asString(json['nom']),
      prixUnitaire: asDouble(json['prix_unitaire']),
      parUnite: asBool(json['par_unite'], false),
      actif: asBool(json['actif'], true),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}

/// Dépense déclarée par un livreur sur sa journée (§ demande) — voir
/// orders/models.py::LivreurExpense.
///
/// Le libellé et le prix unitaire sont recopiés depuis le type au moment de
/// la déclaration ([typeDepenseId] est `null` pour une saisie libre). Elle
/// n'entre dans aucun bilan tant que le gérant ne l'a pas acceptée ; une
/// fois acceptée, elle est déduite du bilan du jour de CE livreur (« NET À
/// REMETTRE »).
class LivreurExpense {
  const LivreurExpense({
    required this.id,
    required this.livreurId,
    this.livreurName,
    this.typeDepenseId,
    this.typeNom,
    required this.libelle,
    required this.prixUnitaire,
    required this.quantite,
    required this.montant,
    this.motif,
    required this.date,
    required this.statut,
    this.motifRejet,
    this.resolvedByName,
    this.resolvedAt,
    this.createdAt,
  });

  final int id;
  final int livreurId;
  final String? livreurName;
  final int? typeDepenseId;
  final String? typeNom;
  final String libelle;
  final double prixUnitaire;
  final int quantite;

  /// Calculé par le serveur : prix_unitaire × quantité.
  final double montant;
  final String? motif;

  /// Jour auquel la dépense se rattache (date calendaire, sans heure) —
  /// c'est ce champ qui la fait entrer dans un bilan, pas [createdAt].
  final DateTime date;
  final ExpenseStatus statut;
  final String? motifRejet;
  final String? resolvedByName;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  bool get estEnAttente => statut == ExpenseStatus.enAttente;
  bool get estAcceptee => statut == ExpenseStatus.accepte;
  bool get estRejetee => statut == ExpenseStatus.rejete;

  /// "Repas x2" — libellé de liste (même forme que le web : la quantité
  /// n'est ajoutée que si elle dépasse 1).
  String get libelleAvecQuantite => quantite > 1 ? '$libelle x$quantite' : libelle;

  /// `YYYY-MM-DD` — forme attendue par les filtres `date_debut`/`date_fin`.
  String get dateIso => formatExpenseDate(date);

  factory LivreurExpense.fromJson(Map<String, dynamic> json) {
    final motif = asStringOrNull(json['motif']);
    final motifRejet = asStringOrNull(json['motif_rejet']);
    return LivreurExpense(
      id: asInt(json['id']),
      livreurId: asInt(json['livreur']),
      livreurName: asStringOrNull(json['livreur_name']),
      typeDepenseId: asIntOrNull(json['type_depense']),
      typeNom: asStringOrNull(json['type_nom']),
      libelle: asString(json['libelle']),
      prixUnitaire: asDouble(json['prix_unitaire']),
      quantite: asInt(json['quantite'], 1),
      montant: asDouble(json['montant']),
      motif: motif == null || motif.isEmpty ? null : motif,
      date: _parseDateOnly(json['date']),
      statut: ExpenseStatusX.fromApi(asStringOrNull(json['statut'])),
      motifRejet: motifRejet == null || motifRejet.isEmpty ? null : motifRejet,
      resolvedByName: asStringOrNull(json['resolved_by_name']),
      resolvedAt: asDateOrNull(json['resolved_at']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }

  /// `DateField` DRF : "2026-09-12" -> DateTime(2026, 9, 12), sans fuseau.
  static DateTime _parseDateOnly(dynamic v) {
    final parsed = asDateOrNull(v);
    // Champ requis côté serveur : le repli (jour J à Antananarivo) ne sert
    // qu'à ne jamais planter sur une réponse inattendue.
    if (parsed == null) return appToday();
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}

/// `YYYY-MM-DD` d'un jour calendaire — format des champs `date` et des
/// filtres `date_debut`/`date_fin` du serveur.
String formatExpenseDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
