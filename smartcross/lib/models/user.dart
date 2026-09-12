import '../core/constants.dart';
import 'json_utils.dart';

/// CustomUser (§11 README) — administrateur, gérant, préparateur ou livreur.
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
    this.lastLoginAt,
    this.lastLogoutAt,
    this.magasinId,
    this.shopName,
    this.position,
    this.rawRole,
    this.isCompanyOwner = false,
  });

  final int id;
  final String fullName;
  final String email;
  final UserRole role;

  /// `is_confirmed` — compte approuvé (le web parle d'utilisateur « actif »).
  final bool isActive;
  final String? phone;
  final String? adresse;
  final String? photo;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final DateTime? lastLogoutAt;

  /// Magasin de l'utilisateur — présent pour magasin/employer, et pour un
  /// admin qui ne possède qu'un seul magasin (cas Smartphone.Mg, §11
  /// Smartreadme.md — commodité ajoutée côté serveur pour les clients mobiles).
  /// Pour les membres d'une équipe (`magasins/users/`), injecté depuis le
  /// magasin parent par [flattenTeamUsers], comme le fait la page web.
  final int? magasinId;
  final String? shopName;

  /// Poste / fonction d'un employé (`EmployerProfile.position`) — colonne
  /// « Poste » de la page Super Administration.
  final String? position;

  /// Rôle Django brut ("admin"/"magasin"/"employer") — distinct du rôle
  /// module Commande ci-dessus, nécessaire pour les fonctionnalités
  /// "Super Admin" (mots de passe réservés à `role=="admin"`, abonnement/
  /// appareils réservés au propriétaire de la société ci-dessous).
  final String? rawRole;

  /// Vrai uniquement pour le fondateur de la société (a un AdminProfile) —
  /// un co-admin ajouté via "Ajouter un administrateur" partage l'accès aux
  /// données mais pas les actions de propriété (abonnement, appareils).
  final bool isCompanyOwner;

  /// `isCurrentlyOnline` du web : connecté et pas encore déconnecté depuis.
  bool get isCurrentlyOnline => lastLoginAt != null && (lastLogoutAt == null || lastLogoutAt!.isBefore(lastLoginAt!));

  AppUser copyWith({UserRole? role, int? magasinId, String? shopName, String? position}) {
    return AppUser(
      id: id,
      fullName: fullName,
      email: email,
      role: role ?? this.role,
      isActive: isActive,
      phone: phone,
      adresse: adresse,
      photo: photo,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      lastLogoutAt: lastLogoutAt,
      magasinId: magasinId ?? this.magasinId,
      shopName: shopName ?? this.shopName,
      position: position ?? this.position,
      rawRole: rawRole,
      isCompanyOwner: isCompanyOwner,
    );
  }

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
      lastLoginAt: asDateOrNull(json['last_login_at']),
      lastLogoutAt: asDateOrNull(json['last_logout_at']),
      magasinId: asIntOrNull(json['magasin_id']),
      shopName: asStringOrNull(json['shop_name']),
      position: asStringOrNull(json['position']),
      rawRole: asStringOrNull(json['role']),
      isCompanyOwner: asBool(json['is_company_owner'], false),
    );
  }
}

/// Une équipe = un magasin de la société, tel que le renvoie
/// `GET /api/users/magasins/users/` (users/views.py::UsersByMagasinView) :
/// `manager` (l'admin propriétaire du magasin), `employers` (les employés
/// rattachés à CE magasin, avec leur sous-rôle Commande) et `company_users`
/// (tous les comptes de la société — admins, co-admins, gérants, employés —
/// chacun annoté de son propre `shop_name`/`magasin_id`).
///
/// Un admin reçoit TOUS ses magasins, un gérant le sien, un employé le sien.
class MagasinTeam {
  MagasinTeam({
    required this.magasinId,
    required this.shopName,
    this.shopLogo,
    this.manager,
    this.employers = const [],
    this.companyUsers = const [],
  });

  final int magasinId;
  final String shopName;
  final String? shopLogo;
  final AppUser? manager;
  final List<AppUser> employers;
  final List<AppUser> companyUsers;

