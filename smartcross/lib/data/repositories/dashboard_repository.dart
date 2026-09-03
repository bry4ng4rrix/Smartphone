import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/dashboard.dart';

/// `GET /api/orders/dashboard/` — Dashboard Gérant (§7.7 README).
class DashboardRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<DashboardData> fetch({DateTime? dateDebut, DateTime? dateFin}) async {
    final response = await _dio.get('orders/dashboard/', queryParameters: {
      if (dateDebut != null) 'date_debut': _fmt(dateDebut),
      if (dateFin != null) 'date_fin': _fmt(dateFin),
    });
    return DashboardData.fromJson(response.data as Map<String, dynamic>);
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
