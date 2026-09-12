import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications_socket_service.dart';
import '../core/permissions.dart';
import '../data/repositories/notifications_repository.dart';
import '../models/app_notification.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

final notificationsRepositoryProvider = Provider((ref) => NotificationsRepository());

/// Notifications poussées en temps réel sur `/ws/notifications/` (§9
/// README), une par trame — c'est ce flux qui alimente le toast global de
/// l'application (`useNotificationsWebSocket({showToast: true})` de la cloche
/// web, voir widgets/topbar.dart). La trame peut ne pas porter d'identifiant
/// (`AppNotification.isPersisted`) : la liste, elle, est toujours relue en
/// REST (voir [NotificationsNotifier]).
final incomingNotificationProvider = StreamProvider<AppNotification>(
  (ref) => NotificationsSocketService.instance.incoming.map(AppNotification.fromJson),
);

/// Liste des notifications de l'utilisateur connecté — page /notifications
/// et cloche de la barre supérieure partagent ce même état (le web les
/// charge séparément et peut diverger jusqu'au prochain rechargement).
///
/// * chaque événement temps réel relit la liste SILENCIEUSEMENT (la liste
///   reste affichée) : la nouvelle notification arrive en tête avec son vrai
///   identifiant, ce que la trame WebSocket ne garantit pas ;
/// * [refresh] (bouton « Actualiser ») repasse par l'état de chargement,
///   comme les skeletons du web ;
/// * les actions sont optimistes (l'écran change immédiatement) puis
///   confirmées par le serveur ; en cas d'échec l'état précédent est rétabli
///   et l'erreur remonte à l'écran pour son toast.
class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  late final _repo = ref.read(notificationsRepositoryProvider);

  @override
  Future<List<AppNotification>> build() {
    ref.listen(realtimeTickProvider, (previous, next) => refreshSilencieux());
    return _repo.list();
  }

  List<AppNotification> get _current => state.value ?? const <AppNotification>[];

  /// Rechargement NON silencieux (« Actualiser ») : état de chargement visible.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.list);
  }

  /// Rechargement SILENCIEUX (temps réel, après une action) : la liste
  /// courante reste affichée pendant l'appel.
  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(_repo.list);
  }

  /// Bascule lue / non lue (`toggleRead` de la page web). Optimiste, puis
  /// relecture silencieuse comme le `fetchNotifications()` du web.
  Future<void> setRead(int id, bool isRead) async {
    final previous = _current;
    state = AsyncData([for (final n in previous) n.id == id ? n.copyWith(isRead: isRead) : n]);
    try {
      await _repo.setRead(id, isRead);
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
    await refreshSilencieux();
  }

  Future<void> markRead(int id) => setRead(id, true);

  /// « Marquer tout lu » / « Tout marquer lu » — toutes les notifications
  /// visibles, côté serveur comme à l'écran.
  Future<void> markAllRead() async {
    final previous = _current;
    state = AsyncData([for (final n in previous) n.copyWith(isRead: true)]);
    try {
      await _repo.markAllRead();
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
    await refreshSilencieux();
  }

  /// Sélection marquée lue (`bulk-read`).
  Future<void> bulkRead(Iterable<int> ids) async {
    final cibles = ids.toSet();
    if (cibles.isEmpty) return;
    final previous = _current;
    state = AsyncData([for (final n in previous) cibles.contains(n.id) ? n.copyWith(isRead: true) : n]);
    try {
      await _repo.bulkRead(cibles.toList());
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
    await refreshSilencieux();
  }

  /// Suppression unitaire — retirée de la liste sans relecture, comme le
  /// `filter` local du web.
  Future<void> delete(int id) async {
    final previous = _current;
    state = AsyncData(previous.where((n) => n.id != id).toList());
    try {
      await _repo.delete(id);
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// Sélection supprimée (`bulk-delete`).
  Future<void> bulkDelete(Iterable<int> ids) async {
    final cibles = ids.toSet();
    if (cibles.isEmpty) return;
    final previous = _current;
    state = AsyncData(previous.where((n) => !cibles.contains(n.id)).toList());
    try {
      await _repo.bulkDelete(cibles.toList());
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// « Supprimer tout » — EN BASE, toutes les notifications visibles ; la
  /// liste est vidée localement sans relecture (`setNotifications([])`).
  Future<void> deleteAll() async {
    final previous = _current;
    state = const AsyncData(<AppNotification>[]);
    try {
      await _repo.deleteAll();
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// Identifiant de la commande visée par [notification] (deep-link), ou
  /// `null` si elle n'en cite aucune, est introuvable ou inaccessible au
  /// rôle courant.
  Future<int?> resolveOrderId(AppNotification notification) async {
    final numero = notification.orderNumero;
    if (numero == null) return null;
    final user = ref.read(authProvider).user;
    final employe = user != null && (user.isPreparateur || user.isLivreur);
    return _repo.findOrderIdByNumero(numero, employe: employe);
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(NotificationsNotifier.new);

/// Identifiants effacés localement par « Tout effacer » de la cloche —
/// persistés sur l'appareil ([DismissedNotificationsStore]), jamais envoyés
/// au serveur. Vide au démarrage, rempli dès que la lecture locale aboutit.
class DismissedNotificationsNotifier extends Notifier<Set<int>> {
  final _store = DismissedNotificationsStore();

  @override
  Set<int> build() {
    _store.load().then((ids) {
      if (ref.mounted && ids.isNotEmpty) state = {...state, ...ids};
    });
    return const <int>{};
  }

  /// Retire [ids] de la cloche (liste ET compteur) et mémorise le choix.
  Future<void> dismiss(Iterable<int> ids) async {
    final next = {...state, ...ids};
    state = next;
    await _store.save(next);
  }
}

final dismissedNotificationIdsProvider =
    NotifierProvider<DismissedNotificationsNotifier, Set<int>>(DismissedNotificationsNotifier.new);

/// Notifications de la CLOCHE : la liste REST moins les identifiants effacés
/// localement (filtre implicite du web, appliqué au chargement comme à
/// l'arrivée d'une nouvelle notification).
final bellNotificationsProvider = Provider<List<AppNotification>>((ref) {
  final all = ref.watch(notificationsProvider).value ?? const <AppNotification>[];
  final dismissed = ref.watch(dismissedNotificationIdsProvider);
  if (dismissed.isEmpty) return all;
  return all.where((n) => !dismissed.contains(n.id)).toList();
});

/// Compteur du badge de la cloche — calculé sur la liste DÉJÀ filtrée des
/// effacés locaux (une notification non lue masquée ne compte plus ici, mais
/// reste non lue sur la page /notifications), comme sur le web.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  return ref.watch(bellNotificationsProvider).where((n) => !n.isRead).length;
});

/// Texte du badge de la cloche : plafonné à « 9+ » comme sur le web.
String notificationsBadgeLabel(int count) => count > 9 ? '9+' : '$count';
