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

/// Libellé de la colonne « Zone » : « Récupération » pour la zone
/// `RECUPERATION`, le nom de la zone sinon (texte de l'export et du PDF).
String _zoneTexte(String zone) => zone == 'RECUPERATION' ? 'Récupération' : zone;

/// Colonnes du tableau « Détail par statut » (Statut avec pastille de
/// couleur / Nb / Part).
final List<ReportColumn<RepartitionStatut>> _colonnesStatut = [
  ReportColumn(
    key: 'label',
    label: 'Statut',
    valeur: (r) => r.label,
    render: (r, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: kStatutCouleurs[r.statut], shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(r.label),
      ],
    ),
  ),
  ReportColumn(key: 'nb', label: 'Nb', align: TextAlign.right, valeur: (r) => r.nb, render: (r, _) => Text(_brut(r.nb))),
  ReportColumn(
    key: 'part',
    label: 'Part',
    align: TextAlign.right,
    valeur: (r) => r.part,
    render: (r, _) => Text(fmtPct(r.part)),
  ),
];

/// Colonnes du tableau « Par zone de livraison » (Zone / Commandes /
/// Livrées / CA livré).
final List<ReportColumn<LigneZoneCommandes>> _colonnesZone = [
  ReportColumn(
    key: 'zone',
    label: 'Zone',
    valeur: (r) => r.zone,
    render: (r, _) => r.zone == 'RECUPERATION' ? const _BadgeOutline('Récupération') : Text(r.zone),
  ),
  ReportColumn(
    key: 'nb',
    label: 'Commandes',
    align: TextAlign.right,
    valeur: (r) => r.nb,
    render: (r, _) => Text(_brut(r.nb)),
  ),
  ReportColumn(
    key: 'livrees',
    label: 'Livrées',
    align: TextAlign.right,
    valeur: (r) => r.livrees,
    render: (r, _) => Text(_brut(r.livrees)),
  ),
  ReportColumn(
    key: 'ca',
    label: 'CA livré',
    align: TextAlign.right,
    valeur: (r) => r.ca,
    render: (r, _) => Text(fmtAr(r.ca)),
  ),
];

/// Colonnes du tableau « Par mode de paiement » (Mode / Commandes / CA
/// livré).
final List<ReportColumn<LignePaiement>> _colonnesPaiement = [
  ReportColumn(key: 'label', label: 'Mode', valeur: (r) => r.label),
  ReportColumn(
    key: 'nb',
    label: 'Commandes',
    align: TextAlign.right,
    valeur: (r) => r.nb,
    render: (r, _) => Text(_brut(r.nb)),
  ),
  ReportColumn(
    key: 'ca',
    label: 'CA livré',
    align: TextAlign.right,
    valeur: (r) => r.ca,
    render: (r, _) => Text(fmtAr(r.ca)),
  ),
];

