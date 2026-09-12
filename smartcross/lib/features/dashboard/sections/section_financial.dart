import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';
import '../widgets/kpi_card.dart';
import '../widgets/report_chart.dart';
import '../widgets/report_printable.dart';
import '../widgets/report_table.dart';

/// Nombre brut tel que le web l'affiche sans `render` (`row[key]`) : entier
/// sans séparateur de milliers, décimales conservées si présentes.
String _brut(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// `COLONNES` de section-financial.tsx : Libellé / Qté / CA / Coût d'achat /
/// Marge (rouge si négative) / Marge %.
final List<ReportColumn<LigneVente>> _colonnes = [
  ReportColumn(key: 'label', label: 'Libellé', valeur: (r) => r.label),
  ReportColumn(
    key: 'quantite',
    label: 'Qté',
    align: TextAlign.right,
    valeur: (r) => r.quantite,
    render: (r, _) => Text(_brut(r.quantite)),
  ),
  ReportColumn(key: 'ca', label: 'CA', align: TextAlign.right, valeur: (r) => r.ca, render: (r, _) => Text(fmtAr(r.ca))),
  ReportColumn(
    key: 'cout',
    label: "Coût d'achat",
    align: TextAlign.right,
    valeur: (r) => r.cout,
    render: (r, _) => Text(fmtAr(r.cout)),
  ),
  ReportColumn(
    key: 'marge',
    label: 'Marge',
    align: TextAlign.right,
    valeur: (r) => r.marge,
    render: (r, _) => Text(fmtAr(r.marge), style: r.marge < 0 ? const TextStyle(color: kCouleurBaisse) : null),
  ),
  ReportColumn(
    key: 'marge_pct',
    label: 'Marge %',
    align: TextAlign.right,
    valeur: (r) => r.margePct,
    render: (r, _) => Text(fmtPct(r.margePct)),
  ),
];

/// Lignes de la carte « Période actuelle vs précédente » : (libellé, clé de
/// `comparaison`, inverse) — ordre exact du web.
const List<(String, String, bool)> _lignesComparaison = [
  ('CA brut', 'ca_total', false),
  ("Coût d'achat", 'cout_achat', true),
  ('Marge brute', 'marge_brute', false),
  ('Dépenses', 'depenses', true),
  ('Bénéfice net', 'benefice_net', false),
];

/// Écart signé (« +1 234 Ar » / « -1 234 Ar »).
String _ecart(num v) => '${v > 0 ? '+' : ''}${fmtAr(v)}';

/// Paragraphe explicatif du web (`text-xs text-muted-foreground`), mot pour mot.
const String _explication =
    "Bénéfice net = CA (produits + frais de livraison encaissés) − coût d'achat des articles vendus − sorties de caisse − frais de tournée "
    'des livreurs acceptés. Les sorties de caisse « Commande stock » ne sont pas des charges : la marchandise achetée est comptée au moment de '
    "la vente, dans le coût d'achat — les compter deux fois ferait de chaque réassort une perte. Le coût d'achat utilise le prix "
    "d'achat actuel de chaque référence (non historisé par commande).";

/// « Financier » — port de components/reports/section-financial.tsx : 5 KPI,
/// « Rentabilité dans le temps », carte « Période actuelle vs précédente »,
/// explication du bénéfice net, rentabilité par produit / catégorie /
/// sous-type.
class SectionFinancial extends ConsumerWidget {
  const SectionFinancial({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ReportRequest.pour(
      ReportSection.financial,
      filter,
      extra: ref.watch(reportExtrasProvider(ReportSection.financial)),
    );
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : FinancialData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final t = data?.totaux;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final graphique = ChartCard(
      titre: 'Rentabilité dans le temps',
      description: "CA, coût d'achat, dépenses et bénéfice net par période",
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
                SerieDef(key: 'ventes', label: 'CA', type: SerieType.bar, color: Color(0xFF2563EB)),
                SerieDef(key: 'cout_achat', label: "Coût d'achat", type: SerieType.bar, color: Color(0xFFF59E0B)),
                SerieDef(key: 'depenses', label: 'Dépenses', type: SerieType.bar, color: Color(0xFFEF4444)),
                SerieDef(key: 'benefices', label: 'Bénéfice net', type: SerieType.line, color: Color(0xFF16A34A)),
              ],
            ),
    );

    final achatsStock = data?.total('achats_stock') ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(
          cols: 5,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: 'CA brut',
              icon: Icons.payments_outlined,
              valeur: t == null ? null : fmtAr(data!.total('ca_total')),
              variation: data?.variation('ca_total'),
              format: fmtAr,
              detail: t == null
                  ? null
                  : 'produits ${fmtAr(data!.total('ca_produits'))} + livraison ${fmtAr(data.total('frais_livraison'))}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: "Coût d'achat des ventes",
              icon: Icons.trending_down,
              valeur: t == null ? null : fmtAr(data!.total('cout_achat')),
              variation: data?.variation('cout_achat'),
              inverse: true,
              format: fmtAr,
              detail: "prix d'achat actuel × quantités",
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Marge brute',
              icon: Icons.percent,
              valeur: t == null ? null : fmtAr(data!.total('marge_brute')),
              variation: data?.variation('marge_brute'),
              format: fmtAr,
              detail: t == null ? null : '${fmtPct(data!.total('taux_marge_brute'))} du CA produits',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Dépenses (charges)',
              icon: Icons.account_balance_wallet_outlined,
              valeur: t == null ? null : fmtAr(data!.total('depenses')),
              variation: data?.variation('depenses'),
              inverse: true,
              format: fmtAr,
              detail: t == null
                  ? null
                  : 'caisse ${fmtAr(data!.total('depenses_caisse'))} · tournées ${fmtAr(data.total('depenses_livreur'))}'
                      '${achatsStock != 0 ? ' · achats de stock exclus : ${fmtAr(achatsStock)}' : ''}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Bénéfice net',
              icon: Icons.trending_up,
              valeur: t == null ? null : fmtAr(data!.total('benefice_net')),
              couleur: t != null && data!.total('benefice_net') < 0 ? kCouleurBaisse : kCouleurHausse,
              variation: data?.variation('benefice_net'),
              format: fmtAr,
              detail: t == null ? null : '${fmtPct(data!.total('taux_benefice'))} du CA',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Grille(flexGauche: 2, gauche: graphique, droite: _ComparaisonCard(data: data, loading: loading)),
        const SizedBox(height: 16),
        Text(_explication, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 16),
        ReportTable<LigneVente>(
          titre: 'Rentabilité par produit',
          colonnes: _colonnes,
          lignes: data?.parProduit,
          loading: loading,
          error: error,
          exportNom: 'rentabilite_produits',
          rowKey: (r, _) => r.label,
        ),
        const SizedBox(height: 16),
        _Grille(
          gauche: ReportTable<LigneVente>(
            titre: 'Rentabilité par catégorie',
            colonnes: _colonnes,
            lignes: data?.parCategorie,
            loading: loading,
            error: error,
            exportNom: 'rentabilite_categories',
            rowKey: (r, _) => r.label,
            pageSize: 10,
          ),
          droite: ReportTable<LigneVente>(
            titre: 'Rentabilité par sous-type',
            colonnes: _colonnes,
            lignes: data?.parSousType,
            loading: loading,
            error: error,
            exportNom: 'rentabilite_sous_types',
            rowKey: (r, _) => r.label,
            pageSize: 10,
          ),
        ),
      ],
    );
  }
}

