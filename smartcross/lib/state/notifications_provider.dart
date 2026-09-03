import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/notifications_repository.dart';
import '../models/app_notification.dart';
import 'realtime_provider.dart';

final notificationsRepositoryProvider = Provider((ref) => NotificationsRepository());

class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  late final _repo = ref.read(notificationsRepositoryProvider);

  @override
  Future<List<AppNotification>> build() {
    ref.watch(realtimeTickProvider);
    return _repo.list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.list);
  }

  Future<void> markRead(int id) async {
    final current = state.value ?? [];
    // Mise à jour optimiste : la notif passe "lue" immédiatement à l'écran,
    // sans attendre l'aller-retour réseau.
    state = AsyncData([for (final n in current) if (n.id == id) n.copyWith(isRead: true) else n]);
    try {
      await _repo.markRead(id);
    } catch (_) {
      await refresh();
    }
  }
}

final notificationsProvider = AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(NotificationsNotifier.new);

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value ?? [];
  return list.where((n) => !n.isRead).length;
});
