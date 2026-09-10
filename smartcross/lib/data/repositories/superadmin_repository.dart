import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/json_utils.dart';

/// Console de super-administration — portage de
/// `frontend/app/(app)/superadmin/page.tsx`.
///
/// La page web n'a qu'UNE source de données : `GET /users/magasins/users/`,
/// qui renvoie la liste des magasins de la société, chacun avec son
/// `manager`, ses `employers` et ses `company_users`. Elle en dérive les 3
/// compteurs et les 2 tableaux. Deux actions d'écriture s'y ajoutent :
/// `PUT /users/role/<id>/` (changement de rôle Django) et
/// `DELETE /users/delete/<id>/` (suppression confirmée par mot de passe).
///
/// Aucun modèle existant n'est réutilisé ici : `Magasin`
/// (`models/magasin.dart`) perd `is_confirmed`/`role` du manager, et
/// `AppUser` (`models/user.dart`) mappe `is_confirmed` sur `isActive` sans
/// conserver le `shop_name` injecté par le `flatMap` du web. Les formes
/// ci-dessous collent exactement à ce que la page affiche.
class SuperadminRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// `djangoClient.get('/users/magasins/users/')`. Le backend
  /// (`users/views.py::UsersByMagasinView`, `[IsAuthenticated]`) scope déjà
  /// par rôle : admin -> tous ses magasins, magasin -> le sien,
  /// employer -> celui de son affectation.
  Future<List<SuperadminStore>> list() async {
    final response = await _dio.get('users/magasins/users/');
    return (response.data as List)
        .map((e) => SuperadminStore.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `PUT /users/role/<id>/ { role }` — `[IsAuthenticated, IsAdmin]`.
  /// Refus possibles côté serveur, remontés tels quels à l'utilisateur via
  /// [ApiClient.messageFromError] : rôle invalide (400), utilisateur
  /// introuvable (404), « Vous ne pouvez pas modifier votre propre rôle »
  /// (400), « Seul le fondateur de la société peut gérer les
  /// administrateurs. » (403), « Action impossible sur le fondateur de la
  /// société. » (403), « Permission refusée : cet utilisateur n'appartient
  /// pas à votre entreprise. » (403).
  Future<void> changeRole(int userId, String role) async {
    await _dio.put('users/role/$userId/', data: {'role': role});
  }

  /// `DELETE /users/delete/<id>/ { password }` — le mot de passe de
  /// l'utilisateur COURANT est exigé par le backend (ré-authentification).
  /// Refus possibles : « Mot de passe requis pour confirmer la
  /// suppression. » (400), « Mot de passe incorrect. » (400), « Vous ne
  /// pouvez pas vous supprimer vous-même » (400), « Utilisateur
  /// introuvable » (404), « Seul le fondateur de la société peut retirer un
  /// administrateur. » (403), « Permission refusée : cet employé
  /// n'appartient pas à votre magasin. » (403).
  Future<void> deleteUser(int userId, String password) async {
    await _dio.delete('users/delete/$userId/', data: {'password': password});
  }
}

/// Un compte tel que la page /superadmin l'affiche. Le `shopName` n'est PAS
/// un champ de l'API sur `manager`/`employers` : le web l'injecte depuis le
/// magasin parent (`{...s.manager, shop_name: s.shop_name}`), on fait pareil.
class SuperadminUser {
  const SuperadminUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isConfirmed,
    required this.role,
    this.shopName,
  });

  final int id;
  final String fullName;
  final String email;

  /// `is_confirmed` : « Actif » / « Inactif » (tableau des équipes) ou
  /// « Actif » / « En attente » (tableau des comptes) — deux libellés pour
  /// la MÊME donnée, comme sur le web.
  final bool isConfirmed;

  /// Rôle Django brut : `admin` | `magasin` | `employer`.
  final String role;

  final String? shopName;

  factory SuperadminUser.fromJson(Map<String, dynamic> json, {String? shopName}) {
    return SuperadminUser(
      id: asInt(json['id']),
      fullName: asString(json['full_name']),
      email: asString(json['email']),
      // Défaut `false` : côté web `!u.is_confirmed` sur un champ absent
      // compte l'utilisateur dans « En attente ».
      isConfirmed: asBool(json['is_confirmed'], false),
      role: asString(json['role']),
      shopName: shopName ?? asStringOrNull(json['shop_name']),
    );
  }
}

/// Une « équipe » = un magasin de la société.
class SuperadminStore {
  const SuperadminStore({
    required this.magasinId,
    required this.shopName,
    this.manager,
    this.employers = const [],
  });

  final int magasinId;
  final String shopName;

  /// ATTENTION : `manager` côté backend est en réalité l'ADMIN de la société
  /// (`mag.admin`), pas le compte `role='magasin'` (`mag.user`). Le web
  /// affiche pourtant cette valeur dans la colonne « Gérant » — comportement
  /// reproduit à l'identique.
  final SuperadminUser? manager;

  final List<SuperadminUser> employers;

  /// Web : `memberCount = (s.employers?.length || 0) + (s.manager ? 1 : 0)`.
  /// Ne compte donc NI `mag.user` (le vrai gérant) NI les co-admins.
  int get memberCount => employers.length + (manager != null ? 1 : 0);

  /// Web : `isActive = !!s.manager?.is_confirmed`.
  bool get isActive => manager?.isConfirmed ?? false;

  factory SuperadminStore.fromJson(Map<String, dynamic> json) {
    final shopName = asString(json['shop_name']);
    final manager = json['manager'] as Map<String, dynamic>?;
    return SuperadminStore(
      magasinId: asInt(json['magasin_id']),
      shopName: shopName,
      manager: manager == null ? null : SuperadminUser.fromJson(manager, shopName: shopName),
      employers: (json['employers'] as List? ?? const [])
          .map((e) => SuperadminUser.fromJson(e as Map<String, dynamic>, shopName: shopName))
          .toList(),
      // `company_users` est renvoyé par l'API mais la page web ne le
      // consomme pas : les co-admins n'apparaissent donc PAS dans le tableau
      // « Tous les utilisateurs ». Non porté, volontairement.
    );
  }
}

/// Réplique exacte du `flatMap` de la page :
/// `stores.flatMap(s => [manager?, ...employers]).filter(Boolean)` — manager
/// avant les employés, pour chaque magasin, dans l'ordre de l'API et SANS
/// dédoublonnage (un admin gérant plusieurs magasins apparaît autant de fois
/// qu'il a de magasins, exactement comme sur le web).
List<SuperadminUser> flattenSuperadminUsers(List<SuperadminStore> stores) => [
  for (final store in stores) ...[
    if (store.manager != null) store.manager!,
    ...store.employers,
  ],
];
