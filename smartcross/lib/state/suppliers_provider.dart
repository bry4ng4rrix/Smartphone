import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/suppliers_repository.dart';
import '../models/catalog.dart';
import '../models/supplier.dart';
import 'realtime_provider.dart';

final suppliersRepositoryProvider = Provider((ref) => SuppliersRepository());

/// Liste des commandes fournisseur — page `/suppliers` du web.
///
/// Deux rechargements, comme `fetchOrders(silent)` côté web :
///
/// * [refresh] — NON silencieux (bouton « Rafraîchir », après réception) :
///   repasse par l'état de chargement ;
/// * [refreshSilencieux] — la liste courante reste affichée pendant l'appel
///   (tirer-pour-rafraîchir).
///
/// Le rafraîchissement temps réel (`useRealtimeRefresh(['supplier_order'])`,
/// refetch silencieux) est assuré par le `watch` de [realtimeTickProvider] :
/// Riverpod 3 conserve la valeur précédente pendant la reconstruction, donc
/// aucun clignotement. Les écrans distinguent eux-mêmes le rechargement non
/// silencieux (indicateur) du silencieux, `hasValue` restant vrai dans les
/// deux cas.
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

  /// `djangoClient.suppliers.create(...)` puis `fetchOrders()` (non
  /// silencieux) — l'appelant navigue vers la liste, qui se recharge.
  Future<SupplierOrder> create({
    String description = '',
    required double prixFournisseur,
    required double fretImport,
    required double douane,
    required List<SupplierOrderLineDraft> lines,
    int? magasinId,
  }) async {
    final order = await _repo.create(
      description: description,
      prixFournisseur: prixFournisseur,
      fretImport: fretImport,
      douane: douane,
      lines: lines,
      magasinId: magasinId,
    );
    await refresh();
    return order;
  }

  /// `receive(order)` du web : POST receive puis `fetchOrders()` NON
  /// silencieux.
  Future<SupplierOrder> receive(int id) async {
    final order = await _repo.receive(id);
    await refresh();
    return order;
  }
}

final supplierOrdersProvider = AsyncNotifierProvider<SupplierOrdersNotifier, List<SupplierOrder>>(SupplierOrdersNotifier.new);

/// Détail d'une commande — rechargé à chaque événement temps réel (le
/// dialog web affiche un instantané non rafraîchi ; ici la fiche suit les
/// mises à jour).
final supplierOrderDetailProvider = FutureProvider.autoDispose.family<SupplierOrder, int>((ref, id) {
  ref.watch(realtimeTickProvider);
  return ref.read(suppliersRepositoryProvider).detail(id);
});

// -----------------------------------------------------------------------------
// Formulaire « Nouvelle commande fournisseur »
// -----------------------------------------------------------------------------

/// Marques du Select « Marque » (`GET /catalog/brands/`), par magasin cible
/// (`null` = magasin unique de l'utilisateur, comme le web).
final supplierFormBrandsProvider = FutureProvider.autoDispose.family<List<Brand>, int?>((ref, magasinId) {
  return ref.read(suppliersRepositoryProvider).brands(magasinId: magasinId);
});

/// Catégories du Select « Catégorie » (`GET /catalog/categories/`).
final supplierFormCategoriesProvider = FutureProvider.autoDispose.family<List<ProductCategory>, int?>((ref, magasinId) {
  return ref.read(suppliersRepositoryProvider).categories(magasinId: magasinId);
});

/// Filtres du chargement des références du formulaire — `useEffect(...,
/// [open, filterBrandId, filterCategoryId])` du web, plus le magasin cible.
typedef SupplierReferencesFilter = ({int? brandId, int? categoryId, int? magasinId});

/// Références (avec variantes imbriquées) alimentant la liste plate des
/// couleurs du formulaire — rechargées à chaque changement de filtre.
final supplierFormReferencesProvider =
    FutureProvider.autoDispose.family<List<ProductReference>, SupplierReferencesFilter>((ref, filter) {
  return ref.read(suppliersRepositoryProvider).references(
        brandId: filter.brandId,
        categoryId: filter.categoryId,
        magasinId: filter.magasinId,
      );
});
