import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/suppliers_repository.dart';
import '../models/supplier.dart';
import 'realtime_provider.dart';

final suppliersRepositoryProvider = Provider((ref) => SuppliersRepository());

/// Liste des approvisionnements — page `/suppliers` du web.
///
/// * [refresh] — NON silencieux (bouton « Rafraîchir ») : repasse par l'état
///   de chargement ;
/// * [refreshSilencieux] — la liste courante reste affichée pendant l'appel.
///
/// Le temps réel (`supplier_order`, `stock_movement`) passe par le `watch`
/// de [realtimeTickProvider] : Riverpod garde la valeur précédente pendant
/// la reconstruction, aucun clignotement.
class SupplierOrdersNotifier extends AsyncNotifier<List<SupplierOrder>> {
  late final _repo = ref.read(suppliersRepositoryProvider);

  @override
  Future<List<SupplierOrder>> build() {
    ref.watch(realtimeTickProvider);
    return _repo.list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.list);
  }

  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(_repo.list);
  }

  /// Remplace un approvisionnement dans la liste après une action (réponse
  /// de l'API), sans rechargement.
  void remplacer(SupplierOrder order) {
    final courant = state.value;
    if (courant == null) return;
    state = AsyncData([for (final o in courant) o.id == order.id ? order : o]);
  }
}

final supplierOrdersProvider = AsyncNotifierProvider<SupplierOrdersNotifier, List<SupplierOrder>>(SupplierOrdersNotifier.new);

/// Détail d'un approvisionnement — rechargé à chaque événement temps réel.
final supplierOrderDetailProvider = FutureProvider.autoDispose.family<SupplierOrder, int>((ref, id) {
  ref.watch(realtimeTickProvider);
  return ref.read(suppliersRepositoryProvider).detail(id);
});

/// Fiches fournisseur (résumé financier inclus).
final suppliersListProvider = FutureProvider.autoDispose<List<Supplier>>((ref) {
  ref.watch(realtimeTickProvider);
  return ref.read(suppliersRepositoryProvider).suppliers();
});

/// Indicateurs de la page.
final supplierKpisProvider = FutureProvider.autoDispose<SupplierKpis>((ref) {
  ref.watch(realtimeTickProvider);
  return ref.read(suppliersRepositoryProvider).kpis();
});
