import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../models/stock.dart';
import '../../state/stock_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status_badge.dart';

final _dateFmt = DateFormat('dd/MM/yyyy');

/// Couleurs reprises telles quelles de la page web (classes Tailwind) : ce
/// sont des couleurs de STATUT, comme celles de `widgets/status_badge.dart`,
/// pas des couleurs de thème.
const _redOutOfStock = Color(0xFFDC2626); // text-red-600
const _orangeLowKpi = Color(0xFFF97316); // text-orange-500
const _orangeLowSection = Color(0xFFEA580C); // text-orange-600
const _yellowExpiring = Color(0xFFCA8A04); // text-yellow-600
const _redExpired = Color(0xFFB91C1C); // text-red-700

/// Ce que la carte d'une section met en avant.
enum _AlertMode { stock, expiry }

/// Produit en alerte — équivalent Flutter de l'objet renvoyé par
/// `mapReferenceToProduct()` côté web (`frontend/lib/django-client.ts`), que
/// la page `/alerts` filtre en 4 groupes.
///
/// Différence assumée : le web agrège au niveau RÉFÉRENCE
/// (`initial_quantity` = somme des `stock_actuel` des variantes,
/// `alert_threshold` = min des `seuil_alerte`), alors que l'app suit le stock
/// au niveau VARIANTE (couleur), comme tout le reste du projet
/// (`StockRepository.ruptures()`, alimenté par le même
/// `GET /catalog/references/`). Les prédicats de tri en groupes sont
/// identiques, la granularité est simplement plus fine — aucune information
/// n'est perdue, la couleur est en plus.
class _AlertProduct {
  const _AlertProduct({
    required this.id,
    required this.name,
    required this.reference,
    required this.brand,
    required this.category,
    required this.type,
    required this.couleur,
    required this.quantity,
    required this.threshold,
    required this.quantiteACommander,
    this.expiryDate,
  });

  final int id;
  final String name;
  final String reference;
  final String brand;
  final String category;
  final String type;
  final String couleur;
  final int quantity;
  final int threshold;
  final int quantiteACommander;
  final DateTime? expiryDate;

  /// Web : `outOfStock = products.filter(p => p.initial_quantity === 0)`.
  bool get isOutOfStock => quantity <= 0;

  String get label {
    final base = [brand, name].where((s) => s.isNotEmpty).join(' ');
    return couleur.isEmpty ? base : '$base — $couleur';
  }

  factory _AlertProduct.fromRupture(RuptureItem item) => _AlertProduct(
        id: item.id,
        name: item.referenceName,
        reference: item.referenceName,
        brand: item.brandName,
        category: item.categoryName,
        type: item.typeName,
        couleur: item.couleur,
        quantity: item.stockActuel,
        threshold: item.seuilAlerte,
        quantiteACommander: item.quantiteACommander,
        // `GET /catalog/references/` n'expose AUCUNE date de péremption : côté
        // web `mapReferenceToProduct()` force `expiry_date: null`, donc les
        // groupes « Expirent bientôt » / « Expirés » y valent toujours 0 et la
        // carte « Dates de péremption » n'est jamais rendue. Le calcul est
        // porté à l'identique : le jour où l'API exposera la date, il suffira
        // de la brancher ici.
        expiryDate: null,
      );
}

