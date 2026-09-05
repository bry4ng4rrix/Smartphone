import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/company.dart';

/// Réinitialisations de mot de passe des employés, résolues par l'admin.
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
}
