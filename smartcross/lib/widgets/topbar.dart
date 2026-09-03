import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/material.dart' as material show Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../state/auth_provider.dart';
import '../state/notifications_provider.dart';
import '../state/realtime_provider.dart';

class TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const TopBar({super.key, this.onMenuTap});

  final VoidCallback? onMenuTap;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final unread = ref.watch(unreadNotificationsCountProvider);
    final connected = ref.watch(wsConnectionStatusProvider).value ?? false;

    return AppBar(
      leading: onMenuTap != null ? IconButton(icon: const Icon(Icons.menu), onPressed: onMenuTap) : null,
      automaticallyImplyLeading: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.phone_iphone, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Smartphone.Mg', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: connected ? 'Temps réel connecté' : 'Connexion au serveur…',
            child: Icon(Icons.circle, size: 10, color: connected ? Colors.green : Colors.orange),
          ),
        ),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: material.Badge(
            label: Text('$unread'),
            isLabelVisible: unread > 0,
            child: const Icon(Icons.notifications_outlined),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Compte',
          onSelected: (value) async {
            if (value == 'logout') {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                '${user?.fullName ?? ''}\n${user?.email ?? ''}\n${(user?.role.label ?? '')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'logout', child: Text('Déconnexion')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CircleAvatar(
              child: Text((user?.fullName.isNotEmpty == true ? user!.fullName[0] : '?').toUpperCase()),
            ),
          ),
        ),
      ],
    );
  }
}
