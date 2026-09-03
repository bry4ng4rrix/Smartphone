import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/secure_storage.dart';
import '../../models/user.dart';

class LoginResult {
  LoginResult({required this.access, required this.refresh, required this.role, required this.fullName});
  final String access;
  final String refresh;
  final String role;
  final String fullName;
}

class AuthRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<LoginResult> login(String email, String password) async {
    final response = await _dio.post('users/login/', data: {'email': email, 'password': password});
    final data = response.data as Map<String, dynamic>;
    final result = LoginResult(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
      role: data['role'] as String? ?? '',
      fullName: data['full_name'] as String? ?? '',
    );
    await TokenStorage.instance.save(access: result.access, refresh: result.refresh);
    return result;
  }

  Future<void> logout() async {
    await TokenStorage.instance.clear();
  }

  Future<AppUser> me() async {
    final response = await _dio.get('users/me/');
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AppUser> updateProfile({String? fullName, String? phone}) async {
    final response = await _dio.patch('users/me/', data: {
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
    });
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    await _dio.post('users/change-password/', data: {'old_password': oldPassword, 'new_password': newPassword});
  }
}
