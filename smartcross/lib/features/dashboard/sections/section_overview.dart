import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';
import '../widgets/kpi_card.dart';
import '../widgets/report_chart.dart';
import '../widgets/report_printable.dart';

/// Lignes du tableau « Comparaison avec la période précédente » :
/// (libellé, clé KPI, format, inverse, icône) — ordre exact du web.
typedef _LigneComparaison = (String, String, String Function(num), bool, IconData);

const List<_LigneComparaison> _lignesComparaison = [
  ('Chiffre d’affaires', 'ca_total', fmtAr, false, Icons.payments_outlined),
  ('Marge brute (produits)', 'marge_brute', fmtAr, false, Icons.trending_up),
  ('Dépenses', 'depenses', fmtAr, true, Icons.account_balance_wallet_outlined),
  ('Bénéfice net', 'benefice_net', fmtAr, false, Icons.trending_up),
  ('Commandes', 'nb_commandes', fmtNb, false, Icons.shopping_cart_outlined),
  ('Commandes livrées', 'nb_livrees', fmtNb, false, Icons.local_shipping_outlined),
  ('Panier moyen', 'panier_moyen', fmtAr, false, Icons.inventory_2_outlined),
];

String _ecart(num v, String Function(num) f) => '${v > 0 ? '+' : ''}${f(v)}';

/// « Vue générale » — port de components/reports/section-overview.tsx :
/// 4 KPI, graphique « Ventes, dépenses et bénéfices », anneau « Commandes
/// par statut », tableau de comparaison avec la période précédente.
class SectionOverview extends ConsumerWidget {
  const SectionOverview({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ReportRequest.pour(ReportSection.overview, filter);
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : OverviewData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final k = data?.kpis;
    List<num>? serie(String cle) => data?.series.map((p) => p.v(cle)).toList();

    final graphiqueSeries = ChartCard(
      titre: 'Ventes, dépenses et bénéfices',
      description: data == null
          ? null
          : 'Par ${data.periode.granulariteMot} — ${fmtDate(data.periode.from)} → ${fmtDate(data.periode.to)}',
      loading: loading,
      error: error,
      vide: data == null || data.series.isEmpty,
      hauteur: 320,
      child: data == null
          ? const SizedBox.shrink()
          : SerieChart(
              data: data.series,
              hauteur: 320,
              series: const [
                SerieDef(key: 'ventes', label: 'Ventes (CA)', type: SerieType.bar, color: Color(0xFF2563EB)),
                SerieDef(key: 'depenses', label: 'Dépenses', type: SerieType.bar, color: Color(0xFFEF4444)),
                SerieDef(key: 'benefices', label: 'Bénéfices', type: SerieType.line, color: Color(0xFF16A34A)),
              ],
            ),
    );

    final statutsNonVides = data?.repartitionStatuts.where((r) => r.nb > 0).toList() ?? const <RepartitionStatut>[];
    final graphiqueStatuts = ChartCard(
      titre: 'Commandes par statut',
      loading: loading,
      error: error,
      vide: statutsNonVides.isEmpty,
      hauteur: 320,
      child: data == null
          ? const SizedBox.shrink()
          : CamembertChart(
              data: [for (final r in data.repartitionStatuts) {'label': r.label, 'nb': r.nb}],
              labelKey: 'label',
              valueKey: 'nb',
              hauteur: 320,
              colors: [for (final r in statutsNonVides) kStatutCouleurs[r.statut] ?? kCouleurNeutre],
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(
          cols: 4,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: "Chiffre d'affaires",
              icon: Icons.payments_outlined,
              valeur: k == null ? null : fmtAr(data!.caTotal.actuel),
              variation: data?.caTotal,
              format: fmtAr,
              serie: serie('ventes'),
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Bénéfice net',
              icon: Icons.trending_up,
              valeur: k == null ? null : fmtAr(data!.beneficeNet.actuel),
              couleur: data == null ? null : (data.beneficeNet.actuel < 0 ? kCouleurBaisse : kCouleurHausse),
              variation: data?.beneficeNet,
              format: fmtAr,
              serie: serie('benefices'),
              detail: "CA − coût d'achat − dépenses (hors achats de stock)",
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Commandes',
              icon: Icons.shopping_cart_outlined,
              valeur: k == null ? null : fmtNb(data!.nbCommandes.actuel),
              variation: data?.nbCommandes,
              format: fmtNb,
              detail: data == null ? null : '${fmtNb(data.nbLivrees.actuel)} livrées',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Panier moyen',
              icon: Icons.inventory_2_outlined,
              valeur: k == null ? null : fmtAr(data!.panierMoyen.actuel),
              variation: data?.panierMoyen,
              format: fmtAr,
              detail: 'CA / commandes livrées',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Bénéfices : obtenu sur la période (marge brute des articles livrés)
        // et estimé sur le stock d'aujourd'hui (si tout est vendu) — mêmes
        // deux cartes que la Vue générale web.
        KpiGrid(
          cols: 2,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: 'Total des bénéfices obtenus',
              icon: Icons.savings_outlined,
              valeur: data == null ? null : fmtAr(data.beneficeObtenu.actuel),
              couleur: data == null ? null : (data.beneficeObtenu.actuel < 0 ? kCouleurBaisse : kCouleurHausse),
              variation: data?.beneficeObtenu,
              format: fmtAr,
              detail: "Articles livrés sur la période : prix de vente − prix d'achat (hors frais et dépenses)",
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Total du bénéfice estimé',
              icon: Icons.inventory_outlined,
              valeur: data == null ? null : fmtAr(data.beneficeEstime.benefice),
              couleur: data == null ? null : (data.beneficeEstime.benefice < 0 ? kCouleurBaisse : kCouleurHausse),
              detail: data == null
                  ? null
                  : 'Potentiel si tout le stock actuel est vendu : ${fmtNb(data.beneficeEstime.quantite)} articles · '
                      'vente ${fmtAr(data.beneficeEstime.valeurVente)} − achat ${fmtAr(data.beneficeEstime.valeurAchat)}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-3` : côte à côte (2/3 – 1/3) dès 1280 px,
        // une colonne sinon.
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1280) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: graphiqueSeries),
                  const SizedBox(width: 16),
                  Expanded(child: graphiqueStatuts),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [graphiqueSeries, const SizedBox(height: 16), graphiqueStatuts],
            );
          },
        ),
        const SizedBox(height: 16),
        _ComparaisonCard(data: data, loading: loading),
      ],
    );
  }
}

