import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/catalog_provider.dart';
import '../../state/stock_provider.dart';

/// Ouvre le dialog « Ajuster le stock » d'une variante ; renvoie `true` si
/// un ajustement a été enregistré (l'appelant peut alors rafraîchir ce
/// qu'il affiche — le catalogue, lui, est déjà rechargé silencieusement).
Future<bool> showAdjustStockDialog(
  BuildContext context, {
  required int variantId,
  required String productLabel,
  required String couleur,
  required int stockActuel,
  required int seuilAlerte,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AdjustStockDialog(
      variantId: variantId,
      productLabel: productLabel,
      couleur: couleur,
      stockActuel: stockActuel,
      seuilAlerte: seuilAlerte,
    ),
  );
  return result ?? false;
}

/// Réplique de `AdjustStockDialog` (products/page.tsx) : entrée/sortie
/// manuelle d'une variante, réservée au gérant (§7.4 du cahier des charges).
///
/// * bascule Entrée / Sortie (Entrée par défaut) ;
/// * quantité (>= 1) — « Quantité requise » sinon ; aucun contrôle client
///   qu'une sortie ne dépasse pas le stock : le serveur tranche ;
/// * note optionnelle reprise dans l'historique des mouvements.
class AdjustStockDialog extends ConsumerStatefulWidget {
  const AdjustStockDialog({
    super.key,
    required this.variantId,
    required this.productLabel,
    required this.couleur,
    required this.stockActuel,
    required this.seuilAlerte,
  });

  final int variantId;

  /// « Marque Référence » — titre du dialog.
  final String productLabel;
  final String couleur;
  final int stockActuel;
  final int seuilAlerte;

  @override
  ConsumerState<AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends ConsumerState<AdjustStockDialog> {
  String _type = 'ENTREE';
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty < 1) {
      _toast('Quantité requise');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(referencesProvider.notifier).adjustStock(
            variantId: widget.variantId,
            type: _type,
            quantite: qty,
            note: _noteController.text.trim(),
          );
      // Les onglets Ruptures / Mouvements (et les écrans Alertes /
      // Mouvements) dérivent du même stock : on les invalide pour qu'ils
      // se rechargent à leur prochain affichage.
      ref.invalidate(rupturesProvider);
      ref.invalidate(movementsProvider(null));
      if (!mounted) return;
      _toast('Stock ajusté');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(catalogErrorMessage(e, 'Erreur'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return AlertDialog(
      title: Text('Ajuster le stock — ${widget.productLabel}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entrée/sortie manuelle réservée au gérant (§7.4 du cahier des charges).',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              // Bandeau récapitulatif : couleur + stock actuel + seuil.
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text('Couleur :', style: TextStyle(color: muted, fontSize: 13)),
                    Chip(
                      label: Text(widget.couleur),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(color: muted, fontSize: 13),
                        children: [
                          const TextSpan(text: 'Stock actuel : '),
                          TextSpan(
                            text: '${widget.stockActuel}',
                            style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                          ),
                          TextSpan(text: " · Seuil d'alerte : ${widget.seuilAlerte}"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Bascule Entrée / Sortie : deux boutons pleine largeur, l'actif
              // en style plein.
              Row(
                children: [
                  Expanded(
                    child: _type == 'ENTREE'
                        ? FilledButton.icon(
                            onPressed: () => setState(() => _type = 'ENTREE'),
                            icon: const Icon(Icons.arrow_circle_up_outlined, size: 18),
                            label: const Text('Entrée'),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => setState(() => _type = 'ENTREE'),
                            icon: const Icon(Icons.arrow_circle_up_outlined, size: 18),
                            label: const Text('Entrée'),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _type == 'SORTIE'
                        ? FilledButton.icon(
                            onPressed: () => setState(() => _type = 'SORTIE'),
                            icon: const Icon(Icons.arrow_circle_down_outlined, size: 18),
                            label: const Text('Sortie'),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => setState(() => _type = 'SORTIE'),
                            icon: const Icon(Icons.arrow_circle_down_outlined, size: 18),
                            label: const Text('Sortie'),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _qtyController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Quantité',
                  hintText: 'Stock actuel : ${widget.stockActuel}',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optionnel)',
                  hintText: 'Ex: correction inventaire',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitting ? null : _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Enregistrement…' : 'Confirmer'),
        ),
      ],
    );
  }
}
