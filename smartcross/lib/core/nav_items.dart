import 'package:flutter/material.dart';

import 'constants.dart';

class NavItem {
  const NavItem({required this.path, required this.label, required this.icon, this.roles});

  final String path;
  final String label;
  final IconData icon;

  /// null = accessible à tous les rôles.
  final Set<UserRole>? roles;

  bool visibleFor(UserRole role) => roles == null || roles!.contains(role);
}

/// Navigation déclarative par rôle (§4 README — droits stricts) :
/// - Gérant : accès complet à tous les modules.
/// - Préparateur : uniquement Dépôt (ses commandes) + Notifications.
/// - Livreur : uniquement Tournée + Notifications.
const List<NavItem> kPrimaryNavItems = [
  NavItem(path: '/dashboard', label: 'Tableau de bord', icon: Icons.space_dashboard_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/orders', label: 'Commandes', icon: Icons.receipt_long_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/caisse', label: 'Caisse', icon: Icons.point_of_sale_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/depot', label: 'Dépôt', icon: Icons.inventory_outlined, roles: {UserRole.preparateur}),
  NavItem(path: '/tournee', label: 'Tournée', icon: Icons.local_shipping_outlined, roles: {UserRole.livreur}),
  NavItem(path: '/catalog', label: 'Catalogue', icon: Icons.style_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/stock', label: 'Stock', icon: Icons.inventory_2_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/suppliers', label: 'Fournisseurs', icon: Icons.local_shipping_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/stores', label: 'Magasins', icon: Icons.storefront_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/transfers', label: 'Transferts', icon: Icons.compare_arrows_outlined, roles: {UserRole.gerant}),
  NavItem(path: '/users', label: 'Utilisateurs', icon: Icons.people_outline, roles: {UserRole.gerant}),
  NavItem(path: '/chats', label: 'Discussions', icon: Icons.chat_bubble_outline),
  NavItem(path: '/notifications', label: 'Notifications', icon: Icons.notifications_outlined),
  NavItem(path: '/settings', label: 'Paramètres', icon: Icons.settings_outlined),
];
