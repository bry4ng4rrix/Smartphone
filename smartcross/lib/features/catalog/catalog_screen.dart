import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../models/catalog.dart';
import '../../models/stock.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart';
import '../../state/realtime_provider.dart';
import '../../state/stock_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;
import '../../widgets/status_badge.dart';
import 'import_export.dart';
import 'reference_dialogs.dart';
import 'stock_adjust_dialog.dart';

final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Module Produits — réplique de `/products` (app/(app)/products/page.tsx) :
/// catalogue Catégorie → Sous-type → Marque → Référence → Couleur (§8 du
/// cahier des charges), CRUD des références/variantes, ajustement de stock,
/// import/export Excel, paramètres du catalogue, prix par sous-type et
/// « Nouvelle commande ».
///
/// Le gérant garde en plus deux onglets propres à l'app (Ruptures /
/// Mouvements — raccourcis des écrans Alertes et Mouvements, réservés au
/// gérant comme sur le web) ; un préparateur ne voit que le catalogue, en
/// lecture seule, exactement comme la page web sans `isGerant`.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGerant = ref.watch(authProvider.select((a) => a.user?.isGerant ?? false));
    if (!isGerant) {
      return Scaffold(
        appBar: AppBar(title: const Text('Catalogue produits')),
        body: const _ReferencesTab(),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catalogue produits'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Références'), Tab(text: 'Ruptures'), Tab(text: 'Mouvements')],
          ),
        ),
        body: const TabBarView(children: [_ReferencesTab(), _RupturesTab(), _MovementsTab()]),
      ),
    );
  }
}

// =============================================================================
// Onglet Références — la page /products
// =============================================================================

class _ReferencesTab extends ConsumerStatefulWidget {
  const _ReferencesTab();

  @override
  ConsumerState<_ReferencesTab> createState() => _ReferencesTabState();
}

