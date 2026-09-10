import '../models/user.dart';
import 'constants.dart';

/// Droits derives de l'utilisateur courant — replique EXACTE de
/// `frontend/lib/auth/useCurrentUser.ts`, qui est la source de verite du
/// portage.
///
/// Le backend a DEUX axes de role, a ne jamais confondre :
///
/// 1. le role Django brut (`role`) : `admin` | `magasin` | `employer` ;
/// 2. le sous-role module Commande (`role_commande` / `commande_role`) :
///    `GERANT` | `PREPARATEUR` | `LIVREUR`, porte par [AppUser.role].
///
/// Le web derive de ces deux axes 8 drapeaux qui pilotent tout son menu et
/// tous ses ecrans. L'app ne connaissait jusqu'ici que l'axe 2, ce qui
/// fusionnait `admin` et `magasin` en un seul « gerant » : un utilisateur
/// `magasin` voyait donc des entrees reservees a `admin` cote web
/// (Magasins, Transferts, Super Admin, Parametres — flag `superAdminOnly`).
extension UserPermissions on AppUser {
  /// `role === 'admin'` — proprietaire ou co-administrateur de la societe.
  /// C'est ce que le web appelle indifferemment `isAdmin` ET `isSuperAdmin`.
  bool get isAdmin => rawRole == 'admin';

  /// `role === 'magasin'` — gerant d'un magasin, sans les droits societe.
  bool get isMagasin => rawRole == 'magasin';

  /// `role === 'employer'` — preparateur ou livreur.
  bool get isEmployer => rawRole == 'employer';

  /// Alias web : `isSuperAdmin = role === 'admin'`. Garde le meme nom que
  /// le web pour que la lecture croisee des deux bases reste immediate.
  bool get isSuperAdmin => isAdmin;

  /// `isAdminOrSuperAdmin` / `isManager` / `isGerant` du web : tous les
  /// trois valent `admin || magasin`.
  bool get isGerant => isAdmin || isMagasin;

  /// Sous-role module Commande.
  bool get isPreparateur => role == UserRole.preparateur;
  bool get isLivreur => role == UserRole.livreur;

  /// Un employer sans sous-role : ni preparateur ni livreur. Le web le
  /// laisse tomber dans une branche « par defaut » (lecture seule) plutot
  /// que de lui refuser l'acces.
  bool get isEmployerSansRole => isEmployer && !isPreparateur && !isLivreur;

  /// Vrai uniquement pour le fondateur de la societe (possede un
  /// AdminProfile). Un co-admin partage l'acces aux donnees mais pas les
  /// actions de propriete (abonnement, appareils, gestion des admins).
  bool get canManageCompany => isAdmin && isCompanyOwner;
}
