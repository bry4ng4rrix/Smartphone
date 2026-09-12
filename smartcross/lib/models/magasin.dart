import 'json_utils.dart';

/// Un magasin de la société (§8 Smartreadme.md — infrastructure multi-tenant
/// conservée). Un gérant ne voit que son propre magasin ; un admin
/// (propriétaire de plusieurs magasins) les voit tous — module "Magasins" +
/// "Transferts", réservé à ce dernier côté backend (`TransferProductsView`,
/// `MagasinViewSet.perform_create`).
class MagasinEmployer {
  MagasinEmployer({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isConfirmed,
    this.position,
    this.commandeRole,
  });

  final int id;
  final String fullName;
  final String email;
  final bool isConfirmed;
  final String? position;
  final String? commandeRole;

  factory MagasinEmployer.fromJson(Map<String, dynamic> json) {
    return MagasinEmployer(
      id: asInt(json['id']),
      fullName: asString(json['full_name']),
      email: asString(json['email']),
      isConfirmed: asBool(json['is_confirmed'], true),
      position: asStringOrNull(json['position']),
      commandeRole: asStringOrNull(json['commande_role']),
    );
  }
}

/// Une carte de la page Magasins (`frontend/app/(app)/stores/page.tsx`) :
/// `GET /users/magasins/users/` fusionné avec `GET /users/magasins/stats/`
/// et, pour un admin, `GET /users/magasins/overview/` (profit).
class Magasin {
  Magasin({
    required this.magasinId,
    required this.shopName,
    this.shopLogo,
    this.managerName,
    this.managerEmail,
    this.employers = const [],
    this.totalProducts,
    this.totalStockQuantity,
    this.totalStockValue,
    this.totalSoldValue,
    this.profit,
  });

  final int magasinId;
  final String shopName;

  /// URL absolue du logo (`shop_logo`), `null` si aucun — l'écran affiche
  /// alors l'icône « Store » en repli, comme le web.
  final String? shopLogo;

  /// Bloc « gérant » de la carte web (`store.manager`). NB : côté serveur
  /// (`UsersByMagasinView`) `manager` est l'ADMIN propriétaire du magasin
  /// (`mag.admin`), pas le compte `role=magasin`.
  final String? managerName;
  final String? managerEmail;
  final List<MagasinEmployer> employers;

  // Fusionnées depuis `magasins/stats/` (endpoint séparé, §8 README). Le web
  // retombe sur 0 quand l'appel échoue : les getters `*OrZero` ci-dessous
  // reproduisent ces valeurs par défaut.
  final int? totalProducts;
  final int? totalStockQuantity;
  final double? totalStockValue;
  final double? totalSoldValue;

  /// `profitStats?.total_profit ?? storeStats.profit ?? 0` du web : profit de
  /// `magasins/overview/` (admin) sinon celui de `magasins/stats/`.
  final double? profit;

  /// `store.manager` non nul sur le web — pilote l'affichage du bloc gérant.
  bool get hasManager => managerName != null || managerEmail != null;

  int get totalProductsOrZero => totalProducts ?? 0;
  int get totalStockQuantityOrZero => totalStockQuantity ?? 0;
  double get totalStockValueOrZero => totalStockValue ?? 0;
  double get totalSoldValueOrZero => totalSoldValue ?? 0;
  double get profitOrZero => profit ?? 0;

  factory Magasin.fromJson(Map<String, dynamic> json) {
    final manager = json['manager'] as Map<String, dynamic>?;
    return Magasin(
      magasinId: asInt(json['magasin_id']),
      shopName: asString(json['shop_name']),
      shopLogo: asStringOrNull(json['shop_logo']),
      managerName: manager != null ? asStringOrNull(manager['full_name']) : null,
      managerEmail: manager != null ? asStringOrNull(manager['email']) : null,
      employers: (json['employers'] as List? ?? [])
          .map((e) => MagasinEmployer.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Fusion des stats (`magasins/stats/`) et, si fourni, du profit de
  /// `magasins/overview/` (`total_profit`) qui prime sur `stats.profit`.
  Magasin withStats(Map<String, dynamic>? stats, {double? overviewProfit}) {
    return Magasin(
      magasinId: magasinId,
      shopName: shopName,
      shopLogo: shopLogo,
      managerName: managerName,
      managerEmail: managerEmail,
      employers: employers,
      totalProducts: stats != null ? asIntOrNull(stats['total_products']) : totalProducts,
      totalStockQuantity: stats != null ? asIntOrNull(stats['total_stock_quantity']) : totalStockQuantity,
      totalStockValue: stats != null ? asDoubleOrNull(stats['total_stock_value']) : totalStockValue,
      totalSoldValue: stats != null ? asDoubleOrNull(stats['total_sold_value']) : totalSoldValue,
      profit: overviewProfit ?? (stats != null ? asDoubleOrNull(stats['profit']) : profit),
    );
  }
}