class _ReferencesTabState extends ConsumerState<_ReferencesTab> with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  String _search = '';
  int? _categoryFilter;
  int? _typeFilter;
  int? _brandFilter;
  bool _exporting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // Comme `useEffect(() => fetchAll())` à l'arrivée sur la page : si le
    // catalogue est déjà en cache (visite précédente, commande créée entre
    // temps…), on le rafraîchit silencieusement ; sinon les providers sont
    // en train de le charger.
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(referencesProvider).hasValue) {
        ref.read(catalogHubProvider).refreshAll(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Débouncé à 250 ms (`useDebouncedValue`).
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = value.trim().toLowerCase());
    });
  }

  void _setSearch(String value) {
    _searchDebounce?.cancel();
    _searchController.text = value;
    setState(() => _search = value.trim().toLowerCase());
  }

  Future<void> _refresh() => ref.read(catalogHubProvider).refreshAll();

  Future<void> _refreshSilent() => ref.read(catalogHubProvider).refreshAll(silent: true);

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await exportCatalogExcel(context, ref);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    // Noms déjà présents AVANT l'import, pour la détection de quasi-doublons
    // parmi les nouvelles références.
    final existingNames = [
      for (final r in ref.read(referencesProvider).value ?? const <ProductReference>[]) '${r.brandName} ${r.referenceName}',
    ];
    setState(() => _importing = true);
    try {
      final outcome = await importCatalogExcel(context, ref, existingNames: existingNames);
      if (!mounted || outcome == null) return;
      if (outcome.action == ImportReviewAction.edit && outcome.searchPrefill != null) {
        _setSearch(outcome.searchPrefill!);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _newOrder() async {
    // Réutilise l'écran « Nouvelle commande » (`/orders/new`) ; au retour, le
    // catalogue est rechargé (le stock a pu bouger) — `onCreated → fetchAll()`.
    await context.push('/orders/new');
    if (mounted) await _refresh();
  }

  Future<void> _newReference() async {
    final created = await showCreateReferenceDialog(context);
    if (created && mounted) await _refresh();
  }

  Future<void> _bulkPrice() async {
    await showDialog<void>(context: context, builder: (_) => _BulkPriceDialog(initialTypeId: _typeFilter));
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CatalogSettingsSheet(),
    );
  }

  /// Menu « ⋮ » (à droite du FAB « Nouvelle référence ») : les actions
  /// secondaires de la barre d'outils web — Nouvelle commande, Export/Import
  /// Excel, Modifier prix par sous-type, Paramètres — regroupées ici plutôt
  /// qu'éparpillées dans l'AppBar (§ demande).
  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Nouvelle commande'),
              onTap: () {
                Navigator.pop(sheetContext);
                _newOrder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(_exporting ? 'Export...' : 'Exporter Excel'),
              enabled: !_exporting,
              onTap: () {
                Navigator.pop(sheetContext);
                _export();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(_importing ? 'Import...' : 'Importer Excel'),
              enabled: !_importing,
              onTap: () {
                Navigator.pop(sheetContext);
                _import();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Paramètres'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_money),
              title: const Text('Modifier prix par sous-type'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkPrice();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(ProductReference reference) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Supprimer ${reference.brandName} ${reference.referenceName} ?'),
        content: const Text('Cette référence et toutes ses variantes seront supprimées définitivement.'),
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
      await ref.read(referencesProvider.notifier).deleteReference(reference.id);
      if (mounted) _toast(context, 'Référence supprimée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Suppression impossible'));
    }
  }

  List<ProductReference> _filter(List<ProductReference> all, List<ProductType> types) {
    // La référence n'a pas de champ `category` : on passe par le sous-type.
    final typeToCategory = {for (final t in types) t.id: t.categoryId};
    final tokens = _search.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return all.where((r) {
      if (_categoryFilter != null && typeToCategory[r.typeId] != _categoryFilter) return false;
      if (_typeFilter != null && r.typeId != _typeFilter) return false;
      if (_brandFilter != null && r.brandId != _brandFilter) return false;
      if (tokens.isEmpty) return true;
      // Chaque mot doit se retrouver quelque part (nom, marque, catégorie,
      // sous-type OU une couleur de variante) — permet "samsung bleu",
      // "pixel 6 pro vert", peu importe l'ordre des mots.
      final haystack = [
        r.referenceName,
        r.brandName,
        r.categoryName,
        r.typeName,
        for (final v in r.variants) v.couleur,
      ].where((s) => s.isNotEmpty).join(' ').toLowerCase();
      return tokens.every((t) => haystack.contains(t));
    }).toList();
  }

  /// Garde recherche et filtres quand on passe sur un autre onglet.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Rafraîchissement temps réel (`useRealtimeRefresh`, debounce 400 ms) :
    // refetch SILENCIEUX à chaque événement WebSocket.
    ref.listen(realtimeTickProvider, (_, _) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _refreshSilent();
      });
    });
    // Erreur de chargement : un toast seulement, la liste garde son état
    // précédent (comme le web).
    ref.listen(referencesProvider, (previous, next) {
      if (next.hasError && !next.isLoading && previous?.error != next.error) {
        _toast(context, catalogErrorMessage(next.error!, 'Erreur de chargement du catalogue'));
      }
    });

    final theme = Theme.of(context);
    final isGerant = ref.watch(authProvider.select((a) => a.user?.isGerant ?? false));
    final async = ref.watch(referencesProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final types = ref.watch(typesProvider).value ?? const <ProductType>[];
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    final typesForCategory = _categoryFilter == null ? types : types.where((t) => t.categoryId == _categoryFilter).toList();
    final busy = _exporting || _importing;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Catégorie → Sous-type → Marque → Référence → Couleur (§8 du cahier des charges).',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  tooltip: 'Rafraîchir',
                  onPressed: async.isLoading ? null : _refresh,
                  icon: async.isLoading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(_importing ? 'Import...' : 'Export...', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          // Recherche + filtres compacts en icônes (Catégorie/Sous-type/
          // Marque) plutôt que 3 menus déroulants pleine largeur — même
          // esprit que les icônes de filtre de la liste Commandes, pour
          // libérer de l'espace vertical (§ demande). Les puces actives
          // ci-dessous montrent/permettent de retirer ce qui est sélectionné.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Marque, référence...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _setSearch('')),
                    ),
                    onChanged: (v) {
                      setState(() {}); // bouton « effacer »
                      _onSearchChanged(v);
                    },
                  ),
                ),
                PopupMenuButton<int?>(
                  tooltip: 'Filtrer par catégorie',
                  icon: Icon(Icons.category_outlined, color: _categoryFilter != null ? theme.colorScheme.primary : null),
                  onSelected: (v) => setState(() {
                    _categoryFilter = v;
                    _typeFilter = null; // changer la catégorie remet le sous-type à « Tous »
                  }),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('Toutes les catégories')),
                    for (final c in categories) PopupMenuItem(value: c.id, child: Text(c.nom)),
                  ],
                ),
                PopupMenuButton<int?>(
                  tooltip: 'Filtrer par sous-type',
                  icon: Icon(Icons.style_outlined, color: _typeFilter != null ? theme.colorScheme.primary : null),
                  onSelected: (v) => setState(() => _typeFilter = v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('Tous les sous-types')),
                    for (final t in typesForCategory) PopupMenuItem(value: t.id, child: Text(t.nom)),
                  ],
                ),
                PopupMenuButton<int?>(
                  tooltip: 'Filtrer par marque',
                  icon: Icon(Icons.storefront_outlined, color: _brandFilter != null ? theme.colorScheme.primary : null),
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
                      label: Text(categories.firstWhereOrNull((c) => c.id == _categoryFilter)?.nom ?? 'Catégorie'),
                      onDeleted: () => setState(() {
                        _categoryFilter = null;
                        _typeFilter = null;
                      }),
                    ),
                  if (_typeFilter != null)
                    Chip(
                      label: Text(types.firstWhereOrNull((t) => t.id == _typeFilter)?.nom ?? 'Sous-type'),
                      onDeleted: () => setState(() => _typeFilter = null),
                    ),
                  if (_brandFilter != null)
                    Chip(
                      label: Text(brands.firstWhereOrNull((b) => b.id == _brandFilter)?.nom ?? 'Marque'),
                      onDeleted: () => setState(() => _brandFilter = null),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildBody(async, types, isGerant)),
        ],
      ),
      floatingActionButton: isGerant
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'catalog-fab-new-reference',
                  onPressed: _newReference,
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle référence'),
                ),
                const SizedBox(width: 10),
                FloatingActionButton(
                  heroTag: 'catalog-fab-more',
                  tooltip: 'Plus d\'options',
                  onPressed: _showMoreMenu,
                  child: const Icon(Icons.more_vert),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildBody(AsyncValue<List<ProductReference>> async, List<ProductType> types, bool isGerant) {
    // Chargement NON silencieux (premier chargement, bouton Rafraîchir,
    // suppression) : état de chargement à la place de la liste, comme le
    // skeleton du web. Un refetch silencieux ne passe jamais ici.
    if (async.isLoading) return const LoadingState();
    final references = async.value;
    if (references == null) {
      return ErrorState(
        message: catalogErrorMessage(async.error ?? 'Erreur', 'Erreur de chargement du catalogue'),
        onRetry: _refresh,
      );
    }
    final filtered = _filter(references, types);
    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshSilent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 48),
            EmptyState(message: 'Aucune référence.', icon: Icons.style_outlined),
          ],
        ),
      );
    }
    // Carte verticale plutôt qu'un DataTable : sur un écran de téléphone, un
    // vrai tableau (10 colonnes côté web) impose un scroll horizontal — pas
    // souhaité (§ demande). Toutes les colonnes du web sont sur la carte.
    return RefreshIndicator(
      onRefresh: _refreshSilent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: filtered.length,
        itemBuilder: (context, i) => _ReferenceCard(
          reference: filtered[i],
          isGerant: isGerant,
          onOpen: () => showProductDetailDialog(context, filtered[i].id),
          onDelete: () => _confirmDelete(filtered[i]),
        ),
      ),
    );
  }
}

