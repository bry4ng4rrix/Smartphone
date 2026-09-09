import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../data/repositories/stock_repository.dart';
import '../../models/catalog.dart';
import '../../models/stock.dart';
import '../../state/auth_provider.dart';
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Produits'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Références'), Tab(text: 'Ruptures'), Tab(text: 'Mouvements')],
          ),
        ),
        body: const TabBarView(children: [_ReferencesTab(), _RupturesTab(), _MovementsTab()]),
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
          // Recherche + filtres compacts en icônes (Catégorie/Sous-type/
          // Marque) plutôt que 3 menus déroulants pleine largeur — même
          // esprit que les icônes de filtre de la liste Commandes
          // (orders_list_screen.dart), pour libérer de l'espace vertical
          // (§ demande). Les puces actives ci-dessous montrent/permettent de
          // retirer ce qui est sélectionné, faute de libellé visible sur l'icône.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(hintText: 'Rechercher (marque, référence)…', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  ),
                ),
                PopupMenuButton<int?>(
                  tooltip: 'Filtrer par catégorie',
                  icon: Icon(Icons.category_outlined, color: _categoryFilter != null ? Theme.of(context).colorScheme.primary : null),
                  onSelected: (v) => setState(() {
                    _categoryFilter = v;
                    _typeFilter = null;
                  }),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('Toutes les catégories')),
                    for (final c in categories) PopupMenuItem(value: c.id, child: Text(c.nom)),
                  ],
                ),
                PopupMenuButton<int?>(
                  tooltip: 'Filtrer par sous-type',
                  icon: Icon(Icons.style_outlined, color: _typeFilter != null ? Theme.of(context).colorScheme.primary : null),
                  onSelected: (v) => setState(() => _typeFilter = v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('Tous les sous-types')),
                    for (final t in typesForCategory) PopupMenuItem(value: t.id, child: Text(t.nom)),
                  ],
                ),
                PopupMenuButton<int?>(
                  tooltip: 'Filtrer par marque',
                  icon: Icon(Icons.storefront_outlined, color: _brandFilter != null ? Theme.of(context).colorScheme.primary : null),
                  onSelected: (v) => setState(() => _brandFilter = v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('Toutes les marques')),
                    for (final b in brands) PopupMenuItem(value: b.id, child: Text(b.nom)),
                  ],
                ),
              ],
            ),
          ),
          if (_categoryFilter != null || _typeFilter != null || _brandFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (_categoryFilter != null)
                    Chip(
                      label: Text(categories.firstWhereOrNull((c) => c.id == _categoryFilter)?.nom ?? ''),
                      onDeleted: () => setState(() {
                        _categoryFilter = null;
                        _typeFilter = null;
                      }),
                    ),
                  if (_typeFilter != null)
                    Chip(
                      label: Text(types.firstWhereOrNull((t) => t.id == _typeFilter)?.nom ?? ''),
                      onDeleted: () => setState(() => _typeFilter = null),
                    ),
                  if (_brandFilter != null)
                    Chip(
                      label: Text(brands.firstWhereOrNull((b) => b.id == _brandFilter)?.nom ?? ''),
                      onDeleted: () => setState(() => _brandFilter = null),
                    ),
                ],
              ),
            ),
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
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'catalog-fab-new-reference',
            onPressed: () => _showAddReferenceDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle référence'),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'catalog-fab-more',
            tooltip: 'Plus d\'options',
            onPressed: () => _showMoreMenu(context, ref),
            child: const Icon(Icons.more_vert),
          ),
        ],
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
      // Chaque mot doit se retrouver quelque part (nom, marque OU une
      // couleur de variante) — permet "samsung bleu", peu importe l'ordre.
      final tokens = _search.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
      final haystack = [
        r.referenceName,
        r.brandName,
        for (final v in r.variants) v.couleur,
      ].join(' ').toLowerCase();
      return tokens.every((t) => haystack.contains(t));
    }).toList();

    if (filtered.isEmpty) {
      return const EmptyState(message: 'Aucune référence pour cette sélection.', icon: Icons.style_outlined);
    }
    // Carte verticale plutôt qu'un DataTable : sur un écran de téléphone, un
    // vrai tableau (10 colonnes côté web) impose un scroll horizontal — pas
    // souhaité (§ demande). Champs affichés sans tap : Catégorie, Marque,
    // Référence, Prix de vente, Marge, Variantes (couleurs+stock), Statut.
    // Actions (modifier/supprimer/couleurs) dans un menu "⋮" par ligne,
    // visible seulement pour le gérant.
    final isGerant = ref.watch(authProvider).user?.role == UserRole.gerant;
    return RefreshIndicator(
      onRefresh: () => ref.read(referencesProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (context, i) => _ReferenceCard(reference: filtered[i], isGerant: isGerant),
      ),
    );
  }

  Future<void> _showAddReferenceDialog(BuildContext context, WidgetRef ref) async {
    final categories = ref.read(categoriesProvider).value ?? [];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créez d\'abord une catégorie (Paramètres → Catalogue, ou ⋮ → Paramètres ici).')),
      );
      return;
    }
    await showDialog<void>(context: context, builder: (_) => const _AddReferenceDialog());
  }

  /// Menu "⋮" (à droite du FAB "Nouvelle référence") : réplique les actions
  /// secondaires de la barre d'outils Next.js (`app/(app)/products/page.tsx`)
  /// — Export/Import Excel, Paramètres du catalogue, Modifier prix par
  /// sous-type — regroupées ici plutôt qu'éparpillées dans l'AppBar (§ demande).
  void _showMoreMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Exporter Excel'),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportExcel(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Importer Excel'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importExcel(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Modifier prix par sous-type'),
              onTap: () {
                Navigator.pop(sheetContext);
                showDialog<void>(context: context, builder: (_) => const _BulkPriceDialog());
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Paramètres'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSettingsSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// GET catalog/references/export-excel/ → fichier .xlsx (une ligne par
  /// variante) — même pattern fetch-bytes-puis-partager que l'export PDF de
  /// l'onglet Ruptures (voir _RupturesTab._exportPdf plus bas).
  Future<void> _exportExcel(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(catalogRepositoryProvider).exportExcelBytes();
      final file = XFile.fromData(
        bytes,
        name: 'catalogue.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await SharePlus.instance.share(ShareParams(files: [file], text: 'Export catalogue'));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    }
  }

  /// Sélectionne un .xlsx local puis POST catalog/references/import-excel/
  /// (multipart). Le serveur renvoie le fichier lui-même, annoté d'une
  /// colonne Statut/Date par ligne (pas de JSON) — on affiche le résumé
  /// chiffré (en-têtes X-Import-*) puis on repartage ce fichier annoté pour
  /// que l'utilisateur puisse le réimporter plus tard sans repartir de zéro
  /// (les lignes déjà marquées sont sautées côté serveur).
  Future<void> _importExcel(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
      if (picked == null) return; // Annulé par l'utilisateur.
      final bytes = await picked.readAsBytes();

      final result = await ref.read(catalogRepositoryProvider).importExcel(bytes, picked.name);

      // L'import peut créer de nouvelles catégories/sous-types/marques en
      // plus des références/variantes (voir catalog/views.py::_import_row) —
      // on invalide donc tout ce que le formulaire "Nouvelle référence" et
      // les filtres consomment, pas seulement les références.
      ref.invalidate(referencesProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(typesProvider);
      ref.invalidate(brandsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${result.createdReferences} référence(s) créée(s), ${result.updatedReferences} mise(s) à jour'
            ' · ${result.createdVariants} couleur(s) créée(s), ${result.updatedVariants} mise(s) à jour'
            '${result.skippedCount > 0 ? ' · ${result.skippedCount} déjà traitée(s)' : ''}'
            '${result.errorsCount > 0 ? ' · ${result.errorsCount} erreur(s) (voir le fichier)' : ''}',
          ),
          duration: const Duration(seconds: 6),
        ));
      }

      final file = XFile.fromData(
        result.bytes,
        name: result.filename,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await SharePlus.instance.share(ShareParams(files: [file], text: 'Résultat de l\'import catalogue'));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    }
  }

  /// Bottom sheet "Paramètres du catalogue" (réplique de CatalogSettingsDialog
  /// côté web) — 3 onglets Marques / Catégories (+ sous-types imbriqués) /
  /// Couleurs, comme les 3 onglets Marques/Catégories/Couleurs du web (§
  /// demande : "bien organiser" plutôt que 4 sections empilées). Réutilise
  /// tel quel le CRUD déjà implémenté plus bas dans ce fichier
  /// (_ConfigSection) — Catégories et Sous-types partagent juste un onglet
  /// maintenant, ils restent 2 sections distinctes dedans (pas de refonte du
  /// CRUD lui-même).
  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Paramètres du catalogue', style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(sheetContext).pop()),
                  ],
                ),
              ),
              const TabBar(
                tabs: [Tab(text: 'Marques'), Tab(text: 'Catégories'), Tab(text: 'Couleurs')],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(12),
                      children: const [_ConfigSection<Brand>(title: 'Marques', kind: _ConfigKind.brand)],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(12),
                      children: const [
                        _ConfigSection<ProductCategory>(title: 'Catégories', kind: _ConfigKind.category),
                        SizedBox(height: 16),
                        _ConfigSection<ProductType>(title: 'Sous-types', kind: _ConfigKind.type),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(12),
                      children: const [_ConfigSection<ProductColor>(title: 'Couleurs', kind: _ConfigKind.color)],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seuils de couleur du badge "Variantes" — indépendants du statut agrégé
/// (is_rupture/is_stock_bas) : rouge = plus de stock, bleu = 2 ou moins,
/// vert = 3 ou plus. Mêmes seuils que le web (`variantStockBadgeClass`,
/// `frontend/app/(app)/products/page.tsx:61-67`).
Color _variantChipColor(int stock) {
  if (stock <= 0) return const Color(0xFFEF4444);
  if (stock <= 2) return const Color(0xFF3B82F6);
  return const Color(0xFF10B981);
}

/// Une référence, en carte verticale (pas de DataTable — évite le scroll
/// horizontal sur téléphone, § demande). [isGerant] masque les actions
/// (modifier/supprimer/couleurs) pour préparateur/livreur — cet écran n'est
/// normalement accessible qu'au gérant (voir nav_items.dart), mais le
/// routeur ne fait pas de contrôle de rôle par route (seule la nav liste
/// filtre), donc ce contrôle reste utile en défense en profondeur.
class _ReferenceCard extends ConsumerWidget {
  const _ReferenceCard({required this.reference, required this.isGerant});
  final ProductReference reference;
  final bool isGerant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = reference.variants;
    final rupture = variants.any((v) => v.isRupture);
    final basStock = variants.any((v) => v.isStockBas);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reference.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
                      ),
                      Text(
                        '${reference.brandName} ${reference.referenceName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StockLevelBadge(isRupture: rupture, isStockBas: basStock),
                if (isGerant)
                  PopupMenuButton<void Function()>(
                    tooltip: 'Actions',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (action) => action(),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: () => showDialog<void>(context: context, builder: (_) => _ManageVariantsDialog(reference: reference)),
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.palette_outlined),
                          title: Text('Gérer les couleurs'),
                        ),
                      ),
                      PopupMenuItem(
                        value: () => showDialog<void>(context: context, builder: (_) => _EditReferenceDialog(reference: reference)),
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Modifier'),
                        ),
                      ),
                      PopupMenuItem(
                        value: () => _confirmDelete(context, ref),
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Supprimer', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 4,
              children: [
                _PriceStat(label: 'Prix de vente', value: _ar(reference.prixVente)),
                _PriceStat(
                  label: 'Marge',
                  value: _ar(reference.margeUnitaire),
                  color: reference.margeUnitaire >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (variants.isEmpty)
              Text('Aucune variante', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in variants)
                    StatusChip(label: '${v.couleur} · ${v.stockActuel}', color: _variantChipColor(v.stockActuel)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(context, 'Supprimer "${reference.referenceName}" et ses variantes ?');
    if (confirmed) await ref.read(referencesProvider.notifier).deleteReference(reference.id);
  }
}

/// Petit couple label/valeur pour la rangée Prix de vente/Marge de [_ReferenceCard].
class _PriceStat extends StatelessWidget {
  const _PriceStat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Gestion des couleurs d'une référence (ajout/suppression/ajustement rapide
/// du stock), ouverte depuis le menu "⋮" de [_ReferenceCard] — équivalent du
/// clic sur une ligne côté web qui ouvre ProductDetailDialog.
class _ManageVariantsDialog extends ConsumerWidget {
  const _ManageVariantsDialog({required this.reference});
  final ProductReference reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Relu depuis referencesProvider pour rester à jour après un ajout/
    // suppression de variante pendant que ce dialog reste ouvert.
    final current = ref.watch(referencesProvider).value?.firstWhereOrNull((r) => r.id == reference.id) ?? reference;

    return AlertDialog(
      title: Text('Couleurs — ${current.brandName} ${current.referenceName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current.variants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucune variante pour cette référence.'),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final v in current.variants)
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
                                  builder: (_) => _QuickAdjustDialog(
                                    variantId: v.id,
                                    productLabel: '${current.brandName} ${current.referenceName}',
                                    couleur: v.couleur,
                                    stockActuel: v.stockActuel,
                                    seuilAlerte: v.seuilAlerte,
                                  ),
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
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => _AddVariantDialog(referenceId: current.id)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter une couleur'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
      ],
    );
  }
}

