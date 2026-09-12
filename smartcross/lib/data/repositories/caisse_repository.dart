import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/caisse.dart';
import '../../models/json_utils.dart';

/// `/api/users/caisse/` — sessions de caisse (ouverture/fermeture),
/// mouvements d'espèces, catégories de dépense et résumé de période.
/// Réplique de `djangoClient.caisse` du web (frontend/lib/django-client.ts),
/// consommé par la page `/caisse`.
///
/// Tous les endpoints sessions/movements/summary sont `[IsAuthenticated,
/// IsGerant]` côté serveur ; seules les catégories sont lisibles par tout
/// utilisateur authentifié.
class CaisseRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// Session actuellement ouverte pour ce magasin, ou `null` s'il n'y en a
  /// pas (le backend répond `204 No Content`).
  Future<CaisseSession?> current(int magasinId) async {
    final response = await _dio.get('users/caisse/sessions/current/', queryParameters: {'magasin_id': magasinId});
    final data = response.data;
    if (response.statusCode == 204 || data == null || data is! Map) return null;
    return CaisseSession.fromJson(data as Map<String, dynamic>);
  }

  /// `listSessions({magasinId, status})` : toutes les sessions du magasin
  /// (ordre serveur `-opened_at`), filtrables sur `open` | `closed`.
  Future<List<CaisseSession>> listSessions(int magasinId, {String? status}) async {
    final response = await _dio.get('users/caisse/sessions/', queryParameters: {
      'magasin_id': magasinId,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return (response.data as List).map((e) => CaisseSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `POST /users/caisse/sessions/open/` — [openedAt] (instant absolu, UTC)
  /// permet d'antidater l'ouverture ; absent = maintenant côté serveur.
  Future<CaisseSession> open({
    required int magasinId,
    required double openingBalance,
    String? openingNote,
    DateTime? openedAt,
  }) async {
    final response = await _dio.post('users/caisse/sessions/open/', data: {
      'magasin_id': magasinId,
      'opening_balance': openingBalance,
      if (openingNote != null && openingNote.isNotEmpty) 'opening_note': openingNote,
      if (openedAt != null) 'opened_at': openedAt.toUtc().toIso8601String(),
    });
    return CaisseSession.fromJson(response.data as Map<String, dynamic>);
  }

  /// `POST /users/caisse/sessions/{id}/close/` — le serveur calcule
  /// `expected_balance` et `difference` ; [closedAt] (UTC) optionnel.
  Future<CaisseSession> close(
    int sessionId, {
    required double closingBalance,
    String? closingNote,
    DateTime? closedAt,
  }) async {
    final response = await _dio.post('users/caisse/sessions/$sessionId/close/', data: {
      'closing_balance': closingBalance,
      if (closingNote != null && closingNote.isNotEmpty) 'closing_note': closingNote,
      if (closedAt != null) 'closed_at': closedAt.toUtc().toIso8601String(),
    });
    return CaisseSession.fromJson(response.data as Map<String, dynamic>);
  }

  /// `listMovements({sessionId, magasinId, dateFrom, dateTo})` — les dates
  /// sont des jours `YYYY-MM-DD`, comparés côté serveur sur
  /// `created_at__date` (fuseau Indian/Antananarivo).
  Future<List<CaisseMovement>> listMovements({
    int? sessionId,
    int? magasinId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await _dio.get('users/caisse/movements/', queryParameters: {
      'session_id': ?sessionId,
      'magasin_id': ?magasinId,
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
    });
    return (response.data as List).map((e) => CaisseMovement.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `POST /users/caisse/movements/` — [categoryId] uniquement pour une
  /// sortie (le serializer refuse une catégorie sur une entrée) ; sans
  /// [sessionId] le serveur déduit la session ouverte du magasin.
  Future<CaisseMovement> addMovement({
    int? sessionId,
    required String movementType, // in | out
    required double amount,
    required String reason,
    int? categoryId,
  }) async {
    final response = await _dio.post('users/caisse/movements/', data: {
      'session': ?sessionId,
      'movement_type': movementType,
      'amount': amount,
      'reason': reason,
      if (movementType == 'out' && categoryId != null) 'category': categoryId,
    });
    return CaisseMovement.fromJson(response.data as Map<String, dynamic>);
  }

  /// `deleteMovement(id)` — présent dans le client web, non utilisé par la
  /// page `/caisse` (aucune action de ligne).
  Future<void> deleteMovement(int id) async {
    await _dio.delete('users/caisse/movements/$id/');
  }

  /// `GET /users/caisse/summary/?magasin_id&date_from&date_to` — par défaut
  /// le mois en cours côté serveur.
  Future<CaisseSummary> summary({int? magasinId, String? dateFrom, String? dateTo}) async {
    final response = await _dio.get('users/caisse/summary/', queryParameters: {
      'magasin_id': ?magasinId,
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
    });
    return CaisseSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// `categories.list()` — catégories de dépense de la société (le serveur
  /// crée les 4 catégories par défaut au premier appel).
  Future<List<CaisseCategory>> categories() async {
    final response = await _dio.get('users/caisse/categories/');
    return (response.data as List).map((e) => CaisseCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Valeur de stock actuelle du magasin (`GET /users/magasins/stats/`,
  /// entrée `magasin_id == magasinId` → `total_stock_value`), utilisée pour
  /// pré-remplir les montants d'ouverture et de fermeture — recalculée à
  /// chaque ouverture de dialog car le stock bouge avec les ventes.
  /// `null` si le magasin est absent de la réponse ou en cas d'erreur
  /// (comportement silencieux du web : champ laissé vide).
  Future<double?> stockValue(int magasinId) async {
    try {
      final response = await _dio.get('users/magasins/stats/');
      final data = response.data;
      if (data is! List) return null;
      for (final entry in data) {
        if (entry is Map && asIntOrNull(entry['magasin_id']) == magasinId) {
          return asDoubleOrNull(entry['total_stock_value']);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