/// Seuils de couleur du badge « Variantes » — indépendants du statut agrégé
/// (is_rupture/is_stock_bas) : rouge = plus de stock, bleu = 2 ou moins,
/// vert = 3 ou plus. Mêmes seuils que le web (`variantStockBadgeClass`).
Color _variantChipColor(int stock) {
  if (stock <= 0) return const Color(0xFFEF4444);
  if (stock <= 2) return const Color(0xFF3B82F6);
  return const Color(0xFF10B981);
}

/// Une ligne du tableau web, en carte : photo, sous-type, marque,
/// référence, prix actuel + marge (gérant), prix de vente, variantes, stock
/// total, statut ; carte cliquable (fiche détail) + menu Modifier /
/// Supprimer pour le gérant.
class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    required this.reference,
    required this.isGerant,
    required this.onOpen,
    required this.onDelete,
  });

  final ProductReference reference;
  final bool isGerant;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final variants = reference.variants;
    final rupture = variants.any((v) => v.isRupture);
    final basStock = variants.any((v) => v.isStockBas);
    final total = variants.fold<int>(0, (s, v) => s + v.stockActuel);
    final marge = reference.prixVente - reference.prixAchat;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CatalogPhoto(url: reference.photo, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${reference.categoryName} · ${reference.typeName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: muted),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: reference.brandName, style: const TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: ' ${reference.referenceName}'),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                        ),
                        if (!reference.actif)
                          Text('Inactive', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
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
                          value: onOpen,
                          child: const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Modifier'),
                          ),
                        ),
                        PopupMenuItem(
                          value: onDelete,
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
                  if (isGerant) _PriceStat(label: 'Prix actuel', value: arFmt(reference.prixAchat)),
                  _PriceStat(label: 'Prix de vente', value: arFmt(reference.prixVente)),
                  if (isGerant)
                    _PriceStat(label: 'Marge', value: arFmt(marge), color: marge >= 0 ? Colors.green : Colors.red),
                  _PriceStat(label: 'Stock total', value: '$total'),
                ],
              ),
              const SizedBox(height: 8),
              if (variants.isEmpty)
                Text('Aucune', style: theme.textTheme.bodySmall?.copyWith(color: muted))
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
      ),
    );
  }
}

