import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../data/repositories/stock_repository.dart';
import '../../models/catalog.dart';
import '../../state/catalog_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

/// Module Catalogue (§8 README) : catégories/sous-types/marques/références
/// et leurs variantes couleur — le stock lui-même reste modifiable
/// uniquement via le module Stock (mouvements/ajustements).
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catalogue'),
          bottom: const TabBar(tabs: [Tab(text: 'Produits'), Tab(text: 'Configuration')]),
        ),
        body: const TabBarView(children: [_ReferencesTab(), _ConfigTab()]),
      ),
    );
  }
}

class _ReferencesTab extends ConsumerStatefulWidget {
  const _ReferencesTab();

  @override
  ConsumerState<_ReferencesTab> createState() => _ReferencesTabState();
}

class _ReferencesTabState extends ConsumerState<_ReferencesTab> {
  final _searchController = TextEditingController();
  String _search = '';
  int? _typeFilter;
  int? _brandFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(referencesProvider);
    final types = ref.watch(typesProvider).value ?? [];
    final brands = ref.watch(brandsProvider).value ?? [];

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(hintText: 'Rechercher (marque, référence)…', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FilterChip(label: 'Tous sous-types', selected: _typeFilter == null, onTap: () => setState(() => _typeFilter = null)),
                for (final t in types)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _FilterChip(label: t.nom, selected: _typeFilter == t.id, onTap: () => setState(() => _typeFilter = t.id)),
                  ),
                const SizedBox(width: 12),
                _FilterChip(label: 'Toutes marques', selected: _brandFilter == null, onTap: () => setState(() => _brandFilter = null)),
                for (final b in brands)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _FilterChip(label: b.nom, selected: _brandFilter == b.id, onTap: () => setState(() => _brandFilter = b.id)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (async) {
              AsyncData(:final value) => _buildList(value),
              AsyncError(:final error) => ErrorState(
                  message: ApiClient.messageFromError(error),
                  onRetry: () => ref.read(referencesProvider.notifier).refresh(),
                ),
              _ => const LoadingState(),
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddReferenceDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Référence'),
      ),
    );
  }

  Widget _buildList(List<ProductReference> all) {
    final filtered = all.where((r) {
      if (_typeFilter != null && r.typeId != _typeFilter) return false;
      if (_brandFilter != null && r.brandId != _brandFilter) return false;
      if (_search.isEmpty) return true;
      return r.referenceName.toLowerCase().contains(_search) || r.brandName.toLowerCase().contains(_search);
    }).toList();

    if (filtered.isEmpty) {
      return const EmptyState(message: 'Aucune référence pour cette sélection.', icon: Icons.style_outlined);
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(referencesProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (context, i) => _ReferenceTile(reference: filtered[i]),
      ),
    );
  }

  Future<void> _showAddReferenceDialog(BuildContext context, WidgetRef ref) async {
    final types = ref.read(typesProvider).value ?? [];
    final brands = ref.read(brandsProvider).value ?? [];
    if (types.isEmpty || brands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créez d\'abord une catégorie/sous-type et une marque (onglet Configuration).')),
      );
      return;
    }
    await showDialog<void>(context: context, builder: (_) => _AddReferenceDialog(types: types, brands: brands));
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

