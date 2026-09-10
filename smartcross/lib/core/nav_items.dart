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
/// - `hidePreparateur`/`hideLivreur` -> masque ces sous-roles
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.adminOnly = false,
    this.superAdminOnly = false,
    this.livreurOnly = false,
    this.hidePreparateur = false,
    this.hideLivreur = false,
  });

  final String path;
  final String label;
  final IconData icon;

  final bool adminOnly;
  final bool superAdminOnly;
  final bool livreurOnly;
  final bool hidePreparateur;
  final bool hideLivreur;

  /// Meme sequence de tests que le `.filter()` du sidebar web.
  bool visibleFor(AppUser user) {
    if (livreurOnly && !user.isLivreur) return false;
    if (superAdminOnly && !user.isSuperAdmin) return false;
    if (adminOnly && !user.isGerant) return false;
    if (hidePreparateur && user.isPreparateur) return false;
    if (hideLivreur && user.isLivreur) return false;
    return true;
  }
}

/// Navigation principale — ordre et libelles identiques au sidebar web.
const List<NavItem> kPrimaryNavItems = [
  NavItem(
    path: '/dashboard',
    label: 'Tableau de bord',
    icon: Icons.space_dashboard_outlined,
    adminOnly: true,
  ),
  // Page unique declinee en 3 experiences par role (gerant / preparateur /
  // livreur), exactement comme /orders cote web : aucun drapeau ici.
  NavItem(path: '/orders', label: 'Commandes', icon: Icons.receipt_long_outlined),
  NavItem(
    path: '/pickup',
    label: 'Récupération',
    icon: Icons.inventory_2_outlined,
    adminOnly: true,
  ),
  NavItem(
    path: '/bilan',
    label: 'Bilan du jour',
    icon: Icons.receipt_outlined,
    livreurOnly: true,
  ),
  NavItem(
    path: '/catalog',
    label: 'Produits',
    icon: Icons.style_outlined,
    hideLivreur: true,
  ),
  NavItem(
    path: '/caisse',
    label: 'Caisse',
    icon: Icons.point_of_sale_outlined,
    hidePreparateur: true,
    hideLivreur: true,
  ),
  NavItem(path: '/chats', label: 'Discussions', icon: Icons.chat_bubble_outline),
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
  NavItem(
    path: '/suppliers',
    label: 'Fournisseurs',
    icon: Icons.local_shipping_outlined,
    adminOnly: true,
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
    path: '/reports',
    label: 'Rapports',
    icon: Icons.insert_chart_outlined,
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
  // Ces deux pages existent cote web mais ne figurent dans AUCUN menu : sur
  // le web on y accede par l'URL, ce qui n'existe pas sur mobile. On les
  // expose donc dans le menu, avec le meme gating que leur page web.
  NavItem(
    path: '/superadmin',
    label: 'Super Administration',
    icon: Icons.admin_panel_settings_outlined,
    superAdminOnly: true,
  ),
  NavItem(
    path: '/scanner',
    label: 'Recherche produit',
    icon: Icons.qr_code_scanner_outlined,
    hideLivreur: true,
  ),
  NavItem(
    path: '/settings',
    label: 'Paramètres',
    icon: Icons.settings_outlined,
    superAdminOnly: true,
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
  final match = kPrimaryNavItems
      .where((i) => path == i.path || path.startsWith('${i.path}/'))
      .toList();
  if (match.isEmpty) return true; // route hors menu (detail, creation…)
  return match.first.visibleFor(user);
}
