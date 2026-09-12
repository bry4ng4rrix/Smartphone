import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/reports.dart';
import '../../state/reports_provider.dart';
import 'sections/section_deliveries.dart';
import 'sections/section_expenses.dart';
import 'sections/section_financial.dart';
import 'sections/section_marketing.dart';
import 'sections/section_orders.dart';
import 'sections/section_overview.dart';
import 'sections/section_sales.dart';
import 'sections/section_stock.dart';
import 'widgets/kpi_card.dart' show ReportSkeleton;
import 'widgets/report_export.dart';
import 'widgets/report_filters.dart';
import 'widgets/report_printable.dart';
import 'widgets/report_tabs.dart';

/// Tableau de bord du gérant = le centre de rapports — portage de
/// `frontend/app/(app)/dashboard/page.tsx` (`ReportsCenter`).
///
/// 8 rapports dans un seul écran, un seul affiché à la fois (onglets / menu
/// « Liste des rapports » sur mobile), filtres de période communs, données
/// agrégées côté serveur (orders/reporting.py) et mises en cache par section
/// ([reportsProvider]). L'onglet et les filtres survivent à un aller-retour
/// (équivalent du `?tab=` de l'URL).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  /// Registre des sections : le widget monté pour l'onglet actif.
  static Widget _section(ReportSection s, ReportsFilter filter) => switch (s) {
        ReportSection.overview => SectionOverview(filter: filter),
        ReportSection.sales => SectionSales(filter: filter),
        ReportSection.financial => SectionFinancial(filter: filter),
        ReportSection.expenses => SectionExpenses(filter: filter),
        ReportSection.stock => SectionStock(filter: filter),
        ReportSection.orders => SectionOrders(filter: filter),
        ReportSection.deliveries => SectionDeliveries(filter: filter),
        ReportSection.marketing => SectionMarketing(filter: filter),
      };

  /// Registre des versions imprimables : réponse brute en cache → PDF.
  static ReportPrintable? _printable(ReportSection s, Map<String, dynamic> json) => switch (s) {
        ReportSection.overview => overviewPrintable(OverviewData.fromJson(json)),
        ReportSection.sales => salesPrintable(SalesData.fromJson(json)),
        ReportSection.financial => financialPrintable(FinancialData.fromJson(json)),
        ReportSection.expenses => expensesPrintable(ExpensesData.fromJson(json)),
        ReportSection.stock => stockPrintable(StockData.fromJson(json)),
        ReportSection.orders => ordersPrintable(OrdersData.fromJson(json)),
        ReportSection.deliveries => deliveriesPrintable(DeliveriesData.fromJson(json)),
        ReportSection.marketing => marketingPrintable(MarketingData.fromJson(json)),
      };

  /// « Imprimer / PDF » : `window.print()` du web → PDF de la section
  /// affichée, à partir des données déjà en cache.
  Future<void> _imprimer(BuildContext context, WidgetRef ref, ReportRequest request, ReportPeriod period) async {
    final messenger = ScaffoldMessenger.of(context);
    final json = ref.read(reportsProvider(request)).value;
    final printable = json == null ? null : _printable(request.section, json);
    if (printable == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Aucune donnée à imprimer')));
      return;
    }
    try {
      await imprimerRapport(printable, period);
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(reportsAccessProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    // `userLoading` : squelettes.
    if (access.loading) {
      return const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReportSkeleton(height: 32, width: 192),
              SizedBox(height: 16),
              ReportSkeleton(height: 40),
              SizedBox(height: 16),
              ReportSkeleton(height: 256),
            ],
          ),
        ),
      );
    }

    if (!access.isGerant) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tableau de bord', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(kReportsAccesRefuseMessage, style: TextStyle(fontSize: 14, color: muted)),
            ],
          ),
        ),
      );
    }

    // Temps réel : invalidation du cache + rechargement silencieux de la
    // section affichée tant que l'écran est monté.
    ref.watch(reportsRealtimeProvider);

    final filter = ref.watch(reportsFilterProvider);
    final actif = ref.watch(activeSectionProvider);
    final period = filter.period;
    final extras = ref.watch(reportExtrasProvider(actif));
    final request = ReportRequest.pour(actif, filter, extra: extras);
    final filtres = ref.read(reportsFilterProvider.notifier);

    final enTete = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tableau de bord', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 14, color: muted),
            children: [
              TextSpan(
                text: actif.label,
                style: TextStyle(fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface),
              ),
              TextSpan(text: ' — ${actif.description}'),
            ],
          ),
        ),
      ],
    );
    final boutonImprimer = OutlinedButton.icon(
      onPressed: () => _imprimer(context, ref, request, period),
      icon: const Icon(Icons.print_outlined, size: 16),
      label: const Text('Imprimer / PDF'),
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
    );

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 640) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: enTete),
                          const SizedBox(width: 12),
                          boutonImprimer,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [enTete, const SizedBox(height: 12), boutonImprimer],
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Comme la page web, `loading` n'est pas transmis aux filtres :
                // le bouton Actualiser reste toujours actif.
                ReportFilters(
                  filter: filter,
                  period: period,
                  onPreset: filtres.setPreset,
                  onCustomFrom: filtres.setCustomFrom,
                  onCustomTo: filtres.setCustomTo,
                  onGranularity: filtres.setGranularity,
                  onReload: () => rechargerReports(ref),
                ),
                const SizedBox(height: 16),
                ReportTabs(actif: actif, onChange: ref.read(activeSectionProvider.notifier).set),
                const SizedBox(height: 16),
                // Une seule section montée à la fois : rien n'est chargé
                // pour les autres.
                _section(actif, filter),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
