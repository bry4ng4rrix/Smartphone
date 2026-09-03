import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/secure_storage.dart';
import '../data/repositories/auth_repository.dart';
import '../models/user.dart';

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
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> logout() async {
    await _repo.logout();
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
