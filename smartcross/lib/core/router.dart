import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/pending_approval_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/auth/server_setup_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/caisse/caisse_screen.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/chats/chat_conversation_screen.dart';
import '../features/chats/chat_list_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/depot/depot_screen.dart';
import '../features/movements/movements_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/pickup/pickup_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/superadmin/superadmin_screen.dart';
import '../features/orders/order_create_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/orders_list_screen.dart';
import '../features/suppliers/supplier_order_create_screen.dart';
import '../features/suppliers/supplier_order_detail_screen.dart';
import '../features/suppliers/suppliers_screen.dart';
import '../features/stores/stores_screen.dart';
import '../features/tournee/bilan_screen.dart';
import '../features/tournee/tournee_screen.dart';
import '../features/transfers/transfers_screen.dart';
import '../features/users/users_screen.dart';
import '../widgets/navigation_shell.dart';
import '../models/user.dart';
import 'nav_items.dart';
import 'permissions.dart';
import '../state/auth_provider.dart';

const _publicPrefixes = [
  '/login',
  '/server-setup',
  '/splash',
  '/register',
  '/forgot-password',
  '/verify-email',
  '/pending-approval',
  '/auth/pending-approval',
];

/// Ecran d'accueil apres connexion, par role. Un `employer` sans sous-role
/// module Commande n'a ni depot ni tournee : on le pose sur /orders, la
/// page que le web lui sert aussi (branche « par defaut », lecture seule).
String _homeFor(AppUser? user) {
  if (user == null) return '/login';
  if (user.isGerant) return '/dashboard';
  if (user.isPreparateur) return '/depot';
  if (user.isLivreur) return '/tournee';
  return '/orders';
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
          final user = auth.user;
          if (isPublic) return _homeFor(user);
          // Garde de role : le sidebar web se contente de masquer le lien,
          // taper l'URL passe quand meme. Ici on refuse reellement l'acces
          // et on renvoie l'utilisateur sur son accueil (core/nav_items.dart
          // ::canAccessPath applique les memes drapeaux que le menu web).
          if (user != null && !canAccessPath(user, loc)) return _homeFor(user);
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/server-setup', builder: (context, state) => const ServerSetupScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/verify-email', builder: (context, state) => const VerifyEmailScreen()),
      // Le web a deux pages distinctes (/pending-approval et
      // /auth/pending-approval) au contenu quasi identique : elles sont
      // fusionnees ici en un seul ecran, joignable par les deux chemins.
      GoRoute(path: '/pending-approval', builder: (context, state) => const PendingApprovalScreen()),
      GoRoute(path: '/auth/pending-approval', builder: (context, state) => const PendingApprovalScreen()),
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
          GoRoute(path: '/bilan', builder: (context, state) => const BilanScreen()),
          GoRoute(path: '/catalog', builder: (context, state) => const CatalogScreen()),
          GoRoute(path: '/movements', builder: (context, state) => const MovementsScreen()),
          GoRoute(path: '/alerts', builder: (context, state) => const AlertsScreen()),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/pickup', builder: (context, state) => const PickupScreen()),
          GoRoute(path: '/scanner', builder: (context, state) => const ScannerScreen()),
          GoRoute(path: '/superadmin', builder: (context, state) => const SuperadminScreen()),
          GoRoute(path: '/reset-password', builder: (context, state) => const ResetPasswordScreen()),
          // Le module Ventes/Ticket a ete retire : le seul flux de vente
          // est la Commande a 6 statuts. Meme redirection heritee que
          // frontend/app/(app)/sales/page.tsx, pour que les anciens liens
          // et raccourcis continuent de fonctionner.
          GoRoute(path: '/sales', redirect: (context, state) => '/orders'),
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
