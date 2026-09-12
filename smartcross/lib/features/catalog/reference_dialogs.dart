import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/permissions.dart';
import '../../models/catalog.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;
import 'stock_adjust_dialog.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

double? _parseNumber(String raw) => double.tryParse(raw.trim().replaceAll(',', '.'));

/// Miniature de la photo produit — image réseau (URL absolue renvoyée par
/// le serializer) ou fichier local fraîchement choisi ; sinon le même
/// carré bordé + icône « colis » grisée que le web (`Package`).
class CatalogPhoto extends StatelessWidget {
  const CatalogPhoto({super.key, this.url, this.localPath, this.size = 32});

  final String? url;
  final String? localPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(size >= 64 ? 10 : 6),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Icon(Icons.inventory_2_outlined, size: size / 2, color: scheme.onSurfaceVariant),
        );

    Widget? image;
    if (localPath != null) {
      image = Image.file(File(localPath!), width: size, height: size, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      image = Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }
    if (image == null) return placeholder();
    return ClipRRect(borderRadius: BorderRadius.circular(size >= 64 ? 10 : 6), child: image);
  }
}

/// Ligne « Marge estimée : X / unité » — vert si >= 0, rouge sinon ; rien
/// tant que les deux prix ne sont pas saisis.
class _MarginLine extends StatelessWidget {
  const _MarginLine({required this.prixAchat, required this.prixVente});

  final String prixAchat;
  final String prixVente;

  @override
  Widget build(BuildContext context) {
    if (prixAchat.trim().isEmpty || prixVente.trim().isEmpty) return const SizedBox.shrink();
    final achat = _parseNumber(prixAchat);
    final vente = _parseNumber(prixVente);
    if (achat == null || vente == null) return const SizedBox.shrink();
    final margin = vente - achat;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Marge estimée : ${arFmt(margin)} / unité',
        style: TextStyle(fontSize: 12, color: margin >= 0 ? Colors.green : Colors.red),
      ),
    );
  }
}

Future<XFile?> _pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);
}

// =============================================================================
// Nouvelle référence
// =============================================================================

/// Ouvre le formulaire « Nouvelle référence produit » (gérant). Renvoie
/// `true` si une référence a été créée.
Future<bool> showCreateReferenceDialog(BuildContext context) async {
  final created = await showDialog<bool>(context: context, builder: (_) => const CreateReferenceDialog());
  return created ?? false;
}

class _VariantDraft {
  _VariantDraft({required this.couleur, required this.stock, required this.seuil});
  final String couleur;
  final int stock;
  final int seuil;
}

/// Réplique de `CreateReferenceDialog` (products/page.tsx) : Catégorie →
/// Sous-type → Marque → Référence, prix (marge estimée), photo optionnelle,
/// et le stock initial selon la catégorie — variantes couleur empilées
/// localement, OU une seule quantité (variante « Standard ») pour une
/// catégorie « sans couleurs ». Création rapide d'un sous-type manquant.
class CreateReferenceDialog extends ConsumerStatefulWidget {
  const CreateReferenceDialog({super.key});

  @override
  ConsumerState<CreateReferenceDialog> createState() => _CreateReferenceDialogState();
}

class _CreateReferenceDialogState extends ConsumerState<CreateReferenceDialog> {
  final _nameController = TextEditingController();
  final _prixAchatController = TextEditingController();
  final _prixVenteController = TextEditingController();
  final _variantStockController = TextEditingController();
  final _variantSeuilController = TextEditingController();
  final _simpleStockController = TextEditingController();
  final _simpleSeuilController = TextEditingController(text: '1');
  final _newTypeController = TextEditingController();

  int? _categoryId;
  int? _typeId;
  int? _brandId;
  int? _variantColorId;
  final List<_VariantDraft> _variants = [];
  XFile? _photoFile;
  bool _submitting = false;
  bool _creatingType = false;

  @override
  void dispose() {
    _nameController.dispose();
    _prixAchatController.dispose();
    _prixVenteController.dispose();
    _variantStockController.dispose();
    _variantSeuilController.dispose();
    _simpleStockController.dispose();
    _simpleSeuilController.dispose();
    _newTypeController.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    final file = await _pickPhoto(context);
    if (file != null && mounted) setState(() => _photoFile = file);
  }

  Future<void> _createType() async {
    final nom = _newTypeController.text.trim();
    if (_categoryId == null || nom.isEmpty) return;
    setState(() => _creatingType = true);
    try {
      final created = await ref.read(typesProvider.notifier).create(_categoryId!, nom);
      if (!mounted) return;
      _toast(context, 'Sous-type créé');
      _newTypeController.clear();
      setState(() => _typeId = created.id);
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    } finally {
      if (mounted) setState(() => _creatingType = false);
    }
  }

