import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/app_notification.dart';

/// `/api/users/notifications/` — notifications de l'utilisateur connecté, par
/// rôle ciblé (§9 Smartreadme.md). Le flux temps réel est géré par
/// `notifications_socket_service.dart`.
class NotificationsRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<AppNotification>> list() async {
    final response = await _dio.get('users/notifications/');
    return (response.data as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppNotification> markRead(int id) async {
    final response = await _dio.patch('users/notifications/$id/', data: {'is_read': true});
    return AppNotification.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> markAllRead() async {
    await _dio.post('users/notifications/mark-all-read/');
  }
}
