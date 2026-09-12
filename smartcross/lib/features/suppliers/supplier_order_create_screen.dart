import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/permissions.dart';
import '../../data/repositories/catalog_repository.dart' show catalogErrorMessage;
import '../../models/catalog.dart';
import '../../models/magasin.dart';
import '../../models/supplier.dart';
import '../../state/auth_provider.dart';
import '../../state/stores_provider.dart';
import '../../state/suppliers_provider.dart';
import 'supplier_status.dart';

/// Une ligne ajoutée au formulaire (`Line` du web : key, variant_id, label,
/// quantite). Les doublons d'une même variante sont autorisés, la
/// suppression se fait par index.
class _Line {
  _Line({required this.variantId, required this.label, required this.quantite});
  final int variantId;
  final String label;
  final int quantite;
}

/// Option du Select « Couleur » : `<marque> <référence> (<couleur>)`.
class _VariantOption {
  const _VariantOption({required this.id, required this.label, required this.stock});
  final int id;
  final String label;
  final int stock;
}

/// Écran « Nouvelle commande fournisseur » — équivalent du dialog
/// `CreateSupplierOrderDialog` (frontend/app/(app)/suppliers/page.tsx) :
/// description + 3 montants (prix fournisseur, fret/import, douane), bloc
/// « Ajouter une ligne » (marque, catégorie, recherche, couleur, quantité),
/// liste des lignes, récapitulatif calculé localement, « Annuler » /
/// « Créer ».
///
/// Ajout Flutter : un admin possédant PLUSIEURS magasins doit choisir le
/// magasin destinataire (le web n'envoie pas `magasin_id` et reçoit un 400
/// « Ce champ est requis (plusieurs magasins accessibles). »).
class SupplierOrderCreateScreen extends ConsumerStatefulWidget {
  const SupplierOrderCreateScreen({super.key});

  @override
  ConsumerState<SupplierOrderCreateScreen> createState() => _SupplierOrderCreateScreenState();
}

class _SupplierOrderCreateScreenState extends ConsumerState<SupplierOrderCreateScreen> {
  final _descController = TextEditingController();
  final _prixController = TextEditingController(text: '0');
  final _fretController = TextEditingController(text: '0');
  final _douaneController = TextEditingController(text: '0');
  final _searchController = TextEditingController();
  final _qtyController = TextEditingController();

  int? _magasinId;
  int? _brandId;
  int? _categoryId;
  int? _variantId;
  String _variantSearch = '';
  final List<_Line> _lines = [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _descController.dispose();
    _prixController.dispose();
    _fretController.dispose();
    _douaneController.dispose();
    _searchController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// `Number(x || 0)` du web.
  double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  int get _totalQty => _lines.fold(0, (sum, l) => sum + l.quantite);
  double get _coutTotal => _num(_prixController) + _num(_fretController) + _num(_douaneController);
  double get _coutUnitaire => _totalQty > 0 ? _coutTotal / _totalQty : 0;

  SupplierReferencesFilter get _filter => (brandId: _brandId, categoryId: _categoryId, magasinId: _magasinId);

  List<_VariantOption> _options(List<ProductReference> references) => [
        for (final r in references)
          for (final v in r.variants)
            _VariantOption(id: v.id, label: '${r.brandName} ${r.referenceName} (${v.couleur})', stock: v.stockActuel),
      ];

  /// Filtre CLIENT, insensible à la casse, sur le libellé complet.
  List<_VariantOption> _filteredOptions(List<_VariantOption> options) {
    final term = _variantSearch.trim().toLowerCase();
    if (term.isEmpty) return options;
    return options.where((o) => o.label.toLowerCase().contains(term)).toList();
  }

  /// `addLine()` du web.
  void _addLine(List<_VariantOption> options) {
    if (_variantId == null) {
      _snack('Choisissez une couleur');
      return;
    }
    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty < 1) {
      _snack('Quantité invalide');
      return;
    }
    _VariantOption? found;
    for (final o in options) {
      if (o.id == _variantId) found = o;
    }
    final option = found;
    if (option == null) return;
    setState(() {
      _lines.add(_Line(variantId: option.id, label: option.label, quantite: qty));
      _variantId = null;
      _qtyController.clear();
    });
  }

