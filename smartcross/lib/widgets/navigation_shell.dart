import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/nav_items.dart';
import '../core/constants.dart';
import '../state/auth_provider.dart';
import 'topbar.dart';

/// Shell de navigation unique : bascule sidebar permanente (desktop/tablette
/// large) <-> drawer (mobile étroit) selon la largeur d'écran, avec des
/// éléments filtrés par rôle (§4 README — droits stricts).
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
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final role = auth.user?.role;
    if (role == null) return const SizedBox.shrink();

    final items = kPrimaryNavItems.where((i) => i.visibleFor(role)).toList();
    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    if (isWide) {
      return Scaffold(
        appBar: const TopBar(),
        body: Row(
          children: [
            SizedBox(width: 240, child: _NavList(items: items, currentPath: widget.currentPath, closeOnTap: false)),
            const VerticalDivider(width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: TopBar(onMenuTap: () => _scaffoldKey.currentState?.openDrawer()),
      drawer: Drawer(
        child: SafeArea(child: _NavList(items: items, currentPath: widget.currentPath, closeOnTap: true)),
      ),
      body: widget.child,
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.items, required this.currentPath, required this.closeOnTap});

  final List<NavItem> items;
  final String currentPath;
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
    return ListTile(
      leading: Icon(item.icon),
      title: Text(item.label),
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
