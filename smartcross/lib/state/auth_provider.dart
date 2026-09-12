import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/secure_storage.dart';
import '../data/repositories/auth_repository.dart';
import '../models/user.dart';
import 'caisse_provider.dart';
import 'campaigns_provider.dart';
import 'catalog_provider.dart';
import 'expenses_provider.dart';
import 'notifications_provider.dart';
import 'orders_provider.dart';
import 'stock_provider.dart';
import 'reports_provider.dart';
import 'stores_provider.dart';
import 'suppliers_provider.dart';
import 'users_provider.dart';

/// Tous les providers de données métier (hors auth) — invalidés à chaque
/// connexion/déconnexion pour qu'un changement de compte sur le même
/// appareil (rôle différent, ou simplement un autre utilisateur) reparte
/// d'un état propre plutôt que de garder en cache les données du compte
/// précédent (ex : un livreur qui se connecte après un gérant ne verrait
/// sinon que le cache — vide ou obsolète — laissé par la session gérant).
void _invalidateDataProviders(Ref ref) {
  ref.invalidate(ordersProvider);
  ref.invalidate(orderDetailProvider);
  ref.invalidate(categoriesProvider);
  ref.invalidate(typesProvider);
  ref.invalidate(brandsProvider);
  ref.invalidate(colorsProvider);
  ref.invalidate(referencesProvider);
  ref.invalidate(productNotesProvider);
  ref.invalidate(referenceAutocompleteProvider);
  ref.invalidate(rupturesProvider);
  ref.invalidate(movementsProvider);
  ref.invalidate(supplierOrdersProvider);
  ref.invalidate(supplierOrderDetailProvider);
  ref.invalidate(notificationsProvider);
  ref.invalidate(currentCaisseProvider);
  ref.invalidate(caisseHistoryProvider);
  ref.invalidate(accountsProvider);
  ref.invalidate(pendingUsersProvider);
  ref.invalidate(storesProvider);
  ref.invalidate(reportsProvider);
  ref.invalidate(campaignsProvider);
  // Dépenses des livreurs (types et déclarations) et zones de livraison :
  // rattachées à la société, jamais autoDispose — sans ceci un autre compte
  // sur le même appareil verrait le cache du précédent.
  ref.invalidate(expenseTypesProvider);
  ref.invalidate(expensesProvider);
  ref.invalidate(deliveryZonesProvider);
  ref.invalidate(preparateurFilterListProvider);
}

enum AuthStatus { loading, unauthenticated, authenticated }

class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final AppUser? user;

  AuthState copyWith({AuthStatus? status, AppUser? user}) {
    return AuthState(status: status ?? this.status, user: user ?? this.user);
  }
}

final authRepositoryProvider = Provider((ref) => AuthRepository());

class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _repo = ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    ref.listen(authEventProvider, (previous, next) {
      final event = next.value;
      if (event == null) return;
      state = const AuthState(status: AuthStatus.unauthenticated);
    });
    Future.microtask(_bootstrap);
    return const AuthState(status: AuthStatus.loading);
  }

  Future<void> _bootstrap() async {
    await ApiClient.instance.ensureInitialized();
    final access = await TokenStorage.instance.accessToken;
    if (access == null || access.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repo.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    await _repo.login(email, password);
    final user = await _repo.me();
    _invalidateDataProviders(ref);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> logout() async {
    await _repo.logout();
    _invalidateDataProviders(ref);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> refreshUser() async {
    try {
      final user = await _repo.me();
      state = state.copyWith(user: user, status: AuthStatus.authenticated);
    } catch (_) {
      // ignore, garde l'utilisateur courant en cache
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Pont entre les événements globaux émis par [ApiClient] (401 non
/// rafraîchissable) et Riverpod.
final authEventProvider = StreamProvider<AuthEvent?>((ref) => AuthEvents.instance.stream);