/// Petit couple label/valeur pour la rangée prix/marge/stock de [_ReferenceCard].
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
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

// =============================================================================
// Modifier le prix par sous-type
// =============================================================================

/// Réplique de `BulkPriceDialog` : change prix_achat/prix_vente de TOUTES
/// les références d'un sous-type en une fois — pré-rempli avec le filtre
/// sous-type courant de la liste.
class _BulkPriceDialog extends ConsumerStatefulWidget {
  const _BulkPriceDialog({this.initialTypeId});

  final int? initialTypeId;

  @override
  ConsumerState<_BulkPriceDialog> createState() => _BulkPriceDialogState();
}

class _BulkPriceDialogState extends ConsumerState<_BulkPriceDialog> {
  late int? _typeId = widget.initialTypeId;
  final _prixAchatController = TextEditingController();
  final _prixVenteController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _prixAchatController.dispose();
    _prixVenteController.dispose();
    super.dispose();
  }

  double? _parse(String raw) => raw.trim().isEmpty ? null : double.tryParse(raw.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    if (_typeId == null) {
      _toast(context, 'Choisissez un sous-type');
      return;
    }
    final prixAchat = _parse(_prixAchatController.text);
    final prixVente = _parse(_prixVenteController.text);
    if (prixAchat == null && prixVente == null) {
      _toast(context, 'Indiquez au moins un prix à modifier');
      return;
    }
    setState(() => _submitting = true);
    try {
      final updated = await ref.read(referencesProvider.notifier).bulkUpdatePrice(
            _typeId!,
            prixAchat: prixAchat,
            prixVente: prixVente,
          );
      if (!mounted) return;
      _toast(context, '$updated référence(s) mise(s) à jour');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur lors de la mise à jour groupée'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final types = ref.watch(typesProvider).value ?? const <ProductType>[];
    final references = ref.watch(referencesProvider).value ?? const <ProductReference>[];
    final matchCount = _typeId == null ? 0 : references.where((r) => r.typeId == _typeId).length;
    final plural = matchCount > 1 ? 's' : '';
    final hasPrice = _prixAchatController.text.trim().isNotEmpty || _prixVenteController.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('Modifier le prix par sous-type'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change le prix d\'achat et/ou de vente de TOUTES les références d\'un sous-type en une seule fois '
                '(ex : toutes les "Flip cover", quelle que soit la marque).',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: types.any((t) => t.id == _typeId) ? _typeId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sous-type', hintText: 'Choisir un sous-type'),
                items: [for (final t in types) DropdownMenuItem(value: t.id, child: Text(t.nom))],
                onChanged: (v) => setState(() => _typeId = v),
              ),
              if (_typeId != null) ...[
                const SizedBox(height: 4),
                Text(
                  '$matchCount référence$plural concernée$plural.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _prixAchatController,
                      decoration: const InputDecoration(labelText: 'Nouveau prix actuel', hintText: 'Laisser vide = inchangé'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _prixVenteController,
                      decoration: const InputDecoration(labelText: 'Nouveau prix de vente', hintText: 'Laisser vide = inchangé'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_typeId != null && matchCount > 0 && hasPrice) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Cette action est irréversible et modifiera directement $matchCount référence$plural.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: (_submitting || _typeId == null || matchCount == 0) ? null : _submit,
          child: Text(_submitting ? 'Mise à jour...' : 'Appliquer'),
        ),
      ],
    );
  }
}

