import '../core/constants.dart';
import 'json_utils.dart';

/// CustomUser (§11 README) — gérant, préparateur ou livreur.
class AppUser {
  AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    this.phone,
    this.createdAt,
    this.magasinId,
    this.shopName,
  });

  final int id;
  final String fullName;
  final String email;
  final UserRole role;
  final bool isActive;
  final String? phone;
  final DateTime? createdAt;
  /// Magasin de l'utilisateur — présent pour magasin/employer, et pour un
  /// admin qui ne possède qu'un seul magasin (cas Smartphone.Mg, §11
  /// Smartreadme.md — commodité ajoutée côté serveur pour les clients mobiles).
  final int? magasinId;
  final String? shopName;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: asInt(json['id']),
      fullName: asString(json['full_name']),
      email: asString(json['email']),
      // Le backend multi-tenant a un rôle Django (admin/magasin/employer) et
      // un sous-rôle module Commande séparé — c'est ce dernier qui pilote
      // cette app (§4 Smartreadme.md), pas le rôle Django brut. `/me/`
      // l'expose sous `role_commande` (calculé : GERANT pour admin/magasin,
      // PREPARATEUR/LIVREUR pour un employer) ; `magasins/users/` expose
      // directement le champ brut `commande_role` sur chaque employé.
      role: UserRoleX.fromApi(asStringOrNull(json['role_commande'] ?? json['commande_role'])),
      isActive: asBool(json['is_confirmed'], true),
      phone: asStringOrNull(json['phone']),
      createdAt: asDateOrNull(json['created_at']),
      magasinId: asIntOrNull(json['magasin_id']),
      shopName: asStringOrNull(json['shop_name']),
    );
  }
}
