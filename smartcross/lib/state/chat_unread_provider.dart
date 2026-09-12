import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/chat_repository.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

/// Cadence du rafraîchissement périodique — `setInterval(refreshUnread,
/// 30000)` du sidebar web.
const Duration kChatUnreadRefreshInterval = Duration(seconds: 30);

/// Texte du badge de non-lus : plafonné à « 99+ » comme sur le web.
String chatUnreadBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// Compteur de messages directs non lus du compte connecté — badge de
/// l'entrée « Discussions » du menu (miroir de `unreadChats` dans
/// frontend/components/layout/sidebar.tsx).
///
/// Le chat a son propre WebSocket, ouvert seulement sur l'écran de
/// conversation : le menu, lui, est monté partout. On interroge donc un
/// compteur léger (`GET users/chat/unread-count/`, un simple COUNT côté
/// serveur) :
///
/// * à l'ouverture de session et à chaque changement de compte ;
/// * toutes les 30 s ([kChatUnreadRefreshInterval]) ;
/// * à chaque événement temps réel (`realtimeTickProvider`) — tout message
///   privé crée une Notification poussée sur /ws/notifications/
///   (users/signals.py::chat_message_created), le badge monte donc dès la
///   réception, sans attendre le prochain tic ;
/// * à la demande ([refresh]) — le web relit à chaque changement de page
///   pour que le badge retombe dès qu'une conversation vient d'être lue :
///   à appeler après un `ChatMessagesRead` reçu sur la socket, en quittant
///   un écran de conversation, et à chaque changement de route du shell.
///
/// Une erreur réseau ne fait jamais disparaître la valeur affichée (le web
/// fait `.catch(() => {})`) ; hors session le compteur vaut 0.
class ChatUnreadNotifier extends AsyncNotifier<int> {
  // Instance directe plutôt qu'un provider : `chatRepositoryProvider` est
  // déclaré dans features/chats/chat_list_screen.dart (un écran), et
  // ChatRepository est sans état (simple enveloppe d'ApiClient.instance).
  final _repo = ChatRepository();
  Timer? _timer;

  @override
  Future<int> build() async {
    _timer?.cancel();
    ref.onDispose(() => _timer?.cancel());

    // Ne dépend que de « qui est connecté » : un simple refreshUser() ne
    // relance pas le compteur, une connexion/déconnexion/changement de
    // compte si.
    final userId = ref.watch(
      authProvider.select((a) => a.status == AuthStatus.authenticated ? a.user?.id : null),
    );
    if (userId == null) return 0;

    // Rafraîchissement sur événement temps réel, sans reconstruire le
    // provider (la valeur affichée reste en place pendant l'appel).
    ref.listen(realtimeTickProvider, (previous, next) => refresh());

    _timer = Timer.periodic(kChatUnreadRefreshInterval, (_) => refresh());
    return _repo.unreadCount();
  }

  /// Relit le compteur immédiatement (à la demande). Silencieux : en cas
  /// d'échec, la dernière valeur connue reste affichée.
  Future<void> refresh() async {
    if (ref.read(authProvider).status != AuthStatus.authenticated) return;
    final result = await AsyncValue.guard(_repo.unreadCount);
    if (result.hasValue) state = result;
  }

  /// Fait retomber le badge sans attendre le serveur — à utiliser quand on
  /// SAIT que des messages viennent d'être lus (ex. `ChatMessagesRead`
  /// portant [count] identifiants), avant le [refresh] de confirmation.
  void decrement(int count) {
    final current = state.value;
    if (current == null || count <= 0) return;
    state = AsyncData(current - count < 0 ? 0 : current - count);
  }
}

final chatUnreadProvider = AsyncNotifierProvider<ChatUnreadNotifier, int>(ChatUnreadNotifier.new);

/// Valeur prête pour le badge : 0 tant que rien n'est chargé, hors session,
/// ou en erreur (le badge est simplement masqué quand la valeur est 0).
final chatUnreadCountProvider = Provider<int>((ref) => ref.watch(chatUnreadProvider).value ?? 0);
