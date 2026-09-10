import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/permissions.dart';
import '../../data/repositories/reports_repository.dart';
import '../../state/auth_provider.dart';
import '../../state/reports_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/kpi_card.dart';

final _numFmt = NumberFormat.decimalPattern('fr_FR');
final _compactFmt = NumberFormat.compact(locale: 'fr');

/// `Intl.NumberFormat('fr-MG')` du web, appliqué à `Math.round(n)`.
String _fmt(num v) => _numFmt.format(v.round());
String _ar(num v) => '${_fmt(v)} Ar';

// Palette Tailwind reprise telle quelle du web (les couleurs sémantiques des
// KPI et des tableaux ne viennent pas du ColorScheme, comme pour les badges
// de statut — voir widgets/status_badge.dart).
const _green = Color(0xFF16A34A); // text-green-600
const _emerald = Color(0xFF059669); // text-emerald-600
const _blue = Color(0xFF2563EB); // text-blue-600
const _purple = Color(0xFF9333EA); // text-purple-600
const _indigo = Color(0xFF4F46E5); // text-indigo-600
const _amber = Color(0xFFD97706); // text-amber-600
const _orange = Color(0xFFF97316); // text-orange-500
const _violet = Color(0xFF8B5CF6); // text-violet-500
const _red = Color(0xFFDC2626); // text-red-600
const _cyan = Color(0xFF0891B2); // text-cyan-600
const _chartBlue = Color(0xFF3B82F6); // fill #3b82f6 de la barre du CA

/// Écran « Rapports » — portage de `frontend/app/(app)/reports/page.tsx`.
///
/// Analyse des ventes, du stock et des performances : KPI globaux, CA
/// journalier sur 7/30/90 jours, top produits, ventes à crédit, performance
/// des vendeurs, performance par magasin (admin) et répartition des
/// mouvements de stock, plus une analyse IA générée à la demande.
///
/// Gating : comme le web, la page N'A AUCUN GARDE de rôle (l'entrée de menu
/// est réservée au gérant, mais l'écran lui-même reste accessible et les
/// données sont filtrées côté serveur). Seul `isAdmin` change quelque chose :
/// il conditionne le calcul et l'affichage de « Performance par magasin »
/// ainsi que l'envoi de `topMagasins` à l'analyse IA.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportsProvider);
    final period = ref.watch(reportsPeriodProvider);
    final isAdmin = ref.watch(authProvider).user?.isAdmin ?? false;
    final loading = async.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: loading ? null : () => ref.read(reportsProvider.notifier).refresh(),
            icon: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (async) {
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.read(reportsProvider.notifier).refresh(),
            child: _ReportsBody(
              analytics: ReportsAnalytics.compute(value, period, isAdmin),
              period: period,
            ),
          ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(reportsProvider.notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
    );
  }
}

class _ReportsBody extends ConsumerWidget {
  const _ReportsBody({required this.analytics, required this.period});

  final ReportsAnalytics analytics;
  final int period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Text('Analyse des ventes, du stock et des performances', style: muted),
        const SizedBox(height: 12),

