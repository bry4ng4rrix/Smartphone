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
    this.adresse,
    this.photo,
    this.createdAt,
    this.magasinId,
    this.shopName,
    this.rawRole,
    this.isCompanyOwner = false,
  });

  final int id;
  final String fullName;
  final String email;
  final UserRole role;
  final bool isActive;
  final String? phone;
  final String? adresse;
  final String? photo;
  final DateTime? createdAt;
  /// Magasin de l'utilisateur — présent pour magasin/employer, et pour un
  /// admin qui ne possède qu'un seul magasin (cas Smartphone.Mg, §11
  /// Smartreadme.md — commodité ajoutée côté serveur pour les clients mobiles).
  final int? magasinId;
  final String? shopName;
  /// Rôle Django brut ("admin"/"magasin"/"employer") — distinct du rôle
  /// module Commande ci-dessus, nécessaire pour les fonctionnalités
  /// "Super Admin" (mots de passe réservés à `role=="admin"`, abonnement/
  /// appareils réservés au propriétaire de la société ci-dessous).
  final String? rawRole;
  /// Vrai uniquement pour le fondateur de la société (a un AdminProfile) —
  /// un co-admin ajouté via "Ajouter un administrateur" partage l'accès aux
  /// données mais pas les actions de propriété (abonnement, appareils).
  final bool isCompanyOwner;

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
      adresse: asStringOrNull(json['adresse']),
      photo: asStringOrNull(json['photo']),
      createdAt: asDateOrNull(json['created_at']),
      magasinId: asIntOrNull(json['magasin_id']),
      shopName: asStringOrNull(json['shop_name']),
      rawRole: asStringOrNull(json['role']),
      isCompanyOwner: asBool(json['is_company_owner'], false),
    );
  }
}

/// Compte auto-inscrit en attente d'approbation par le gérant
/// (`GET /api/users/pending/`) — flux distinct de la création directe par
/// le gérant (§4 Smartreadme.md), pour un employé qui s'inscrit lui-même.
class PendingUser {
  PendingUser({required this.id, required this.fullName, required this.email, required this.role, this.position, this.createdAt});

  final int id;
  final String fullName;
  final String email;
  final String role;
  final String? position;
  final DateTime? createdAt;

  factory PendingUser.fromJson(Map<String, dynamic> json) {
    return PendingUser(
      id: asInt(json['id']),
      fullName: asString(json['full_name']),
      email: asString(json['email']),
      role: asString(json['role']),
      position: asStringOrNull(json['position']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}