class _QuickAdjustDialog extends ConsumerStatefulWidget {
  const _QuickAdjustDialog({
    required this.variantId,
    required this.productLabel,
    required this.couleur,
    required this.stockActuel,
    required this.seuilAlerte,
  });
  final int variantId;
  final String productLabel;
  final String couleur;
  final int stockActuel;
  final int seuilAlerte;

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
      title: Text('Ajuster le stock — ${widget.productLabel}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text('Couleur : ', style: TextStyle(color: Colors.grey)),
                Chip(label: Text(widget.couleur), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                const Spacer(),
                Text('Stock : ${widget.stockActuel} · Seuil : ${widget.seuilAlerte}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                builder: (_) => _QuickAdjustDialog(
                  variantId: item.id,
                  productLabel: '${item.brandName} ${item.referenceName}',
                  couleur: item.couleur,
                  stockActuel: item.stockActuel,
                  seuilAlerte: item.seuilAlerte,
                ),
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

    return _QuickAdjustDialog(
      variantId: _variant!.id,
      productLabel: '${_variant!.brandName} ${_variant!.referenceName}',
      couleur: _variant!.couleur,
      stockActuel: _variant!.stockActuel,
      seuilAlerte: _variant!.seuilAlerte,
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
  late final _purchasePriceController = TextEditingController(text: widget.reference.prixAchat.toStringAsFixed(0));
  late final _priceController = TextEditingController(text: widget.reference.prixVente.toStringAsFixed(0));
  late bool _actif = widget.reference.actif;
  XFile? _photoFile;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _purchasePriceController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  double? get _margin {
    final achat = double.tryParse(_purchasePriceController.text.replaceAll(',', '.'));
    final vente = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (achat == null || vente == null) return null;
    return vente - achat;
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _photoFile = file);
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final purchasePrice = double.tryParse(_purchasePriceController.text.replaceAll(',', '.')) ?? 0;
    if (price == null || _nameController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(referencesProvider.notifier).updateReference(
            widget.reference.id,
            referenceName: _nameController.text.trim(),
            prixAchat: purchasePrice,
            prixVente: price,
            actif: _actif,
          );
      if (_photoFile != null) {
        await ref.read(referencesProvider.notifier).uploadPhoto(widget.reference.id, _photoFile!.path);
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
      title: const Text('Modifier la référence'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Référence')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _purchasePriceController,
                  decoration: const InputDecoration(labelText: "Prix d'achat (Ar)"),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Prix de vente (Ar)'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (_margin != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Marge estimée : ${_ar(_margin!)} / unité',
                style: TextStyle(fontSize: 12, color: _margin! >= 0 ? Colors.green : Colors.red),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _photoFile != null
                    ? Image.file(File(_photoFile!.path), width: 56, height: 56, fit: BoxFit.cover)
                    : (widget.reference.photo != null
                        ? Image.network(widget.reference.photo!, width: 56, height: 56, fit: BoxFit.cover)
                        : Container(
                            width: 56,
                            height: 56,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_outlined, size: 24),
                          )),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.photo_outlined, size: 18),
                label: const Text('Changer la photo'),
              ),
            ],
          ),
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

class _VariantDraft {
  _VariantDraft({required this.couleur, required this.stock, required this.seuil});
  final String couleur;
  final int stock;
  final int seuil;
}

class _AddReferenceDialogState extends ConsumerState<_AddReferenceDialog> {
  final _nameController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _seuilController = TextEditingController(text: '1');
  final _newTypeController = TextEditingController();
  final _newBrandController = TextEditingController();
  final _newColorController = TextEditingController();

  int? _categoryId;
  int? _typeId;
  int? _brandId;
  int? _variantColorId;
  final List<_VariantDraft> _variants = [];
  XFile? _photoFile;
  bool _saving = false;
  bool _creatingType = false;
  bool _creatingBrand = false;
  bool _creatingColor = false;

  @override
  void dispose() {
    _nameController.dispose();
    _purchasePriceController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _seuilController.dispose();
    _newTypeController.dispose();
    _newBrandController.dispose();
    _newColorController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _photoFile = file);
  }

  double? get _margin {
    final achat = double.tryParse(_purchasePriceController.text.replaceAll(',', '.'));
    final vente = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (achat == null || vente == null) return null;
    return vente - achat;
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

  Future<void> _createColor() async {
    if (_newColorController.text.trim().isEmpty) return;
    setState(() => _creatingColor = true);
    try {
      final created = await ref.read(colorsProvider.notifier).create(_newColorController.text.trim());
      _newColorController.clear();
      if (mounted) setState(() => _variantColorId = created.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _creatingColor = false);
    }
  }

  void _addVariant() {
    final colors = ref.read(colorsProvider).value ?? const <ProductColor>[];
    final color = colors.where((c) => c.id == _variantColorId).firstOrNull;
    if (color == null) return;
    if (_variants.any((v) => v.couleur == color.nom)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette couleur est déjà dans la liste')));
      return;
    }
    setState(() {
      _variants.add(_VariantDraft(
        couleur: color.nom,
        stock: int.tryParse(_stockController.text) ?? 0,
        seuil: int.tryParse(_seuilController.text) ?? 1,
      ));
      _variantColorId = null;
      _stockController.text = '0';
      _seuilController.text = '1';
    });
  }

  void _removeVariant(String couleur) {
    setState(() => _variants.removeWhere((v) => v.couleur == couleur));
  }

  Future<void> _save() async {
    if (_typeId == null || _brandId == null || _nameController.text.trim().isEmpty || _priceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tous les champs sont requis')));
      return;
    }
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final purchasePrice = double.tryParse(_purchasePriceController.text.replaceAll(',', '.')) ?? 0;
    if (price == null) return;
    setState(() => _saving = true);
    try {
      final created = await ref.read(referencesProvider.notifier).createReference(
            typeId: _typeId!,
            brandId: _brandId!,
            referenceName: _nameController.text.trim(),
            prixAchat: purchasePrice,
            prixVente: price,
          );
      for (final v in _variants) {
        await ref.read(referencesProvider.notifier).createVariant(
              productReferenceId: created.id,
              couleur: v.couleur,
              seuilAlerte: v.seuil,
              stockActuel: v.stock,
            );
      }
      if (_photoFile != null) {
        await ref.read(referencesProvider.notifier).uploadPhoto(created.id, _photoFile!.path);
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
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Référence (modèle)', hintText: 'Ex: A16, S25 Ultra'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _purchasePriceController,
                      decoration: const InputDecoration(labelText: "Prix d'achat (Ar)", hintText: '0'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(labelText: 'Prix vente (Ar)'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_margin != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Marge estimée : ${_ar(_margin!)} / unité',
                  style: TextStyle(fontSize: 12, color: _margin! >= 0 ? Colors.green : Colors.red),
                ),
              ],
              const SizedBox(height: 14),
              Text('Photo (optionnel)', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_photoFile != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_photoFile!.path), width: 64, height: 64, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                  ],
                  OutlinedButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: Text(_photoFile == null ? 'Choisir une photo' : 'Changer'),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Variantes (couleurs)', style: Theme.of(context).textTheme.labelLarge),
                  if (_variants.isNotEmpty)
                    Text(
                      '${_variants.length} couleur(s) · ${_variants.fold<int>(0, (s, v) => s + v.stock)} unité(s)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      initialValue: _variantColorId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, labelText: 'Couleur'),
                      items: [
                        for (final c in ref.watch(colorsProvider).value ?? const <ProductColor>[])
                          DropdownMenuItem(value: c.id, child: Text(c.nom, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _variantColorId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _stockController,
                      decoration: const InputDecoration(isDense: true, labelText: 'Nombre'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _seuilController,
                      decoration: const InputDecoration(isDense: true, labelText: "Seuil d'alerte"),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _variantColorId == null ? null : _addVariant,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Ajouter'),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newColorController,
                      decoration: const InputDecoration(isDense: true, hintText: 'Nouvelle couleur (ex: Bleu)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _creatingColor ? null : _createColor, child: const Text('Créer')),
                ],
              ),
              if (_variants.isNotEmpty) ...[
                const SizedBox(height: 10),
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
  final _stockController = TextEditingController(text: '0');
  final _thresholdController = TextEditingController(text: '5');
  final _newColorController = TextEditingController();
  int? _colorId;
  bool _saving = false;
  bool _creatingColor = false;

  @override
  void dispose() {
    _stockController.dispose();
    _thresholdController.dispose();
    _newColorController.dispose();
    super.dispose();
  }

  Future<void> _createColor() async {
    if (_newColorController.text.trim().isEmpty) return;
    setState(() => _creatingColor = true);
    try {
      final created = await ref.read(colorsProvider.notifier).create(_newColorController.text.trim());
      _newColorController.clear();
      if (mounted) setState(() => _colorId = created.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _creatingColor = false);
    }
  }

  Future<void> _save() async {
    final colors = ref.read(colorsProvider).value ?? [];
    final color = colors.where((c) => c.id == _colorId).firstOrNull;
    if (color == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(referencesProvider.notifier).createVariant(
            productReferenceId: widget.referenceId,
            couleur: color.nom,
            seuilAlerte: int.tryParse(_thresholdController.text) ?? 0,
            stockActuel: int.tryParse(_stockController.text) ?? 0,
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
    final colors = ref.watch(colorsProvider).value ?? const <ProductColor>[];
    return AlertDialog(
      title: const Text('Nouvelle couleur'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _colorId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Couleur'),
            items: [for (final c in colors) DropdownMenuItem(value: c.id, child: Text(c.nom))],
            onChanged: (v) => setState(() => _colorId = v),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newColorController,
                  decoration: const InputDecoration(isDense: true, hintText: 'Nouvelle couleur'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _creatingColor ? null : _createColor, child: const Text('Créer')),
            ],
          ),
          const SizedBox(height: 10),
          TextField(controller: _stockController, decoration: const InputDecoration(labelText: 'Nombre'), keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          TextField(controller: _thresholdController, decoration: const InputDecoration(labelText: 'Seuil d\'alerte'), keyboardType: TextInputType.number),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: (_saving || _colorId == null) ? null : _save, child: const Text('Ajouter')),
      ],
    );
  }
}

/// Réplique de BulkPriceDialog côté web (`products/page.tsx`) : modifie
/// prix_achat/prix_vente de TOUTES les références d'un sous-type en une
/// seule fois — ouvert depuis le menu "⋮" de l'onglet Références.
class _BulkPriceDialog extends ConsumerStatefulWidget {
  const _BulkPriceDialog();

  @override
  ConsumerState<_BulkPriceDialog> createState() => _BulkPriceDialogState();
}

class _BulkPriceDialogState extends ConsumerState<_BulkPriceDialog> {
  int? _typeId;
  final _prixAchatController = TextEditingController();
  final _prixVenteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _prixAchatController.dispose();
    _prixVenteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_typeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choisissez un sous-type')));
      return;
    }
    final prixAchat = double.tryParse(_prixAchatController.text.replaceAll(',', '.'));
    final prixVente = double.tryParse(_prixVenteController.text.replaceAll(',', '.'));
    if (prixAchat == null && prixVente == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Indiquez au moins un prix à modifier')));
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await ref.read(referencesProvider.notifier).bulkUpdatePrice(
            _typeId!,
            prixAchat: prixAchat,
            prixVente: prixVente,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$updated référence(s) mise(s) à jour')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(typesProvider).value ?? const <ProductType>[];
    return AlertDialog(
      title: const Text('Modifier le prix par sous-type'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Change le prix d\'achat et/ou de vente de TOUTES les références d\'un sous-type '
              '(ex : toutes les "Flip cover", quelle que soit la marque).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _typeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sous-type'),
              items: [for (final t in types) DropdownMenuItem(value: t.id, child: Text(t.nom))],
              onChanged: (v) => setState(() => _typeId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prixAchatController,
              decoration: const InputDecoration(labelText: 'Nouveau prix actuel (Ar)', hintText: 'Laisser vide = inchangé'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prixVenteController,
              decoration: const InputDecoration(labelText: 'Nouveau prix de vente (Ar)', hintText: 'Laisser vide = inchangé'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Mise à jour…' : 'Appliquer')),
      ],
    );
  }
}

/// Sections CRUD Catégories/Sous-types/Marques/Couleurs — anciennement le
/// contenu de l'onglet "Configuration" (aujourd'hui présenté dans la feuille
/// "Paramètres", voir _ReferencesTabState._showSettingsSheet), inchangées
/// sinon. Note : la couleur ("Couleurs") n'existait pas dans l'ancien onglet
/// (seulement Catégories/Sous-types/Marques) — ajoutée ici pour la parité
/// avec CatalogSettingsDialog côté web (onglets Marques/Catégories/Couleurs),
/// en réutilisant le CRUD déjà implémenté par ailleurs (colorsProvider).
enum _ConfigKind { category, type, brand, color }

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
              _ConfigKind.color => _ColorList(),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    switch (kind) {
      case _ConfigKind.category:
        final controller = TextEditingController();
        final name = await _promptText(context, 'Nouvelle catégorie', controller, hint: 'ex : HOUSSE');
        if (name != null && name.isNotEmpty) {
          await ref.read(categoriesProvider.notifier).create(name, 0);
        }
      case _ConfigKind.brand:
        final controller = TextEditingController();
        final name = await _promptText(context, 'Nouvelle marque', controller, hint: 'ex : Samsung');
        if (name != null && name.isNotEmpty) {
          await ref.read(brandsProvider.notifier).create(name);
        }
      case _ConfigKind.color:
        final controller = TextEditingController();
        final name = await _promptText(context, 'Nouvelle couleur', controller, hint: 'ex : Bleu');
        if (name != null && name.isNotEmpty) {
          await ref.read(colorsProvider.notifier).create(name);
        }
      case _ConfigKind.type:
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

class _ColorList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(colorsProvider).value ?? [];
    if (list.isEmpty) return const Text('Aucune couleur.');
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
                    'Renommer la couleur',
                    c.nom,
                    (name) => ref.read(colorsProvider.notifier).rename(c.id, name),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    if (await _confirm(context, 'Supprimer la couleur "${c.nom}" ?')) {
                      await ref.read(colorsProvider.notifier).delete(c.id);
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
