import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../data/repositories/chat_repository.dart';
import '../../models/chat.dart';
import '../../widgets/async_state_widgets.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository());
final chatUsersProvider = FutureProvider.autoDispose<List<ChatUser>>((ref) => ref.read(chatRepositoryProvider).users());

const _roleLabel = {'admin': 'Gérant', 'magasin': 'Gérant', 'employer': 'Équipe'};

/// "En ligne" / "Vu à l'instant" / "Vu il y a Xmin" / "Vu à HH:mm" / "Hors
/// ligne" — même formulation que `formatLastSeen()` côté web
/// (chats/page.tsx). Public (pas `_`) pour être réutilisé par
/// chat_conversation_screen.dart (en-tête du contact actif).
String presenceLabel(ChatUser user) {
  if (user.isOnline) return 'En ligne';
  final seen = lastSeenLabel(user.lastSeenAt);
  return seen != null ? 'Vu $seen' : 'Hors ligne';
}

String? lastSeenLabel(DateTime? date) {
  if (date == null) return null;
  final local = date.toLocal();
  final diffMin = DateTime.now().difference(date).inMinutes;
  if (diffMin < 1) return "à l'instant";
  if (diffMin < 60) return 'il y a $diffMin min';
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return 'à $hh:$mm';
}

/// Avatar + petit point vert si en ligne (façon WhatsApp) — réutilisé par
/// l'en-tête de conversation.
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({super.key, required this.user, this.radius = 20});

  final ChatUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(radius: radius, child: Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?')),
        if (user.isOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Liste des conversations : salon général de la société + un fil privé par
/// collègue (§9 README — infrastructure conservée, indépendante du cahier
/// des charges Smartphone.Mg).
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    // Le serveur ne pousse pas de présence (pas de push) : la liste des
    // collègues est recalculée à chaque appel, donc on la refetch toutes les
    // 20s pour garder "En ligne"/"Vu il y a ..." à jour (miroir web :
    // setInterval(fetchUsers, 20000) dans chats/page.tsx). Ce timer continue
    // de tourner même quand une conversation est poussée par-dessus, cet
    // écran restant monté sous la pile de navigation.
    _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) => ref.invalidate(chatUsersProvider));
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chatUsersProvider);
    // .value (nullable, Riverpod 3 — équivalent de l'ancien valueOrNull)
    // garde la dernière liste affichée pendant un refresh (silencieux ou
    // pull-to-refresh) au lieu de tout remplacer par un spinner toutes les 20s.
    final users = async.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Discussions')),
      body: users != null
          ? RefreshIndicator(
              onRefresh: () => ref.refresh(chatUsersProvider.future),
              child: ListView(
                children: [
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                    title: const Text('Général', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Toute l\'équipe'),
                    onTap: () => context.push('/chats/room/general'),
                  ),
                  const Divider(height: 1),
                  for (final user in users)
                    ListTile(
                      leading: PresenceAvatar(user: user),
                      title: Text(user.fullName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_roleLabel[user.role] ?? user.role),
                          Text(
                            presenceLabel(user),
                            style: TextStyle(
                              fontSize: 11,
                              color: user.isOnline ? Colors.green : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      onTap: () => context.push('/chats/dm/${user.id}', extra: user.fullName),
                    ),
                ],
              ),
            )
          : switch (async) {
              AsyncError(:final error) => ErrorState(message: ApiClient.messageFromError(error), onRetry: () => ref.invalidate(chatUsersProvider)),
              _ => const LoadingState(),
            },
    );
  }
}
