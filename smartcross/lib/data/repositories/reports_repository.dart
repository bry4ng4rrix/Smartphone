import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/reports.dart';

/// Centre de rapports — `djangoClient.reports.section(section, params)` du
/// web : `GET /api/orders/reports/{section}/?date_from&date_to&prev_from&
/// prev_to&granularity[&dormant_days][&platform]` (orders/reporting.py).
///
/// GÉRANT UNIQUEMENT — le serveur répond 403 à tout autre compte : la
/// réponse contient coûts d'achat et marges, jamais exposés aux autres rôles.
class ReportsRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// Réponse brute d'une section ; seuls les paramètres non vides sont envoyés
  /// (comme `section()` du client web).
  Future<Map<String, dynamic>> section(ReportSection s, Map<String, String> params) async {
    final query = <String, String>{
      for (final e in params.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    final response = await _dio.get('orders/reports/${s.key}/', queryParameters: query);
    final data = response.data;
    if (data is! Map) {
      throw FormatException('Réponse inattendue du serveur pour le rapport « ${s.label} ».');
    }
    return data.cast<String, dynamic>();
  }

  /// Section typée : [parse] convertit la réponse brute.
  Future<T> fetch<T>(ReportSection s, Map<String, String> params, T Function(Map<String, dynamic>) parse) async =>
      parse(await section(s, params));

  Future<OverviewData> overview(Map<String, String> params) => fetch(ReportSection.overview, params, OverviewData.fromJson);
  Future<SalesData> sales(Map<String, String> params) => fetch(ReportSection.sales, params, SalesData.fromJson);
  Future<FinancialData> financial(Map<String, String> params) =>
      fetch(ReportSection.financial, params, FinancialData.fromJson);
  Future<ExpensesData> expenses(Map<String, String> params) => fetch(ReportSection.expenses, params, ExpensesData.fromJson);
  Future<StockData> stock(Map<String, String> params) => fetch(ReportSection.stock, params, StockData.fromJson);
  Future<OrdersData> orders(Map<String, String> params) => fetch(ReportSection.orders, params, OrdersData.fromJson);
  Future<DeliveriesData> deliveries(Map<String, String> params) =>
      fetch(ReportSection.deliveries, params, DeliveriesData.fromJson);
  Future<MarketingData> marketing(Map<String, String> params) =>
      fetch(ReportSection.marketing, params, MarketingData.fromJson);
}