/// « Commandes » — port de components/reports/section-orders.tsx : 5 KPI,
/// graphique « Commandes dans le temps », anneau « Répartition par statut »,
/// tableaux par statut / zone de livraison / mode de paiement.
class SectionOrders extends ConsumerWidget {
  const SectionOrders({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ReportRequest.pour(
      ReportSection.orders,
      filter,
      extra: ref.watch(reportExtrasProvider(ReportSection.orders)),
    );
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : OrdersData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final k = data?.kpis;
    final c = data?.comparaison;

    final graphiqueSerie = ChartCard(
      titre: 'Commandes dans le temps',
      loading: loading,
      error: error,
      vide: data == null || data.serie.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : SerieChart(
              data: data.serie,
              series: const [
                SerieDef(key: 'total', label: 'Toutes', type: SerieType.bar, unite: ChartUnite.nb, color: Color(0xFF94A3B8)),
                SerieDef(key: 'livrees', label: 'Livrées', type: SerieType.line, unite: ChartUnite.nb, color: Color(0xFF16A34A)),
                SerieDef(key: 'annulees', label: 'Annulées', type: SerieType.line, unite: ChartUnite.nb, color: Color(0xFFEF4444)),
                SerieDef(key: 'retours', label: 'Retours', type: SerieType.line, unite: ChartUnite.nb, color: Color(0xFFF97316)),
              ],
            ),
    );

    final statutsNonVides = data?.repartition.where((r) => r.nb > 0).toList() ?? const <RepartitionStatut>[];
    final graphiqueStatuts = ChartCard(
      titre: 'Répartition par statut',
      loading: loading,
      error: error,
      vide: statutsNonVides.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : CamembertChart(
              data: [for (final r in data.repartition) {'label': r.label, 'nb': r.nb}],
              labelKey: 'label',
              valueKey: 'nb',
              colors: [for (final r in statutsNonVides) kStatutCouleurs[r.statut] ?? kCouleurNeutre],
            ),
    );

    final tableStatuts = ReportTable<RepartitionStatut>(
      titre: 'Détail par statut',
      colonnes: _colonnesStatut,
      lignes: data?.repartition,
      loading: loading,
      error: error,
      pageSize: 10,
      rowKey: (r, _) => r.statut,
      exportNom: 'commandes_par_statut',
    );

    final tableZones = ReportTable<LigneZoneCommandes>(
      titre: 'Par zone de livraison',
      colonnes: _colonnesZone,
      lignes: data?.parZone,
      loading: loading,
      error: error,
      pageSize: 10,
      rowKey: (r, _) => r.zone,
      exportNom: 'commandes_par_zone',
    );

    final tablePaiements = ReportTable<LignePaiement>(
      titre: 'Par mode de paiement',
      colonnes: _colonnesPaiement,
      lignes: data?.parPaiement,
      loading: loading,
      error: error,
      pageSize: 10,
      rowKey: (r, _) => r.mode,
      exportNom: 'commandes_par_paiement',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(
          cols: 5,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: 'Commandes',
              icon: Icons.assignment_outlined,
              valeur: k == null ? null : fmtNb(data!.kpi('total')),
              variation: c?['total'],
              format: fmtNb,
              detail: k == null
                  ? null
                  : '${fmtNb(data!.kpi('nouvelles'))} nouvelles · ${fmtNb(data.kpi('en_cours'))} en préparation/prêtes',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'En livraison',
              icon: Icons.local_shipping_outlined,
              valeur: k == null ? null : fmtNb(data!.kpi('en_livraison')),
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Livrées',
              icon: Icons.check_circle_outline,
              valeur: k == null ? null : fmtNb(data!.kpi('livrees')),
              variation: c?['livrees'],
              format: fmtNb,
              detail: k == null ? null : 'taux de livraison ${fmtPct(data!.kpi('taux_livraison'))}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Annulées',
              icon: Icons.block_outlined,
              valeur: k == null ? null : fmtNb(data!.kpi('annulees')),
              variation: c?['annulees'],
              inverse: true,
              format: fmtNb,
              couleur: k != null && data!.kpi('annulees') > 0 ? kCouleurBaisse : null,
              detail: k == null
                  ? null
                  : "taux d'annulation ${fmtPct(data!.kpi('taux_annulation'))} · ${fmtAr(data.montantAnnule)}",
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Retournées',
              icon: Icons.replay_outlined,
              valeur: k == null ? null : fmtNb(data!.kpi('retournees')),
              variation: c?['retournees'],
              inverse: true,
              format: fmtNb,
              detail: k == null ? null : 'taux de retour ${fmtPct(data!.kpi('taux_retour'))} · ${fmtAr(data.montantRetourne)}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-3` (+ `xl:col-span-2`) : 2/3 – 1/3 côte
        // à côte dès 1280 px (`xl`), une colonne sinon.
        _Grille(enfants: [graphiqueSerie, graphiqueStatuts], flex: const [2, 1]),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-3` : les trois tableaux côte à côte dès
        // 1280 px, l'un sous l'autre sinon.
        _Grille(enfants: [tableStatuts, tableZones, tablePaiements]),
      ],
    );
  }
}

/// Cartes côte à côte dès 1280 px (`xl` du web ; proportions [flex], 1 par
/// défaut), l'une sous l'autre sinon.
class _Grille extends StatelessWidget {
  const _Grille({required this.enfants, this.flex});

  final List<Widget> enfants;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1280) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < enfants.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(flex: flex?[i] ?? 1, child: enfants[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < enfants.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              enfants[i],
            ],
          ],
        );
      },
    );
  }
}

/// `<Badge variant="outline">` du web.
class _BadgeOutline extends StatelessWidget {
  const _BadgeOutline(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface)),
    );
  }
}

/// Version imprimable de la section Commandes : les 5 KPI puis les trois
/// tableaux avec les colonnes de l'écran.
ReportPrintable? ordersPrintable(OrdersData data) {
  final annulees = data.comparaison['annulees'];
  final total = data.comparaison['total'];
  final livrees = data.comparaison['livrees'];
  final retournees = data.comparaison['retournees'];
  String detail(Variation? v, String texte) => v == null ? texte : 'préc. ${fmtNb(v.precedent)} · $texte';
  return ReportPrintable(
    sectionLabel: ReportSection.orders.label,
    sectionDescription: ReportSection.orders.description,
    kpis: [
      PrintableKpi(
        'Commandes',
        fmtNb(data.kpi('total')),
        detail(total, '${fmtNb(data.kpi('nouvelles'))} nouvelles · ${fmtNb(data.kpi('en_cours'))} en préparation/prêtes'),
      ),
      PrintableKpi('En livraison', fmtNb(data.kpi('en_livraison'))),
      PrintableKpi('Livrées', fmtNb(data.kpi('livrees')), detail(livrees, 'taux de livraison ${fmtPct(data.kpi('taux_livraison'))}')),
      PrintableKpi(
        'Annulées',
        fmtNb(data.kpi('annulees')),
        detail(annulees, "taux d'annulation ${fmtPct(data.kpi('taux_annulation'))} · ${fmtAr(data.montantAnnule)}"),
      ),
      PrintableKpi(
        'Retournées',
        fmtNb(data.kpi('retournees')),
        detail(retournees, 'taux de retour ${fmtPct(data.kpi('taux_retour'))} · ${fmtAr(data.montantRetourne)}'),
      ),
    ],
    tables: [
      PrintableTable(
        titre: 'Détail par statut',
        headers: [for (final c in _colonnesStatut) c.label],
        rows: [
          for (final r in data.repartition) [r.label, _brut(r.nb), fmtPct(r.part)],
        ],
      ),
      PrintableTable(
        titre: 'Par zone de livraison',
        headers: [for (final c in _colonnesZone) c.label],
        rows: [
          for (final r in data.parZone) [_zoneTexte(r.zone), _brut(r.nb), _brut(r.livrees), fmtAr(r.ca)],
        ],
      ),
      PrintableTable(
        titre: 'Par mode de paiement',
        headers: [for (final c in _colonnesPaiement) c.label],
        rows: [
          for (final r in data.parPaiement) [r.label, _brut(r.nb), fmtAr(r.ca)],
        ],
      ),
    ],
  );
}
