import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/catalog.dart';
import '../../models/json_utils.dart';

/// Catégorie du catalogue avec son drapeau `avec_couleurs` (exposé par
/// `catalog/serializers.py::ProductCategorySerializer`) : « Sans couleurs »
/// pour les catégories sans déclinaison couleur (chargeur, écouteur…) — la
/// référence n'a alors qu'une seule variante « Standard » et le formulaire
/// de création saisit directement une quantité (miroir de
/// `CreateReferenceDialog.avecCouleurs`, products/page.tsx).
///
/// Sous-classe de [ProductCategory] (models/catalog.dart, partagé par
/// d'autres modules) pour rester substituable partout où une catégorie est
/// attendue : `categoriesProvider` continue d'exposer des `ProductCategory`.
class CatalogCategory extends ProductCategory {
  CatalogCategory({
    required super.id,
    required super.nom,
    required super.ordre,
    required this.avecCouleurs,
  });

  final bool avecCouleurs;

  factory CatalogCategory.fromJson(Map<String, dynamic> json) {
    return CatalogCategory(
      id: asInt(json['id']),
      nom: asString(json['nom']),
      ordre: asInt(json['ordre']),
      // Absent = avec couleurs (même défaut que `c.avec_couleurs !== false`
      // côté web).
      avecCouleurs: asBool(json['avec_couleurs'], true),
    );
  }
}

/// Lecture du drapeau `avec_couleurs` sur n'importe quelle catégorie — une
/// catégorie venue d'ailleurs (sans le drapeau) est réputée avec couleurs,
/// comme sur le web.
extension ProductCategoryCouleursX on ProductCategory {
  bool get avecCouleurs {
    final self = this;
    return self is CatalogCategory ? self.avecCouleurs : true;
  }
}

/// Fichier renvoyé par `GET catalog/references/export-excel/` — octets +
/// nom lu dans `Content-Disposition` (repli `catalogue.xlsx`, comme
/// `handleExportExcel` côté web).
class ExcelExportResult {
  ExcelExportResult({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// Résultat de `CatalogRepository.importExcel` — le serveur renvoie le
/// fichier .xlsx lui-même (annoté d'une colonne Statut/Date par ligne), pas
/// du JSON ; le résumé chiffré voyage dans des en-têtes `X-Import-*` (voir
/// catalog/views.py::import_excel).
class ExcelImportResult {
  ExcelImportResult({
    required this.bytes,
    required this.filename,
    required this.batchId,
    required this.createdReferences,
    required this.updatedReferences,
    required this.createdVariants,
    required this.updatedVariants,
    required this.errorsCount,
    required this.skippedCount,
    required this.newReferenceNames,
    required this.updatedReferenceNames,
  });

  final Uint8List bytes;
  final String filename;

  /// Clé d'annulation post-import (`X-Import-Batch-Id`) — peut être nulle si
  /// le serveur ne l'a pas fournie ; l'annulation est alors impossible.
  final String? batchId;
  final int createdReferences;
  final int updatedReferences;
  final int createdVariants;
  final int updatedVariants;
  final int errorsCount;
  final int skippedCount;

  /// Noms « Marque Référence » créés / mis à jour par cet import (bornés à
  /// 50 côté serveur) — servent à la revue post-import.
  final List<String> newReferenceNames;
  final List<String> updatedReferenceNames;
}

/// Message d'erreur utilisateur pour une action du catalogue : le message
/// métier renvoyé par le backend s'il existe (`{"error": ...}`,
/// `{"detail": ...}`, erreurs de validation DRF), le message de
/// connectivité si le serveur est injoignable, sinon [fallback] — même
/// logique que `toast.error(err.message || 'Fallback')` côté web, sans
/// jamais exposer un message technique brut de Dio.
String catalogErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map || ApiClient.isConnectivityError(error)) {
      final message = ApiClient.messageFromError(error);
      if (message.isNotEmpty) return message;
    }
    return fallback;
  }
  return fallback;
}

/// `/api/catalog/` — CRUD catalogue (lecture pour tous, écriture réservée
/// au gérant, §11 README).
class CatalogRepository {
  Dio get _dio => ApiClient.instance.dio;

  static const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static String? _filenameFromDisposition(Headers headers) {
    final disposition = headers.value('content-disposition') ?? '';
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
    return match?.group(1);
  }

  // ---------------------------------------------------------------------------
  // Catégories
  // ---------------------------------------------------------------------------

