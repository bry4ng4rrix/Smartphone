import 'package:flutter/material.dart';

import '../models/user.dart';
import 'permissions.dart';

/// Entree de navigation — porte les MEMES drapeaux que
/// `frontend/components/layout/sidebar.tsx`, pour que le menu mobile et le
/// menu web laissent voir exactement les memes pages aux memes roles.
///
/// Regles du web, reprises telles quelles :
/// - `adminOnly`      -> visible si `isAdminOrSuperAdmin` (= admin OU magasin)
/// - `superAdminOnly` -> visible si `isSuperAdmin` (= admin uniquement)
/// - `livreurOnly`    -> visible uniquement par le livreur
/// - `livreurOrGerant` -> visible par le livreur ET par le gerant (bilan)
/// - `hidePreparateur`/`hideLivreur` -> masque ces sous-roles
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.adminOnly = false,
    this.superAdminOnly = false,
    this.livreurOnly = false,
    this.livreurOrGerant = false,
    this.hidePreparateur = false,
    this.hideLivreur = false,
  });

  final String path;
  final String label;
  final IconData icon;

  final bool adminOnly;
  final bool superAdminOnly;
  final bool livreurOnly;
  final bool livreurOrGerant;
  final bool hidePreparateur;
  final bool hideLivreur;

  /// Meme sequence de tests que le `.filter()` du sidebar web.
  bool visibleFor(AppUser user) {
    if (livreurOnly && !user.isLivreur) return false;
    if (livreurOrGerant && !user.isLivreur && !user.isGerant) return false;
    if (superAdminOnly && !user.isSuperAdmin) return false;
    if (adminOnly && !user.isGerant) return false;
    if (hidePreparateur && user.isPreparateur) return false;
    if (hideLivreur && user.isLivreur) return false;
    return true;
  }
}

/// Navigation principale — ordre et libelles identiques au sidebar web.
const List<NavItem> kPrimaryNavItems = [
  // Le tableau de bord mobile EST le centre de rapports (couts, marges,
  // benefices) : ADMIN GLOBAL uniquement (mission 5 et 25). Le gerant de
  // magasin demarre sur /orders — voir _homeFor dans router.dart.
  NavItem(
    path: '/dashboard',
    label: 'Tableau de bord',
    icon: Icons.space_dashboard_outlined,
    superAdminOnly: true,
  ),
  // Page unique declinee en 3 experiences par role (gerant / preparateur /
  // livreur), exactement comme /orders cote web : aucun drapeau ici.
  NavItem(path: '/orders', label: 'Commandes', icon: Icons.receipt_long_outlined),
  NavItem(
    path: '/catalog',
    label: 'Produits',
    icon: Icons.style_outlined,
    hideLivreur: true,
  ),
  // Caisse et tresorerie : ADMIN GLOBAL uniquement (mission 14). Le gerant
  // de magasin n'ouvre plus de session et ne voit plus les mouvements.
  NavItem(
    path: '/caisse',
    label: 'Caisse',
    icon: Icons.point_of_sale_outlined,
    superAdminOnly: true,
  ),
  NavItem(
    path: '/bilan',
    label: 'Bilan du jour',
    icon: Icons.receipt_outlined,
    livreurOrGerant: true,
  ),
  NavItem(
    path: '/pickup',
    label: 'Récupération',
    icon: Icons.inventory_2_outlined,
    adminOnly: true,
  ),
  NavItem(path: '/chats', label: 'Chats', icon: Icons.chat_bubble_outline),
  NavItem(
    path: '/movements',
    label: 'Mouvements',
    icon: Icons.trending_up_outlined,
    adminOnly: true,
  ),
  NavItem(
    path: '/alerts',
    label: 'Alertes',
    icon: Icons.error_outline,
    adminOnly: true,
  ),
  // Fournisseurs : ADMIN GLOBAL uniquement (mission 16) — le module expose
  // les couts d'achat et le cout de revient.
  NavItem(
    path: '/suppliers',
    label: 'Fournisseurs',
    icon: Icons.local_shipping_outlined,
    superAdminOnly: true,
  ),
  NavItem(
    path: '/transfers',
    label: 'Transferts',
    icon: Icons.compare_arrows_outlined,
    superAdminOnly: true,
  ),
  NavItem(
    path: '/notifications',
    label: 'Notifications',
    icon: Icons.notifications_outlined,
    adminOnly: true,
  ),
  NavItem(
    path: '/stores',
    label: 'Magasins',
    icon: Icons.storefront_outlined,
    superAdminOnly: true,
  ),
  NavItem(
    path: '/users',
    label: 'Super Admin',
    icon: Icons.shield_outlined,
    superAdminOnly: true,
  ),
  // /superadmin et /scanner (pages web sans lien dans le menu, accessibles
  // seulement par l'URL) ne sont pas portees : retirees de l'app a la demande.
  // Profil et securite pour tous ; depenses et zones restent a l'admin.
  NavItem(
    path: '/settings',
    label: 'Paramètres',
    icon: Icons.settings_outlined,
    adminOnly: true,
  ),
];

/// Depot et Tournee n'existent pas dans le menu web (le preparateur et le
/// livreur y passent par /orders). L'app garde ces deux ecrans dedies, plus
/// adaptes au mobile, et les expose au seul sous-role concerne.
const List<NavItem> kRoleHomeNavItems = [
  NavItem(path: '/depot', label: 'Dépôt', icon: Icons.inventory_outlined),
  NavItem(path: '/tournee', label: 'Tournée', icon: Icons.local_shipping_outlined),
];

/// Menu effectif d'un utilisateur : les entrees web autorisees, precedees de
/// son ecran d'accueil dedie quand il en a un.
List<NavItem> navItemsFor(AppUser user) {
  return [
    if (user.isPreparateur) kRoleHomeNavItems[0],
    if (user.isLivreur) kRoleHomeNavItems[1],
    ...kPrimaryNavItems.where((i) => i.visibleFor(user)),
  ];
}

/// Une route est-elle autorisee pour cet utilisateur ? Sert de garde au
/// routeur : cote web le menu masque le lien, mais taper l'URL passe quand
/// meme — ici on refuse reellement l'acces.
bool canAccessPath(AppUser user, String path) {
  if (path == '/depot') return user.isPreparateur || user.isGerant;
  if (path == '/tournee') return user.isLivreur || user.isGerant;
  // Le menu web reserve l'entree au gerant, mais la PAGE /notifications
  // accepte tous les roles (lien « Voir toutes les notifications » de la
  // cloche) : meme regle ici.
  if (path == '/notifications') return true;
  // « Mon profil » de la TopBar web mene tout le monde sur /settings (la
  // page se degrade en lecture seule pour un non-gerant) ; le menu, lui,
  // reste reserve a l'admin comme le sidebar.
  if (path == '/settings') return true;
  // Administration des comptes : ADMIN GLOBAL uniquement (mission 26). Le
  // gerant ne gere plus les utilisateurs, meme ceux de son magasin.
  if (path == '/users' || path.startsWith('/users/')) return user.isAdmin;
  final match = kPrimaryNavItems
      .where((i) => path == i.path || path.startsWith('${i.path}/'))
      .toList();
  if (match.isEmpty) return true; // route hors menu (detail, creation…)
  return match.first.visibleFor(user);
}
