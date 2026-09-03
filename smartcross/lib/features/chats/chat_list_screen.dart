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

/// Liste des conversations : salon général de la société + un fil privé par
/// collègue (§9 README — infrastructure conservée, indépendante du cahier
/// des charges Smartphone.Mg).
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chatUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Discussions')),
      body: switch (async) {
        AsyncData(:final value) => RefreshIndicator(
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
                for (final user in value)
                  ListTile(
                    leading: CircleAvatar(child: Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?')),
                    title: Text(user.fullName),
                    subtitle: Text(_roleLabel[user.role] ?? user.role),
                    onTap: () => context.push('/chats/dm/${user.id}', extra: user.fullName),
                  ),
              ],
            ),
          ),
        AsyncError(:final error) => ErrorState(message: ApiClient.messageFromError(error), onRetry: () => ref.invalidate(chatUsersProvider)),
        _ => const LoadingState(),
      },
    );
  }
}
