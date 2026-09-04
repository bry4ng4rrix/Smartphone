import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/server_setup_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/caisse/caisse_screen.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/chats/chat_conversation_screen.dart';
import '../features/chats/chat_list_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/depot/depot_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/orders/order_create_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/orders_list_screen.dart';
import '../features/suppliers/supplier_order_create_screen.dart';
import '../features/suppliers/supplier_order_detail_screen.dart';
import '../features/suppliers/suppliers_screen.dart';
import '../features/stores/stores_screen.dart';
import '../features/tournee/tournee_screen.dart';
import '../features/transfers/transfers_screen.dart';
import '../features/users/users_screen.dart';
import '../widgets/navigation_shell.dart';
import 'constants.dart';
import '../state/auth_provider.dart';

const _publicPrefixes = ['/login', '/server-setup', '/splash'];

String _homeFor(UserRole? role) {
  switch (role) {
    case UserRole.gerant:
      return '/dashboard';
    case UserRole.preparateur:
      return '/depot';
    case UserRole.livreur:
      return '/tournee';
    case UserRole.unknown:
    case null:
      return '/login';
  }
}

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.status != next.status) notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final isPublic = _publicPrefixes.any((p) => loc.startsWith(p));

      switch (auth.status) {
        case AuthStatus.loading:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return isPublic && loc != '/splash' ? null : '/login';
        case AuthStatus.authenticated:
          if (isPublic) return _homeFor(auth.user?.role);
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/server-setup', builder: (context, state) => const ServerSetupScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => NavigationShell(currentPath: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/caisse', builder: (context, state) => const CaisseScreen()),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersListScreen(),
            routes: [
              GoRoute(path: 'new', builder: (context, state) => const OrderCreateScreen()),
              GoRoute(
                path: ':id',
                builder: (context, state) => OrderDetailScreen(orderId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: '/depot', builder: (context, state) => const DepotScreen()),
          GoRoute(path: '/tournee', builder: (context, state) => const TourneeScreen()),
          GoRoute(path: '/catalog', builder: (context, state) => const CatalogScreen()),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) => const SuppliersScreen(),
            routes: [
              GoRoute(path: 'new', builder: (context, state) => const SupplierOrderCreateScreen()),
              GoRoute(
                path: ':id',
                builder: (context, state) => SupplierOrderDetailScreen(orderId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: '/users', builder: (context, state) => const UsersScreen()),
          GoRoute(path: '/stores', builder: (context, state) => const StoresScreen()),
          GoRoute(path: '/transfers', builder: (context, state) => const TransfersScreen()),
          GoRoute(
            path: '/chats',
            builder: (context, state) => const ChatListScreen(),
            routes: [
              GoRoute(path: 'room/:room', builder: (context, state) => const ChatConversationScreen()),
              GoRoute(
                path: 'dm/:id',
                builder: (context, state) => ChatConversationScreen(
                  recipientId: int.parse(state.pathParameters['id']!),
                  title: state.extra as String? ?? 'Discussion',
                ),
              ),
            ],
          ),
          GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ],
      ),
    ],
  );
});
