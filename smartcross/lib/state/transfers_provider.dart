import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/catalog.dart';
import 'stores_provider.dart';

/// Catalogue (références + variantes couleur) du MAGASIN SOURCE d'un
/// transfert — `GET /catalog/references/?magasin_id=` — pour le panneau
/// « Produits du magasin » de `TransferProductsPanel`
/// (frontend/components/transfer-products-panel.tsx).
///
/// Comme sur le web, aucun rafraîchissement temps réel ici : les stocks
/// affichés sont ceux du chargement initial du magasin source. Le provider
/// est `autoDispose` : changer de magasin source remonte le panneau (clé sur
/// `magasin_id`, comme le `key={sourceStore.magasin_id}` du web) et
/// recharge le catalogue du nouveau magasin.
final transferCatalogProvider = FutureProvider.autoDispose.family<List<ProductReference>, int>((ref, magasinId) {
  return ref.read(storesRepositoryProvider).catalogFor(magasinId);
});
