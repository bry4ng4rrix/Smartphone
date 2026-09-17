import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/catalog.dart';
import '../../models/supplier.dart';

/// `/api/suppliers/` — approvisionnements (1 produit, N paiements, Frais +
/// Douane, coût par pièce), fiches fournisseur, historique des envois.
/// Réservé au gérant. Miroir de `djangoClient.suppliers` (frontend/lib/
/// django-client.ts).
class SuppliersRepository {
  Dio get _dio => ApiClient.instance.dio;

  // ---------------------------------------------------------------------------
  // Approvisionnements
  // ---------------------------------------------------------------------------

  Future<List<SupplierOrder>> list({int? magasinId, int? supplierId, String? statut, String? search}) async {
    final response = await _dio.get('suppliers/orders/', queryParameters: {
      'magasin_id': ?magasinId,
      'supplier': ?supplierId,
      if (statut != null && statut.isNotEmpty) 'statut': statut,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    });
    return (response.data as List).map((e) => SupplierOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SupplierOrder> detail(int id) async {
    final response = await _dio.get('suppliers/orders/$id/');
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SupplierKpis> kpis() async {
    final response = await _dio.get('suppliers/orders/kpis/');
    return SupplierKpis.fromJson(response.data as Map<String, dynamic>);
  }

  /// UN produit, UNE quantité (§ 3).
  Future<SupplierOrder> create({
    int? supplierId,
    required int productVariantId,
    required int quantite,
    String devise = 'USD',
    double montantPrevu = 0,
    String description = '',
    String? date,
    String statut = 'BROUILLON',
    int? magasinId,
  }) async {
    final response = await _dio.post('suppliers/orders/', data: {
      'supplier': supplierId,
      'product_variant': productVariantId,
      'quantite': quantite,
      'devise': devise,
      'montant_prevu': montantPrevu,
      'description': description,
      'date': ?date,
      'statut': statut,
      'magasin_id': ?magasinId,
    });
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SupplierOrder> update(int id, Map<String, dynamic> data) async {
    final response = await _dio.patch('suppliers/orders/$id/', data: data);
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('suppliers/orders/$id/');

  Future<SupplierOrder> _post(int id, String action, [Map<String, dynamic>? data]) async {
    final response = await _dio.post('suppliers/orders/$id/$action/', data: data ?? const {});
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SupplierOrder> commander(int id) => _post(id, 'commander');
  Future<SupplierOrder> preparer(int id) => _post(id, 'preparer');
  Future<SupplierOrder> expedier(int id, Map<String, dynamic> transport) => _post(id, 'expedier', transport);
  Future<SupplierOrder> transit(int id, [Map<String, dynamic>? transport]) => _post(id, 'transit', transport);
  Future<SupplierOrder> arriver(int id, {String? dateArrivee, double? fraisDouaneMga}) =>
      _post(id, 'arriver', {'date_arrivee': ?dateArrivee, 'frais_douane_mga': ?fraisDouaneMga});

  /// UN seul montant Frais + Douane (MGA) ; [enCaisse] enregistre la sortie.
  Future<SupplierOrder> fraisDouane(int id, {required double montant, bool enCaisse = false}) =>
      _post(id, 'frais-douane', {'frais_douane_mga': montant, 'en_caisse': enCaisse});

  /// Fige le coût et réceptionne dans le stock.
  Future<SupplierOrder> finaliser(int id, {bool mettreAJourPrixAchat = true, int? quantiteRecue}) =>
      _post(id, 'finaliser', {'mettre_a_jour_prix_achat': mettreAJourPrixAchat, 'quantite_recue': ?quantiteRecue});

  // ---------------------------------------------------------------------------
  // Paiements (taux du jour figé)
  // ---------------------------------------------------------------------------

  Future<SupplierOrder> addPayment(
    int id, {
    required double montant,
    required String devise,
    double? tauxChange,
    String? date,
    String typePaiement = 'ACOMPTE',
    String methode = 'VIREMENT',
    String reference = '',
    String commentaire = '',
    bool enCaisse = false,
  }) =>
      _post(id, 'payments', {
        'montant': montant,
        'devise': devise,
        'taux_change': devise == 'MGA' ? 1 : tauxChange,
        'date': ?date,
        'type_paiement': typePaiement,
        'methode': methode,
        'reference': reference,
        'commentaire': commentaire,
        'en_caisse': enCaisse,
      });

  Future<SupplierOrder> deletePayment(int id, int paymentId) async {
    final response = await _dio.delete('suppliers/orders/$id/payments/$paymentId/');
    return SupplierOrder.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Fiches fournisseur
  // ---------------------------------------------------------------------------

  Future<List<Supplier>> suppliers({String? search, bool actif = false}) async {
    final response = await _dio.get('suppliers/suppliers/', queryParameters: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (actif) 'actif': '1',
    });
    return (response.data as List).map((e) => Supplier.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Supplier> supplierCreate(Map<String, dynamic> data) async {
    final response = await _dio.post('suppliers/suppliers/', data: data);
    return Supplier.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Supplier> supplierUpdate(int id, Map<String, dynamic> data) async {
    final response = await _dio.patch('suppliers/suppliers/$id/', data: data);
    return Supplier.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> supplierDelete(int id) => _dio.delete('suppliers/suppliers/$id/');

  // ---------------------------------------------------------------------------
  // Catalogue du formulaire (recherche de LA référence du produit)
  // ---------------------------------------------------------------------------

  /// `GET catalog/references/autocomplete/?q=` — référence + couleurs
  /// (variant_id) pour choisir le produit de l'approvisionnement.
  Future<List<ReferenceOption>> autocomplete(String query, {int? magasinId}) async {
    final response = await _dio.get('catalog/references/autocomplete/', queryParameters: {
      'q': query,
      'magasin_id': ?magasinId,
    });
    return (response.data as List).map((e) => ReferenceOption.fromJson(e as Map<String, dynamic>)).toList();
  }
}