  factory MagasinTeam.fromJson(Map<String, dynamic> json) {
    final manager = json['manager'] as Map<String, dynamic>?;
    return MagasinTeam(
      magasinId: asInt(json['magasin_id']),
      shopName: asString(json['shop_name']),
      shopLogo: asStringOrNull(json['shop_logo']),
      manager: manager == null ? null : AppUser.fromJson(manager),
      employers: (json['employers'] as List? ?? const [])
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList(),
      companyUsers: (json['company_users'] as List? ?? const [])
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Réplique exacte de la construction de `allUsers` dans
/// `frontend/app/(app)/users/page.tsx` (`fetchUsers`) : pour chaque magasin,
/// d'abord le manager, puis les employés, puis les `company_users`, avec
/// DÉDOUBLONNAGE par id (le premier gagne — un admin propriétaire de
/// plusieurs magasins n'apparaît qu'une fois, sous son premier magasin).
///
/// Le nom du magasin est injecté depuis le magasin parent pour le manager et
/// les employés (`shop_name: store.shop_name`), et pour un `company_user`
/// c'est son propre `shop_name` qui prime (`companyUser.shop_name ||
/// store.shop_name`) — idem pour `magasin_id`.
///
/// Ajout mobile : `company_users` (liste GLOBALE de la société, identique
/// sous chaque magasin) ne porte pas `commande_role`, si bien qu'un employé
/// d'un 2e magasin, rencontré d'abord dans les `company_users` du 1er,
/// perdrait son sous-rôle Préparateur/Livreur. On le récupère depuis les
/// `employers` de tous les magasins.
List<AppUser> flattenTeamUsers(List<MagasinTeam> teams) {
  final seen = <int>{};
  final flat = <AppUser>[];
  final employerById = <int, AppUser>{
    for (final team in teams)
      for (final emp in team.employers) emp.id: emp,
  };

  void add(AppUser? user, {required String? shopName, required int? magasinId}) {
    if (user == null || !seen.add(user.id)) return;
    final name = (shopName != null && shopName.isNotEmpty) ? shopName : user.shopName;
    final employer = employerById[user.id];
    flat.add(
      user.copyWith(
        shopName: (name == null || name.isEmpty) ? '-' : name,
        magasinId: magasinId ?? user.magasinId,
        role: (user.role == UserRole.unknown && employer != null) ? employer.role : null,
        position: (user.position == null || user.position!.isEmpty) ? employer?.position : null,
      ),
    );
  }

  for (final team in teams) {
    add(team.manager, shopName: team.shopName, magasinId: team.magasinId);
    for (final emp in team.employers) {
      add(emp, shopName: team.shopName, magasinId: team.magasinId);
    }
    for (final cu in team.companyUsers) {
      add(
        cu,
        shopName: (cu.shopName != null && cu.shopName!.isNotEmpty) ? cu.shopName : team.shopName,
        magasinId: cu.magasinId ?? team.magasinId,
      );
    }
  }
  return flat;
}

/// Compte auto-inscrit en attente d'approbation par le gérant
/// (`GET /api/users/pending/`) — flux distinct de la création directe par
/// le gérant (§4 Smartreadme.md), pour un employé qui s'inscrit lui-même.
/// Le backend renvoie aussi les gérants de magasin en attente (`role`
/// magasin, avec `shop_name`).
class PendingUser {
  PendingUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.position,
    this.shopName,
    this.phone,
    this.adresse,
    this.photo,
    this.createdAt,
  });

  final int id;
  final String fullName;
  final String email;

  /// Rôle Django brut : `employer` | `magasin`.
  final String role;
  final String? position;
  final String? shopName;
  final String? phone;
  final String? adresse;
  final String? photo;
  final DateTime? createdAt;

  factory PendingUser.fromJson(Map<String, dynamic> json) {
    return PendingUser(
      id: asInt(json['id']),
      fullName: asString(json['full_name']),
      email: asString(json['email']),
      role: asString(json['role']),
      position: asStringOrNull(json['position']),
      shopName: asStringOrNull(json['shop_name']),
      phone: asStringOrNull(json['phone']),
      adresse: asStringOrNull(json['adresse']),
      photo: asStringOrNull(json['photo']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}
