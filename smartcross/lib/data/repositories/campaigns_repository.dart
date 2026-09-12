import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/campaign.dart';

/// Campagnes marketing — `djangoClient.campaigns` du web
/// (`MarketingCampaignViewSet`, orders/views.py). Lecture pour tout
/// utilisateur du magasin, écriture réservée au gérant (403 sinon).
class CampaignsRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// `GET /api/orders/campaigns/[?actif=1][&magasin_id=…]`.
  Future<List<MarketingCampaign>> list({bool actif = false, int? magasinId}) async {
    final response = await _dio.get(
      'orders/campaigns/',
      queryParameters: {
        if (magasinId != null) 'magasin_id': '$magasinId',
        if (actif) 'actif': '1',
      },
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Réponse inattendue du serveur pour les campagnes.');
    }
    return data.whereType<Map>().map((e) => MarketingCampaign.fromJson(e.cast<String, dynamic>())).toList();
  }

  MarketingCampaign _parse(dynamic data) {
    if (data is! Map) {
      throw const FormatException('Réponse inattendue du serveur pour la campagne.');
    }
    return MarketingCampaign.fromJson(data.cast<String, dynamic>());
  }

  /// `POST /api/orders/campaigns/` — payload : `nom`, `plateforme`,
  /// `montant`, `date_debut`, `date_fin?`, `note?`, `actif?`, `magasin_id?`.
  Future<MarketingCampaign> create(Map<String, dynamic> payload) async {
    final response = await _dio.post('orders/campaigns/', data: payload);
    return _parse(response.data);
  }

  /// `PATCH /api/orders/campaigns/{id}/`.
  Future<MarketingCampaign> update(int id, Map<String, dynamic> payload) async {
    final response = await _dio.patch('orders/campaigns/$id/', data: payload);
    return _parse(response.data);
  }

  /// `DELETE /api/orders/campaigns/{id}/`.
  Future<void> delete(int id) => _dio.delete('orders/campaigns/$id/');

  /// `POST /api/orders/{orderId}/campagne/` — rattache (ou détache avec
  /// `null`) une commande à une campagne.
  Future<void> setOrderCampaign(int orderId, int? campagne) =>
      _dio.post('orders/$orderId/campagne/', data: {'campagne': campagne});
}
