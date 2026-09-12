import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/catalog.dart';
import '../../state/catalog_provider.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Ouvre le formulaire « Nouvelle note » (gérant). Renvoie `true` si une
/// note a été enregistrée — l'appelant relance alors le rechargement
/// silencieux du catalogue (`onCreated → fetchAll(true)` côté web).
///
/// Chaque ouverture construit un nouvel état : tous les champs repartent
/// vides, comme le `useEffect([open])` du web qui remet le formulaire à
/// zéro à chaque `open`.
Future<bool> showProductNoteDialog(BuildContext context) async {
  final created = await showDialog<bool>(context: context, builder: (_) => const ProductNoteDialog());
  return created ?? false;
}

/// Réplique de `CreateNoteDialog` (products/page.tsx) : un produit repéré
/// mais pas encore au catalogue, à commander au fournisseur. Même
/// hiérarchie que la référence (catégorie, sous-type, marque, couleurs)
/// mais sans prix ni stock — rien n'est créé dans le catalogue lui-même.
class ProductNoteDialog extends ConsumerStatefulWidget {
  const ProductNoteDialog({super.key});

  @override
  ConsumerState<ProductNoteDialog> createState() => _ProductNoteDialogState();
}

class _ProductNoteDialogState extends ConsumerState<ProductNoteDialog> {
  final _nomController = TextEditingController();
  int? _categoryId;
  int? _typeId;
  int? _brandId;
  bool _avecCouleur = false;
  final List<String> _couleurs = [];
  int? _couleurId;
  bool _submitting = false;

  @override
  void dispose() {
    _nomController.dispose();
    super.dispose();
  }

  /// Ajoute le NOM de la couleur choisie (pas son id : `couleurs` est une
  /// liste de noms libres côté serveur), sans doublon, puis vide le
  /// sélecteur — `addCouleur` du web.
  void _addCouleur() {
    final colors = ref.read(colorsProvider).value ?? const <ProductColor>[];
    final color = colors.firstWhereOrNull((c) => c.id == _couleurId);
    if (color == null) return;
    setState(() {
      if (!_couleurs.contains(color.nom)) _couleurs.add(color.nom);
      _couleurId = null;
    });
  }

  void _removeCouleur(String nom) {
    setState(() => _couleurs.remove(nom));
  }

  Future<void> _submit() async {
    final nom = _nomController.text.trim();
    if (nom.isEmpty || _categoryId == null || _typeId == null) {
      _toast(context, 'Nom, catégorie et sous-type sont requis');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(productNotesProvider.notifier).create(
            nom: nom,
            categoryId: _categoryId!,
            typeId: _typeId!,
            brandId: _brandId,
            // Interrupteur éteint = sans couleur, même si des couleurs
            // avaient été ajoutées avant de l'éteindre (comme le web).
            couleurs: _avecCouleur ? List.of(_couleurs) : const [],
          );
      if (!mounted) return;
      _toast(context, 'Note enregistrée');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final types = ref.watch(typesProvider).value ?? const <ProductType>[];
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    final colors = ref.watch(colorsProvider).value ?? const <ProductColor>[];
    final typesForCategory = types.where((t) => t.categoryId == _categoryId).toList();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text('Nouvelle note')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Un produit à commander au fournisseur, pas encore au catalogue. Sans prix ni stock.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nomController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom du produit', hintText: 'Ex: Coque MagSafe iPhone 16'),
              ),
              const SizedBox(height: 10),
              // Catégorie et sous-type sont côte à côte sur le web (grille 2
              // colonnes) ; empilés ici pour que les noms et le libellé
              // « Catégorie d'abord » restent lisibles sur un téléphone.
              // Libellé toujours flottant : le texte d'attente (« Choisir »,
              // « Catégorie d'abord », « Aucune / inconnue ») reste visible
              // dans le champ vide, comme le placeholder du web.
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Catégorie',
                  hintText: 'Choisir',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                onChanged: (v) => setState(() {
                  _categoryId = v;
                  // Changer la catégorie remet le sous-type à zéro.
                  _typeId = null;
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                // La liste change avec la catégorie : la clé force le champ
                // à repartir de la valeur courante (null).
                key: ValueKey('note-type-$_categoryId'),
                initialValue: _typeId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Sous-type',
                  hintText: _categoryId != null ? 'Choisir' : 'Catégorie d\'abord',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                items: [for (final t in typesForCategory) DropdownMenuItem(value: t.id, child: Text(t.nom))],
                // Désactivé tant qu'aucune catégorie n'est choisie.
                onChanged: _categoryId == null ? null : (v) => setState(() => _typeId = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _brandId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Marque (facultatif)',
                  hintText: 'Aucune / inconnue',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                items: [for (final b in brands) DropdownMenuItem(value: b.id, child: Text(b.nom))],
                onChanged: (v) => setState(() => _brandId = v),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Avec couleur', style: theme.textTheme.labelLarge)),
                        Switch(value: _avecCouleur, onChanged: (v) => setState(() => _avecCouleur = v)),
                      ],
                    ),
                    if (_avecCouleur) ...[
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: ValueKey('note-color-$_couleurId'),
                              initialValue: _couleurId,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true, hintText: 'Choisir une couleur'),
                              items: [for (final c in colors) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                              onChanged: (v) => setState(() => _couleurId = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _couleurId == null ? null : _addCouleur,
                            style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero),
                            child: const Icon(Icons.add, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_couleurs.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in _couleurs)
                              Chip(
                                label: Text(c),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                deleteIcon: const Icon(Icons.close, size: 16),
                                deleteButtonTooltipMessage: 'Retirer $c',
                                onDeleted: () => _removeCouleur(c),
                              ),
                          ],
                        )
                      else
                        Text(
                          'Aucune couleur ajoutée (les couleurs se gèrent dans Paramètres › Couleurs).',
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Enregistrement…' : 'Enregistrer la note'),
        ),
      ],
    );
  }
}
