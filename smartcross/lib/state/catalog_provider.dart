import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/catalog_repository.dart';
import '../models/catalog.dart';

final catalogRepositoryProvider = Provider((ref) => CatalogRepository());

class CategoriesNotifier extends AsyncNotifier<List<ProductCategory>> {
  late final _repo = ref.read(catalogRepositoryProvider);

  @override
  Future<List<ProductCategory>> build() => _repo.categories();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.categories());
  }

  Future<void> create(String nom, int ordre) async {
    await _repo.createCategory(nom, ordre);
    await refresh();
  }

  Future<void> rename(int id, String nom) async {
    await _repo.updateCategory(id, nom);
    await refresh();
  }

  Future<void> delete(int id) async {
    await _repo.deleteCategory(id);
    await refresh();
  }
}

final categoriesProvider = AsyncNotifierProvider<CategoriesNotifier, List<ProductCategory>>(CategoriesNotifier.new);

class TypesNotifier extends AsyncNotifier<List<ProductType>> {
  late final _repo = ref.read(catalogRepositoryProvider);

  @override
  Future<List<ProductType>> build() => _repo.types();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.types());
  }

  Future<void> create(int categoryId, String nom) async {
    await _repo.createType(categoryId, nom);
    await refresh();
  }

  Future<void> rename(int id, String nom) async {
    await _repo.updateType(id, nom);
    await refresh();
  }

  Future<void> delete(int id) async {
    await _repo.deleteType(id);
    await refresh();
  }
}

final typesProvider = AsyncNotifierProvider<TypesNotifier, List<ProductType>>(TypesNotifier.new);

class BrandsNotifier extends AsyncNotifier<List<Brand>> {
  late final _repo = ref.read(catalogRepositoryProvider);

  @override
  Future<List<Brand>> build() => _repo.brands();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.brands());
  }

  Future<void> create(String nom) async {
    await _repo.createBrand(nom);
    await refresh();
  }

  Future<void> rename(int id, String nom) async {
    await _repo.updateBrand(id, nom);
    await refresh();
  }

  Future<void> delete(int id) async {
    await _repo.deleteBrand(id);
    await refresh();
  }
}

final brandsProvider = AsyncNotifierProvider<BrandsNotifier, List<Brand>>(BrandsNotifier.new);

/// Toutes les références (avec leurs variantes imbriquées) — volume attendu
/// ~360 produits (§8.1 README), chargé en une fois pour le module Catalogue
/// du gérant et filtré côté client.
class ReferencesNotifier extends AsyncNotifier<List<ProductReference>> {
  late final _repo = ref.read(catalogRepositoryProvider);

  @override
  Future<List<ProductReference>> build() => _repo.references();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.references());
  }

  Future<void> createReference({
    required int typeId,
    required int brandId,
    required String referenceName,
    required double prixVente,
  }) async {
    await _repo.createReference(typeId: typeId, brandId: brandId, referenceName: referenceName, prixVente: prixVente);
    await refresh();
  }

  Future<void> updateReference(int id, {String? referenceName, double? prixVente, bool? actif}) async {
    await _repo.updateReference(id, referenceName: referenceName, prixVente: prixVente, actif: actif);
    await refresh();
  }

  Future<void> deleteReference(int id) async {
    await _repo.deleteReference(id);
    await refresh();
  }

  Future<void> createVariant({required int productReferenceId, required String couleur, int seuilAlerte = 0}) async {
    await _repo.createVariant(productReferenceId: productReferenceId, couleur: couleur, seuilAlerte: seuilAlerte);
    await refresh();
  }

  Future<void> deleteVariant(int id) async {
    await _repo.deleteVariant(id);
    await refresh();
  }
}

final referencesProvider = AsyncNotifierProvider<ReferencesNotifier, List<ProductReference>>(ReferencesNotifier.new);

/// Recherche autocomplete pour le formulaire Nouvelle commande (§6 README).
final referenceAutocompleteProvider = FutureProvider.autoDispose.family<List<ReferenceOption>, String>((ref, query) {
  return ref.read(catalogRepositoryProvider).autocomplete(query);
});
