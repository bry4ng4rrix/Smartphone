import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/reports.dart';

/// Rapports du gérant — `djangoClient.reports` du web.
///
/// Un seul endpoint, `GET /api/orders/reports/`, qui agrège TOUT côté
/// serveur (orders/reports.py) : chiffre d'affaires, marge, dépenses,
/// résultat, activité par jour, classements produits, performance des
/// livreurs et des préparateurs, mouvements de stock. Plus aucune
/// agrégation côté client : le bénéfice a besoin du prix d'achat, qui ne
/// doit pas transiter par l'appareil d'un livreur ou d'un préparateur.
class ReportsRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// `GET /api/orders/reports/?date_from=YYYY-MM-DD&date_to=YYYY-MM-DD`.
  ///
  /// GÉRANT UNIQUEMENT — le serveur répond 403 à tout autre compte, quoi
  /// qu'affiche l'écran. Bornes comprises, en date de livraison prévue
  /// (`date_commande`). Aucune validation des bornes côté web : une période
  /// inversée (`dateFrom` après `dateTo`) revient simplement vide.
  Future<ReportsData> fetch({required DateTime dateFrom, required DateTime dateTo}) async {
    final response = await _dio.get(
      'orders/reports/',
      queryParameters: {
        'date_from': formatReportsDate(dateFrom),
        'date_to': formatReportsDate(dateTo),
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Réponse inattendue du serveur pour les rapports.');
    }
    return ReportsData.fromJson(data.cast<String, dynamic>());
  }
}