/// Page `/alerts` du web (`frontend/app/(app)/alerts/page.tsx`) : tableau de
/// bord LECTURE SEULE des produits nécessitant une attention (ruptures,
/// stocks sous le seuil, péremptions). Une seule action en plus côté mobile :
/// l'export PDF de réapprovisionnement (§7.5 Smartreadme.md), qui remplace le
/// « copier/coller du tableau » impossible sur téléphone.
///
/// Gating : la page web n'a AUCUN garde interne (le composant n'importe même
/// pas `useCurrentUser`) — seul le lien de menu est `adminOnly`. On reproduit
/// tel quel : le contrôle d'accès est fait en amont par `core/router.dart` /
/// `core/nav_items.dart::canAccessPath`, comme pour toutes les autres pages.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  bool _exporting = false;

  /// Rechargement NON silencieux en cours (bouton « Actualiser », bouton
  /// « Réessayer »). Riverpod 3 conserve la valeur précédente quand le
  /// notifier repasse en `AsyncLoading`, on ne peut donc pas s'appuyer sur
  /// `hasValue` pour distinguer ce rechargement du refresh silencieux du
  /// WebSocket : l'écran s'en souvient lui-même.
  bool _refreshing = false;

  /// Équivalent du bouton « Actualiser » du web : refetch NON silencieux (on
  /// repasse en chargement, comme les skeletons du web). Le refresh
  /// SILENCIEUX de `useRealtimeRefresh` est déjà assuré par
  /// `rupturesProvider`, qui écoute `realtimeTickProvider` (WebSocket §9
  /// README).
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(rupturesProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    _signalRefreshError();
  }

  /// Tirer-pour-rafraîchir : la liste reste affichée pendant l'appel
  /// (équivalent du `fetchData(true)` silencieux du web).
  Future<void> _silentRefresh() async {
    await ref.read(rupturesProvider.notifier).refreshSilencieux();
    _signalRefreshError();
  }

  /// Web : `catch { console.error(err) }` — les données précédentes restent
  /// affichées. Ici aussi la liste reste en place, mais l'échec du
  /// rechargement demandé par l'utilisateur lui est signalé.
  void _signalRefreshError() {
    if (!mounted) return;
    final after = ref.read(rupturesProvider);
    if (after.hasError && after.hasValue) _snack(ApiClient.messageFromError(after.error!));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Export PDF de réapprovisionnement (§7.5 Smartreadme.md) — construit sur
  /// les alertes AFFICHÉES, pour que le document corresponde à l'écran.
  Future<void> _exportPdf() async {
    final items = ref.read(rupturesProvider).value;
    if (items == null || items.isEmpty) {
      _snack('Aucune alerte à exporter');
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = await ref.read(stockRepositoryProvider).ruptureExportPdfBytes(items: items);
      final file = XFile.fromData(bytes, name: 'alertes-reapprovisionnement.pdf', mimeType: 'application/pdf');
      await SharePlus.instance.share(
        ShareParams(files: [file], text: 'Alertes de stock — liste de réapprovisionnement'),
      );
      _snack('${items.length} alerte(s) exportée(s)');
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rupturesProvider);
    // Chargement « bloquant » : premier chargement et « Actualiser »
    // uniquement. Un rafraîchissement déclenché par le WebSocket garde les
    // données à l'écran, sans indicateur (web : loading reste false).
    final initialLoading = !async.hasValue && !async.hasError;
    final loading = _refreshing || initialLoading;
    final items = (async.value ?? const <RuptureItem>[]).map(_AlertProduct.fromRupture).toList();

    // Jour de référence à l'heure d'Antananarivo (core/app_time.dart) : le web
    // fait `new Date()` / `+30 jours`.
    final today = appToday();
    final in30Days = today.add(const Duration(days: 30));

    final outOfStock = items.where((p) => p.isOutOfStock).toList();
    final lowStock = items.where((p) => !p.isOutOfStock).toList();
    final expiringSoon = items
        .where((p) => p.expiryDate != null && !p.expiryDate!.isAfter(in30Days) && !p.expiryDate!.isBefore(today))
        .toList();
    final expired = items.where((p) => p.expiryDate != null && p.expiryDate!.isBefore(today)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertes'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: loading ? null : _refresh,
              icon: loading
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Actualiser'),
            ),
          ),
        ],
      ),
      body: _buildBody(
        async: async,
        loading: loading,
        outOfStock: outOfStock,
        lowStock: lowStock,
        expiringSoon: expiringSoon,
        expired: expired,
        today: today,
      ),
      floatingActionButton: items.isEmpty || loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _exporting ? null : _exportPdf,
              icon: _exporting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_exporting ? 'Export…' : 'Exporter PDF'),
            ),
    );
  }

  Widget _buildBody({
    required AsyncValue<List<RuptureItem>> async,
    required bool loading,
    required List<_AlertProduct> outOfStock,
    required List<_AlertProduct> lowStock,
    required List<_AlertProduct> expiringSoon,
    required List<_AlertProduct> expired,
    required DateTime today,
  }) {
    // Web : pendant `loading`, chaque KPI et chaque tableau est remplacé par
    // un Skeleton — ici l'indicateur de chargement partagé.
    if (loading) return const LoadingState();
    // Le web se contente d'un `console.error` et garde les données
    // précédentes : on n'affiche donc l'écran d'erreur que s'il n'y a rien à
    // montrer, sinon la liste reste en place.
    if (async.hasError && !async.hasValue) {
      return ErrorState(message: ApiClient.messageFromError(async.error!), onRetry: _refresh);
    }

    return RefreshIndicator(
      onRefresh: _silentRefresh,
      child: ListView(
        // Tirer-pour-rafraîchir possible même quand la page tient dans
        // l'écran (peu d'alertes).
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          Text(
            'Produits nécessitant une attention',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          KpiGrid(
            children: [
              KpiCard(
                label: 'Rupture de stock',
                value: '${outOfStock.length}',
                icon: Icons.inventory_2_outlined,
                accentColor: _redOutOfStock,
              ),
              KpiCard(
                label: 'Stock faible',
                value: '${lowStock.length}',
                icon: Icons.warning_amber_rounded,
                accentColor: _orangeLowKpi,
              ),
              KpiCard(
                label: 'Expirent bientôt',
                value: '${expiringSoon.length}',
                icon: Icons.warning_amber_rounded,
                accentColor: _yellowExpiring,
              ),
              KpiCard(
                label: 'Expirés',
                value: '${expired.length}',
                icon: Icons.warning_amber_rounded,
                accentColor: _redExpired,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AlertSection(
            title: 'Rupture de stock',
            icon: Icons.inventory_2_outlined,
            color: _redOutOfStock,
            items: outOfStock,
            emptyMessage: 'Aucun produit en rupture de stock',
            mode: _AlertMode.stock,
            today: today,
          ),
          _AlertSection(
            title: 'Stock faible',
            description: "Quantité en dessous du seuil d'alerte",
            icon: Icons.warning_amber_rounded,
            color: _orangeLowSection,
            items: lowStock,
            emptyMessage: 'Tous les stocks sont au-dessus du seuil d\'alerte',
            mode: _AlertMode.stock,
            today: today,
          ),
          // Carte rendue UNIQUEMENT s'il y a au moins un produit concerné —
          // exactement comme le web (`{(expiringSoon.length > 0 ||
          // expired.length > 0) && (...)}`).
          if (expiringSoon.isNotEmpty || expired.isNotEmpty)
            _AlertSection(
              title: 'Dates de péremption',
              icon: Icons.warning_amber_rounded,
              color: _yellowExpiring,
              // Ordre du web : les produits DÉJÀ expirés d'abord.
              items: [...expired, ...expiringSoon],
              emptyMessage: 'Aucun produit proche de la péremption',
              mode: _AlertMode.expiry,
              today: today,
            ),
        ],
      ),
    );
  }
}

/// Une des 3 cartes de la page (`Card` + `CardHeader` + `AlertTable` du web).
class _AlertSection extends StatelessWidget {
  const _AlertSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
    required this.emptyMessage,
    required this.mode,
    required this.today,
    this.description,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<_AlertProduct> items;
  final String emptyMessage;
  final _AlertMode mode;
  final DateTime today;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$title (${items.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: EmptyState(message: emptyMessage, icon: Icons.check_circle_outline),
              )
            else
              for (final product in items) _AlertTile(product: product, mode: mode, today: today),
          ],
        ),
      ),
    );
  }
}