// =============================================================================
// Paramètres du catalogue — Marques / Catégories (+ sous-types) / Couleurs
// =============================================================================

/// Marques de téléphones courantes (§8.1 du cahier des charges) — proposées
/// en un clic pour éviter de les retaper à chaque nouvelle référence.
const _kSuggestedBrands = [
  'Samsung',
  'iPhone',
  'Huawei',
  'Redmi',
  'Xiaomi',
  'Tecno',
  'Infinix',
  'Itel',
  'Oppo',
  'Realme',
  'Google Pixel',
  'Poco',
  'Vivo',
  'Honor',
];

/// Réplique de `CatalogSettingsDialog` en feuille : 3 onglets Marques
/// (défaut) / Catégories / Couleurs, pied « Fermer ».
class _CatalogSettingsSheet extends StatelessWidget {
  const _CatalogSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Paramètres du catalogue', style: theme.textTheme.titleLarge),
                        Text(
                          'Marques, catégories et couleurs utilisés dans le catalogue produits (§8 du cahier des charges).',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const TabBar(tabs: [Tab(text: 'Marques'), Tab(text: 'Catégories'), Tab(text: 'Couleurs')]),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _BrandsSettingsTab(scrollController: scrollController),
                  const _CategoriesSettingsTab(),
                  const _ColorsSettingsTab(),
                ],
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne de liste éditable (nom + renommer/supprimer) — patron partagé par
/// les marques, les couleurs et les sous-types (`CrudRow` du web) : le
/// crayon bascule la ligne en champ + OK/Annuler ; la corbeille supprime
/// immédiatement, sans confirmation (comme le web — le serveur refuse si
/// l'élément est encore utilisé).
class _CrudRow extends StatefulWidget {
  const _CrudRow({
    super.key,
    required this.label,
    required this.onRename,
    required this.onDelete,
    this.dense = false,
  });

  final String label;
  final Future<void> Function(String newName) onRename;
  final Future<void> Function() onDelete;
  final bool dense;

  @override
  State<_CrudRow> createState() => _CrudRowState();
}

class _CrudRowState extends State<_CrudRow> {
  bool _editing = false;
  late final _controller = TextEditingController(text: widget.label);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await widget.onRename(name);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = widget.dense ? 16.0 : 18.0;
    return Container(
      margin: EdgeInsets.only(bottom: widget.dense ? 2 : 6),
      padding: EdgeInsets.symmetric(horizontal: widget.dense ? 8 : 12, vertical: 2),
      decoration: widget.dense
          ? null
          : BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
      child: _editing
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: _save,
                  child: const Text('OK'),
                ),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() {
                    _controller.text = widget.label;
                    _editing = false;
                  }),
                  child: const Text('Annuler'),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: widget.dense ? TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant) : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Renommer',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit_outlined, size: iconSize),
                  onPressed: () => setState(() {
                    _controller.text = widget.label;
                    _editing = true;
                  }),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, size: iconSize, color: Colors.red),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
    );
  }
}

