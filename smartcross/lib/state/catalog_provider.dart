import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/catalog_repository.dart';
import '../models/catalog.dart';

export '../data/repositories/catalog_repository.dart'
    show CatalogCategory, ProductCategoryCouleursX, ExcelExportResult, ExcelImportResult, catalogErrorMessage;

final catalogRepositoryProvider = Provider((ref) => CatalogRepository());

/// Socle commun des 5 listes du catalogue (catégories, sous-types, marques,
/// couleurs, références) : deux rechargements, comme `fetchAll(silent)`
/// côté web (products/page.tsx) —
///
/// * [refresh] — NON silencieux : repasse par l'état de chargement (bouton
///   « Rafraîchir », après création/suppression de référence) ;
/// * [refreshSilencieux] — la liste courante reste affichée pendant l'appel
///   (rafraîchissement temps réel, callbacks `onChanged`/`onCatalogChanged`).
abstract class _CatalogListNotifier<T> extends AsyncNotifier<List<T>> {
  late final CatalogRepository repo = ref.read(catalogRepositoryProvider);

  Future<List<T>> fetch();

  @override
  Future<List<T>> build() => fetch();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(fetch);
  }

  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(fetch);
  }
}

class CategoriesNotifier extends _CatalogListNotifier<ProductCategory> {
  @override
  Future<List<ProductCategory>> fetch() => repo.categories();

  /// [avecCouleurs] : « Sans couleurs » pour les catégories sans
  /// déclinaison couleur (chargeur, écouteur…).
  Future<ProductCategory> create(String nom, int ordre, {bool avecCouleurs = true}) async {
    final created = await repo.createCategory(nom, ordre, avecCouleurs: avecCouleurs);
    await refreshSilencieux();
    return created;
  }

  Future<void> rename(int id, String nom) async {
    await repo.updateCategory(id, nom: nom);
    await refreshSilencieux();
  }

  /// Bascule immédiate du drapeau (badge cliquable « Avec couleurs » /
  /// « Sans couleurs » des Paramètres du catalogue).
  Future<void> setAvecCouleurs(int id, bool avecCouleurs) async {
    await repo.updateCategory(id, avecCouleurs: avecCouleurs);
    await refreshSilencieux();
  }

  Future<void> delete(int id) async {
    await repo.deleteCategory(id);
    await refreshSilencieux();
  }
}

final categoriesProvider = AsyncNotifierProvider<CategoriesNotifier, List<ProductCategory>>(CategoriesNotifier.new);

class TypesNotifier extends _CatalogListNotifier<ProductType> {
  @override
  Future<List<ProductType>> fetch() => repo.types();

  Future<ProductType> create(int categoryId, String nom) async {
    final created = await repo.createType(categoryId, nom);
    await refreshSilencieux();
    return created;
  }

  Future<void> rename(int id, String nom) async {
    await repo.updateType(id, nom);
    await refreshSilencieux();
  }

  Future<void> delete(int id) async {
    await repo.deleteType(id);
    await refreshSilencieux();
  }
}

final typesProvider = AsyncNotifierProvider<TypesNotifier, List<ProductType>>(TypesNotifier.new);

class BrandsNotifier extends _CatalogListNotifier<Brand> {
  @override
  Future<List<Brand>> fetch() => repo.brands();

  Future<Brand> create(String nom) async {
    final created = await repo.createBrand(nom);
    await refreshSilencieux();
    return created;
  }

  Future<void> rename(int id, String nom) async {
    await repo.updateBrand(id, nom);
    await refreshSilencieux();
  }

  Future<void> delete(int id) async {
    await repo.deleteBrand(id);
    await refreshSilencieux();
  }
}

final brandsProvider = AsyncNotifierProvider<BrandsNotifier, List<Brand>>(BrandsNotifier.new);

class ColorsNotifier extends _CatalogListNotifier<ProductColor> {
  @override
  Future<List<ProductColor>> fetch() => repo.colors();

  Future<ProductColor> create(String nom) async {
    final created = await repo.createColor(nom);
    await refreshSilencieux();
    return created;
  }

  Future<void> rename(int id, String nom) async {
    await repo.updateColor(id, nom);
    await refreshSilencieux();
  }

  Future<void> delete(int id) async {
    await repo.deleteColor(id);
    await refreshSilencieux();
  }
}

final colorsProvider = AsyncNotifierProvider<ColorsNotifier, List<ProductColor>>(ColorsNotifier.new);

/// Toutes les références (avec leurs variantes imbriquées) — volume attendu
/// ~360 produits (§8.1 README), chargé en une fois pour le module Catalogue
/// et filtré côté client, comme le tableau de products/page.tsx.
///
/// Chaque mutation est suivie d'un re-fetch complet (pas d'optimistic
/// update), exactement comme le web.
class ReferencesNotifier extends _CatalogListNotifier<ProductReference> {
  @override
  Future<List<ProductReference>> fetch() => repo.references();

