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

/// `COLONNES_VENTE` de section-sales.tsx : Libellé / Qté vendue / Commandes /
/// CA / Marge / Marge %. Partagées par les tableaux « Ventes par … »,
/// « Produits les plus vendus » et « Produits les moins vendus ».
final List<ReportColumn<LigneVente>> kColonnesVente = [
  ReportColumn(key: 'label', label: 'Libellé', valeur: (r) => r.label),
  ReportColumn(
    key: 'quantite',
    label: 'Qté vendue',
    align: TextAlign.right,
    valeur: (r) => r.quantite,
    render: (r, _) => Text(fmtNb(r.quantite)),
  ),
  ReportColumn(
    key: 'nb_commandes',
    label: 'Commandes',
    align: TextAlign.right,
    valeur: (r) => r.nbCommandes,
    render: (r, _) => Text(fmtNb(r.nbCommandes)),
  ),
  ReportColumn(key: 'ca', label: 'CA', align: TextAlign.right, valeur: (r) => r.ca, render: (r, _) => Text(fmtAr(r.ca))),
  ReportColumn(
    key: 'marge',
    label: 'Marge',
    align: TextAlign.right,
    valeur: (r) => r.marge,
    render: (r, _) => Text(fmtAr(r.marge)),
  ),
  ReportColumn(
    key: 'marge_pct',
    label: 'Marge %',
    align: TextAlign.right,
    valeur: (r) => r.margePct,
    render: (r, _) => Text(fmtPct(r.margePct)),
  ),
];

/// Colonnes du tableau « Ventes par livreur ».
final List<ReportColumn<LigneVenteLivreur>> _colonnesLivreur = [
  ReportColumn(key: 'nom', label: 'Livreur', valeur: (r) => r.nom),
  ReportColumn(
    key: 'commandes',
    label: 'Commandes',
    align: TextAlign.right,
    valeur: (r) => r.commandes,
    render: (r, _) => Text(_brut(r.commandes)),
  ),
  ReportColumn(
    key: 'livrees',
    label: 'Livrées',
    align: TextAlign.right,
    valeur: (r) => r.livrees,
    render: (r, _) => Text(_brut(r.livrees)),
  ),
  ReportColumn(
    key: 'retours',
    label: 'Retours',
    align: TextAlign.right,
    valeur: (r) => r.retours,
    render: (r, _) => Text(_brut(r.retours)),
  ),
  ReportColumn(
    key: 'en_cours',
    label: 'En cours',
    align: TextAlign.right,
    valeur: (r) => r.enCours,
    render: (r, _) => Text(_brut(r.enCours)),
  ),
  ReportColumn(key: 'ca', label: 'CA', align: TextAlign.right, valeur: (r) => r.ca, render: (r, _) => Text(fmtAr(r.ca))),
  ReportColumn(
    key: 'taux_reussite',
    label: 'Taux réussite',
    align: TextAlign.right,
    valeur: (r) => r.tauxReussite,
    render: (r, _) => Text(fmtPct(r.tauxReussite)),
  ),
];

/// Dimension proposée tant que le serveur n'a pas répondu (`[{ cle:
/// 'produit', label: 'Produit' }]` du web).
const List<DimensionVente> _dimensionsParDefaut = [DimensionVente(cle: 'produit', label: 'Produit')];

/// Lignes de ventes triées par CA décroissant, 10 premières (« Top 10 »).
List<LigneVente> _top10ParCa(List<LigneVente> lignes) {
  final triees = [...lignes]..sort((a, b) => b.ca.compareTo(a.ca));
  return triees.take(10).toList();
}

