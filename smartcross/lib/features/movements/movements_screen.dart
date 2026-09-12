import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/permissions.dart';
import '../../models/catalog.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart';
import '../../state/realtime_provider.dart';
import '../../state/stock_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';
import 'movement_view_data.dart';

/// Historique complet des mouvements de stock (§7.4/§10 Smartreadme.md) —
/// portage de `frontend/app/(app)/movements/page.tsx`.
///
/// Écran en LECTURE SEULE : aucune création/modification/suppression n'est
/// possible ici, exactement comme la page web. Il rassemble :
///   * 3 KPI (total sorties / total entrées / nombre de mouvements) calculés
///     sur les filtres du tableau ;
///   * un bloc « statistiques produits » avec sa PROPRE plage de dates
///     (top 5 des plus vendus + 5 produits sans mouvement) ;
///   * la liste chronologique filtrable (recherche + plage de dates) ;
///   * le regroupement « Mouvements par jour » avec sélecteur de jour.
///
/// Gating (réplique de `useCurrentUser`) : l'export est réservé à `isAdmin`
/// (role === 'admin'), le badge Magasin à `isGerant` (admin || magasin). La
/// page elle-même n'est jamais refusée — le serveur scope déjà les
/// mouvements au(x) magasin(s) accessibles (StockMovementViewSet).
class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({super.key});

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  /// Terme de recherche débouncé (250 ms, comme `useDebouncedValue`).
  String _search = '';

  /// Filtres du tableau (partagés avec les 3 KPI et le sélecteur de jour).
  DateTime? _startDate;
  DateTime? _endDate;

  /// Filtres indépendants du bloc statistiques produits.
  DateTime? _statsStart;
  DateTime? _statsEnd;

  bool _exporting = false;

  /// Rechargement NON silencieux en cours (bouton « Actualiser », bouton
  /// « Réessayer »). Riverpod 3 conserve la valeur précédente quand un
  /// notifier repasse en `AsyncLoading` : `hasValue` ne permet donc pas de
  /// distinguer ce rechargement du refresh silencieux du WebSocket — l'écran
  /// s'en souvient lui-même, comme le `loading` de la page web.
  bool _refreshing = false;

  /// Debounce 400 ms des événements temps réel (`useRealtimeRefresh`).
  Timer? _realtimeDebounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _realtimeDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // met à jour le bouton « effacer » sans attendre.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _search = value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _search = '');
  }

  /// Bouton « Actualiser » : refetch NON silencieux (on repasse en
  /// chargement, comme les skeletons du web, boutons désactivés).
  /// `fetchData()` côté web recharge les mouvements ET le catalogue
  /// (`Promise.all`) : on attend les deux.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        ref.read(referencesProvider.notifier).refreshSilencieux(),
        ref.read(movementsProvider(null).notifier).refresh(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    _signalRefreshError();
  }

  /// Tirer-pour-rafraîchir : équivalent du refresh SILENCIEUX
  /// (`fetchData(true)`) — les données restent à l'écran pendant le
  /// rechargement.
  Future<void> _silentRefresh() async {
    await Future.wait([
      ref.read(referencesProvider.notifier).refreshSilencieux(),
      ref.read(movementsProvider(null).notifier).refreshSilencieux(),
    ]);
    _signalRefreshError();
  }

  /// Web : `catch (err) { console.error(...) }` — les données précédentes
  /// restent affichées, sans message. Ici aussi la page garde ses données,
  /// mais l'échec d'un rechargement demandé par l'utilisateur lui est
  /// signalé (l'écran d'erreur plein ne s'affiche que s'il n'y a rien à
  /// montrer).
  void _signalRefreshError() {
    if (!mounted) return;
    final movements = ref.read(movementsProvider(null));
    final references = ref.read(referencesProvider);
    final Object? error = movements.hasError && movements.hasValue
        ? movements.error
        : references.hasError && references.hasValue
            ? references.error
            : null;
    if (error != null) _snack(ApiClient.messageFromError(error));
  }

  // --- Filtrage ------------------------------------------------------------

  List<MovementView> _tableFiltered(List<MovementView> all) {
    final term = _search.trim().toLowerCase();
    return all.where((m) {
      final matchesTerm = term.isEmpty || m.searchHaystack.contains(term);
      final day = m.day;
      final matchesStart = _startDate == null || (day != null && !day.isBefore(_startDate!));
      final matchesEnd = _endDate == null || (day != null && !day.isAfter(_endDate!));
      return matchesTerm && matchesStart && matchesEnd;
    }).toList();
  }

  List<MovementView> _statsFiltered(List<MovementView> all) {
    return all.where((m) {
      final day = m.day;
      final matchesStart = _statsStart == null || (day != null && !day.isBefore(_statsStart!));
      final matchesEnd = _statsEnd == null || (day != null && !day.isAfter(_statsEnd!));
      return matchesStart && matchesEnd;
    }).toList();
  }

  /// Libellé « Période analysée » — le web y reprend les valeurs BRUTES des
  /// champs date (`AAAA-MM-JJ`), non localisées : identique ici.
  String get _statsPeriodLabel {
    final start = _statsStart;
    final end = _statsEnd;
    if (start != null && end != null) {
      return 'du ${movementIsoDayFmt.format(start)} au ${movementIsoDayFmt.format(end)}';
    }
    if (start != null) return 'depuis le ${movementIsoDayFmt.format(start)}';
    if (end != null) return "jusqu'au ${movementIsoDayFmt.format(end)}";
    return 'toute la période';
  }

  /// Jour sélectionné via le calendrier : le web considère qu'un jour est
  /// filtré quand `startDate === endDate` et non vide.
  DateTime? get _selectedDay =>
      _startDate != null && _endDate != null && _startDate == _endDate ? _startDate : null;

  // --- Sélecteurs de date --------------------------------------------------

  Future<DateTime?> _pickDate({DateTime? initial, DateTime? minimum}) async {
    final today = appToday();
    var init = initial ?? today;
    if (minimum != null && init.isBefore(minimum)) init = minimum;
    return showDatePicker(
      context: context,
      initialDate: init,
      firstDate: minimum ?? DateTime(2020),
      lastDate: today.add(const Duration(days: 365)),
    );
  }

  // --- Export --------------------------------------------------------------

  Future<void> _export(List<MovementView> filtered) async {
    if (filtered.isEmpty) {
      _snack('Aucun mouvement à exporter pour les filtres sélectionnés');
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = buildMovementsXlsx(
        headers: kMovementsExportHeaders,
        rows: filtered.map(movementExportRow).toList(),
      );
      final file = XFile.fromData(
        bytes,
        name: movementsExportFileName(),
        mimeType: kXlsxMimeType,
      );
      await SharePlus.instance.share(
        ShareParams(files: [file], text: 'Mouvements de stock'),
      );
      _snack('${filtered.length} mouvement(s) exporté(s)');
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Temps réel (`useRealtimeRefresh(['stock_movement','product_variant',
    // 'order'], () => fetchData(true))`, debounce 400 ms) : les mouvements
    // se rechargent d'eux-mêmes (le notifier écoute le tick) ; le catalogue,
    // partagé avec les autres écrans, est rechargé silencieusement ici.
    ref.listen(realtimeTickProvider, (_, _) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) ref.read(referencesProvider.notifier).refreshSilencieux();
      });
    });

    final movementsAsync = ref.watch(movementsProvider(null));
    final referencesAsync = ref.watch(referencesProvider);
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin ?? false;
    final isManager = user?.isGerant ?? false;

    final all = (movementsAsync.value ?? []).map(MovementView.fromModel).toList();
    final filtered = _tableFiltered(all);
    // Chargement « bloquant » : premier chargement (mouvements ET catalogue,
    // comme le `Promise.all` du web) et « Actualiser ». Un rafraîchissement
    // déclenché par le WebSocket garde les données à l'écran (refresh
    // silencieux du web : ni skeleton ni spinner).
    final movementsInitial = !movementsAsync.hasValue && !movementsAsync.hasError;
    final referencesInitial = !referencesAsync.hasValue && !referencesAsync.hasError;
    final loading = _refreshing || movementsInitial || referencesInitial;
    final movementsError = movementsAsync.hasError && !movementsAsync.hasValue ? movementsAsync.error : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mouvements de stock'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: loading ? null : _refresh,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          if (isAdmin)
            IconButton(
              tooltip: 'Exporter XLSX',
              onPressed: loading || filtered.isEmpty || _exporting ? null : () => _export(filtered),
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
        ],
      ),
      body: loading
          ? const LoadingState()
          : movementsError != null
              ? ErrorState(
                  message: ApiClient.messageFromError(movementsError),
                  onRetry: _refresh,
                )
              : _buildContent(
                  context,
                  all: all,
                  filtered: filtered,
                  references: referencesAsync.value ?? const <ProductReference>[],
                  referencesError: referencesAsync.hasError && !referencesAsync.hasValue
                      ? ApiClient.messageFromError(referencesAsync.error!)
                      : null,
                  isManager: isManager,
                ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required List<MovementView> all,
    required List<MovementView> filtered,
    required List<ProductReference> references,
    required String? referencesError,
    required bool isManager,
  }) {
    final theme = Theme.of(context);
    final statsSource = _statsFiltered(all);
    final stats = _computeStats(statsSource, references);

    final totalExits = filtered.fold<int>(0, (sum, m) => sum + (m.change < 0 ? m.change.abs() : 0));
    final totalEntries = filtered.fold<int>(0, (sum, m) => sum + (m.change > 0 ? m.change : 0));

    // Marque · catégorie de la sous-ligne « Produit » : le web indexe les
    // références par leur id alors que le mouvement porte un ID DE VARIANTE.
    // On résout d'abord par variante (résultat correct), puis par id de
    // référence (comportement littéral du web) — jamais moins d'info.
    final refByVariantId = <int, ProductReference>{};
    final refById = <int, ProductReference>{};
    for (final r in references) {
      refById[r.id] = r;
      for (final v in r.variants) {
        refByVariantId[v.id] = r;
      }
    }
    String brandCategoryOf(MovementView m) {
      final ref = refByVariantId[m.productVariantId] ?? refById[m.productVariantId];
      if (ref == null) return '';
      return [ref.brandName, ref.categoryName].where((e) => e.isNotEmpty).join(' · ');
    }

    // Regroupement par jour (jour métier Antananarivo), construit sur les
    // mouvements DÉJÀ filtrés — comme `groupedByDay` côté web.
    final groups = <DateTime, List<MovementView>>{};
    for (final m in filtered) {
      final day = m.day;
      if (day == null) continue;
      groups.putIfAbsent(day, () => []).add(m);
    }
    final today = appToday();
    final hideToday = _selectedDay == null;
    final sortedDays = groups.keys.where((d) => !hideToday || d != today).toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _silentRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'Historique complet des mouvements de stock',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                _KpiRow(totalExits: totalExits, totalEntries: totalEntries, count: filtered.length),
                const SizedBox(height: 12),
                _statsFilterCard(context),
                const SizedBox(height: 12),
                _statsListCard(
                  context,
                  title: 'Produits les plus vendus',
                  icon: Icons.trending_up,
                  color: const Color(0xFF16A34A),
                  description: 'Sorties de stock sur la période ($_statsPeriodLabel)',
                  emptyMessage: 'Aucune vente enregistrée sur cette période.',
                  entries: stats.fastest,
                  badgeSuffix: 'unités',
                  errorMessage: null,
                ),
                const SizedBox(height: 12),
                _statsListCard(
                  context,
                  title: 'Produits sans mouvement',
                  icon: Icons.arrow_downward,
                  color: const Color(0xFFEA580C),
                  description: 'Aucun mouvement sur la période ($_statsPeriodLabel)',
                  emptyMessage: 'Tous les produits ont eu au moins un mouvement sur cette période.',
                  entries: stats.slowest,
                  badgeSuffix: 'mouvement',
                  errorMessage: referencesError,
                ),
                const SizedBox(height: 20),
                Text(
                  'Filtre mouvements par date',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _tableFilters(context),
                const SizedBox(height: 16),
                Text(
                  'Historique des mouvements de stock',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${filtered.length} mouvement(s) affiché(s)',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          if (filtered.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: EmptyState(message: 'Aucun mouvement enregistré', icon: Icons.swap_vert),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final m = filtered[i];
                  return _MovementCard(
                    movement: m,
                    brandCategory: brandCategoryOf(m),
                    isManager: isManager,
                    onTap: () => _showMovementDetails(m, brandCategoryOf(m), isManager),
                    onShowVariants: () => _showVariants(m),
                  );
                },
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
            sliver: SliverToBoxAdapter(child: _daySectionHeader(context)),
          ),
          if (sortedDays.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                child: Text(
                  'Aucun mouvement pour cette période.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverList.builder(
                itemCount: sortedDays.length,
                itemBuilder: (context, i) {
                  final day = sortedDays[i];
                  final items = groups[day]!;
                  return _DayCard(
                    heading: frDayHeading(day, today),
                    movements: items,
                    isManager: isManager,
                    onTapMovement: (m) => _showMovementDetails(m, brandCategoryOf(m), isManager),
                  );
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  // --- Blocs ---------------------------------------------------------------

  Widget _statsFilterCard(BuildContext context) {
    final theme = Theme.of(context);
    final canReset = _statsStart != null || _statsEnd != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtre statistiques produits', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Période analysée : $_statsPeriodLabel',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DateField(
                  label: 'Date début',
                  value: _statsStart,
                  onPick: () async {
                    final picked = await _pickDate(initial: _statsStart);
                    if (picked == null) return;
                    setState(() {
                      _statsStart = DateTime(picked.year, picked.month, picked.day);
                      // Le web borne la date de fin par `min={statsStartDate}`.
                      if (_statsEnd != null && _statsEnd!.isBefore(_statsStart!)) _statsEnd = null;
                    });
                  },
                  onClear: _statsStart == null ? null : () => setState(() => _statsStart = null),
                ),
                _DateField(
                  label: 'Date fin',
                  value: _statsEnd,
                  onPick: () async {
                    final picked = await _pickDate(initial: _statsEnd, minimum: _statsStart);
                    if (picked == null) return;
                    setState(() => _statsEnd = DateTime(picked.year, picked.month, picked.day));
                  },
                  onClear: _statsEnd == null ? null : () => setState(() => _statsEnd = null),
                ),
                OutlinedButton(
                  onPressed: canReset
                      ? () => setState(() {
                            _statsStart = null;
                            _statsEnd = null;
                          })
                      : null,
                  child: const Text('Réinitialiser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsListCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required String description,
    required String emptyMessage,
    required List<_ProductQty> entries,
    required String badgeSuffix,
    required String? errorMessage,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (errorMessage != null)
              Text(
                errorMessage,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              )
            else if (entries.isEmpty)
              Text(
                emptyMessage,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (var i = 0; i < entries.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: i == entries.length - 1
                      ? null
                      : BoxDecoration(
                          border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
                        ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entries[i].name,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(label: '${entries[i].qty} $badgeSuffix', color: color),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _tableFilters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _DateField(
              label: 'Date début',
              value: _startDate,
              onPick: () async {
                final picked = await _pickDate(initial: _startDate);
                if (picked == null) return;
                setState(() => _startDate = DateTime(picked.year, picked.month, picked.day));
              },
              onClear: _startDate == null ? null : () => setState(() => _startDate = null),
            ),
            _DateField(
              label: 'Date fin',
              value: _endDate,
              onPick: () async {
                final picked = await _pickDate(initial: _endDate);
                if (picked == null) return;
                setState(() => _endDate = DateTime(picked.year, picked.month, picked.day));
              },
              onClear: _endDate == null ? null : () => setState(() => _endDate = null),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Rechercher produit, référence, vendeur...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _clearSearch,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _daySectionHeader(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedDay;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Mouvements par jour',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await _pickDate(initial: selected);
            if (picked == null) return;
            final day = DateTime(picked.year, picked.month, picked.day);
            setState(() {
              _startDate = day;
              _endDate = day;
            });
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(selected == null ? 'Filtrer par jour' : frLongDate(selected)),
        ),
        if (selected != null)
          IconButton(
            tooltip: 'Annuler le filtre du jour',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _startDate = null;
              _endDate = null;
            }),
          ),
      ],
    );
  }

  // --- Feuilles ------------------------------------------------------------

  /// Équivalent tactile du HoverCard « {n} variantes » du web.
  void _showVariants(MovementView m) {
    final entries = m.variantEntries;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Variante(s)', style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in entries) StatusChip(label: v.label, color: kVariantBadgeColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Feuille de détail : porte les colonnes que la carte ne peut pas montrer
  /// en entier (note, auteur, magasin, référence source).
  void _showMovementDetails(MovementView m, String brandCategory, bool isManager) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final entries = m.variantEntries;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.productName.isEmpty ? 'Produit #${m.productVariantId}' : m.productName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    StatusChip(
                      label: m.signedChange,
                      color: movementChangeColor(m.change, m.movementType),
                    ),
                  ],
                ),
                if (brandCategory.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    brandCategory,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                _DetailRow(label: 'Date', value: m.formattedDate),
                _DetailRow(label: 'Référence', value: m.productReference.isEmpty ? '-' : m.productReference),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          'Variante(s)',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: entries.isEmpty
                            ? const Text('-')
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final v in entries)
                                    StatusChip(label: v.label, color: kVariantBadgeColor),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          'Type',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusChip(
                            label: m.movementType,
                            color: movementTypeColor(m.movementType),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _DetailRow(label: 'Quantité', value: m.signedChange),
                _DetailRow(label: 'Note', value: m.note.isEmpty ? '-' : m.note),
                _DetailRow(label: 'Fait par', value: m.changedByLabel),
                if (m.changedByUsername.isNotEmpty) _DetailRow(label: 'Email', value: m.changedByUsername),
                if (isManager) _DetailRow(label: 'Magasin', value: m.magasinName.isEmpty ? '-' : m.magasinName),
                if (m.sourceReference.isNotEmpty)
                  _DetailRow(label: 'Référence source', value: m.sourceReference),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Statistiques --------------------------------------------------------

  ({List<_ProductQty> fastest, List<_ProductQty> slowest}) _computeStats(
    List<MovementView> statsFiltered,
    List<ProductReference> references,
  ) {
    final soldMap = <String, int>{};
    final movedProductNames = <String>{};

    for (final m in statsFiltered) {
      final name = m.productName.isEmpty ? 'Produit inconnu' : m.productName;
      movedProductNames.add(name);
      // Le web ne retient que `product_name` (« Référence (Couleur) ») et
      // compare ensuite au nom de RÉFÉRENCE : une référence dont seule une
      // variante colorée a bougé y ressort à tort « sans mouvement ». On
      // retient aussi la référence elle-même — la règle voulue (aucun
      // mouvement sur aucune de ses variantes), sans rien perdre.
      if (m.productReference.isNotEmpty) movedProductNames.add(m.productReference);
      if (m.change < 0) {
        soldMap[name] = (soldMap[name] ?? 0) + m.change.abs();
      }
    }

    final fastest = soldMap.entries.map((e) => _ProductQty(e.key, e.value)).toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));

    // Comme le web : les 5 premières références sans mouvement, dans l'ordre
    // renvoyé par l'API (aucun tri).
    final slowest = references
        .where((p) => !movedProductNames.contains(p.referenceName))
        .take(5)
        .map((p) => _ProductQty(p.referenceName, 0))
        .toList();

    return (fastest: fastest.take(5).toList(), slowest: slowest);
  }
}

class _ProductQty {
  const _ProductQty(this.name, this.qty);
  final String name;
  final int qty;
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Les 3 KPI du haut de page — calculés sur les mouvements FILTRÉS (filtres
/// du tableau), pas sur ceux du bloc statistiques.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.totalExits, required this.totalEntries, required this.count});

  final int totalExits;
  final int totalEntries;
  final int count;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight : les 3 cartes gardent la même hauteur sans réclamer
    // une hauteur infinie dans la liste (CrossAxisAlignment.stretch seul est
    // interdit ici, le sliver ne borne pas la hauteur).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _KpiCard(
              icon: Icons.arrow_downward,
              iconColor: const Color(0xFFEF4444),
              label: 'Total sorties',
              value: '${fmtQty(totalExits)} unités',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              icon: Icons.trending_up,
              iconColor: const Color(0xFF22C55E),
              label: 'Total entrées',
              value: '${fmtQty(totalEntries)} unités',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              icon: Icons.inventory_2_outlined,
              iconColor: const Color(0xFF3B82F6),
              label: 'Nb mouvements',
              // Volontairement sans séparateur de milliers : le web affiche
              // ici la valeur brute (pas de fmt()).
              value: '$count',
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Champ de date du formulaire de filtres — remplace l'`<input type="date">`
/// du web. La croix rend le champ effaçable, ce que le navigateur permet
/// nativement mais pas `showDatePicker`.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.event, size: 16),
          label: Text(value == null ? label : movementDayFmt.format(value!)),
        ),
        if (onClear != null)
          IconButton(
            tooltip: 'Effacer $label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
            onPressed: onClear,
          ),
      ],
    );
  }
}