/// Carte « Période actuelle vs précédente » : 5 lignes (libellé + « préc. »,
/// valeur + écart signé, badge d'évolution).
class _ComparaisonCard extends StatelessWidget {
  const _ComparaisonCard({required this.data, required this.loading});

  final FinancialData? data;
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
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              const ReportSkeleton(height: 28),
            ],
          ],
        ),
      );
    } else if (d == null) {
      corps = const SizedBox.shrink();
    } else {
      corps = Column(
        children: [
          for (var i = 0; i < _lignesComparaison.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: i < _lignesComparaison.length - 1
                  ? BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor)))
                  : null,
              child: Builder(builder: (context) {
                final (label, cle, inverse) = _lignesComparaison[i];
                final v = d.variation(cle);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          Text('préc. ${fmtAr(v.precedent)}', style: TextStyle(fontSize: 12, color: muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          fmtAr(v.actuel),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          _ecart(v.variation),
                          style: TextStyle(fontSize: 12, color: muted, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    VariationBadge(pct: v.variationPct, inverse: inverse),
                  ],
                );
              }),
            ),
        ],
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
                  'Période actuelle vs précédente',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (d != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${fmtDate(d.periode.from)} → ${fmtDate(d.periode.to)} vs ${fmtDate(d.periode.prevFrom)} → ${fmtDate(d.periode.prevTo)}',
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

/// `grid-cols-1 xl:grid-cols-N` du web : deux colonnes ([flexGauche] / 1)
/// dès 1280 px (`xl`), une colonne sinon.
class _Grille extends StatelessWidget {
  const _Grille({required this.gauche, required this.droite, this.flexGauche = 1});

  final Widget gauche;
  final Widget droite;
  final int flexGauche;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1280) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: flexGauche, child: gauche),
              const SizedBox(width: 16),
              Expanded(child: droite),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [gauche, const SizedBox(height: 16), droite],
        );
      },
    );
  }
}

