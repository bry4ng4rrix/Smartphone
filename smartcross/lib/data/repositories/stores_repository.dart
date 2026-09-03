import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/catalog.dart';
import '../../models/magasin.dart';

/// Module "Magasins" + "Transferts" (§8 Smartreadme.md) — réservé à un admin
/// propriétaire de plusieurs magasins. Sur ce tenant Smartphone.Mg il n'y a
/// qu'un seul magasin, mais l'infrastructure multi-magasin est conservée
/// (côté backend, `TransferProductsView`/`MagasinViewSet`) pour rester
/// compatible avec une société qui en ouvrirait d'autres.
class StoresRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<Magasin>> list() async {
    final usersRes = await _dio.get('users/magasins/users/');
    final magasins = (usersRes.data as List)
        .map((e) => Magasin.fromJson(e as Map<String, dynamic>))
        .toList();

    try {
      final statsRes = await _dio.get('users/magasins/stats/');
      final statsById = <int, Map<String, dynamic>>{
        for (final s in (statsRes.data as List)) asIntKey(s['magasin_id']): s as Map<String, dynamic>,
      };
      return [
        for (final m in magasins)
          if (statsById.containsKey(m.magasinId)) m.withStats(statsById[m.magasinId]!) else m,
      ];
    } catch (_) {
      return magasins;
    }
  }

  /// Crée un nouveau magasin : un compte gérant (`role=magasin`) est
  /// enregistré puis auto-approuvé (même flux que le web, §8 README).
  Future<void> create({
    required String shopName,
    required String managerFullName,
    required String managerEmail,
    required String managerPassword,
  }) async {
    final response = await _dio.post('users/register/', data: {
      'full_name': managerFullName,
      'email': managerEmail,
      'password': managerPassword,
      'role': 'magasin',
      'shop_name': shopName,
    });
    final id = response.data['id'];
    if (id != null) {
      await _dio.put('users/approve/$id/');
    }
  }

  Future<void> rename(int magasinId, String shopName) async {
    await _dio.patch('users/magasins/$magasinId/', data: {'shop_name': shopName});
  }

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