class _ReferenceTile extends ConsumerWidget {
  const _ReferenceTile({required this.reference});
  final ProductReference reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text('${reference.brandName} ${reference.referenceName}'),
        subtitle: Text('${reference.categoryName} / ${reference.typeName} — ${_ar(reference.prixVente)}${reference.actif ? '' : ' · inactive'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showDialog<void>(context: context, builder: (_) => _EditReferenceDialog(reference: reference)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDeleteReference(context, ref),
            ),
          ],
        ),
        children: [
          for (final v in reference.variants)
            ListTile(
              dense: true,
              title: Text(v.couleur),
              subtitle: Text('Stock : ${v.stockActuel} · Seuil : ${v.seuilAlerte}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StockLevelBadge(isRupture: v.isRupture, isStockBas: v.isStockBas),
                  IconButton(
                    icon: const Icon(Icons.tune, size: 18),
                    tooltip: 'Ajuster le stock',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _QuickAdjustDialog(variantId: v.id, label: '${reference.referenceName} — ${v.couleur}'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      final confirmed = await _confirm(context, 'Supprimer la variante "${v.couleur}" ?');
                      if (confirmed) await ref.read(referencesProvider.notifier).deleteVariant(v.id);
                    },
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => _AddVariantDialog(referenceId: reference.id)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter une couleur'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteReference(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(context, 'Supprimer "${reference.referenceName}" et ses variantes ?');
    if (confirmed) await ref.read(referencesProvider.notifier).deleteReference(reference.id);
  }
}

class _QuickAdjustDialog extends ConsumerStatefulWidget {
  const _QuickAdjustDialog({required this.variantId, required this.label});
  final int variantId;
  final String label;

  @override
  ConsumerState<_QuickAdjustDialog> createState() => _QuickAdjustDialogState();
}

class _QuickAdjustDialogState extends ConsumerState<_QuickAdjustDialog> {
  String _type = 'ENTREE';
  final _qtyController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) return;
    setState(() => _saving = true);
    try {
      await StockRepository().adjust(productVariantId: widget.variantId, type: _type, quantite: qty, note: _noteController.text.trim());
      ref.invalidate(referencesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ajuster : ${widget.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'ENTREE', label: Text('Entrée')), ButtonSegment(value: 'SORTIE', label: Text('Sortie'))],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: _qtyController, decoration: const InputDecoration(labelText: 'Quantité'), keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note (optionnel)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _EditReferenceDialog extends ConsumerStatefulWidget {
  const _EditReferenceDialog({required this.reference});
  final ProductReference reference;

  @override
  ConsumerState<_EditReferenceDialog> createState() => _EditReferenceDialogState();
}

class _EditReferenceDialogState extends ConsumerState<_EditReferenceDialog> {
  late final _nameController = TextEditingController(text: widget.reference.referenceName);
  late final _priceController = TextEditingController(text: widget.reference.prixVente.toStringAsFixed(0));
  late bool _actif = widget.reference.actif;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (price == null || _nameController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(referencesProvider.notifier).updateReference(
            widget.reference.id,
            referenceName: _nameController.text.trim(),
            prixVente: price,
            actif: _actif,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier la référence'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Référence')),
          const SizedBox(height: 10),
          TextField(controller: _priceController, decoration: const InputDecoration(labelText: 'Prix de vente (Ar)'), keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: const Text('Visible dans la recherche de commande'),
            value: _actif,
            onChanged: (v) => setState(() => _actif = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirmer'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Supprimer')),
      ],
    ),
  );
  return result ?? false;
}

class _AddReferenceDialog extends ConsumerStatefulWidget {
  const _AddReferenceDialog({required this.types, required this.brands});
  final List<ProductType> types;
  final List<Brand> brands;

  @override
  ConsumerState<_AddReferenceDialog> createState() => _AddReferenceDialogState();
}

class _AddReferenceDialogState extends ConsumerState<_AddReferenceDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  ProductType? _type;
  Brand? _brand;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_type == null || _brand == null || _nameController.text.trim().isEmpty) return;
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (price == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(referencesProvider.notifier).createReference(
            typeId: _type!.id,
            brandId: _brand!.id,
            referenceName: _nameController.text.trim(),
            prixVente: price,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle référence'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ProductType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Sous-type'),
            items: [for (final t in widget.types) DropdownMenuItem(value: t, child: Text(t.nom))],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Brand>(
            initialValue: _brand,
            decoration: const InputDecoration(labelText: 'Marque'),
            items: [for (final b in widget.brands) DropdownMenuItem(value: b, child: Text(b.nom))],
            onChanged: (v) => setState(() => _brand = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Référence (ex: A15, S25 Ultra)')),
          const SizedBox(height: 10),
          TextField(
            controller: _priceController,
            decoration: const InputDecoration(labelText: 'Prix de vente (Ar)'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Créer')),
      ],
    );
  }
}

class _AddVariantDialog extends ConsumerStatefulWidget {
  const _AddVariantDialog({required this.referenceId});
  final int referenceId;

  @override
  ConsumerState<_AddVariantDialog> createState() => _AddVariantDialogState();
}

class _AddVariantDialogState extends ConsumerState<_AddVariantDialog> {
  final _colorController = TextEditingController();
  final _thresholdController = TextEditingController(text: '5');
  bool _saving = false;

  @override
  void dispose() {
    _colorController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_colorController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(referencesProvider.notifier).createVariant(
            productReferenceId: widget.referenceId,
            couleur: _colorController.text.trim(),
            seuilAlerte: int.tryParse(_thresholdController.text) ?? 0,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle couleur'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _colorController, decoration: const InputDecoration(labelText: 'Couleur')),
          const SizedBox(height: 10),
          TextField(controller: _thresholdController, decoration: const InputDecoration(labelText: 'Seuil d\'alerte'), keyboardType: TextInputType.number),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Ajouter')),
      ],
    );
  }
}

