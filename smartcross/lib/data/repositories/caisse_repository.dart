import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/caisse.dart';

/// `/api/users/caisse/` — ouverture/fermeture de caisse et mouvements
/// d'espèces (fonctionnalité conservée telle quelle du backend générique,
/// non spécifique au cahier des charges Smartphone.Mg).
class CaisseRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// Session actuellement ouverte pour ce magasin, ou `null` s'il n'y en a pas.
  Future<CaisseSession?> current(int magasinId) async {
    final response = await _dio.get('users/caisse/sessions/current/', queryParameters: {'magasin_id': magasinId});
    if (response.statusCode == 204 || response.data == null) return null;
    return CaisseSession.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<CaisseSession>> history(int magasinId) async {
    final response = await _dio.get('users/caisse/sessions/', queryParameters: {'magasin_id': magasinId});
    return (response.data as List).map((e) => CaisseSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CaisseSession> open({
    required int magasinId,
    required double openingBalance,
    String? openingNote,
  }) async {
    final response = await _dio.post('users/caisse/sessions/open/', data: {
      'magasin_id': magasinId,
      'opening_balance': openingBalance,
      if (openingNote != null && openingNote.isNotEmpty) 'opening_note': openingNote,
    });
    return CaisseSession.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CaisseSession> close(int sessionId, {required double closingBalance, String? closingNote}) async {
    final response = await _dio.post('users/caisse/sessions/$sessionId/close/', data: {
      'closing_balance': closingBalance,
      if (closingNote != null && closingNote.isNotEmpty) 'closing_note': closingNote,
    });
    return CaisseSession.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CaisseMovement> addMovement({
    required int sessionId,
    required String movementType, // in | out
    required double amount,
    required String reason,
  }) async {
    final response = await _dio.post('users/caisse/movements/', data: {
      'session': sessionId,
      'movement_type': movementType,
      'amount': amount,
      'reason': reason,
    });
    return CaisseMovement.fromJson(response.data as Map<String, dynamic>);
  }
}
