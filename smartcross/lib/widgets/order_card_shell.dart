import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

/// Enveloppe commune des cartes de commande (liste gérant, dépôt du
/// préparateur, tournée du livreur, historiques). Une carte doit se
/// distinguer nettement de la suivante quand on fait défiler une longue
/// file : marge verticale généreuse, bordure épaisse, ombre légère et
/// bande de couleur du statut en tête (§ demande « plus de marge, plus
/// d'épaisseur sur les bordures pour bien séparer les commandes »).
///
/// [header] est rendu sur un fond teinté de la couleur du statut (numéro,
/// badge, pastille de livraison) ; [child] est le corps ; [footer] une zone
/// d'action séparée par un filet.
class OrderCardShell extends StatelessWidget {
  const OrderCardShell({
    super.key,
    required this.status,
    required this.child,
    this.header,
    this.footer,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  final OrderStatus status;
  final Widget child;
  final Widget? header;
  final Widget? footer;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Espace entre deux cartes.
  static const double espacement = 14;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = statusColor(context, status.apiValue);
    final bordure = dark ? scheme.outline.withValues(alpha: 0.75) : scheme.outline.withValues(alpha: 0.9);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: espacement / 2),
      decoration: BoxDecoration(
        color: dark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bordure, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Liseré de statut : la couleur se lit avant même le badge.
              Container(height: 5, color: accent),
              if (header != null)
                Container(
                  color: accent.withValues(alpha: dark ? 0.16 : 0.09),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: header,
                ),
              Padding(padding: padding, child: child),
              if (footer != null) ...[
                Divider(height: 1, thickness: 1, color: bordure.withValues(alpha: 0.5)),
                Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), child: footer),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Titre de section à l'intérieur d'une carte (« ARTICLES », « CLIENT »…) :
/// petit libellé en capitales avec icône, pour découper visuellement le
/// contenu d'une commande.
class OrderCardSectionTitle extends StatelessWidget {
  const OrderCardSectionTitle({super.key, required this.label, required this.icon, this.trailing});
  final String label;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: scheme.primary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Bloc de section : titre + contenu sur un fond légèrement contrasté,
/// pour que chaque groupe d'informations (articles, client, paiement) se
/// détache du reste de la carte.
class OrderCardSection extends StatelessWidget {
  const OrderCardSection({
    super.key,
    required this.label,
    required this.icon,
    required this.child,
    this.trailing,
    this.margin = const EdgeInsets.only(bottom: 10),
  });
  final String label;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderCardSectionTitle(label: label, icon: icon, trailing: trailing),
          child,
        ],
      ),
    );
  }
}