class _ConfigTab extends ConsumerWidget {
  const _ConfigTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        _ConfigSection<ProductCategory>(title: 'Catégories', kind: _ConfigKind.category),
        SizedBox(height: 16),
        _ConfigSection<ProductType>(title: 'Sous-types', kind: _ConfigKind.type),
        SizedBox(height: 16),
        _ConfigSection<Brand>(title: 'Marques', kind: _ConfigKind.brand),
      ],
    );
  }
}

enum _ConfigKind { category, type, brand }

class _ConfigSection<T> extends ConsumerWidget {
  const _ConfigSection({required this.title, required this.kind});
  final String title;
  final _ConfigKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _showAddDialog(context, ref)),
              ],
            ),
            const SizedBox(height: 6),
            switch (kind) {
              _ConfigKind.category => _CategoryList(),
              _ConfigKind.type => _TypeList(),
              _ConfigKind.brand => _BrandList(),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    if (kind == _ConfigKind.category) {
      final controller = TextEditingController();
      final name = await _promptText(context, 'Nouvelle catégorie', controller, hint: 'ex : HOUSSE');
      if (name != null && name.isNotEmpty) {
        await ref.read(categoriesProvider.notifier).create(name, 0);
      }
    } else if (kind == _ConfigKind.brand) {
      final controller = TextEditingController();
      final name = await _promptText(context, 'Nouvelle marque', controller, hint: 'ex : Samsung');
      if (name != null && name.isNotEmpty) {
        await ref.read(brandsProvider.notifier).create(name);
      }
    } else {
      final categories = ref.read(categoriesProvider).value ?? [];
      if (categories.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez d\'abord une catégorie.')));
        return;
      }
      await showDialog<void>(context: context, builder: (_) => _AddTypeDialog(categories: categories));
    }
  }
}

Future<String?> _promptText(BuildContext context, String title, TextEditingController controller, {String? hint, String confirmLabel = 'Créer'}) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, decoration: InputDecoration(hintText: hint), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: Text(confirmLabel)),
      ],
    ),
  );
}

class _AddTypeDialog extends ConsumerStatefulWidget {
  const _AddTypeDialog({required this.categories});
  final List<ProductCategory> categories;

  @override
  ConsumerState<_AddTypeDialog> createState() => _AddTypeDialogState();
}

class _AddTypeDialogState extends ConsumerState<_AddTypeDialog> {
  final _nameController = TextEditingController();
  ProductCategory? _category;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau sous-type'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ProductCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Catégorie'),
            items: [for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c.nom))],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nom (ex : FLIP COVER)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _category == null || _nameController.text.trim().isEmpty
              ? null
              : () async {
                  await ref.read(typesProvider.notifier).create(_category!.id, _nameController.text.trim());
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

Future<void> _renamePrompt(BuildContext context, String title, String currentValue, Future<void> Function(String) onSave) async {
  final controller = TextEditingController(text: currentValue);
  final name = await _promptText(context, title, controller, confirmLabel: 'Enregistrer');
  if (name != null && name.isNotEmpty && name != currentValue) {
    await onSave(name);
  }
}

class _CategoryList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(categoriesProvider).value ?? [];
    if (list.isEmpty) return const Text('Aucune catégorie.');
    return Column(
      children: [
        for (final c in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(c.nom),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _renamePrompt(
                    context,
                    'Renommer la catégorie',
                    c.nom,
                    (name) => ref.read(categoriesProvider.notifier).rename(c.id, name),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    if (await _confirm(context, 'Supprimer la catégorie "${c.nom}" ?')) {
                      await ref.read(categoriesProvider.notifier).delete(c.id);
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TypeList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(typesProvider).value ?? [];
    if (list.isEmpty) return const Text('Aucun sous-type.');
    return Column(
      children: [
        for (final t in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(t.nom),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _renamePrompt(
                    context,
                    'Renommer le sous-type',
                    t.nom,
                    (name) => ref.read(typesProvider.notifier).rename(t.id, name),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    if (await _confirm(context, 'Supprimer le sous-type "${t.nom}" ?')) {
                      await ref.read(typesProvider.notifier).delete(t.id);
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BrandList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(brandsProvider).value ?? [];
    if (list.isEmpty) return const Text('Aucune marque.');
    return Column(
      children: [
        for (final b in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(b.nom),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _renamePrompt(
                    context,
                    'Renommer la marque',
                    b.nom,
                    (name) => ref.read(brandsProvider.notifier).rename(b.id, name),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    if (await _confirm(context, 'Supprimer la marque "${b.nom}" ?')) {
                      await ref.read(brandsProvider.notifier).delete(b.id);
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
