import 'package:flutter/material.dart';

/// Rôle destinataire d'une note de commande.
enum NoteRole { preparateur, livreur }

/// Note destinée au préparateur ou au livreur — encart très visible (fond
/// coloré, bordure gauche épaisse, icône, texte agrandi) pour que la consigne
/// du gérant ne passe pas inaperçue sur les listes, les fiches et les
/// confirmations (§ demande). Port de `components/orders/note-callout.tsx` :
/// ambre = préparateur, bleu = livreur. Ne rend rien si la note est vide.
class NoteCallout extends StatelessWidget {
  const NoteCallout({super.key, required this.role, required this.text, this.compact = false, this.margin});

  final NoteRole role;
  final String? text;

  /// Variante réduite pour une carte de liste.
  final bool compact;
  final EdgeInsetsGeometry? margin;

  static const _amber = Color(0xFFF59E0B);
  static const _amberBg = Color(0xFFFFFBEB);
  static const _amberBgDark = Color(0x66451A03);
  static const _amberText = Color(0xFF451A03);
  static const _amberTextDark = Color(0xFFFEF3C7);
  static const _amberAccent = Color(0xFFB45309);
  static const _amberAccentDark = Color(0xFFFCD34D);
  static const _sky = Color(0xFF38BDF8);
  static const _skyBg = Color(0xFFF0F9FF);
  static const _skyBgDark = Color(0x66082F49);
  static const _skyText = Color(0xFF082F49);
  static const _skyTextDark = Color(0xFFE0F2FE);
  static const _skyAccent = Color(0xFF0369A1);
  static const _skyAccentDark = Color(0xFF7DD3FC);

  @override
  Widget build(BuildContext context) {
    final contenu = (text ?? '').trim();
    if (contenu.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final prep = role == NoteRole.preparateur;
    final bordure = prep ? _amber : _sky;
    final fond = prep ? (dark ? _amberBgDark : _amberBg) : (dark ? _skyBgDark : _skyBg);
    final texte = prep ? (dark ? _amberTextDark : _amberText) : (dark ? _skyTextDark : _skyText);
    final accent = prep ? (dark ? _amberAccentDark : _amberAccent) : (dark ? _skyAccentDark : _skyAccent);
    // Bordure gauche épaisse dessinée comme une barre : une `Border` aux
    // côtés de couleurs différentes ne peut pas porter de borderRadius
    // (assertion Flutter), ce qui cassait le rendu de la carte.
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bordure.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: bordure),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 6 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          prep ? Icons.assignment_outlined : Icons.local_shipping_outlined,
                          size: compact ? 14 : 16,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            prep ? 'NOTE POUR LE PRÉPARATEUR' : 'NOTE POUR LE LIVREUR',
                            style: TextStyle(
                              fontSize: compact ? 10 : 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contenu,
                      style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: texte,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
