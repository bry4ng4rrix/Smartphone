import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/expense.dart';

/// Dépenses des livreurs (§ demande) — portage de `djangoClient.expenseTypes`
/// et `djangoClient.expenses` (frontend/lib/django-client.ts).
///
/// * Types de dépense (`/orders/expense-types/`) : lecture ouverte à tous
///   (le livreur en a besoin pour peupler son formulaire), écriture réservée
///   au gérant — voir orders/views.py::ExpenseTypeViewSet.
/// * Dépenses (`/orders/expenses/`) : le livreur ne voit et ne crée que les
///   siennes ; le gérant voit celles de ses magasins et les tranche. Une
///   dépense n'est déduite d'un bilan qu'une fois ACCEPTÉE — voir
///   orders/views.py::LivreurExpenseViewSet.
class ExpensesRepository {
  Dio get _dio => ApiClient.instance.dio;

  // -----------------------------------------------------------------------
  // Types de dépense (Paramètres > « Dépenses des livreurs »)
  // -----------------------------------------------------------------------

  Future<List<ExpenseType>> listTypes() async {
    final response = await _dio.get('orders/expense-types/');
    return _rows(response.data).map(ExpenseType.fromJson).toList();
  }

  Future<ExpenseType> createType({
    required String nom,
    required double prixUnitaire,
    bool parUnite = false,
  }) async {
    final response = await _dio.post('orders/expense-types/', data: {
      'nom': nom,
      'prix_unitaire': prixUnitaire,
      'par_unite': parUnite,
    });
    return ExpenseType.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ExpenseType> updateType(
    int id, {
    String? nom,
    double? prixUnitaire,
    bool? parUnite,
    bool? actif,
  }) async {
    final response = await _dio.patch('orders/expense-types/$id/', data: {
      'nom': ?nom,
      'prix_unitaire': ?prixUnitaire,
      'par_unite': ?parUnite,
      'actif': ?actif,
    });
    return ExpenseType.fromJson(response.data as Map<String, dynamic>);
  }

  /// Un type déjà utilisé par une dépense est DÉSACTIVÉ plutôt que supprimé
  /// (le serveur le renvoie alors en 200) ; sinon suppression réelle (204).
  /// Renvoie le type désactivé dans le premier cas, `null` s'il a été
  /// supprimé.
  Future<ExpenseType?> deleteType(int id) async {
    final response = await _dio.delete('orders/expense-types/$id/');
    final data = response.data;
    if (data is Map) return ExpenseType.fromJson(data.cast<String, dynamic>());
    return null;
  }

  // -----------------------------------------------------------------------
  // Dépenses déclarées
  // -----------------------------------------------------------------------

  /// [statut] : une valeur (`EN_ATTENTE`…) ou plusieurs séparées par une
  /// virgule ; [dateDebut]/[dateFin] : jours calendaires inclusifs (le champ
  /// `date` de la dépense, pas `created_at`) ; [livreurId] : gérant
  /// uniquement (le livreur ne reçoit de toute façon que les siennes).
  Future<List<LivreurExpense>> list({
    String? statut,
    DateTime? dateDebut,
    DateTime? dateFin,
    int? livreurId,
  }) async {
    final response = await _dio.get('orders/expenses/', queryParameters: {
      if (statut != null && statut.isNotEmpty) 'statut': statut,
      if (dateDebut != null) 'date_debut': formatExpenseDate(dateDebut),
      if (dateFin != null) 'date_fin': formatExpenseDate(dateFin),
      'livreur_id': ?livreurId,
    });
    return _rows(response.data).map(LivreurExpense.fromJson).toList();
  }

  /// Déclaration par le LIVREUR (le serveur refuse tout autre rôle) — crée
  /// une notification au gérant. [typeDepenseId] `null` = saisie libre
  /// (« Autre ») ; [date] = jour de travail auquel rattacher la dépense
  /// (vide = aujourd'hui côté serveur). Le serveur exige `prix_unitaire > 0`
  /// et `quantite >= 1`.
  Future<LivreurExpense> create({
    int? typeDepenseId,
    required String libelle,
    required double prixUnitaire,
    int quantite = 1,
    String motif = '',
    DateTime? date,
  }) async {
    final response = await _dio.post('orders/expenses/', data: {
      'type_depense': typeDepenseId,
      'libelle': libelle,
      'prix_unitaire': prixUnitaire,
      'quantite': quantite,
      'motif': motif,
      if (date != null) 'date': formatExpenseDate(date),
    });
    return LivreurExpense.fromJson(response.data as Map<String, dynamic>);
  }

  /// Retrait par son auteur (ou le gérant), uniquement tant qu'elle est
  /// EN_ATTENTE — une dépense tranchée est entrée (ou non) dans un bilan.
  Future<void> delete(int id) => _dio.delete('orders/expenses/$id/');

  /// Gérant : accepte ou rejette une dépense en attente. [statut] =
  /// 'ACCEPTE' | 'REJETE' ; [motifRejet] facultatif. Le livreur est notifié.
  Future<LivreurExpense> resoudre(int id, String statut, {String motifRejet = ''}) async {
    final response = await _dio.post('orders/expenses/$id/resoudre/', data: {
      'statut': statut,
      'motif_rejet': motifRejet,
    });
    return LivreurExpense.fromJson(response.data as Map<String, dynamic>);
  }

  /// DRF renvoie soit une liste brute, soit une enveloppe paginée
  /// `{results: [...]}` — les deux sont acceptées.
  List<Map<String, dynamic>> _rows(dynamic data) {
    final list = data is List
        ? data
        : data is Map
            ? (data['results'] as List? ?? const [])
            : const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
}
