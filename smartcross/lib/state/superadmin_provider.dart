import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/superadmin_repository.dart';

final superadminRepositoryProvider = Provider((ref) => SuperadminRepository());

/// État de la page `/superadmin`. Le web n'a qu'un seul `stores` + un
/// `loading` global : `fetchData()` fait `setLoading(true)` AVANT chaque
/// rechargement, y compris après un changement de rôle ou une suppression —
/// l'écran repasse donc en chargement complet à chaque action. [refresh]
/// reproduit ce comportement (`state = AsyncLoading()`), sans mode
/// silencieux : la page n'a aucun rafraîchissement temps réel (pas de
/// WebSocket, contrairement à /alerts ou /pickup).
class SuperadminNotifier extends AsyncNotifier<List<SuperadminStore>> {
  late final _repo = ref.read(superadminRepositoryProvider);

  @override
  Future<List<SuperadminStore>> build() => _repo.list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.list);
  }

  /// Laisse remonter l'erreur : l'appelant affiche le message du serveur
  /// (équivalent de `toast.error(err.message)`), et la liste n'est PAS
  /// rechargée en cas d'échec — comme sur le web, où `fetchData()` n'est
  /// appelé que dans la branche succès.
  Future<void> changeRole(int userId, String role) async {
    await _repo.changeRole(userId, role);
    await refresh();
  }

  /// Idem : l'erreur remonte à la modale, qui l'affiche en ligne et reste
  /// ouverte (aucun toast d'erreur sur cette action côté web).
  Future<void> deleteUser(int userId, String password) async {
    await _repo.deleteUser(userId, password);
    await refresh();
  }
}

final superadminProvider =
    AsyncNotifierProvider<SuperadminNotifier, List<SuperadminStore>>(SuperadminNotifier.new);
