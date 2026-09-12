import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/catalog.dart';
import '../../models/magasin.dart';

/// Module "Magasins" + "Transferts" (§8 Smartreadme.md) — réservé à un admin
/// propriétaire de plusieurs magasins. Sur ce tenant Smartphone.Mg il n'y a
/// qu'un seul magasin, mais l'infrastructure multi-magasin est conservée
/// (côté backend, `TransferProductsView`/`MagasinViewSet`) pour rester
/// compatible avec une société qui en ouvrirait d'autres.
///
/// Portage de `frontend/app/(app)/stores/page.tsx` (`fetchData`,
/// `handleRegisterStore`, `handleUpdateStore`) et de
/// `djangoClient.transfers` (`frontend/lib/django-client.ts`).
class StoresRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// `fetchData()` du web :
  /// 1. `GET /users/magasins/users/` — la liste (une erreur ici remonte) ;
  /// 2. `GET /users/magasins/stats/` — silencieuse en cas d'échec (stats à 0) ;
  /// 3. si [includeProfitOverview] (= `isAdmin` du web) :
  ///    `GET /users/magasins/overview/` (`transfers.getProfitByMagasins()`),
  ///    silencieuse aussi — son `total_profit` prime sur `stats.profit`.
  ///
  /// L'endpoint overview est `[IsAuthenticated, IsAdmin]` : ne pas l'appeler
  /// pour un gérant/employé (403 inutile), exactement comme le web.
  Future<List<Magasin>> list({bool includeProfitOverview = false}) async {
    final usersRes = await _dio.get('users/magasins/users/');
    final magasins = (usersRes.data as List)
        .map((e) => Magasin.fromJson(e as Map<String, dynamic>))
        .toList();

    var statsById = const <int, Map<String, dynamic>>{};
    try {
      final statsRes = await _dio.get('users/magasins/stats/');
      statsById = {
        for (final s in (statsRes.data as List)) asIntKey((s as Map)['magasin_id']): Map<String, dynamic>.from(s),
      };
    } catch (_) {
      // `console.error(statsErr)` : KPI à 0, aucun toast.
    }

    var overviewProfitById = const <int, double?>{};
    if (includeProfitOverview) {
      try {
        final overviewRes = await _dio.get('users/magasins/overview/');
        final data = overviewRes.data;
        final rows = data is Map ? (data['magasins'] as List? ?? const []) : const [];
        overviewProfitById = {
          for (final r in rows) asIntKey((r as Map)['magasin_id']): _asDouble(r['total_profit']),
        };
      } catch (_) {
        // `console.error(profitErr)` : repli sur `stats.profit`, aucun toast.
      }
    }

    return [
      for (final m in magasins)
        m.withStats(
          statsById[m.magasinId],
          overviewProfit: overviewProfitById[m.magasinId],
        ),
    ];
  }

  /// `handleRegisterStore` : `POST /users/register/` d'un compte gérant
  /// (`role=magasin`, `username` = email, `admin_email` = email de l'admin
  /// connecté — sans lui le backend répond « Administrateur introuvable avec
  /// cet email. ») puis `PUT /users/approve/{id}/` si un `id` est renvoyé.
  ///
  /// Le web laisse l'échec de l'approbation couper le flux alors que le
  /// magasin EXISTE déjà (risque signalé par le cahier des charges) : ici
  /// l'erreur d'approbation est renvoyée dans [StoreCreateResult
  /// .approvalError] pour que l'écran annonce la création ET le problème.
  Future<StoreCreateResult> create({
    required String shopName,
    required String managerFullName,
    required String managerEmail,
    required String managerPassword,
    required String adminEmail,
  }) async {
    final response = await _dio.post('users/register/', data: {
      'email': managerEmail,
      'username': managerEmail,
      'password': managerPassword,
      'role': 'magasin',
      'full_name': managerFullName,
      'shop_name': shopName,
      'admin_email': adminEmail,
    });
    final data = response.data;
    final id = data is Map ? data['id'] : null;
    if (id == null) return const StoreCreateResult();
    try {
      await _dio.put('users/approve/$id/');
      return const StoreCreateResult();
    } catch (e) {
      return StoreCreateResult(approvalError: ApiClient.messageFromError(e));
    }
  }

  /// `handleUpdateStore` : `PATCH /users/magasins/{id}/` en multipart
  /// (`patchFormData`) — `shop_name` toujours, `shop_logo` seulement si un
  /// fichier a été choisi (le backend ignore un `shop_logo` de type string).
  Future<void> update(int magasinId, {required String shopName, String? logoPath}) async {
    final formData = FormData.fromMap({
      'shop_name': shopName,
      if (logoPath != null) 'shop_logo': await MultipartFile.fromFile(logoPath),
    });
    await _dio.patch('users/magasins/$magasinId/', data: formData);
  }

  /// Renommage seul (nom sans logo) — conservé pour compatibilité, délègue à
  /// [update].
  Future<void> rename(int magasinId, String shopName) => update(magasinId, shopName: shopName);

  /// `DELETE /users/magasins/{id}/` — le backend (`MagasinViewSet.destroy`)
  /// exige le mot de passe de l'utilisateur courant (« Mot de passe requis
  /// pour confirmer la suppression. » / « Mot de passe incorrect. »).
  Future<void> delete(int magasinId, String password) async {
    await _dio.delete('users/magasins/$magasinId/', data: {'password': password});
  }

  /// Catalogue d'un magasin donné, pour le sélecteur produit du transfert.
  Future<List<ProductReference>> catalogFor(int magasinId) async {
    final response = await _dio.get('catalog/references/', queryParameters: {'magasin_id': magasinId});
    return (response.data as List).map((e) => ProductReference.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Déplace du stock d'un magasin source vers un magasin destination, par
  /// variante (couleur) — le backend recrée la chaîne Catégorie→Type→Marque
  /// dans le magasin destination si besoin (§8 README).
  Future<void> transfer({
    required int sourceMagasinId,
    required int destinationMagasinId,
    required List<TransferItem> items,
  }) async {
    await _dio.post('users/transfer/products/', data: {
      'source_magasin_id': sourceMagasinId,
      'destination_magasin_id': destinationMagasinId,
      'items': [for (final it in items) {'variant_id': it.variantId, 'quantity': it.quantity}],
    });
  }
}

/// Résultat de [StoresRepository.create] : le magasin est créé ; si
/// l'approbation du compte gérant a échoué, [approvalError] porte le message
/// (le compte reste alors « en attente », approuvable depuis Super Admin).
class StoreCreateResult {
  const StoreCreateResult({this.approvalError});
  final String? approvalError;
}

class TransferItem {
  const TransferItem({required this.variantId, required this.quantity, required this.label});
  final int variantId;
  final int quantity;
  final String label;
}

int asIntKey(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? -1;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