        // --- KPI (6 cartes, mêmes libellés/couleurs/icônes que le web).
        KpiGrid(
          children: [
            KpiCard(
              label: "Chiffre d'affaires",
              value: _ar(analytics.totalRevenue),
              icon: Icons.attach_money,
              accentColor: _green,
            ),
            KpiCard(
              label: 'Bénéfice net',
              value: _ar(analytics.totalProfit),
              icon: Icons.trending_up,
              accentColor: _emerald,
            ),
            KpiCard(
              label: 'Unités vendues',
              value: _fmt(analytics.totalQty),
              icon: Icons.shopping_bag_outlined,
              accentColor: _blue,
            ),
            KpiCard(
              label: 'Transactions',
              value: '${analytics.transactions}',
              icon: Icons.shopping_bag_outlined,
              accentColor: _purple,
            ),
            KpiCard(
              label: 'Produits en stock',
              value: '${_fmt(analytics.totalStock)} u.',
              icon: Icons.inventory_2_outlined,
              accentColor: _indigo,
            ),
            KpiCard(
              label: 'Alertes stock',
              value: '${analytics.alertesStock}',
              icon: Icons.warning_amber_rounded,
              accentColor: _amber,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // --- Graphique du CA + sélecteur de période (filtre 100 % client :
        // aucun appel API n'est relancé).
        _ReportCard(
          title: "Chiffre d'affaires — $period derniers jours",
          description: 'Évolution journalière du CA',
          header: Wrap(
            spacing: 8,
            children: [
              for (final p in kReportsPeriods)
                ChoiceChip(
                  label: Text('${p}j'),
                  selected: period == p,
                  onSelected: (_) => ref.read(reportsPeriodProvider.notifier).set(p),
                ),
            ],
          ),
          child: _RevenueChart(points: analytics.revenueChart, period: period),
        ),
        const SizedBox(height: 12),

        // --- Top produits vendus (top 10 par quantité).
        _ReportCard(
          title: 'Top produits vendus',
          description: 'Classement par quantités vendues',
          child: analytics.topProducts.isEmpty
              ? const EmptyState(message: 'Aucune vente enregistrée', icon: Icons.receipt_long_outlined)
              : Column(
                  children: _withDividers([
                    for (var i = 0; i < analytics.topProducts.length; i++)
                      _ProductRow(rank: i + 1, stat: analytics.topProducts[i]),
                  ]),
                ),
        ),
        const SizedBox(height: 12),

        // --- Ventes à crédit (8 lignes max, échéance la plus proche d'abord).
        _ReportCard(
          icon: Icons.warning_amber_rounded,
          iconColor: _orange,
          title: 'Ventes à crédit',
          description: 'Paiements en attente ou partiels',
          child: analytics.unpaidSorted.isEmpty
              ? const EmptyState(message: 'Aucune vente impayée', icon: Icons.check_circle_outline)
              : Column(
                  children: _withDividers([
                    for (final sale in analytics.unpaidSorted) _UnpaidRow(sale: sale),
                  ]),
                ),
        ),
        const SizedBox(height: 12),

        // --- Performance des vendeurs (top 8 par CA).
        _ReportCard(
          icon: Icons.people_alt_outlined,
          iconColor: _blue,
          title: 'Performance des vendeurs',
          description: "Classement par chiffre d'affaires",
          child: analytics.topSellers.isEmpty
              ? const EmptyState(message: 'Aucune vente enregistrée', icon: Icons.receipt_long_outlined)
              : Column(
                  children: _withDividers([
                    for (final seller in analytics.topSellers) _SellerRow(stat: seller),
                  ]),
                ),
        ),

        // --- Performance par magasin : ADMIN UNIQUEMENT (comparaison
        // multi-magasins), liste complète non tronquée.
        if (analytics.isAdmin) ...[
          const SizedBox(height: 12),
          _ReportCard(
            icon: Icons.storefront_outlined,
            iconColor: _violet,
            title: 'Performance par magasin',
            description: "Comparaison du chiffre d'affaires entre magasins",
            child: analytics.topShops.isEmpty
                ? const EmptyState(message: 'Aucune vente enregistrée', icon: Icons.receipt_long_outlined)
                : Column(
                    children: _withDividers([
                      for (final shop in analytics.topShops) _ShopRow(stat: shop),
                    ]),
                  ),
          ),
        ],
        const SizedBox(height: 12),

        // --- Mouvements de stock sur la période sélectionnée.
        _ReportCard(
          title: 'Mouvements de stock — $period derniers jours',
          description: 'Entrées, sorties et transferts enregistrés',
          child: Row(
            children: [
              Expanded(
                child: _MovementTile(
                  icon: Icons.north_east,
                  color: _green,
                  count: analytics.movementCounts.entrees,
                  label: 'Entrées',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MovementTile(
                  icon: Icons.south_east,
                  color: _red,
                  count: analytics.movementCounts.sorties,
                  label: 'Sorties',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MovementTile(
                  icon: Icons.swap_horiz,
                  color: _cyan,
                  count: analytics.movementCounts.transferts,
                  label: 'Transferts',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // --- Analyse IA (dernier élément de la page, comme sur le web).
        _AiAnalysisCard(analytics: analytics),
      ],
    );
  }
}

/// Sépare les lignes d'un « tableau » par un filet, comme les `border-b` des
/// lignes de `<Table>` côté web.
List<Widget> _withDividers(List<Widget> rows) {
  final out = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) out.add(const Divider(height: 1));
    out.add(rows[i]);
  }
  return out;
}

/// Carte de section : titre (+ icône colorée facultative), description, et
/// éventuel bandeau d'actions — équivalent d'un `<Card>` shadcn.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.description,
    required this.child,
    this.icon,
    this.iconColor,
    this.header,
  });

  final String title;
  final String description;
  final Widget child;
  final IconData? icon;
  final Color? iconColor;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (header != null) ...[const SizedBox(height: 10), header!],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Graphique du CA journalier — équivalent du `<BarChart>` recharts
/// (hauteur 260, grille pointillée, barres bleues, tooltip au toucher).
class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.points, required this.period});

  final List<RevenuePoint> points;
  final int period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxRevenue = points.fold<double>(0, (m, p) => p.revenue > m ? p.revenue : m);
    final maxY = maxRevenue <= 0 ? 1.0 : maxRevenue * 1.15;
    final interval = maxY / 4 <= 0 ? 1.0 : maxY / 4;
    // `interval` recharts = max(floor(period / 8), 0) -> une étiquette toutes
    // les (interval + 1) barres : toutes les dates en 7j, ~8 dates en 30/90j.
    final labelStep = (period / 8).floor() + 1;

