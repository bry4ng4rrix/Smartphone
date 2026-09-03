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
  final String? shopLogo;
  final String? managerName;
  final String? managerEmail;
  final List<MagasinEmployer> employers;

  // Fusionnées depuis `magasins/stats/` (endpoint séparé, §8 README).
  final int? totalProducts;
  final int? totalStockQuantity;
  final double? totalStockValue;
  final double? totalSoldValue;
  final double? profit;

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

  Magasin withStats(Map<String, dynamic> stats) {
    return Magasin(
      magasinId: magasinId,
      shopName: shopName,
      shopLogo: shopLogo,
      managerName: managerName,
      managerEmail: managerEmail,
      employers: employers,
      totalProducts: asIntOrNull(stats['total_products']),
      totalStockQuantity: asIntOrNull(stats['total_stock_quantity']),
      totalStockValue: asDoubleOrNull(stats['total_stock_value']),
      totalSoldValue: asDoubleOrNull(stats['total_sold_value']),
      profit: asDoubleOrNull(stats['profit']),
    );
  }
}