/// Carte « Comparaison avec la période précédente ».
class _ComparaisonCard extends StatelessWidget {
  const _ComparaisonCard({required this.data, required this.loading});

  final OverviewData? data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final d = data;

    Widget corps;
    if (loading) {
      corps = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              const ReportSkeleton(height: 32),
            ],
          ],
        ),
      );
    } else if (d == null) {
      corps = const SizedBox.shrink();
    } else {
      corps = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columnSpacing: 20,
          horizontalMargin: 16,
          headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
          dataTextStyle: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
          columns: const [
            DataColumn(label: Text('Indicateur')),
            DataColumn(label: Text('Période actuelle'), headingRowAlignment: MainAxisAlignment.end),
            DataColumn(label: Text('Période précédente'), headingRowAlignment: MainAxisAlignment.end),
            DataColumn(label: Text('Écart'), headingRowAlignment: MainAxisAlignment.end),
            DataColumn(label: Text('Évolution'), headingRowAlignment: MainAxisAlignment.end),
          ],
          rows: [
            for (final (label, cle, f, inverse, icon) in _lignesComparaison)
              DataRow(cells: [
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: muted),
                    const SizedBox(width: 8),
                    Text(label),
                  ],
                )),
                DataCell(Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    f(d.kpi(cle).actuel),
                    style: const TextStyle(fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                )),
                DataCell(Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    f(d.kpi(cle).precedent),
                    style: TextStyle(color: muted, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                )),
                DataCell(Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _ecart(d.kpi(cle).variation, f),
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                )),
                DataCell(Align(
                  alignment: Alignment.centerRight,
                  child: VariationBadge(pct: d.kpi(cle).variationPct, inverse: inverse),
                )),
              ]),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comparaison avec la période précédente',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (d != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${fmtDate(d.periode.from)} → ${fmtDate(d.periode.to)} comparé à ${fmtDate(d.periode.prevFrom)} → ${fmtDate(d.periode.prevTo)}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ],
            ),
          ),
          corps,
        ],
      ),
    );
  }
}

/// Version imprimable de la vue générale : les 4 KPI, la répartition par
/// statut (le graphique du web) et le tableau de comparaison.
ReportPrintable? overviewPrintable(OverviewData data) {
  return ReportPrintable(
    sectionLabel: ReportSection.overview.label,
    sectionDescription: ReportSection.overview.description,
    kpis: [
      PrintableKpi("Chiffre d'affaires", fmtAr(data.caTotal.actuel), 'préc. ${fmtAr(data.caTotal.precedent)}'),
      PrintableKpi('Bénéfice net', fmtAr(data.beneficeNet.actuel), "CA − coût d'achat − dépenses (hors achats de stock)"),
      PrintableKpi('Commandes', fmtNb(data.nbCommandes.actuel), '${fmtNb(data.nbLivrees.actuel)} livrées'),
      PrintableKpi('Panier moyen', fmtAr(data.panierMoyen.actuel), 'CA / commandes livrées'),
      PrintableKpi(
        'Total des bénéfices obtenus',
        fmtAr(data.beneficeObtenu.actuel),
        "articles livrés : vente − achat · préc. ${fmtAr(data.beneficeObtenu.precedent)}",
      ),
      PrintableKpi(
        'Total du bénéfice estimé',
        fmtAr(data.beneficeEstime.benefice),
        'stock actuel : ${fmtNb(data.beneficeEstime.quantite)} articles · vente ${fmtAr(data.beneficeEstime.valeurVente)} − achat ${fmtAr(data.beneficeEstime.valeurAchat)}',
      ),
    ],
    tables: [
      PrintableTable(
        titre: 'Comparaison avec la période précédente',
        headers: const ['Indicateur', 'Période actuelle', 'Période précédente', 'Écart', 'Évolution'],
        rows: [
          for (final (label, cle, f, _, _) in _lignesComparaison)
            [
              label,
              f(data.kpi(cle).actuel),
              f(data.kpi(cle).precedent),
              _ecart(data.kpi(cle).variation, f),
              fmtPct(data.kpi(cle).variationPct, signe: true),
            ],
        ],
      ),
      PrintableTable(
        titre: 'Commandes par statut',
        headers: const ['Statut', 'Commandes'],
        rows: [
          for (final r in data.repartitionStatuts.where((r) => r.nb > 0)) [r.label, fmtNb(r.nb)],
        ],
      ),
    ],
  );
}