    return SizedBox(
      height: 260,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth - 48;
          final barWidth = (available / points.length * 0.7).clamp(1.5, 18.0).toDouble();
          return BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceBetween,
              maxY: maxY,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: theme.colorScheme.outlineVariant,
                  strokeWidth: 1,
                  dashArray: const [3, 3],
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      space: 4,
                      child: Text(
                        _compactFmt.format(value),
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= points.length) return const SizedBox.shrink();
                      if (index % labelStep != 0) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        space: 4,
                        child: Text(
                          points[index].label,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final point = points[group.x.clamp(0, points.length - 1)];
                    return BarTooltipItem(
                      '${point.label}\nCA : ${_ar(rod.toY)}',
                      TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].revenue,
                        color: _chartBlue,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Couple libellé/valeur — remplace une colonne de tableau du web sur mobile.
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.child, this.leading});

  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Ligne du tableau « Top produits vendus » : rang, produit, qté vendue,
/// CA généré, bénéfice.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.rank, required this.stat});

  final int rank;
  final ProductStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _RowShell(
      leading: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$rank',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _Metric(label: 'Qté vendue', value: '${stat.qty}', bold: true),
              _Metric(label: 'CA généré', value: _ar(stat.revenue)),
              _Metric(label: 'Bénéfice', value: _ar(stat.profit), color: _emerald),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ligne du tableau « Ventes à crédit » : client, produit, restant dû, statut.
class _UnpaidRow extends StatelessWidget {
  const _UnpaidRow({required this.sale});

  final ReportSale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // « En retard » dès que l'échéance est dépassée (heure d'Antananarivo),
    // sinon « En attente ».
    final overdue =
        sale.paymentDueDate != null && appLocal(sale.paymentDueDate!).isBefore(appNow());

    return _RowShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sale.customerName?.isNotEmpty == true ? sale.customerName! : 'Client anonyme',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              _CreditBadge(overdue: overdue),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sale.productName,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          _Metric(label: 'Restant dû', value: _ar(sale.remaining), color: _red, bold: true),
        ],
      ),
    );
  }
}

/// Badge de la vente à crédit : rouge plein « En retard », contour « En
/// attente » (variants `destructive` / `outline` du web).
class _CreditBadge extends StatelessWidget {
  const _CreditBadge({required this.overdue});

  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: overdue ? _red : Colors.transparent,
        border: Border.all(color: overdue ? _red : theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        overdue ? 'En retard' : 'En attente',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: overdue ? Colors.white : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Ligne du tableau « Performance des vendeurs » : vendeur, ventes, CA,
/// bénéfice.
class _SellerRow extends StatelessWidget {
  const _SellerRow({required this.stat});

  final SellerStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _RowShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _Metric(label: 'Ventes', value: '${stat.count}'),
              _Metric(label: 'CA', value: _ar(stat.revenue)),
              _Metric(label: 'Bénéfice', value: _ar(stat.profit), color: _emerald),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ligne du tableau « Performance par magasin » : magasin, qté vendue, CA,
/// bénéfice.
class _ShopRow extends StatelessWidget {
  const _ShopRow({required this.stat});

  final ShopStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _RowShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _Metric(label: 'Qté vendue', value: '${stat.qty}'),
              _Metric(label: 'CA', value: _ar(stat.revenue)),
              _Metric(label: 'Bénéfice', value: _ar(stat.profit), color: _emerald),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tuile de comptage des mouvements (entrées vertes, sorties rouges,
/// transferts cyan).
class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.icon, required this.color, required this.count, required this.label});

  final IconData icon;
  final Color color;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$count',
              style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Carte « Analyse IA Stratégique » — portage de
/// `frontend/components/ai-analysis.tsx`. Le texte généré n'est pas persisté
/// et n'est pas régénéré automatiquement par le temps réel : il devient
/// silencieusement obsolète, comme sur le web.
class _AiAnalysisCard extends ConsumerWidget {
  const _AiAnalysisCard({required this.analytics});

  final ReportsAnalytics analytics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final state = ref.watch(aiAnalysisProvider);
    final titleColor = dark ? const Color(0xFF818CF8) : const Color(0xFF4338CA);
    final gradient = dark
        ? [const Color(0xFF1E1B4B).withValues(alpha: 0.35), const Color(0xFF3B0764).withValues(alpha: 0.35)]
        : [const Color(0xFFEEF2FF), const Color(0xFFFAF5FF)];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        border: Border.all(
          color: dark ? const Color(0xFF312E81) : const Color(0xFFE0E7FF),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: titleColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Analyse IA Stratégique',
                  style: theme.textTheme.titleMedium?.copyWith(color: titleColor, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Générez une analyse basée sur le CA, le bénéfice, le stock et les produits les plus vendus.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (state.analysis.isEmpty && !state.loading)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
              ),
              onPressed: () => ref.read(aiAnalysisProvider.notifier).generate(analytics.aiPayload()),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text("Générer l'analyse"),
            )
          else if (state.loading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Génération en cours (modèle IA local — cela peut prendre plusieurs minutes)...',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                for (final width in [1.0, 0.9, 0.8, 0.85]) _SkeletonLine(widthFactor: width),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  state.analysis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: state.error
                        ? (dark ? const Color(0xFFF87171) : _red)
                        : (dark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: state.loading
                      ? null
                      : () => ref.read(aiAnalysisProvider.notifier).generate(analytics.aiPayload()),
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('Régénérer'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: 14,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}
