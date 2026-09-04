import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/company.dart';

/// Fonctions "Super Admin" (§11 README, infrastructure SaaS conservée) :
/// réinitialisations de mot de passe des employés (admin), et abonnement /
/// appareils connectés de la société (propriétaire uniquement).
class CompanyRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<PasswordResetRequest>> passwordResetRequests({String? status}) async {
    final response = await _dio.get('users/password-reset-requests/', queryParameters: {
      if (status != null && status != 'all') 'status': status,
    });
    return (response.data as List).map((e) => PasswordResetRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> resolvePasswordReset(int id, String action) async {
    await _dio.patch('users/password-reset-requests/$id/', data: {'action': action});
  }

  Future<({List<CompanyDevice> devices, int count, int limit})> devices() async {
    final response = await _dio.get('users/my-company/devices/');
    final data = response.data as Map<String, dynamic>;
    return (
      devices: (data['devices'] as List).map((e) => CompanyDevice.fromJson(e as Map<String, dynamic>)).toList(),
      count: data['count'] as int? ?? 0,
      limit: data['limit'] as int? ?? 0,
    );
  }

  Future<CompanySubscription> subscription() async {
    final response = await _dio.get('users/my-company/subscription/');
    return CompanySubscription.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<CompanyRequest>> requests() async {
    final response = await _dio.get('users/my-company/requests/');
    return (response.data as List).map((e) => CompanyRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> requestActivation() async {
    await _dio.post('users/my-company/requests/', data: {'request_type': 'activation'});
  }

  Future<void> requestDeviceDeletion(int deviceId) async {
    await _dio.post('users/my-company/requests/', data: {'request_type': 'device_deletion', 'device_id': deviceId});
  }
}
