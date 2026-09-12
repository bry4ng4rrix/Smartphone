import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/nav_items.dart';
import '../core/constants.dart';
import '../state/auth_provider.dart';
import '../state/chat_unread_provider.dart';
import 'assistant_bubble.dart';
import 'topbar.dart';

/// Shell de navigation unique : bascule sidebar permanente (desktop/tablette
/// large) <-> drawer (mobile étroit) selon la largeur d'écran, avec des
/// éléments filtrés par rôle (§4 README — droits stricts).
///
/// Porte aussi le badge « Chats » du menu (messages directs non lus,
/// `unreadChats` de frontend/components/layout/sidebar.tsx) : le compteur
/// est relu toutes les 30 s par `chatUnreadProvider` et immédiatement à
/// chaque changement de page (`useEffect(..., [pathname])` du web), pour
/// qu'il retombe dès qu'une conversation vient d'être lue.
class NavigationShell extends ConsumerStatefulWidget {
  const NavigationShell({super.key, required this.child, required this.currentPath});

  final Widget child;
  final String currentPath;

  @override
  ConsumerState<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<NavigationShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void didUpdateWidget(covariant NavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath != widget.currentPath) _refreshChatUnread();
  }

  /// Relecture immédiate du compteur de non-lus, hors phase de construction.
  void _refreshChatUnread() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatUnreadProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    // Maintenu vivant par le shell (et pas seulement par le tiroir, qui n'est
    // construit qu'ouvert) : le rafraîchissement périodique tourne dès la
    // connexion, et le bouton du tiroir affiche le compteur tiroir fermé.
    final unreadChats = ref.watch(chatUnreadCountProvider);

    // Menu filtre avec les memes regles que le sidebar web (adminOnly,
    // superAdminOnly, livreurOnly, hidePreparateur, hideLivreur) — voir
    // core/nav_items.dart.
    final items = navItemsFor(user);
    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    if (isWide) {
      return Scaffold(
        appBar: const TopBar(),
        body: Row(
          children: [
            SizedBox(
              width: 240,
              child: _NavList(items: items, currentPath: widget.currentPath, unreadChats: unreadChats, closeOnTap: false),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: Stack(fit: StackFit.expand, children: [widget.child, const AssistantBubble()])),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: TopBar(onMenuTap: () => _scaffoldKey.currentState?.openDrawer(), menuBadgeCount: unreadChats),
      drawer: Drawer(
        child: SafeArea(
          child: _NavList(items: items, currentPath: widget.currentPath, unreadChats: unreadChats, closeOnTap: true),
        ),
      ),
      // Bulle « Assistant » flottante en bas à droite, sur toutes les pages
      // connectées (frontend/app/(app)/layout.tsx monte <AssistantBubble />).
      body: Stack(fit: StackFit.expand, children: [widget.child, const AssistantBubble()]),
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.items, required this.currentPath, required this.unreadChats, required this.closeOnTap});

  final List<NavItem> items;
  final String currentPath;

  /// Messages directs non lus — badge rouge de l'entrée « Chats ».
  final int unreadChats;
  final bool closeOnTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [for (final item in items) _navTile(context, item)],
    );
  }

  Widget _navTile(BuildContext context, NavItem item) {
    final selected = currentPath.startsWith(item.path);
    final showBadge = item.path == '/chats' && unreadChats > 0;
    return ListTile(
      leading: Icon(item.icon),
      title: Text(item.label),
      trailing: showBadge ? _UnreadBadge(count: unreadChats, selected: selected) : null,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      onTap: () {
        if (closeOnTap) Navigator.of(context).pop();
        context.go(item.path);
      },
    );
  }
}

/// Pastille « n messages non lus » (plafonnée à 99+) : rouge sur fond
/// neutre, inversée (fond clair, texte primaire) sur l'entrée active — comme
/// le `bg-red-500 text-white` / `bg-white text-blue-600` du web.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = chatUnreadBadgeLabel(count);
    return Semantics(
      label: '$count message${count > 1 ? 's' : ''} non lu${count > 1 ? 's' : ''}',
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? scheme.primary : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