  /// Les éléments sont des [CatalogCategory] (drapeau `avec_couleurs`).
  Future<List<ProductCategory>> categories() async {
    final response = await _dio.get('catalog/categories/');
    return (response.data as List).map((e) => CatalogCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProductCategory> createCategory(String nom, int ordre, {bool avecCouleurs = true}) async {
    final response = await _dio.post('catalog/categories/', data: {
      'nom': nom,
      'ordre': ordre,
      'avec_couleurs': avecCouleurs,
    });
    return CatalogCategory.fromJson(response.data as Map<String, dynamic>);
  }

  /// PATCH partiel : renommage et/ou bascule « avec couleurs ».
  Future<ProductCategory> updateCategory(int id, {String? nom, bool? avecCouleurs}) async {
    final response = await _dio.patch('catalog/categories/$id/', data: {
      'nom': ?nom,
      'avec_couleurs': ?avecCouleurs,
    });
    return CatalogCategory.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCategory(int id) async {
    await _dio.delete('catalog/categories/$id/');
  }

  // ---------------------------------------------------------------------------
  // Sous-types
  // ---------------------------------------------------------------------------

  Future<List<ProductType>> types({int? categoryId}) async {
    final response = await _dio.get('catalog/types/', queryParameters: {
      'category': ?categoryId,
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

  // ---------------------------------------------------------------------------
  // Marques
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Couleurs
  // ---------------------------------------------------------------------------

  Future<List<ProductColor>> colors() async {
    final response = await _dio.get('catalog/colors/');
    return (response.data as List).map((e) => ProductColor.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProductColor> createColor(String nom) async {
    final response = await _dio.post('catalog/colors/', data: {'nom': nom});
    return ProductColor.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductColor> updateColor(int id, String nom) async {
    final response = await _dio.patch('catalog/colors/$id/', data: {'nom': nom});
    return ProductColor.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteColor(int id) async {
    await _dio.delete('catalog/colors/$id/');
  }

  // ---------------------------------------------------------------------------
  // Références
  // ---------------------------------------------------------------------------

  Future<List<ProductReference>> references({int? typeId, int? brandId, int? categoryId}) async {
    final response = await _dio.get('catalog/references/', queryParameters: {
      'type': ?typeId,
      'brand': ?brandId,
      'category': ?categoryId,
    });
    return (response.data as List).map((e) => ProductReference.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProductReference> reference(int id) async {
    final response = await _dio.get('catalog/references/$id/');
    return ProductReference.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductReference> createReference({
    required int typeId,
    required int brandId,
    required String referenceName,
    double prixAchat = 0,
    required double prixVente,
    bool actif = true,
  }) async {
    final response = await _dio.post('catalog/references/', data: {
      'type': typeId,
      'brand': brandId,
      'reference_name': referenceName,
      'prix_achat': prixAchat,
      'prix_vente': prixVente,
      'actif': actif,
    });
    return ProductReference.fromJson(response.data as Map<String, dynamic>);
  }

  /// Mise à jour d'une référence — tous les champs du formulaire de détail
  /// (type, marque, nom, prix, statut) ; chaque champ omis reste inchangé.
  Future<ProductReference> updateReference(
    int id, {
    int? typeId,
    int? brandId,
    String? referenceName,
    double? prixAchat,
    double? prixVente,
    bool? actif,
  }) async {
    final response = await _dio.patch('catalog/references/$id/', data: {
      'type': ?typeId,
      'brand': ?brandId,
      'reference_name': ?referenceName,
      'prix_achat': ?prixAchat,
      'prix_vente': ?prixVente,
      'actif': ?actif,
    });
    return ProductReference.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteReference(int id) async {
    await _dio.delete('catalog/references/$id/');
  }

  /// Upload de la photo produit (multipart) — appel séparé des autres
  /// champs, exactement comme `patchFormData(/catalog/references/{id}/)`
  /// côté web, pour ne pas mélanger JSON et fichier sur le même appel.
  Future<ProductReference> uploadReferencePhoto(int id, String filePath) async {
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath),
    });
    final response = await _dio.patch('catalog/references/$id/', data: formData);
    return ProductReference.fromJson(response.data as Map<String, dynamic>);
  }

  /// Recherche autocomplete pour le formulaire Nouvelle commande (§6 README).
  Future<List<ReferenceOption>> autocomplete(String query, {int? typeId, int? brandId, int? categoryId}) async {
    final response = await _dio.get('catalog/references/autocomplete/', queryParameters: {
      if (query.isNotEmpty) 'q': query,
      'type': ?typeId,
      'brand': ?brandId,
      'category': ?categoryId,
    });
    return (response.data as List).map((e) => ReferenceOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Modification groupée prix_achat/prix_vente pour TOUTES les références
  /// d'un même sous-type (ex : toutes les "Flip cover", quelle que soit la
  /// marque) — voir catalog/views.py::bulk_update_price. Renvoie le nombre
  /// de références modifiées.
  Future<int> bulkUpdatePrice(int typeId, {double? prixAchat, double? prixVente}) async {
    final response = await _dio.post('catalog/references/bulk-update-price/', data: {
      'type_id': typeId,
      'prix_achat': ?prixAchat,
      'prix_vente': ?prixVente,
    });
    return asInt((response.data as Map<String, dynamic>)['updated']);
  }

  // ---------------------------------------------------------------------------
  // Variantes (couleurs) et stock
  // ---------------------------------------------------------------------------

  Future<List<ProductVariant>> variants({int? referenceId}) async {
    final response = await _dio.get('catalog/variants/', queryParameters: {
      'reference': ?referenceId,
    });
    return (response.data as List).map((e) => ProductVariant.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Le serializer garde `stock_actuel` en lecture seule, mais la vue
  /// (`ProductVariantViewSet.perform_create`) lit ce champ dans la requête
  /// et applique un mouvement d'ENTRÉE tracé « Stock initial à la création
  /// de la couleur » — le stock initial saisi est donc bien pris en compte.
  Future<ProductVariant> createVariant({
    required int productReferenceId,
    required String couleur,
    int seuilAlerte = 1,
    int? stockActuel,
  }) async {
    final response = await _dio.post('catalog/variants/', data: {
      'product_reference': productReferenceId,
      'couleur': couleur,
      'seuil_alerte': seuilAlerte,
      'stock_actuel': ?stockActuel,
    });
    return ProductVariant.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteVariant(int id) async {
    await _dio.delete('catalog/variants/$id/');
  }

  /// Ajustement manuel du stock d'une variante (ENTREE | SORTIE), réservé
  /// au gérant (§7.4) — `POST catalog/variants/{id}/adjust/`.
  Future<ProductVariant> adjustStock({
    required int variantId,
    required String type,
    required int quantite,
    String note = '',
  }) async {
    final response = await _dio.post('catalog/variants/$variantId/adjust/', data: {
      'type': type,
      'quantite': quantite,
      'note': note,
    });
    return ProductVariant.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Import / export Excel
  // ---------------------------------------------------------------------------

  /// Export Excel du catalogue (une ligne par variante couleur), pour
  /// édition hors-ligne puis réimport via [importExcel] — voir
  /// catalog/views.py::export_excel.
  Future<ExcelExportResult> exportExcel() async {
    final response = await _dio.get<List<int>>(
      'catalog/references/export-excel/',
      options: Options(responseType: ResponseType.bytes),
    );
    return ExcelExportResult(
      bytes: Uint8List.fromList(response.data ?? const <int>[]),
      filename: _filenameFromDisposition(response.headers) ?? 'catalogue.xlsx',
    );
  }

  /// Compatibilité avec les anciens appelants : octets seuls.
  Future<Uint8List> exportExcelBytes() async => (await exportExcel()).bytes;

  /// Import Excel (multipart) : crée/actualise Catégorie → Sous-type →
  /// Marque → Référence → Couleur à partir d'un fichier au format
  /// [exportExcel]. Voir catalog/views.py::import_excel — le serveur répond
  /// avec le fichier annoté (pas du JSON), résumé chiffré dans des en-têtes
  /// `X-Import-*`.
  ///
  /// Prend des octets déjà lus (plutôt qu'un chemin de fichier) : sur
  /// Android, `file_picker` peut renvoyer un document choisi via le Storage
  /// Access Framework, dont l'URI `content://` n'a pas de chemin disque
  /// direct — `PlatformFile.readAsBytes()` fonctionne dans tous les cas.
  Future<ExcelImportResult> importExcel(Uint8List bytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(_xlsxMime)),
    });
    final response = await _dio.post<List<int>>(
      'catalog/references/import-excel/',
      data: formData,
      options: Options(
        responseType: ResponseType.bytes,
        // L'import de plusieurs centaines de lignes peut dépasser les 30 s
        // du client par défaut.
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    final headers = response.headers;
    int count(String name) => asInt(headers.value(name));
    List<String> names(String name) {
      final raw = headers.value(name);
      if (raw == null || raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        // En-tête non JSON : même repli que le client web (liste vide).
      }
      return const [];
    }

    final batchId = headers.value('x-import-batch-id');
    return ExcelImportResult(
      bytes: Uint8List.fromList(response.data ?? const <int>[]),
      filename: _filenameFromDisposition(headers) ?? 'catalogue_import.xlsx',
      batchId: (batchId == null || batchId.isEmpty) ? null : batchId,
      createdReferences: count('x-import-created-references'),
      updatedReferences: count('x-import-updated-references'),
      createdVariants: count('x-import-created-variants'),
      updatedVariants: count('x-import-updated-variants'),
      errorsCount: count('x-import-errors-count'),
      skippedCount: count('x-import-skipped-count'),
      newReferenceNames: names('x-import-new-reference-names'),
      updatedReferenceNames: names('x-import-updated-reference-names'),
    );
  }

  /// Annule un import Excel déjà écrit en base (supprime ce qui a été créé,
  /// restaure les valeurs précédentes de ce qui a été mis à jour) — voir
  /// catalog/views.py::ImportBatchViewSet.cancel. Renvoie le statut serveur.
  Future<String> cancelImportBatch(String batchId) async {
    final response = await _dio.post('catalog/import-batches/$batchId/cancel/', data: const <String, dynamic>{});
    final data = response.data;
    return data is Map ? asString(data['status'], 'cancelled') : 'cancelled';
  }
}
