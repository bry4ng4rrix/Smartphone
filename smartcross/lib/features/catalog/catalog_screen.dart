import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../data/repositories/stock_repository.dart';
import '../../models/catalog.dart';
import '../../models/stock.dart';
import '../../state/catalog_provider.dart';
import '../../state/stock_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Module Produits (§7.4/7.5/§8 README) : catalogue (catégories/sous-types/
/// marques/références/variantes) ET suivi de stock (ruptures, historique
/// des mouvements) réunis dans une seule page — comme la page Produits de
/// Next.js, qui est le hub unique pour tout ce qui touche au produit et à
/// son stock (pas de page "Stock" séparée côté web).
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Produits'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Références'), Tab(text: 'Ruptures'), Tab(text: 'Mouvements'), Tab(text: 'Configuration')],
          ),
        ),
        body: const TabBarView(children: [_ReferencesTab(), _RupturesTab(), _MovementsTab(), _ConfigTab()]),
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
  int? _categoryFilter;
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
    final categories = ref.watch(categoriesProvider).value ?? [];
    final types = ref.watch(typesProvider).value ?? [];
    final brands = ref.watch(brandsProvider).value ?? [];
    final typesForCategory = _categoryFilter == null ? types : types.where((t) => t.categoryId == _categoryFilter).toList();

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _categoryFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, labelText: 'Catégorie', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Toutes les catégories')),
                      for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.nom, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() {
                      _categoryFilter = v;
                      _typeFilter = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _typeFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, labelText: 'Sous-type', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tous les sous-types')),
                      for (final t in typesForCategory) DropdownMenuItem(value: t.id, child: Text(t.nom, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _typeFilter = v),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: DropdownButtonFormField<int?>(
              initialValue: _brandFilter,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, labelText: 'Marque', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes les marques')),
                for (final b in brands) DropdownMenuItem(value: b.id, child: Text(b.nom, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _brandFilter = v),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: switch (async) {
              AsyncData(:final value) => _buildList(value, types),
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

  Widget _buildList(List<ProductReference> all, List<ProductType> types) {
    final typeToCategory = {for (final t in types) t.id: t.categoryId};
    final filtered = all.where((r) {
      if (_categoryFilter != null && typeToCategory[r.typeId] != _categoryFilter) return false;
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
    final categories = ref.read(categoriesProvider).value ?? [];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créez d\'abord une catégorie (Paramètres → Catalogue, ou onglet Configuration).')),
      );
      return;
    }
    await showDialog<void>(context: context, builder: (_) => const _AddReferenceDialog());
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
      ref.invalidate(rupturesProvider);
      ref.invalidate(movementsProvider(null));
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

/// Onglet "Ruptures" (§7.5 README) — produits en rupture ou sous le seuil
/// d'alerte, avec export PDF de réapprovisionnement et ajustement rapide.
class _RupturesTab extends ConsumerWidget {
  const _RupturesTab();

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(stockRepositoryProvider).ruptureExportPdfBytes();
      final file = XFile.fromData(bytes, name: 'reapprovisionnement.pdf', mimeType: 'application/pdf');
      await SharePlus.instance.share(ShareParams(files: [file], text: 'Liste de réapprovisionnement'));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rupturesProvider);

    return Scaffold(
      body: switch (async) {
        AsyncData(:final value) => value.isEmpty
            ? const EmptyState(message: 'Aucune rupture ni stock bas.', icon: Icons.check_circle_outline)
            : RefreshIndicator(
                onRefresh: () => ref.read(rupturesProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _RuptureTile(item: value[i]),
                ),
              ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(rupturesProvider.notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
      floatingActionButton: (async.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _exportPdf(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exporter PDF'),
            )
          : null,
    );
  }
}

class _RuptureTile extends ConsumerWidget {
  const _RuptureTile({required this.item});
  final RuptureItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text('${item.brandName} ${item.referenceName} — ${item.couleur}'),
        subtitle: Text('${item.categoryName} / ${item.typeName} · Stock : ${item.stockActuel} · Seuil : ${item.seuilAlerte}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StockLevelBadge(isRupture: item.isRupture, isStockBas: !item.isRupture),
            IconButton(
              tooltip: 'Ajuster le stock',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _QuickAdjustDialog(variantId: item.id, label: '${item.brandName} ${item.referenceName} — ${item.couleur}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Onglet "Mouvements" (§7.4 README) — historique des entrées/sorties de
/// stock, avec ajustement manuel libre (choix du produit dans un sélecteur).
class _MovementsTab extends ConsumerWidget {
  const _MovementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movementsProvider(null));

    return Scaffold(
      body: switch (async) {
        AsyncData(:final value) => value.isEmpty
            ? const EmptyState(message: 'Aucun mouvement de stock.', icon: Icons.sync_alt)
            : RefreshIndicator(
                onRefresh: () => ref.read(movementsProvider(null).notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _MovementTile(movement: value[i]),
                ),
              ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(movementsProvider(null).notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const _AdjustDialogWithPicker()),
        icon: const Icon(Icons.add),
        label: const Text('Ajustement'),
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});
  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final isEntree = movement.type == StockMovementType.entree;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isEntree ? Colors.green : Colors.red).withValues(alpha: 0.15),
          child: Icon(isEntree ? Icons.arrow_downward : Icons.arrow_upward, color: isEntree ? Colors.green : Colors.red, size: 18),
        ),
        title: Text(movement.variantLabel),
        subtitle: Text(
          '${movement.type.label} de ${movement.quantite} · ${movement.origine}'
          '${movement.note != null && movement.note!.isNotEmpty ? ' · ${movement.note}' : ''}'
          '${movement.timestamp != null ? '\n${_dateFmt.format(movement.timestamp!)}' : ''}'
          '${movement.userName != null ? ' · ${movement.userName}' : ''}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// Même dialog que dans l'onglet Références, mais avec un sélecteur de
/// variante (accès depuis l'onglet Mouvements, sans variante pré-sélectionnée).
class _AdjustDialogWithPicker extends ConsumerStatefulWidget {
  const _AdjustDialogWithPicker();

  @override
  ConsumerState<_AdjustDialogWithPicker> createState() => _AdjustDialogWithPickerState();
}

class _AdjustDialogWithPickerState extends ConsumerState<_AdjustDialogWithPicker> {
  ProductVariant? _variant;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final references = ref.watch(referencesProvider).value ?? [];
    final variants = <MapEntry<ProductVariant, String>>[
      for (final r in references)
        for (final v in r.variants) MapEntry(v, '${r.brandName} ${r.referenceName} — ${v.couleur}'),
    ].where((e) => _query.isEmpty || e.value.toLowerCase().contains(_query.toLowerCase())).toList();

    if (_variant == null) {
      return AlertDialog(
        title: const Text('Choisir un produit'),
        content: SizedBox(
          width: 380,
          height: 440,
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(hintText: 'Rechercher…', prefixIcon: Icon(Icons.search), isDense: true),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: variants.isEmpty
                    ? const Center(child: Text('Aucune variante disponible.'))
                    : ListView.builder(
                        itemCount: variants.length,
                        itemBuilder: (context, i) {
                          final entry = variants[i];
                          return ListTile(
                            title: Text(entry.value),
                            subtitle: Text('Stock actuel : ${entry.key.stockActuel}'),
                            onTap: () => setState(() => _variant = entry.key),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler'))],
      );
    }

    return _QuickAdjustDialog(variantId: _variant!.id, label: variants.firstWhere((e) => e.key.id == _variant!.id, orElse: () => MapEntry(_variant!, _variant!.label)).value);
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

/// Réplique du dialog "Nouvelle référence produit" de Next.js
/// (`app/(app)/products/page.tsx` → `CreateReferenceDialog`) : Catégorie →
/// Sous-type → Marque en cascade, création inline de sous-type/marque
/// manquants, et une première couleur optionnelle en une seule étape.
class _AddReferenceDialog extends ConsumerStatefulWidget {
  const _AddReferenceDialog();

  @override
  ConsumerState<_AddReferenceDialog> createState() => _AddReferenceDialogState();
}

class _AddReferenceDialogState extends ConsumerState<_AddReferenceDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _couleurController = TextEditingController(text: 'Standard');
  final _stockController = TextEditingController(text: '0');
  final _seuilController = TextEditingController(text: '1');
  final _newTypeController = TextEditingController();
  final _newBrandController = TextEditingController();

  int? _categoryId;
  int? _typeId;
  int? _brandId;
  bool _saving = false;
  bool _creatingType = false;
  bool _creatingBrand = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _couleurController.dispose();
    _stockController.dispose();
    _seuilController.dispose();
    _newTypeController.dispose();
    _newBrandController.dispose();
    super.dispose();
  }

  List<ProductType> get _typesForCategory =>
      _categoryId == null ? const [] : ref.watch(typesProvider).value?.where((t) => t.categoryId == _categoryId).toList() ?? [];

  Future<void> _createType() async {
    if (_categoryId == null || _newTypeController.text.trim().isEmpty) return;
    setState(() => _creatingType = true);
    try {
      final created = await ref.read(typesProvider.notifier).create(_categoryId!, _newTypeController.text.trim());
      _newTypeController.clear();
      if (mounted) setState(() => _typeId = created.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _creatingType = false);
    }
  }

  Future<void> _createBrand() async {
    if (_newBrandController.text.trim().isEmpty) return;
    setState(() => _creatingBrand = true);
    try {
      final created = await ref.read(brandsProvider.notifier).create(_newBrandController.text.trim());
      _newBrandController.clear();
      if (mounted) setState(() => _brandId = created.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _creatingBrand = false);
    }
  }

  Future<void> _save() async {
    if (_typeId == null || _brandId == null || _nameController.text.trim().isEmpty || _priceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tous les champs sont requis')));
      return;
    }
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (price == null) return;
    setState(() => _saving = true);
    try {
      final created = await ref.read(referencesProvider.notifier).createReference(
            typeId: _typeId!,
            brandId: _brandId!,
            referenceName: _nameController.text.trim(),
            prixVente: price,
          );
      final couleur = _couleurController.text.trim();
      if (couleur.isNotEmpty) {
        await ref.read(referencesProvider.notifier).createVariant(
              productReferenceId: created.id,
              couleur: couleur,
              seuilAlerte: int.tryParse(_seuilController.text) ?? 1,
              stockActuel: int.tryParse(_stockController.text) ?? 0,
            );
      }
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
      title: const Text('Nouvelle référence produit'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catégorie → Sous-type → Marque → Référence (§8 du cahier des charges).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [for (final c in ref.watch(categoriesProvider).value ?? const <ProductCategory>[]) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                onChanged: (v) => setState(() {
                  _categoryId = v;
                  _typeId = null;
                }),
              ),
              if (_categoryId != null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _typeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sous-type'),
                  items: [for (final t in _typesForCategory) DropdownMenuItem(value: t.id, child: Text(t.nom))],
                  onChanged: (v) => setState(() => _typeId = v),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTypeController,
                        decoration: const InputDecoration(isDense: true, hintText: 'Nouveau sous-type (ex: MAGSAFE)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _creatingType ? null : _createType, child: const Text('Créer')),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _brandId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Marque'),
                items: [for (final b in ref.watch(brandsProvider).value ?? const <Brand>[]) DropdownMenuItem(value: b.id, child: Text(b.nom))],
                onChanged: (v) => setState(() => _brandId = v),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newBrandController,
                      decoration: const InputDecoration(isDense: true, hintText: 'Nouvelle marque'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _creatingBrand ? null : _createBrand, child: const Text('Créer')),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Référence (modèle)', hintText: 'Ex: A16, S25 Ultra'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(labelText: 'Prix vente (Ar)'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text('Première couleur (optionnel)', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(controller: _couleurController, decoration: const InputDecoration(isDense: true, labelText: 'Couleur')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _stockController,
                      decoration: const InputDecoration(isDense: true, labelText: 'Stock'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _seuilController,
                      decoration: const InputDecoration(isDense: true, labelText: 'Seuil'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Création…' : 'Créer la référence')),
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
