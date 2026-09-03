import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/app_notification.dart';
import '../../state/notifications_provider.dart';
import '../../widgets/async_state_widgets.dart';

final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Notifications de l'utilisateur connecté (§9 README), reçues en REST et
/// mises à jour en temps réel via le WebSocket (voir realtime_provider.dart).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
        child: switch (async) {
          AsyncData(:final value) => value.isEmpty
              ? const EmptyState(message: 'Aucune notification.', icon: Icons.notifications_none)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _NotificationTile(notification: value[i]),
                ),
          AsyncError(:final error) => ErrorState(
              message: ApiClient.messageFromError(error),
              onRetry: () => ref.read(notificationsProvider.notifier).refresh(),
            ),
          _ => const LoadingState(),
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPrete = notification.notifType == NotifType.commandePrete;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: notification.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isPrete ? Colors.blue : Colors.orange).withValues(alpha: 0.15),
          child: Icon(isPrete ? Icons.local_shipping_outlined : Icons.receipt_long_outlined, color: isPrete ? Colors.blue : Colors.orange),
        ),
        title: Text(notification.message, style: TextStyle(fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w700)),
        subtitle: notification.createdAt != null ? Text(_dateFmt.format(notification.createdAt!)) : null,
        onTap: () {
          if (!notification.isRead) ref.read(notificationsProvider.notifier).markRead(notification.id);
          if (notification.orderId != null) context.push('/orders/${notification.orderId}');
        },
      ),
    );
  }
}
