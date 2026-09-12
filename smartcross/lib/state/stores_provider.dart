import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/permissions.dart';
import '../data/repositories/stores_repository.dart';
import '../models/magasin.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

final storesRepositoryProvider = Provider((ref) => StoresRepository());

/// Liste des magasins de la société (page `/stores` du web, réutilisée par
/// Caisse, Transferts et Commandes fournisseur pour le sélecteur de
/// magasin).
///
/// Deux modes de rechargement, comme `fetchData(silent)` du web :
/// * [refresh] — NON silencieux (chargement initial, « Actualiser », après
///   création / modification / transfert) : l'état passe par `AsyncLoading`
///   et les écrans affichent leur skeleton ;
/// * [refreshSilencieux] — silencieux : `useRealtimeRefresh(['product_variant',
///   'order'])` (WebSocket, debounce 400 ms) et tirer-pour-rafraîchir ; les
///   données se remplacent en place, sans indicateur ni toast.
class StoresNotifier extends AsyncNotifier<List<Magasin>> {
  late final _repo = ref.read(storesRepositoryProvider);
  Timer? _realtimeDebounce;

  /// `isAdmin` du web : seul l'admin appelle `magasins/overview/` (profit).
  bool get _isAdmin => ref.read(authProvider).user?.isAdmin ?? false;

  @override
  Future<List<Magasin>> build() {
    ref.onDispose(() => _realtimeDebounce?.cancel());
    // Rafraîchissement temps réel SILENCIEUX (le `watch` du tick rejouerait
    // `build()` en passant par `AsyncLoading`, donc par le skeleton).
    ref.listen(realtimeTickProvider, (previous, next) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 400), refreshSilencieux);
    });
    return _repo.list(includeProfitOverview: _isAdmin);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() => _repo.list(includeProfitOverview: _isAdmin));
    if (ref.mounted) state = next;
  }

  /// `fetchData(true)` : silencieux — en cas d'échec le web se contente d'un
  /// `console.error`, la liste précédente reste en place. Aucun état d'erreur
  /// n'est donc émis tant qu'une valeur existe ; l'erreur éventuelle est
  /// renvoyée pour que l'appelant (tirer-pour-rafraîchir) puisse la
  /// signaler s'il le souhaite.
  Future<Object?> refreshSilencieux() async {
    final next = await AsyncValue.guard(() => _repo.list(includeProfitOverview: _isAdmin));
    if (!ref.mounted) return null;
    if (next.hasError && state.hasValue) return next.error;
    state = next;
    return next.error;
  }

  /// `handleRegisterStore` : création du magasin + compte gérant, puis
  /// `fetchData()` non silencieux. Le résultat signale un éventuel échec de
  /// l'approbation du gérant (le magasin, lui, existe).
  Future<StoreCreateResult> create({
    required String shopName,
    required String managerFullName,
    required String managerEmail,
    required String managerPassword,
  }) async {
    final adminEmail = ref.read(authProvider).user?.email ?? '';
    final result = await _repo.create(
      shopName: shopName,
      managerFullName: managerFullName,
      managerEmail: managerEmail,
      managerPassword: managerPassword,
      adminEmail: adminEmail,
    );
    await refresh();
    return result;
  }

  /// `handleUpdateStore` : nom + logo facultatif, puis `fetchData()` non
  /// silencieux.
  Future<void> updateStore(int magasinId, {required String shopName, String? logoPath}) async {
    await _repo.update(magasinId, shopName: shopName, logoPath: logoPath);
    await refresh();
  }

  Future<void> rename(int magasinId, String shopName) => updateStore(magasinId, shopName: shopName);

  Future<void> delete(int magasinId, String password) async {
    await _repo.delete(magasinId, password);
    await refresh();
  }
}

final storesProvider = AsyncNotifierProvider<StoresNotifier, List<Magasin>>(StoresNotifier.new);