/// Une ligne du tableau principal, en carte : porte les colonnes Date,
/// Référence, Produit (+ marque · catégorie), Variante(s), Type, Quantité,
/// Fait par et Magasin (gérant).
class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.movement,
    required this.brandCategory,
    required this.isManager,
    required this.onTap,
    required this.onShowVariants,
  });

  final MovementView movement;
  final String brandCategory;
  final bool isManager;
  final VoidCallback onTap;
  final VoidCallback onShowVariants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final variants = movement.variantEntries;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      movement.productName.isEmpty
                          ? 'Produit #${movement.productVariantId}'
                          : movement.productName,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: movement.signedChange,
                    color: movementChangeColor(movement.change, movement.movementType),
                  ),
                ],
              ),
              if (brandCategory.isNotEmpty) Text(brandCategory, style: muted),
              const SizedBox(height: 4),
              Text(
                '${movement.formattedDate} · Réf. ${movement.productReference.isEmpty ? '-' : movement.productReference}',
                style: muted,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(
                    label: movement.movementType,
                    color: movementTypeColor(movement.movementType),
                  ),
                  if (variants.isEmpty)
                    Text('Variante : -', style: muted)
                  else if (variants.length == 1)
                    StatusChip(label: variants.first.label, color: kVariantBadgeColor)
                  else
                    InkWell(
                      onTap: onShowVariants,
                      borderRadius: BorderRadius.circular(999),
                      child: StatusChip(
                        label: '${variants.length} variantes',
                        color: kVariantBadgeColor,
                      ),
                    ),
                  if (isManager)
                    StatusChip(
                      label: movement.magasinName.isEmpty ? '-' : movement.magasinName,
                      color: kMagasinBadgeColor,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movement.changedByLabel,
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        if (movement.changedByUsername.isNotEmpty)
                          Text(movement.changedByUsername, style: muted),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une journée du bloc « Mouvements par jour » — équivalent d'une Card de
/// `DailyMovementsTable` (en-tête + lignes Heure/Produit/Type/Qté/Note/
/// Utilisateur/Magasin).
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.heading,
    required this.movements,
    required this.isManager,
    required this.onTapMovement,
  });

  final String heading;
  final List<MovementView> movements;
  final bool isManager;
  final void Function(MovementView) onTapMovement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final totalUnits = movements.fold<int>(0, (sum, m) => sum + m.change.abs());

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        // Retire les traits de l'ExpansionTile pour coller au style des
        // autres cartes de l'app.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  heading,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                label: '${movements.length} mouvement(s)',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          subtitle: Text('${fmtQty(totalUnits)} unités', style: muted),
          children: [
            for (final m in movements)
              InkWell(
                onTap: () => onTapMovement(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.formattedTime,
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m.productName.isEmpty ? 'Produit #${m.productVariantId}' : m.productName,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(
                            label: m.signedChange,
                            color: movementChangeColor(m.change, m.movementType),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusChip(label: m.movementType, color: movementTypeColor(m.movementType)),
                          if (isManager)
                            StatusChip(
                              label: m.magasinName.isEmpty ? '-' : m.magasinName,
                              color: kMagasinBadgeColor,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Note : ${m.note.isEmpty ? '-' : m.note}', style: muted),
                      Text(
                        'Par ${m.changedByLabel}'
                        '${m.changedByUsername.isEmpty ? '' : ' · ${m.changedByUsername}'}',
                        style: muted,
                      ),
                      const Divider(height: 16),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