/// Champ + bouton « Ajouter » en bas de chaque liste.
class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.controller,
    required this.hint,
    required this.onAdd,
    this.icon = Icons.add,
    this.dense = false,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onAdd;
  final IconData icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint, isDense: true),
            style: dense ? const TextStyle(fontSize: 13) : null,
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: dense ? FilledButton.styleFrom(visualDensity: VisualDensity.compact) : null,
          onPressed: onAdd,
          icon: Icon(icon, size: 16),
          label: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _BrandsSettingsTab extends ConsumerStatefulWidget {
  const _BrandsSettingsTab({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_BrandsSettingsTab> createState() => _BrandsSettingsTabState();
}

class _BrandsSettingsTabState extends ConsumerState<_BrandsSettingsTab> {
  final _newController = TextEditingController();
  String? _addingBrand;

  @override
  void dispose() {
    _newController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final nom = _newController.text.trim();
    if (nom.isEmpty) return;
    try {
      await ref.read(brandsProvider.notifier).create(nom);
      if (!mounted) return;
      _toast(context, 'Marque ajoutée');
      _newController.clear();
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _addSuggested(String nom) async {
    setState(() => _addingBrand = nom);
    try {
      await ref.read(brandsProvider.notifier).create(nom);
      if (mounted) _toast(context, 'Marque ajoutée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    } finally {
      if (mounted) setState(() => _addingBrand = null);
    }
  }

  Future<void> _rename(Brand b, String nom) async {
    try {
      await ref.read(brandsProvider.notifier).rename(b.id, nom);
      if (mounted) _toast(context, 'Marque renommée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _remove(Brand b) async {
    try {
      await ref.read(brandsProvider.notifier).delete(b.id);
      if (mounted) _toast(context, 'Marque supprimée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Suppression impossible (marque utilisée par des références)'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final nom in _kSuggestedBrands)
              Builder(builder: (context) {
                final already = brands.any((b) => b.nom.toLowerCase() == nom.toLowerCase());
                final adding = _addingBrand == nom;
                return ActionChip(
                  avatar: adding
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(already ? Icons.check : Icons.add, size: 16),
                  label: Text(nom),
                  backgroundColor: already ? theme.colorScheme.secondaryContainer : null,
                  onPressed: (already || adding) ? null : () => _addSuggested(nom),
                );
              }),
          ],
        ),
        const SizedBox(height: 12),
        if (brands.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Aucune marque.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          )
        else
          for (final b in brands)
            _CrudRow(
              key: ValueKey('brand-${b.id}'),
              label: b.nom,
              onRename: (nom) => _rename(b, nom),
              onDelete: () => _remove(b),
            ),
        const SizedBox(height: 8),
        _AddRow(controller: _newController, hint: 'Nouvelle marque', onAdd: _add),
      ],
    );
  }
}

class _ColorsSettingsTab extends ConsumerStatefulWidget {
  const _ColorsSettingsTab();

  @override
  ConsumerState<_ColorsSettingsTab> createState() => _ColorsSettingsTabState();
}

class _ColorsSettingsTabState extends ConsumerState<_ColorsSettingsTab> {
  final _newController = TextEditingController();

  @override
  void dispose() {
    _newController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final nom = _newController.text.trim();
    if (nom.isEmpty) return;
    try {
      await ref.read(colorsProvider.notifier).create(nom);
      if (!mounted) return;
      _toast(context, 'Couleur ajoutée');
      _newController.clear();
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _rename(ProductColor c, String nom) async {
    try {
      await ref.read(colorsProvider.notifier).rename(c.id, nom);
      if (mounted) _toast(context, 'Couleur renommée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _remove(ProductColor c) async {
    try {
      await ref.read(colorsProvider.notifier).delete(c.id);
      if (mounted) _toast(context, 'Couleur supprimée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur lors de la suppression'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ref.watch(colorsProvider).value ?? const <ProductColor>[];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Liste des couleurs proposées dans le sélecteur de variante.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (colors.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Aucune couleur.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          )
        else
          for (final c in colors)
            _CrudRow(
              key: ValueKey('color-${c.id}'),
              label: c.nom,
              onRename: (nom) => _rename(c, nom),
              onDelete: () => _remove(c),
            ),
        const SizedBox(height: 8),
        _AddRow(controller: _newController, hint: 'Nouvelle couleur (ex: Bleu)', onAdd: _add),
      ],
    );
  }
}

class _CategoriesSettingsTab extends ConsumerStatefulWidget {
  const _CategoriesSettingsTab();

  @override
  ConsumerState<_CategoriesSettingsTab> createState() => _CategoriesSettingsTabState();
}

class _CategoriesSettingsTabState extends ConsumerState<_CategoriesSettingsTab> {
  final _newCatController = TextEditingController();
  bool _newCatAvecCouleurs = true;
  // Un champ « Nouveau sous-type » propre à chaque catégorie.
  final Map<int, TextEditingController> _newTypeControllers = {};

  @override
  void dispose() {
    _newCatController.dispose();
    for (final c in _newTypeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _typeControllerFor(int categoryId) =>
      _newTypeControllers.putIfAbsent(categoryId, TextEditingController.new);

  Future<void> _addCategory() async {
    final nom = _newCatController.text.trim();
    if (nom.isEmpty) return;
    final ordre = ref.read(categoriesProvider).value?.length ?? 0;
    try {
      await ref.read(categoriesProvider.notifier).create(nom, ordre, avecCouleurs: _newCatAvecCouleurs);
      if (!mounted) return;
      _toast(context, 'Catégorie ajoutée');
      setState(() {
        _newCatController.clear();
        _newCatAvecCouleurs = true;
      });
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _renameCategory(ProductCategory c, String nom) async {
    try {
      await ref.read(categoriesProvider.notifier).rename(c.id, nom);
      if (mounted) _toast(context, 'Catégorie renommée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _removeCategory(ProductCategory c) async {
    try {
      await ref.read(categoriesProvider.notifier).delete(c.id);
      if (mounted) _toast(context, 'Catégorie supprimée');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Suppression impossible (des sous-types en dépendent encore)'));
    }
  }

  /// Bascule immédiate, sans toast de succès (comme le web).
  Future<void> _toggleAvecCouleurs(ProductCategory c) async {
    try {
      await ref.read(categoriesProvider.notifier).setAvecCouleurs(c.id, !c.avecCouleurs);
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _addType(int categoryId) async {
    final controller = _typeControllerFor(categoryId);
    final nom = controller.text.trim();
    if (nom.isEmpty) return;
    try {
      await ref.read(typesProvider.notifier).create(categoryId, nom);
      if (!mounted) return;
      _toast(context, 'Sous-type ajouté');
      controller.clear();
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _renameType(ProductType t, String nom) async {
    try {
      await ref.read(typesProvider.notifier).rename(t.id, nom);
      if (mounted) _toast(context, 'Sous-type renommé');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Erreur'));
    }
  }

  Future<void> _removeType(ProductType t) async {
    try {
      await ref.read(typesProvider.notifier).delete(t.id);
      if (mounted) _toast(context, 'Sous-type supprimé');
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, 'Suppression impossible (des références en dépendent encore)'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final types = ref.watch(typesProvider).value ?? const <ProductType>[];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Catégorie (ex. Housse, Cache écran, Chargeur) → sous-type (ex. Flip cover, Privacy, Écouteur). '
          '« Sans couleurs » pour les catégories sans déclinaison couleur (chargeur, écouteur…) — la référence '
          'n\'a alors qu\'une quantité, sans gestion de couleur.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        // ---- Nouvelle catégorie ----------------------------------------
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NOUVELLE CATÉGORIE', style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              _AddRow(controller: _newCatController, hint: 'Ex. Accessoires', onAdd: _addCategory, icon: Icons.create_new_folder_outlined),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Avec couleurs'), icon: Icon(Icons.palette_outlined, size: 16)),
                    ButtonSegment(value: false, label: Text('Sans couleurs')),
                  ],
                  selected: {_newCatAvecCouleurs},
                  onSelectionChanged: (s) => setState(() => _newCatAvecCouleurs = s.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '« Avec couleurs » : housse, cache écran… « Sans couleurs » : chargeur, écouteur… — une seule quantité par référence.',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (categories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Aucune catégorie.', style: TextStyle(color: muted))),
          )
        else
          for (final c in categories)
            _CategoryCard(
              key: ValueKey('category-${c.id}'),
              category: c,
              types: types.where((t) => t.categoryId == c.id).toList(),
              newTypeController: _typeControllerFor(c.id),
              onRename: (nom) => _renameCategory(c, nom),
              onDelete: () => _removeCategory(c),
              onToggleAvecCouleurs: () => _toggleAvecCouleurs(c),
              onAddType: () => _addType(c.id),
              onRenameType: _renameType,
              onDeleteType: _removeType,
            ),
      ],
    );
  }
}

/// Une carte par catégorie : icône, nom (renommable en place), badge
/// cliquable « Avec couleurs » / « Sans couleurs », corbeille ; puis la
/// sous-liste indentée de ses sous-types et le champ « Nouveau sous-type ».
class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    super.key,
    required this.category,
    required this.types,
    required this.newTypeController,
    required this.onRename,
    required this.onDelete,
    required this.onToggleAvecCouleurs,
    required this.onAddType,
    required this.onRenameType,
    required this.onDeleteType,
  });

  final ProductCategory category;
  final List<ProductType> types;
  final TextEditingController newTypeController;
  final Future<void> Function(String nom) onRename;
  final Future<void> Function() onDelete;
  final Future<void> Function() onToggleAvecCouleurs;
  final Future<void> Function() onAddType;
  final Future<void> Function(ProductType t, String nom) onRenameType;
  final Future<void> Function(ProductType t) onDeleteType;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _editing = false;
  late final _controller = TextEditingController(text: widget.category.nom);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nom = _controller.text.trim();
    if (nom.isEmpty) return;
    await widget.onRename(nom);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final avecCouleurs = widget.category.avecCouleurs;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editing)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: const InputDecoration(isDense: true),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: _save,
                  child: const Text('OK'),
                ),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() {
                    _controller.text = widget.category.nom;
                    _editing = false;
                  }),
                  child: const Text('Annuler'),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.category.nom, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                // Badge cliquable : bascule immédiate du drapeau.
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: avecCouleurs ? const Icon(Icons.palette_outlined, size: 14) : null,
                  label: Text(avecCouleurs ? 'Avec couleurs' : 'Sans couleurs', style: const TextStyle(fontSize: 12)),
                  backgroundColor: avecCouleurs ? theme.colorScheme.secondaryContainer : null,
                  onPressed: widget.onToggleAvecCouleurs,
                ),
                IconButton(
                  tooltip: 'Renommer',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => setState(() {
                    _controller.text = widget.category.nom;
                    _editing = true;
                  }),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.types.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Aucun sous-type.', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  )
                else
                  for (final t in widget.types)
                    _CrudRow(
                      key: ValueKey('type-${t.id}'),
                      label: t.nom,
                      dense: true,
                      onRename: (nom) => widget.onRenameType(t, nom),
                      onDelete: () => widget.onDeleteType(t),
                    ),
                const SizedBox(height: 4),
                _AddRow(
                  controller: widget.newTypeController,
                  hint: 'Nouveau sous-type',
                  onAdd: widget.onAddType,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Onglets Ruptures / Mouvements (gérant) — raccourcis propres à l'app
// =============================================================================

/// Onglet « Ruptures » (§7.5 README) — produits en rupture ou sous le seuil
/// d'alerte, avec export PDF de réapprovisionnement et ajustement rapide.
class _RupturesTab extends ConsumerWidget {
  const _RupturesTab();

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(stockRepositoryProvider).ruptureExportPdfBytes();
      final file = XFile.fromData(bytes, name: 'reapprovisionnement.pdf', mimeType: 'application/pdf');
      await SharePlus.instance.share(ShareParams(files: [file], text: 'Liste de réapprovisionnement'));
    } catch (e) {
      if (context.mounted) _toast(context, ApiClient.messageFromError(e));
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
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
              heroTag: 'catalog-fab-ruptures-pdf',
              onPressed: () => _exportPdf(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exporter PDF'),
            )
          : null,
    );
  }
}

class _RuptureTile extends StatelessWidget {
  const _RuptureTile({required this.item});
  final RuptureItem item;

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => showAdjustStockDialog(
                context,
                variantId: item.id,
                productLabel: '${item.brandName} ${item.referenceName}',
                couleur: item.couleur,
                stockActuel: item.stockActuel,
                seuilAlerte: item.seuilAlerte,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Onglet « Mouvements » (§7.4 README) — historique des entrées/sorties de
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
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
        heroTag: 'catalog-fab-adjust',
        onPressed: () async {
          final variant = await showDialog<ProductVariant>(context: context, builder: (_) => const _VariantPickerDialog());
          if (variant == null || !context.mounted) return;
          await showAdjustStockDialog(
            context,
            variantId: variant.id,
            productLabel: '${variant.brandName} ${variant.referenceName}',
            couleur: variant.couleur,
            stockActuel: variant.stockActuel,
            seuilAlerte: variant.seuilAlerte,
          );
        },
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

/// Sélecteur de variante (accès depuis l'onglet Mouvements, sans variante
/// pré-sélectionnée) : renvoie la variante choisie, l'appelant ouvre ensuite
/// le dialog d'ajustement.
class _VariantPickerDialog extends ConsumerStatefulWidget {
  const _VariantPickerDialog();

  @override
  ConsumerState<_VariantPickerDialog> createState() => _VariantPickerDialogState();
}

class _VariantPickerDialogState extends ConsumerState<_VariantPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final references = ref.watch(referencesProvider).value ?? const <ProductReference>[];
    final q = _query.trim().toLowerCase();
    final variants = <(ProductVariant, String)>[
      for (final r in references)
        for (final v in r.variants) (v, '${r.brandName} ${r.referenceName} — ${v.couleur}'),
    ].where((e) => q.isEmpty || e.$2.toLowerCase().contains(q)).toList();

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
                        final (variant, label) = variants[i];
                        return ListTile(
                          title: Text(label),
                          subtitle: Text('Stock actuel : ${variant.stockActuel}'),
                          onTap: () => Navigator.of(context).pop(variant),
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
}