/// « Ventes » — port de components/reports/section-sales.tsx : 4 KPI,
/// graphique « Évolution des ventes », ventes par dimension (sélecteur
/// local) + top 10, produits les plus / moins vendus, ventes par livreur +
/// CA par livreur.
class SectionSales extends ConsumerStatefulWidget {
  const SectionSales({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  ConsumerState<SectionSales> createState() => _SectionSalesState();
}

class _SectionSalesState extends ConsumerState<SectionSales> {
  /// `useState('produit')` : dimension du tableau « Ventes par … ».
  String _dimension = 'produit';

  @override
  Widget build(BuildContext context) {
    final request = ReportRequest.pour(
      ReportSection.sales,
      widget.filter,
      extra: ref.watch(reportExtrasProvider(ReportSection.sales)),
    );
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : SalesData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final k = data?.kpis;
    final lignes = data?.par[_dimension] ?? const <LigneVente>[];
    final dimensions = data == null || data.dimensions.isEmpty ? _dimensionsParDefaut : data.dimensions;
    final dimLabel = data?.dimensions.where((d) => d.cle == _dimension).firstOrNull?.label ?? 'Produit';
    final dimMinuscule = dimLabel.toLowerCase();
    final theme = Theme.of(context);

    final tableParDimension = ReportTable<LigneVente>(
      titre: 'Ventes par $dimMinuscule',
      description: "Commandes livrées de la période, articles rapportés exclus. Marge = CA − coût d'achat actuel du catalogue.",
      colonnes: kColonnesVente,
      lignes: lignes,
      loading: loading,
      error: error,
      exportNom: 'ventes_par_$_dimension',
      rowKey: (r, _) => r.label,
      // `<Select>` h-8 w-40 text-xs du web : liste déroulante compacte.
      actions: Container(
        width: 160,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DropdownButton<String>(
          value: dimensions.any((d) => d.cle == _dimension) ? _dimension : null,
          isDense: true,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
          items: [for (final d in dimensions) DropdownMenuItem(value: d.cle, child: Text(d.label))],
          onChanged: (v) {
            if (v != null) setState(() => _dimension = v);
          },
        ),
      ),
    );

    final graphiqueTop = ChartCard(
      titre: 'Top 10 par $dimMinuscule (CA)',
      loading: loading,
      error: error,
      vide: lignes.isEmpty,
      hauteur: 360,
      child: BarresChart(
        data: [for (final l in _top10ParCa(lignes)) {'label': l.label, 'ca': l.ca}],
        labelKey: 'label',
        valueKey: 'ca',
        hauteur: 360,
      ),
    );

    final tableLivreurs = ReportTable<LigneVenteLivreur>(
      titre: 'Ventes par livreur',
      description: 'CA = total encaissé des commandes livrées (articles + frais).',
      colonnes: _colonnesLivreur,
      lignes: data?.parLivreur,
      loading: loading,
      error: error,
      exportNom: 'ventes_par_livreur',
      rowKey: (r, _) => r.id,
      vide: 'Aucune commande assignée à un livreur sur la période.',
    );

    final graphiqueLivreurs = ChartCard(
      titre: 'CA par livreur',
      loading: loading,
      error: error,
      vide: data == null || data.parLivreur.isEmpty,
      hauteur: 300,
      child: data == null
          ? const SizedBox.shrink()
          : BarresChart(
              data: [for (final l in data.parLivreur.take(10)) {'nom': l.nom, 'ca': l.ca}],
              labelKey: 'nom',
              valueKey: 'ca',
              hauteur: 300,
              color: const Color(0xFF16A34A),
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
              valeur: k == null ? null : fmtAr(data!.kpi('ca_total').actuel),
              variation: data?.kpi('ca_total'),
              format: fmtAr,
              detail: k == null ? null : 'dont produits ${fmtAr(data!.kpi('ca_produits').actuel)}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Ventes (commandes livrées)',
              icon: Icons.shopping_bag_outlined,
              valeur: k == null ? null : fmtNb(data!.kpi('nb_livrees').actuel),
              variation: data?.kpi('nb_livrees'),
              format: fmtNb,
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Quantité vendue',
              icon: Icons.inventory_outlined,
              valeur: k == null ? null : fmtNb(data!.kpi('quantite_vendue').actuel),
              variation: data?.kpi('quantite_vendue'),
              format: fmtNb,
              detail: 'articles livrés, hors retours',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Panier moyen',
              icon: Icons.inventory_2_outlined,
              valeur: k == null ? null : fmtAr(data!.kpi('panier_moyen').actuel),
              variation: data?.kpi('panier_moyen'),
              format: fmtAr,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ChartCard(
          titre: 'Évolution des ventes',
          loading: loading,
          error: error,
          vide: data == null || data.serie.isEmpty,
          child: data == null
              ? const SizedBox.shrink()
              : SerieChart(
                  data: data.serie,
                  series: const [
                    SerieDef(key: 'ca', label: 'CA produits', type: SerieType.bar, color: Color(0xFF2563EB)),
                    SerieDef(
                      key: 'ventes',
                      label: 'Commandes livrées',
                      type: SerieType.line,
                      unite: ChartUnite.nb,
                      color: Color(0xFF16A34A),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Grille(flexGauche: 2, gauche: tableParDimension, droite: graphiqueTop),
        const SizedBox(height: 16),
        _Grille(
          gauche: ReportTable<LigneVente>(
            titre: 'Produits les plus vendus',
            colonnes: kColonnesVente,
            lignes: data?.topProduits,
            loading: loading,
            error: error,
            pageSize: 10,
            exportNom: 'top_produits',
            rowKey: (r, _) => r.label,
          ),
          droite: ReportTable<LigneVente>(
            titre: 'Produits les moins vendus',
            description: 'Parmi les produits vendus au moins une fois sur la période.',
            colonnes: kColonnesVente,
            lignes: data?.moinsVendus,
            loading: loading,
            error: error,
            pageSize: 10,
            exportNom: 'produits_moins_vendus',
            rowKey: (r, _) => r.label,
          ),
        ),
        const SizedBox(height: 16),
        _Grille(flexGauche: 2, gauche: tableLivreurs, droite: graphiqueLivreurs),
      ],
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

/// Lignes imprimables d'un tableau à colonnes [kColonnesVente].
List<List<String>> _lignesVente(List<LigneVente> lignes) => [
      for (final r in lignes)
        [r.label, fmtNb(r.quantite), fmtNb(r.nbCommandes), fmtAr(r.ca), fmtAr(r.marge), fmtPct(r.margePct)],
    ];

/// Version imprimable de la section Ventes : les 4 KPI puis les tableaux
/// avec les colonnes de l'écran. La dimension sélectionnée étant un état
/// local de l'écran, « Ventes par … » est imprimé pour chaque dimension
/// proposée par le serveur.
ReportPrintable? salesPrintable(SalesData data) {
  final entetesVente = [for (final c in kColonnesVente) c.label];
  return ReportPrintable(
    sectionLabel: ReportSection.sales.label,
    sectionDescription: ReportSection.sales.description,
    kpis: [
      PrintableKpi(
        "Chiffre d'affaires",
        fmtAr(data.kpi('ca_total').actuel),
        'dont produits ${fmtAr(data.kpi('ca_produits').actuel)}',
      ),
      PrintableKpi(
        'Ventes (commandes livrées)',
        fmtNb(data.kpi('nb_livrees').actuel),
        'préc. ${fmtNb(data.kpi('nb_livrees').precedent)}',
      ),
      PrintableKpi('Quantité vendue', fmtNb(data.kpi('quantite_vendue').actuel), 'articles livrés, hors retours'),
      PrintableKpi(
        'Panier moyen',
        fmtAr(data.kpi('panier_moyen').actuel),
        'préc. ${fmtAr(data.kpi('panier_moyen').precedent)}',
      ),
    ],
    tables: [
      for (final d in (data.dimensions.isEmpty ? _dimensionsParDefaut : data.dimensions))
        PrintableTable(
          titre: 'Ventes par ${d.label.toLowerCase()}',
          headers: entetesVente,
          rows: _lignesVente(data.par[d.cle] ?? const []),
        ),
      PrintableTable(titre: 'Produits les plus vendus', headers: entetesVente, rows: _lignesVente(data.topProduits)),
      PrintableTable(titre: 'Produits les moins vendus', headers: entetesVente, rows: _lignesVente(data.moinsVendus)),
      PrintableTable(
        titre: 'Ventes par livreur',
        headers: [for (final c in _colonnesLivreur) c.label],
        rows: [
          for (final r in data.parLivreur)
            [
              r.nom,
              _brut(r.commandes),
              _brut(r.livrees),
              _brut(r.retours),
              _brut(r.enCours),
              fmtAr(r.ca),
              fmtPct(r.tauxReussite),
            ],
        ],
      ),
    ],
  );
}