/// Lignes imprimables d'un tableau de rentabilité (colonnes de l'écran).
List<List<String>> _lignesRentabilite(List<LigneVente> lignes) => [
      for (final r in lignes) [r.label, _brut(r.quantite), fmtAr(r.ca), fmtAr(r.cout), fmtAr(r.marge), fmtPct(r.margePct)],
    ];

/// Version imprimable de la section Financier : les 5 KPI, la comparaison
/// avec la période précédente et les trois tableaux de rentabilité.
ReportPrintable? financialPrintable(FinancialData data) {
  final entetes = [for (final c in _colonnes) c.label];
  final achatsStock = data.total('achats_stock');
  return ReportPrintable(
    sectionLabel: ReportSection.financial.label,
    sectionDescription: ReportSection.financial.description,
    kpis: [
      PrintableKpi(
        'CA brut',
        fmtAr(data.total('ca_total')),
        'produits ${fmtAr(data.total('ca_produits'))} + livraison ${fmtAr(data.total('frais_livraison'))}',
      ),
      PrintableKpi("Coût d'achat des ventes", fmtAr(data.total('cout_achat')), "prix d'achat actuel × quantités"),
      PrintableKpi('Marge brute', fmtAr(data.total('marge_brute')), '${fmtPct(data.total('taux_marge_brute'))} du CA produits'),
      PrintableKpi(
        'Dépenses (charges)',
        fmtAr(data.total('depenses')),
        'caisse ${fmtAr(data.total('depenses_caisse'))} · tournées ${fmtAr(data.total('depenses_livreur'))}'
        '${achatsStock != 0 ? ' · achats de stock exclus : ${fmtAr(achatsStock)}' : ''}',
      ),
      PrintableKpi('Bénéfice net', fmtAr(data.total('benefice_net')), '${fmtPct(data.total('taux_benefice'))} du CA'),
    ],
    tables: [
      PrintableTable(
        titre: 'Période actuelle vs précédente',
        headers: const ['Indicateur', 'Période actuelle', 'Période précédente', 'Écart', 'Évolution'],
        rows: [
          for (final (label, cle, _) in _lignesComparaison)
            [
              label,
              fmtAr(data.variation(cle).actuel),
              fmtAr(data.variation(cle).precedent),
              _ecart(data.variation(cle).variation),
              fmtPct(data.variation(cle).variationPct, signe: true),
            ],
        ],
      ),
      PrintableTable(titre: 'Rentabilité par produit', headers: entetes, rows: _lignesRentabilite(data.parProduit)),
      PrintableTable(titre: 'Rentabilité par catégorie', headers: entetes, rows: _lignesRentabilite(data.parCategorie)),
      PrintableTable(titre: 'Rentabilité par sous-type', headers: entetes, rows: _lignesRentabilite(data.parSousType)),
    ],
  );
}