/// Une ligne du tableau web, transposée en carte dépliable : l'entête reprend
/// les colonnes visibles de la section, le détail déplié porte TOUTES les
/// colonnes (des trois tableaux) plus la quantité à commander.
class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.product, required this.mode, required this.today});

  final _AlertProduct product;
  final _AlertMode mode;
  final DateTime today;

  bool get _isExpired => product.expiryDate != null && product.expiryDate!.isBefore(today);

  Widget _badge() {
    if (mode == _AlertMode.expiry) {
      // Web : badge dont le texte EST la date (JJ/MM/AAAA), rouge si déjà
      // expiré, orange sinon.
      final date = product.expiryDate;
      if (date == null) return const SizedBox.shrink();
      return StatusChip(label: _dateFmt.format(date), color: _isExpired ? _redExpired : _orangeLowKpi);
    }
    // Web : 'Rupture' (rouge) si quantité nulle, sinon 'Faible' (orange).
    return product.isOutOfStock
        ? const StatusChip(label: 'Rupture', color: _redOutOfStock)
        : const StatusChip(label: 'Faible', color: _orangeLowKpi);
  }

  String _subtitle() {
    if (mode == _AlertMode.expiry) {
      return 'Réf. ${product.reference} · Qté ${product.quantity}';
    }
    final parts = <String>[
      'Réf. ${product.reference}',
      if (product.category.isNotEmpty) product.category,
      'Qté ${product.quantity}',
      'Seuil ${product.threshold}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // Supprime les liserés par défaut de l'ExpansionTile dans la carte.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Row(
          children: [
            Expanded(
              child: Text(
                product.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            _badge(),
          ],
        ),
        subtitle: Text(
          _subtitle(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          _DetailRow(label: 'Produit', value: product.name),
          _DetailRow(label: 'Référence', value: product.reference),
          _DetailRow(label: 'Marque', value: product.brand),
          _DetailRow(label: 'Catégorie', value: product.category),
          _DetailRow(label: 'Sous-type', value: product.type),
          _DetailRow(label: 'Couleur', value: product.couleur),
          _DetailRow(label: 'Qté actuelle', value: '${product.quantity}', strong: true),
          _DetailRow(label: "Seuil d'alerte", value: '${product.threshold}'),
          _DetailRow(label: 'À commander', value: '${product.quantiteACommander}'),
          if (product.expiryDate != null)
            _DetailRow(label: 'Date expiration', value: _dateFmt.format(product.expiryDate!)),
          _DetailRow(
            label: 'Statut',
            value: mode == _AlertMode.expiry
                ? (_isExpired ? 'Expiré' : 'Expire bientôt')
                : (product.isOutOfStock ? 'Rupture' : 'Faible'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Web : toute colonne sans rendu spécial affiche `p[c.key] ?? '-'`.
    final display = value.trim().isEmpty ? '-' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}