  Future<ProductReference> createReference({
    required int typeId,
    required int brandId,
    required String referenceName,
    double prixAchat = 0,
    required double prixVente,
  }) async {
    final created = await repo.createReference(
      typeId: typeId,
      brandId: brandId,
      referenceName: referenceName,
      prixAchat: prixAchat,
      prixVente: prixVente,
    );
    await refreshSilencieux();
    return created;
  }

  Future<void> updateReference(
    int id, {
    int? typeId,
    int? brandId,
    String? referenceName,
    double? prixAchat,
    double? prixVente,
    bool? actif,
  }) async {
    await repo.updateReference(
      id,
      typeId: typeId,
      brandId: brandId,
      referenceName: referenceName,
      prixAchat: prixAchat,
      prixVente: prixVente,
      actif: actif,
    );
    await refreshSilencieux();
  }

  Future<void> deleteReference(int id) async {
    await repo.deleteReference(id);
    await refresh();
  }

  Future<void> uploadPhoto(int id, String filePath) async {
    await repo.uploadReferencePhoto(id, filePath);
    await refreshSilencieux();
  }

  Future<void> createVariant({
    required int productReferenceId,
    required String couleur,
    int seuilAlerte = 1,
    int? stockActuel,
  }) async {
    await repo.createVariant(
      productReferenceId: productReferenceId,
      couleur: couleur,
      seuilAlerte: seuilAlerte,
      stockActuel: stockActuel,
    );
    await refreshSilencieux();
  }

  Future<void> deleteVariant(int id) async {
    await repo.deleteVariant(id);
    await refreshSilencieux();
  }

  /// Ajustement manuel ENTREE/SORTIE d'une variante (§7.4, gérant).
  Future<void> adjustStock({
    required int variantId,
    required String type,
    required int quantite,
    String note = '',
  }) async {
    await repo.adjustStock(variantId: variantId, type: type, quantite: quantite, note: note);
    await refreshSilencieux();
  }

  /// Modification groupée prix_achat/prix_vente pour toutes les références
  /// d'un sous-type — voir CatalogRepository.bulkUpdatePrice. Renvoie le
  /// nombre de références modifiées.
  Future<int> bulkUpdatePrice(int typeId, {double? prixAchat, double? prixVente}) async {
    final updated = await repo.bulkUpdatePrice(typeId, prixAchat: prixAchat, prixVente: prixVente);
    await refreshSilencieux();
    return updated;
  }
}

final referencesProvider = AsyncNotifierProvider<ReferencesNotifier, List<ProductReference>>(ReferencesNotifier.new);

/// Recherche autocomplete pour le formulaire Nouvelle commande (§6 README).
final referenceAutocompleteProvider = FutureProvider.autoDispose.family<List<ReferenceOption>, String>((ref, query) {
  return ref.read(catalogRepositoryProvider).autocomplete(query);
});

/// Actions transverses aux 5 listes — le `fetchAll(silent)` de
/// products/page.tsx et les opérations qui touchent tout le catalogue à la
/// fois (import Excel, annulation d'import).
class CatalogHub {
  CatalogHub(this._ref);

  final Ref _ref;

  CatalogRepository get _repo => _ref.read(catalogRepositoryProvider);

  /// Recharge les 5 listes en parallèle (`Promise.all` côté web).
  Future<void> refreshAll({bool silent = false}) async {
    if (silent) {
      await Future.wait([
        _ref.read(referencesProvider.notifier).refreshSilencieux(),
        _ref.read(categoriesProvider.notifier).refreshSilencieux(),
        _ref.read(typesProvider.notifier).refreshSilencieux(),
        _ref.read(brandsProvider.notifier).refreshSilencieux(),
        _ref.read(colorsProvider.notifier).refreshSilencieux(),
      ]);
      return;
    }
    await Future.wait([
      _ref.read(referencesProvider.notifier).refresh(),
      _ref.read(categoriesProvider.notifier).refresh(),
      _ref.read(typesProvider.notifier).refresh(),
      _ref.read(brandsProvider.notifier).refresh(),
      _ref.read(colorsProvider.notifier).refresh(),
    ]);
  }

  Future<ExcelExportResult> exportExcel() => _repo.exportExcel();

  /// L'import peut créer de nouvelles catégories/sous-types/marques en plus
  /// des références/variantes (voir catalog/views.py::_import_row) : tout
  /// le catalogue est rechargé ensuite, pas seulement les références.
  Future<ExcelImportResult> importExcel(Uint8List bytes, String filename) async {
    final result = await _repo.importExcel(bytes, filename);
    await refreshAll();
    return result;
  }

  /// Défait un import (références créées supprimées, valeurs précédentes
  /// restaurées) puis recharge tout.
  Future<String> cancelImportBatch(String batchId) async {
    final status = await _repo.cancelImportBatch(batchId);
    await refreshAll();
    return status;
  }
}

final catalogHubProvider = Provider<CatalogHub>((ref) => CatalogHub(ref));