  void _addVariant() {
    final colors = ref.read(colorsProvider).value ?? const <ProductColor>[];
    final color = colors.firstWhereOrNull((c) => c.id == _variantColorId);
    if (color == null) return;
    if (_variants.any((v) => v.couleur == color.nom)) {
      _toast(context, 'Cette couleur est déjà dans la liste');
      return;
    }
    setState(() {
      _variants.add(_VariantDraft(
        couleur: color.nom,
        stock: int.tryParse(_variantStockController.text.trim()) ?? 0,
        seuil: int.tryParse(_variantSeuilController.text.trim()) ?? 1,
      ));
      _variantColorId = null;
      _variantStockController.clear();
      _variantSeuilController.clear();
    });
  }

  void _removeVariant(String couleur) {
    setState(() => _variants.removeWhere((v) => v.couleur == couleur));
  }

  Future<void> _submit(bool avecCouleurs) async {
    if (_typeId == null || _brandId == null || _nameController.text.trim().isEmpty || _prixVenteController.text.trim().isEmpty) {
      _toast(context, 'Tous les champs sont requis');
      return;
    }
    final prixVente = _parseNumber(_prixVenteController.text);
    if (prixVente == null) {
      _toast(context, 'Tous les champs sont requis');
      return;
    }
    final prixAchat = _parseNumber(_prixAchatController.text) ?? 0;
    setState(() => _submitting = true);
    try {
      final notifier = ref.read(referencesProvider.notifier);
      final created = await notifier.createReference(
        typeId: _typeId!,
        brandId: _brandId!,
        referenceName: _nameController.text.trim(),
        prixAchat: prixAchat,
        prixVente: prixVente,
      );
      if (_photoFile != null) {
        await notifier.uploadPhoto(created.id, _photoFile!.path);
      }
      final variantsToCreate = avecCouleurs
          ? _variants
          : [
              _VariantDraft(
                couleur: 'Standard',
                stock: int.tryParse(_simpleStockController.text.trim()) ?? 0,
                seuil: int.tryParse(_simpleSeuilController.text.trim()) ?? 1,
              ),
            ];
      for (final v in variantsToCreate) {
        await notifier.createVariant(
          productReferenceId: created.id,
          couleur: v.couleur,
          stockActuel: v.stock,
          seuilAlerte: v.seuil,
        );
      }
      if (!mounted) return;
      _toast(context, 'Référence créée');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur lors de la création'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final types = ref.watch(typesProvider).value ?? const <ProductType>[];
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    final colors = ref.watch(colorsProvider).value ?? const <ProductColor>[];
    final typesForCategory = types.where((t) => t.categoryId == _categoryId).toList();
    final selectedCategory = categories.firstWhereOrNull((c) => c.id == _categoryId);
    // Certaines catégories (chargeur, écouteur…) n'ont pas de déclinaison
    // couleur — une seule variante « Standard » avec une quantité directe.
    final avecCouleurs = selectedCategory?.avecCouleurs ?? true;
    final totalUnits = _variants.fold<int>(0, (s, v) => s + v.stock);

    return AlertDialog(
      title: const Text('Nouvelle référence produit'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catégorie → Sous-type → Marque → Référence (§8 du cahier des charges).',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Catégorie', hintText: 'Choisir'),
                items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                onChanged: (v) => setState(() {
                  _categoryId = v;
                  _typeId = null;
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _brandId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Marque', hintText: 'Choisir'),
                items: [for (final b in brands) DropdownMenuItem(value: b.id, child: Text(b.nom))],
                onChanged: (v) => setState(() => _brandId = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Référence (modèle)', hintText: 'Ex: A16, S25 Ultra'),
              ),
              if (_categoryId != null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  // La liste change avec la catégorie : la clé force le
                  // champ à repartir de la valeur courante (null).
                  key: ValueKey('type-$_categoryId-$_typeId'),
                  initialValue: _typeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sous-type', hintText: 'Choisir un sous-type'),
                  items: [for (final t in typesForCategory) DropdownMenuItem(value: t.id, child: Text(t.nom))],
                  onChanged: (v) => setState(() => _typeId = v),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTypeController,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(isDense: true, hintText: 'Nouveau sous-type (ex: MAGSAFE)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _creatingType ? null : _createType, child: const Text('Créer')),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _prixAchatController,
                      decoration: const InputDecoration(labelText: 'Prix actuel (Ar)', hintText: '0'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _prixVenteController,
                      decoration: const InputDecoration(labelText: 'Prix de vente (Ar)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              _MarginLine(prixAchat: _prixAchatController.text, prixVente: _prixVenteController.text),
              const SizedBox(height: 12),
              Text('Photo (optionnel)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (_photoFile != null) ...[
                    CatalogPhoto(localPath: _photoFile!.path, size: 96),
                    const SizedBox(width: 10),
                  ],
                  OutlinedButton.icon(
                    onPressed: _choosePhoto,
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: Text(_photoFile == null ? 'Choisir une photo' : 'Changer la photo'),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (avecCouleurs) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Variantes (couleurs)', style: theme.textTheme.labelLarge),
                    if (_variants.isNotEmpty)
                      Text(
                        '${_variants.length} couleur(s) · $totalUnits unité(s)',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: ValueKey('variant-color-$_variantColorId'),
                  initialValue: _variantColorId,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, labelText: 'Couleur', hintText: 'Choisir'),
                  items: [for (final c in colors) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                  onChanged: (v) => setState(() => _variantColorId = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _variantStockController,
                        decoration: const InputDecoration(isDense: true, labelText: 'Nombre', hintText: '0'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _variantSeuilController,
                        decoration: const InputDecoration(isDense: true, labelText: "Seuil d'alerte", hintText: '1'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _variantColorId == null ? null : _addVariant,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ajouter'),
                  ),
                ),
                if (_variants.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in _variants)
                        Chip(
                          label: Text('${v.couleur} · ${v.stock} (seuil ${v.seuil})'),
                          onDeleted: () => _removeVariant(v.couleur),
                        ),
                    ],
                  ),
                ],
              ] else ...[
                Text('Stock', style: theme.textTheme.labelLarge),
                Text(
                  'Catégorie sans couleurs — une seule quantité pour cette référence.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _simpleStockController,
                        decoration: const InputDecoration(isDense: true, labelText: 'Quantité en stock', hintText: '0'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _simpleSeuilController,
                        decoration: const InputDecoration(isDense: true, labelText: "Seuil d'alerte", hintText: '1'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _submitting ? null : () => _submit(avecCouleurs),
          child: Text(_submitting ? 'Création…' : 'Créer la référence'),
        ),
      ],
    );
  }
}

// =============================================================================
// Détail / modification d'une référence + variantes
// =============================================================================

/// Ouvre la fiche produit complète d'une référence (clic sur une carte ou
/// bouton « Modifier ») — en lecture seule pour un non-gérant.
Future<void> showProductDetailDialog(BuildContext context, int referenceId) {
  return showDialog<void>(context: context, builder: (_) => ProductDetailDialog(referenceId: referenceId));
}

/// Réplique de `ProductDetailDialog` (products/page.tsx) : identité
/// (catégorie → sous-type → marque → référence), prix/marge, photo, statut
/// actif/inactif ET gestion des variantes (couleurs) au même endroit —
/// ajuster le stock, supprimer une couleur, en ajouter une (avec création
/// rapide d'une couleur manquante).
///
/// Relit la référence dans [referencesProvider] pour rester à jour après
/// chaque action tant que le dialog reste ouvert.
class ProductDetailDialog extends ConsumerStatefulWidget {
  const ProductDetailDialog({super.key, required this.referenceId});

  final int referenceId;

  @override
  ConsumerState<ProductDetailDialog> createState() => _ProductDetailDialogState();
}

class _ProductDetailDialogState extends ConsumerState<ProductDetailDialog> {
  final _nameController = TextEditingController();
  final _prixAchatController = TextEditingController();
  final _prixVenteController = TextEditingController();
  final _newStockController = TextEditingController();
  final _newSeuilController = TextEditingController();
  final _newColorController = TextEditingController();

  int? _categoryId;
  int? _typeId;
  int? _brandId;
  bool _actif = true;
  XFile? _photoFile;
  int? _variantColorId;
  bool _submitting = false;
  bool _addingVariant = false;
  bool _creatingColor = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _prixAchatController.dispose();
    _prixVenteController.dispose();
    _newStockController.dispose();
    _newSeuilController.dispose();
    _newColorController.dispose();
    super.dispose();
  }

  /// Pré-remplissage depuis l'objet référence (catégorie déduite du
  /// sous-type courant) — une seule fois, à l'ouverture.
  void _initFrom(ProductReference reference, List<ProductType> types) {
    if (!_initialized) {
      _initialized = true;
      _typeId = reference.typeId;
      _brandId = reference.brandId;
      _nameController.text = reference.referenceName;
      _prixAchatController.text = _formatPrice(reference.prixAchat);
      _prixVenteController.text = _formatPrice(reference.prixVente);
      _actif = reference.actif;
    }
    // La catégorie n'est pas portée par la référence : déduite du sous-type
    // courant dès que la liste des sous-types est disponible.
    if (_categoryId == null && types.isNotEmpty) {
      _categoryId = types.firstWhereOrNull((t) => t.id == (_typeId ?? reference.typeId))?.categoryId;
    }
  }

  static String _formatPrice(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  Future<void> _choosePhoto() async {
    final file = await _pickPhoto(context);
    if (file != null && mounted) setState(() => _photoFile = file);
  }

  Future<void> _submit(ProductReference reference) async {
    if (_nameController.text.trim().isEmpty || _prixVenteController.text.trim().isEmpty) {
      _toast(context, 'Champs requis manquants');
      return;
    }
    final prixVente = _parseNumber(_prixVenteController.text);
    if (prixVente == null) {
      _toast(context, 'Champs requis manquants');
      return;
    }
    setState(() => _submitting = true);
    try {
      final notifier = ref.read(referencesProvider.notifier);
      await notifier.updateReference(
        reference.id,
        typeId: _typeId ?? reference.typeId,
        brandId: _brandId ?? reference.brandId,
        referenceName: _nameController.text.trim(),
        prixAchat: _parseNumber(_prixAchatController.text) ?? 0,
        prixVente: prixVente,
        actif: _actif,
      );
      if (_photoFile != null) {
        await notifier.uploadPhoto(reference.id, _photoFile!.path);
      }
      if (!mounted) return;
      _toast(context, 'Référence mise à jour');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur lors de la mise à jour'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _createColor() async {
    final nom = _newColorController.text.trim();
    if (nom.isEmpty) return;
    setState(() => _creatingColor = true);
    try {
      final created = await ref.read(colorsProvider.notifier).create(nom);
      if (!mounted) return;
      _toast(context, 'Couleur créée');
      _newColorController.clear();
      setState(() => _variantColorId = created.id);
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    } finally {
      if (mounted) setState(() => _creatingColor = false);
    }
  }

  Future<void> _addVariant(ProductReference reference) async {
    final colors = ref.read(colorsProvider).value ?? const <ProductColor>[];
    final color = colors.firstWhereOrNull((c) => c.id == _variantColorId);
    if (color == null) {
      _toast(context, 'Choisissez une couleur');
      return;
    }
    setState(() => _addingVariant = true);
    try {
      await ref.read(referencesProvider.notifier).createVariant(
            productReferenceId: reference.id,
            couleur: color.nom,
            stockActuel: int.tryParse(_newStockController.text.trim()) ?? 0,
            seuilAlerte: int.tryParse(_newSeuilController.text.trim()) ?? 1,
          );
      if (!mounted) return;
      _toast(context, 'Variante ajoutée');
      setState(() {
        _variantColorId = null;
        _newStockController.clear();
        _newSeuilController.clear();
      });
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    } finally {
      if (mounted) setState(() => _addingVariant = false);
    }
  }

  Future<void> _confirmDeleteVariant(ProductVariant variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Supprimer la couleur ${variant.couleur} ?'),
        content: const Text('Cette variante et son historique de stock seront supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(referencesProvider.notifier).deleteVariant(variant.id);
      if (mounted) _toast(context, 'Variante supprimée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Suppression impossible'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final canEdit = ref.watch(authProvider.select((a) => a.user?.isGerant ?? false));
    final references = ref.watch(referencesProvider).value ?? const <ProductReference>[];
    final reference = references.firstWhereOrNull((r) => r.id == widget.referenceId);
    if (reference == null) {
      // Supprimée entre-temps (ou par un autre poste) : plus rien à montrer.
      return AlertDialog(
        title: const Text('Référence introuvable'),
        content: const Text('Cette référence n\'existe plus dans le catalogue.'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
      );
    }
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final types = ref.watch(typesProvider).value ?? const <ProductType>[];
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    final colors = ref.watch(colorsProvider).value ?? const <ProductColor>[];
    _initFrom(reference, types);

    final typesForCategory = _categoryId == null ? types : types.where((t) => t.categoryId == _categoryId).toList();
    final usedColors = reference.variants.map((v) => v.couleur).toSet();
    final availableColors = colors.where((c) => !usedColors.contains(c.nom)).toList();
    final stockTotal = reference.variants.fold<int>(0, (s, v) => s + v.stockActuel);
    final productLabel = '${reference.brandName} ${reference.referenceName}';

    return AlertDialog(
      title: Text(productLabel),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catégorie → Sous-type → Marque → Référence, prix, photo et variantes (§8 du cahier des charges).',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              // ---- Identité, prix, photo, statut ------------------------
              DropdownButtonFormField<int>(
                key: ValueKey('detail-cat-$_categoryId'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Catégorie', hintText: 'Choisir une catégorie'),
                items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                onChanged: canEdit
                    ? (v) => setState(() {
                          _categoryId = v;
                          _typeId = null;
                        })
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                key: ValueKey('detail-type-$_categoryId-$_typeId'),
                initialValue: _typeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sous-type', hintText: 'Choisir un sous-type'),
                items: [for (final t in typesForCategory) DropdownMenuItem(value: t.id, child: Text(t.nom))],
                onChanged: canEdit ? (v) => setState(() => _typeId = v) : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _brandId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Marque'),
                items: [for (final b in brands) DropdownMenuItem(value: b.id, child: Text(b.nom))],
                onChanged: canEdit ? (v) => setState(() => _brandId = v) : null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                enabled: canEdit,
                decoration: const InputDecoration(labelText: 'Référence (modèle)'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Prix actuel (achat) : affiché UNIQUEMENT au gérant.
                  if (canEdit) ...[
                    Expanded(
                      child: TextField(
                        controller: _prixAchatController,
                        decoration: const InputDecoration(labelText: 'Prix actuel (Ar)'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _prixVenteController,
                      enabled: canEdit,
                      decoration: const InputDecoration(labelText: 'Prix de vente (Ar)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (canEdit) _MarginLine(prixAchat: _prixAchatController.text, prixVente: _prixVenteController.text),
              const SizedBox(height: 12),
              Text('Photo', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(
                children: [
                  CatalogPhoto(url: reference.photo, localPath: _photoFile?.path, size: 64),
                  const SizedBox(width: 10),
                  if (canEdit)
                    OutlinedButton.icon(
                      onPressed: _choosePhoto,
                      icon: const Icon(Icons.photo_outlined, size: 18),
                      label: Text(_photoFile == null ? 'Choisir une photo' : 'Changer la photo'),
                    ),
                ],
              ),
              if (canEdit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    _actif
                        ? FilledButton(onPressed: () => setState(() => _actif = false), child: const Text('Active'))
                        : OutlinedButton(onPressed: () => setState(() => _actif = true), child: const Text('Inactive')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Inactive = invisible dans la recherche de commande.',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _submit(reference),
                    child: Text(_submitting ? 'Enregistrement…' : 'Enregistrer les informations'),
                  ),
                ),
              ],
              const Divider(height: 28),
              // ---- Variantes (couleurs) ---------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Variantes (${reference.variants.length})', style: theme.textTheme.titleSmall),
                  Text('Stock total : $stockTotal', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              ),
              const SizedBox(height: 8),
              if (reference.variants.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('Aucune couleur pour cette référence.', style: TextStyle(color: muted)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final v in reference.variants)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(v.couleur, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    Text(
                                      'Stock: ${v.stockActuel} · Seuil: ${v.seuilAlerte}',
                                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              if (canEdit) ...[
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  onPressed: () => showAdjustStockDialog(
                                    context,
                                    variantId: v.id,
                                    productLabel: productLabel,
                                    couleur: v.couleur,
                                    stockActuel: v.stockActuel,
                                    seuilAlerte: v.seuilAlerte,
                                  ),
                                  child: const Text('Ajuster'),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer la couleur',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  onPressed: () => _confirmDeleteVariant(v),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              if (canEdit) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ajouter une couleur', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        key: ValueKey('add-color-$_variantColorId-${availableColors.length}'),
                        initialValue: availableColors.any((c) => c.id == _variantColorId) ? _variantColorId : null,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true, labelText: 'Couleur', hintText: 'Couleur'),
                        items: [for (final c in availableColors) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                        onChanged: (v) => setState(() => _variantColorId = v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newStockController,
                              decoration: const InputDecoration(isDense: true, labelText: 'Stock initial', hintText: '0'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _newSeuilController,
                              decoration: const InputDecoration(isDense: true, labelText: "Seuil d'alerte", hintText: '1'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (_variantColorId == null || _addingVariant) ? null : () => _addVariant(reference),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Ajouter'),
                        ),
                      ),
                      const Divider(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newColorController,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(isDense: true, hintText: 'Nouvelle couleur (ex: Bleu)'),
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(onPressed: _creatingColor ? null : _createColor, child: const Text('Créer')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
      ],
    );
  }
}