  void _onMagasinChanged(int? id) {
    if (id == _magasinId) return;
    setState(() {
      _magasinId = id;
      _brandId = null;
      _categoryId = null;
      _variantId = null;
      if (_lines.isNotEmpty) {
        _lines.clear();
        _snack('Lignes réinitialisées : le magasin a changé');
      }
    });
  }

  /// `submit()` du web : au moins une ligne, POST, toast succès, retour à la
  /// liste (fermeture du dialog + `fetchOrders()`). En cas d'erreur l'écran
  /// reste ouvert et les champs sont conservés.
  Future<void> _submit({required bool needsMagasin}) async {
    if (_lines.isEmpty) {
      _snack('Ajoutez au moins une ligne');
      return;
    }
    if (needsMagasin && _magasinId == null) {
      _snack('Choisissez le magasin destinataire');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(supplierOrdersProvider.notifier).create(
            description: _descController.text.trim(),
            prixFournisseur: _num(_prixController),
            fretImport: _num(_fretController),
            douane: _num(_douaneController),
            lines: [for (final l in _lines) SupplierOrderLineDraft(productVariant: l.variantId, quantite: l.quantite)],
            magasinId: _magasinId,
          );
      if (!mounted) return;
      _snack('Commande fournisseur créée');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/suppliers');
      }
    } catch (e) {
      final message = catalogErrorMessage(e, 'Erreur');
      if (mounted) setState(() => _error = message);
      _snack(message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authProvider).user;
    // Un admin dont le compte n'expose pas de magasin unique possède
    // plusieurs magasins : le serveur exige `magasin_id`.
    final needsMagasin = user != null && user.isAdmin && user.magasinId == null;
    final storesAsync = needsMagasin ? ref.watch(storesProvider) : null;
    final stores = storesAsync?.value ?? const <Magasin>[];
    if (needsMagasin && _magasinId == null && stores.length == 1) {
      // Un seul magasin finalement accessible : présélection silencieuse.
      _magasinId = stores.first.magasinId;
    }
    final catalogLocked = needsMagasin && _magasinId == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle commande fournisseur')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '§7.6 — coût de revient réel calculé automatiquement.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
            const SizedBox(height: 12),
          ],
          if (needsMagasin) ...[
            _MagasinField(
              storesAsync: storesAsync!,
              value: _magasinId,
              onChanged: _onMagasinChanged,
              onRetry: () => ref.read(storesProvider.notifier).refresh(),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _descController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Ex: réappro coques Samsung — lot Chine mars',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _amountField(_prixController, 'Prix fournisseur (Ar)')),
              const SizedBox(width: 10),
              Expanded(child: _amountField(_fretController, 'Fret/import (Ar)')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _amountField(_douaneController, 'Douane (Ar)')),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 16),
          _AddLineBlock(
            filter: _filter,
            locked: catalogLocked,
            brandId: _brandId,
            categoryId: _categoryId,
            variantId: _variantId,
            searchController: _searchController,
            qtyController: _qtyController,
            onBrandChanged: (v) => setState(() {
              _brandId = v;
              _variantId = null;
            }),
            onCategoryChanged: (v) => setState(() {
              _categoryId = v;
              _variantId = null;
            }),
            onSearchChanged: (v) => setState(() => _variantSearch = v),
            onVariantSelected: (v) => setState(() => _variantId = v),
            optionsOf: _options,
            filterOptions: _filteredOptions,
            onAdd: _addLine,
          ),
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < _lines.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text('${_lines[i].label} x${_lines[i].quantite}')),
                    IconButton(
                      tooltip: 'Supprimer la ligne',
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                      onPressed: () => setState(() => _lines.removeAt(i)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Coût total ($_totalQty u.)'),
              Text(supplierAr(_coutTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Coût unitaire estimé'),
              Text(supplierAr(_coutUnitaire), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/suppliers');
                          }
                        },
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : () => _submit(needsMagasin: needsMagasin),
                  child: Text(_submitting ? 'Création…' : 'Créer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
    );
  }
}

/// Sélecteur du magasin destinataire (admin multi-magasins uniquement).
class _MagasinField extends StatelessWidget {
  const _MagasinField({required this.storesAsync, required this.value, required this.onChanged, required this.onRetry});

  final AsyncValue<List<Magasin>> storesAsync;
  final int? value;
  final ValueChanged<int?> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (storesAsync.isLoading && !storesAsync.hasValue) {
      return const Row(
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Chargement des magasins…'),
        ],
      );
    }
    if (storesAsync.hasError && !storesAsync.hasValue) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Magasins indisponibles : ${ApiClient.messageFromError(storesAsync.error!)}',
              style: TextStyle(color: scheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      );
    }
    final stores = storesAsync.value ?? const <Magasin>[];
    return _DropdownField<int?>(
      label: 'Magasin destinataire',
      value: value,
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Choisir un magasin')),
        for (final s in stores) DropdownMenuItem<int?>(value: s.magasinId, child: Text(s.shopName, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Bloc « Ajouter une ligne » : Marque, Catégorie, Rechercher, Couleur,
/// Quantité, bouton « Ajouter ». Les références sont rechargées à chaque
/// changement de marque/catégorie (provider famille sur le filtre).
class _AddLineBlock extends ConsumerWidget {
  const _AddLineBlock({
    required this.filter,
    required this.locked,
    required this.brandId,
    required this.categoryId,
    required this.variantId,
    required this.searchController,
    required this.qtyController,
    required this.onBrandChanged,
    required this.onCategoryChanged,
    required this.onSearchChanged,
    required this.onVariantSelected,
    required this.optionsOf,
    required this.filterOptions,
    required this.onAdd,
  });

  final SupplierReferencesFilter filter;

  /// Vrai tant qu'un admin multi-magasins n'a pas choisi le magasin.
  final bool locked;
  final int? brandId;
  final int? categoryId;
  final int? variantId;
  final TextEditingController searchController;
  final TextEditingController qtyController;
  final ValueChanged<int?> onBrandChanged;
  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onVariantSelected;
  final List<_VariantOption> Function(List<ProductReference>) optionsOf;
  final List<_VariantOption> Function(List<_VariantOption>) filterOptions;
  final void Function(List<_VariantOption> options) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    if (locked) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Choisissez d\'abord le magasin destinataire pour ajouter des lignes.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final brandsAsync = ref.watch(supplierFormBrandsProvider(filter.magasinId));
    final categoriesAsync = ref.watch(supplierFormCategoriesProvider(filter.magasinId));
    final referencesAsync = ref.watch(supplierFormReferencesProvider(filter));
    final brands = brandsAsync.value ?? const <Brand>[];
    final categories = categoriesAsync.value ?? const <ProductCategory>[];
    final options = optionsOf(referencesAsync.value ?? const <ProductReference>[]);
    final filtered = filterOptions(options);
    _VariantOption? selected;
    for (final o in options) {
      if (o.id == variantId) selected = o;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Ajouter une ligne', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DropdownField<int?>(
                  label: 'Marque',
                  value: brandId,
                  loading: brandsAsync.isLoading && !brandsAsync.hasValue,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Toutes')),
                    for (final b in brands) DropdownMenuItem<int?>(value: b.id, child: Text(b.nom, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: onBrandChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownField<int?>(
                  label: 'Catégorie',
                  value: categoryId,
                  loading: categoriesAsync.isLoading && !categoriesAsync.hasValue,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Toutes')),
                    for (final c in categories) DropdownMenuItem<int?>(value: c.id, child: Text(c.nom, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: onCategoryChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Rechercher',
              hintText: 'Rechercher une référence ou couleur…',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),
          Text('Couleur', style: labelStyle),
          const SizedBox(height: 4),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(selected.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
                  IconButton(
                    tooltip: 'Désélectionner',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => onVariantSelected(null),
                  ),
                ],
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: referencesAsync.isLoading && !referencesAsync.hasValue
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : referencesAsync.hasError && !referencesAsync.hasValue
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                ApiClient.messageFromError(referencesAsync.error!),
                                style: TextStyle(color: scheme.error, fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: () => ref.invalidate(supplierFormReferencesProvider(filter)),
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('Aucun résultat', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final o = filtered[i];
                              final isSelected = o.id == variantId;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: scheme.primary.withValues(alpha: 0.08),
                                title: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text('Stock actuel : ${o.stock}', style: labelStyle),
                                trailing: isSelected ? Icon(Icons.check, color: scheme.primary, size: 18) : null,
                                onTap: () => onVariantSelected(o.id),
                              );
                            },
                          ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantité', hintText: 'Ex: 10', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: () => onAdd(options),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Select contrôlé (valeur pilotée par le parent, réinitialisable) habillé
/// comme un champ de formulaire.
class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.loading = false,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        suffixIcon: loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))) : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
