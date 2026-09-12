import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/catalog.dart';
import '../../models/supplier.dart';

/// `/api/suppliers/` — commandes fournisseur, coût de revient réel
/// (§7.6 README, réservé au gérant : `SupplierOrderViewSet.permission_classes
/// = [IsGerant]`). Miroir de `djangoClient.suppliers` (frontend/lib/
/// django-client.ts) + les trois appels catalogue du formulaire de création
/// (marques, catégories, références filtrées).
class SuppliersRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// `GET suppliers/orders/?magasin_id=` — toutes les commandes des magasins
  /// accessibles (ordre serveur : la plus récente en premier).
  Future<List<SupplierOrder>> list({int? magasinId}) async {
    final response = await _dio.get('suppliers/orders/', queryParameters: {
      'magasin_id': ?magasinId,
    });
    return (response.data as List).map((e) => SupplierOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SupplierOrder> detail(int id) async {
    final response = await _dio.get('suppliers/orders/$id/');
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  /// `POST suppliers/orders/` — crée la commande + ses lignes puis recalcule
  /// les coûts côté serveur. [magasinId] n'est requis que pour un admin qui
  /// possède PLUSIEURS magasins (`resolve_magasin_for_request` : sans lui le
  /// serveur répond 400 « magasin_id: Ce champ est requis (plusieurs
  /// magasins accessibles). »).
  Future<SupplierOrder> create({
    String description = '',
    required double prixFournisseur,
    required double fretImport,
    required double douane,
    required List<SupplierOrderLineDraft> lines,
    int? magasinId,
  }) async {
    final response = await _dio.post('suppliers/orders/', data: {
      'description': description,
      'prix_fournisseur': prixFournisseur,
      'fret_import': fretImport,
      'douane': douane,
      'lines': lines.map((e) => e.toJson()).toList(),
      'magasin_id': ?magasinId,
    });
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  /// Réception -> entrée stock automatique par ligne (§7.6 README),
  /// mouvements d'origine FOURNISSEUR, statut RECU, notification
  /// `supplier_order`. Irréversible : une seconde réception répond 400
  /// « Cette commande fournisseur a déjà été reçue. ».
  Future<SupplierOrder> receive(int id) async {
    final response = await _dio.post('suppliers/orders/$id/receive/');
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Catalogue du formulaire « Ajouter une ligne » (CreateSupplierOrderDialog)
  // ---------------------------------------------------------------------------

  /// `GET catalog/brands/?magasin_id=` — Select « Marque ». Le filtre magasin
  /// (absent du web) évite à un admin multi-magasins de choisir une marque
  /// d'un autre magasin que celui de la commande.
  Future<List<Brand>> brands({int? magasinId}) async {
    final response = await _dio.get('catalog/brands/', queryParameters: {'magasin_id': ?magasinId});
    return (response.data as List).map((e) => Brand.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET catalog/categories/?magasin_id=` — Select « Catégorie ».
  Future<List<ProductCategory>> categories({int? magasinId}) async {
    final response = await _dio.get('catalog/categories/', queryParameters: {'magasin_id': ?magasinId});
    return (response.data as List).map((e) => ProductCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET catalog/references/?brand=&category=&magasin_id=` — alimente la
  /// liste plate des variantes (Select « Couleur »), rechargée à chaque
  /// changement de marque/catégorie comme le `useEffect` du web.
  Future<List<ProductReference>> references({int? brandId, int? categoryId, int? magasinId}) async {
    final response = await _dio.get('catalog/references/', queryParameters: {
      'brand': ?brandId,
      'category': ?categoryId,
      'magasin_id': ?magasinId,
    });
    return (response.data as List).map((e) => ProductReference.fromJson(e as Map<String, dynamic>)).toList();
  }
}
