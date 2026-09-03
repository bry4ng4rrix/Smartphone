import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/catalog.dart';

/// `/api/catalog/` — CRUD catalogue (lecture pour tous, écriture réservée
/// au gérant, §11 README).
class CatalogRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<ProductCategory>> categories() async {
    final response = await _dio.get('catalog/categories/');
    return (response.data as List).map((e) => ProductCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProductCategory> createCategory(String nom, int ordre) async {
    final response = await _dio.post('catalog/categories/', data: {'nom': nom, 'ordre': ordre});
    return ProductCategory.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductCategory> updateCategory(int id, String nom) async {
    final response = await _dio.patch('catalog/categories/$id/', data: {'nom': nom});
    return ProductCategory.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCategory(int id) async {
    await _dio.delete('catalog/categories/$id/');
  }

  Future<List<ProductType>> types({int? categoryId}) async {
    final response = await _dio.get('catalog/types/', queryParameters: {
      if (categoryId != null) 'category': categoryId,
    });
    return (response.data as List).map((e) => ProductType.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProductType> createType(int categoryId, String nom) async {
    final response = await _dio.post('catalog/types/', data: {'category': categoryId, 'nom': nom});
    return ProductType.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductType> updateType(int id, String nom) async {
    final response = await _dio.patch('catalog/types/$id/', data: {'nom': nom});
    return ProductType.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteType(int id) async {
    await _dio.delete('catalog/types/$id/');
  }

  Future<List<Brand>> brands() async {
    final response = await _dio.get('catalog/brands/');
    return (response.data as List).map((e) => Brand.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Brand> createBrand(String nom) async {
    final response = await _dio.post('catalog/brands/', data: {'nom': nom});
    return Brand.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Brand> updateBrand(int id, String nom) async {
    final response = await _dio.patch('catalog/brands/$id/', data: {'nom': nom});
    return Brand.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteBrand(int id) async {
    await _dio.delete('catalog/brands/$id/');
  }

  Future<List<ProductReference>> references({int? typeId, int? brandId, int? categoryId}) async {
    final response = await _dio.get('catalog/references/', queryParameters: {
      if (typeId != null) 'type': typeId,
      if (brandId != null) 'brand': brandId,
      if (categoryId != null) 'category': categoryId,
    });
    return (response.data as List).map((e) => ProductReference.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProductReference> createReference({
    required int typeId,
    required int brandId,
    required String referenceName,
    required double prixVente,
  }) async {
    final response = await _dio.post('catalog/references/', data: {
      'type': typeId,
      'brand': brandId,
      'reference_name': referenceName,
      'prix_vente': prixVente,
      'actif': true,
    });
    return ProductReference.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductReference> updateReference(int id, {String? referenceName, double? prixVente, bool? actif}) async {
    final response = await _dio.patch('catalog/references/$id/', data: {
      if (referenceName != null) 'reference_name': referenceName,
      if (prixVente != null) 'prix_vente': prixVente,
      if (actif != null) 'actif': actif,
    });
    return ProductReference.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteReference(int id) async {
    await _dio.delete('catalog/references/$id/');
  }

  /// Recherche autocomplete pour le formulaire Nouvelle commande (§6 README).
  Future<List<ReferenceOption>> autocomplete(String query, {int? typeId, int? brandId, int? categoryId}) async {
    final response = await _dio.get('catalog/references/autocomplete/', queryParameters: {
      if (query.isNotEmpty) 'q': query,
      if (typeId != null) 'type': typeId,
      if (brandId != null) 'brand': brandId,
      if (categoryId != null) 'category': categoryId,
    });
    return (response.data as List).map((e) => ReferenceOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ProductVariant>> variants({int? referenceId}) async {
    final response = await _dio.get('catalog/variants/', queryParameters: {
      if (referenceId != null) 'reference': referenceId,
    });
    return (response.data as List).map((e) => ProductVariant.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProductVariant> createVariant({required int productReferenceId, required String couleur, int seuilAlerte = 0}) async {
    final response = await _dio.post('catalog/variants/', data: {
      'product_reference': productReferenceId,
      'couleur': couleur,
      'seuil_alerte': seuilAlerte,
    });
    return ProductVariant.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteVariant(int id) async {
    await _dio.delete('catalog/variants/$id/');
  }
}
