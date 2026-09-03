import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/supplier.dart';

/// `/api/suppliers/` — commandes fournisseur, coût de revient réel
/// (§7.6 README, réservé au gérant).
class SuppliersRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<SupplierOrder>> list() async {
    final response = await _dio.get('suppliers/orders/');
    return (response.data as List).map((e) => SupplierOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SupplierOrder> detail(int id) async {
    final response = await _dio.get('suppliers/orders/$id/');
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SupplierOrder> create({
    String description = '',
    required double prixFournisseur,
    required double fretImport,
    required double douane,
    required double metaAds,
    required List<SupplierOrderLineDraft> lines,
  }) async {
    final response = await _dio.post('suppliers/orders/', data: {
      'description': description,
      'prix_fournisseur': prixFournisseur,
      'fret_import': fretImport,
      'douane': douane,
      'meta_ads': metaAds,
      'lines': lines.map((e) => e.toJson()).toList(),
    });
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  /// Réception -> entrée stock automatique par ligne (§7.6 README).
  Future<SupplierOrder> receive(int id) async {
    final response = await _dio.post('suppliers/orders/$id/receive/');
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }
}
