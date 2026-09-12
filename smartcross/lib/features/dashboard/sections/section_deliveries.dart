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

/// Paragraphe explicatif de la section (mot pour mot).
const String _explication =
    "La livraison est assurée par les livreurs de l'équipe (pas d'agence externe) : chaque livreur est traité comme une agence. "
    'Livraison réussie = commande livrée, échouée = retour. Coût payé = frais de tournée acceptés. '
    'Délai = passage « En livraison » → « Livré ».';

/// `COLONNES` de section-deliveries.tsx : les 12 colonnes du tableau
/// « Comparatif des livreurs ».
final List<ReportColumn<LigneLivreur>> _colonnesLivreur = [
  ReportColumn(key: 'nom', label: 'Livreur', valeur: (r) => r.nom),
  ReportColumn(
    key: 'livraisons',
    label: 'Livraisons',
    align: TextAlign.right,
    valeur: (r) => r.livraisons,
    render: (r, _) => Text(_brut(r.livraisons)),
  ),
  ReportColumn(
    key: 'reussies',
    label: 'Réussies',
    align: TextAlign.right,
    valeur: (r) => r.reussies,
    render: (r, _) => Text(fmtNb(r.reussies), style: const TextStyle(color: kCouleurHausse)),
  ),
  ReportColumn(
    key: 'echouees',
    label: 'Échouées',
    align: TextAlign.right,
    valeur: (r) => r.echouees,
    render: (r, _) => Text(fmtNb(r.echouees), style: r.echouees > 0 ? const TextStyle(color: kCouleurBaisse) : null),
  ),
  ReportColumn(
    key: 'en_cours',
    label: 'En cours',
    align: TextAlign.right,
    valeur: (r) => r.enCours,
    render: (r, _) => Text(_brut(r.enCours)),
  ),
  ReportColumn(
    key: 'cout_total',
    label: 'Coût total payé',
    align: TextAlign.right,
    valeur: (r) => r.coutTotal,
    render: (r, _) => Text(fmtAr(r.coutTotal)),
  ),
  ReportColumn(
    key: 'cout_moyen',
    label: 'Coût moyen',
    align: TextAlign.right,
    valeur: (r) => r.coutMoyen,
    render: (r, _) => Text(fmtAr(r.coutMoyen)),
  ),
  ReportColumn(
    key: 'frais_factures',
    label: 'Frais facturés',
    align: TextAlign.right,
    valeur: (r) => r.fraisFactures,
    render: (r, _) => Text(fmtAr(r.fraisFactures)),
  ),
  ReportColumn(
    key: 'marge_livraison',
    label: 'Marge livraison',
    align: TextAlign.right,
    valeur: (r) => r.margeLivraison,
    render: (r, _) =>
        Text(fmtAr(r.margeLivraison), style: r.margeLivraison < 0 ? const TextStyle(color: kCouleurBaisse) : null),
  ),
  ReportColumn(
    key: 'taux_reussite',
    label: 'Taux réussite',
    align: TextAlign.right,
    valeur: (r) => r.tauxReussite,
    render: (r, _) => Text(fmtPct(r.tauxReussite)),
  ),
  ReportColumn(
    key: 'taux_echec',
    label: 'Taux échec',
    align: TextAlign.right,
    valeur: (r) => r.tauxEchec,
    render: (r, _) => Text(fmtPct(r.tauxEchec)),
  ),
  ReportColumn(
    key: 'delai_moyen_minutes',
    label: 'Délai moyen',
    align: TextAlign.right,
    valeur: (r) => r.delaiMoyenMinutes,
    render: (r, _) => Text(fmtDuree(r.delaiMoyenMinutes)),
    // Export Excel en minutes brutes (`export: (r) => r.delai_moyen_minutes`).
    export: (r) => r.delaiMoyenMinutes,
  ),
];

/// Cellules formatées d'une ligne « livreur » (PDF), mêmes colonnes que
/// l'écran.
List<String> _ligneLivreurTexte(LigneLivreur r) => [
      r.nom,
      _brut(r.livraisons),
      fmtNb(r.reussies),
      fmtNb(r.echouees),
      _brut(r.enCours),
      fmtAr(r.coutTotal),
      fmtAr(r.coutMoyen),
      fmtAr(r.fraisFactures),
      fmtAr(r.margeLivraison),
      fmtPct(r.tauxReussite),
      fmtPct(r.tauxEchec),
      fmtDuree(r.delaiMoyenMinutes),
    ];

/// Colonnes du tableau « Par zone de livraison » (Zone / Livraisons /
/// Réussies / Échouées / Frais encaissés / Taux réussite).
final List<ReportColumn<LigneZoneLivraison>> _colonnesZone = [
  ReportColumn(
    key: 'zone',
    label: 'Zone',
    valeur: (r) => r.zone,
    render: (r, _) => r.zone == 'RECUPERATION' ? const _BadgeOutline('Récupération') : Text(r.zone),
  ),
  ReportColumn(
    key: 'livraisons',
    label: 'Livraisons',
    align: TextAlign.right,
    valeur: (r) => r.livraisons,
    render: (r, _) => Text(_brut(r.livraisons)),
  ),
  ReportColumn(
    key: 'reussies',
    label: 'Réussies',
    align: TextAlign.right,
    valeur: (r) => r.reussies,
    render: (r, _) => Text(_brut(r.reussies)),
  ),
  ReportColumn(
    key: 'echouees',
    label: 'Échouées',
    align: TextAlign.right,
    valeur: (r) => r.echouees,
    render: (r, _) => Text(_brut(r.echouees)),
  ),
  ReportColumn(
    key: 'frais',
    label: 'Frais encaissés',
    align: TextAlign.right,
    valeur: (r) => r.frais,
    render: (r, _) => Text(fmtAr(r.frais)),
  ),
  ReportColumn(
    key: 'taux_reussite',
    label: 'Taux réussite',
    align: TextAlign.right,
    valeur: (r) => r.tauxReussite,
    render: (r, _) => Text(fmtPct(r.tauxReussite)),
  ),
];

/// Cellules formatées d'une ligne « zone » (PDF), mêmes colonnes que l'écran.
List<String> _ligneZoneTexte(LigneZoneLivraison r) => [
      _zoneTexte(r.zone),
      _brut(r.livraisons),
      _brut(r.reussies),
      _brut(r.echouees),
      fmtAr(r.frais),
      fmtPct(r.tauxReussite),
    ];

/// « Livraisons » — port de components/reports/section-deliveries.tsx :
/// paragraphe explicatif, 5 KPI, comparatif des livreurs, graphiques
/// « Livraisons réussies et échouées » et « Taux de réussite par livreur »,
/// tableau par zone de livraison.
class SectionDeliveries extends ConsumerWidget {
  const SectionDeliveries({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ReportRequest.pour(
      ReportSection.deliveries,
      filter,
      extra: ref.watch(reportExtrasProvider(ReportSection.deliveries)),
    );
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : DeliveriesData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final t = data?.totaux;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final graphiqueSerie = ChartCard(
      titre: 'Livraisons réussies et échouées',
      loading: loading,
      error: error,
      vide: data == null || data.serie.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : SerieChart(
              data: data.serie,
              series: const [
                SerieDef(
                  key: 'reussies',
                  label: 'Réussies',
                  type: SerieType.bar,
                  unite: ChartUnite.nb,
                  color: Color(0xFF16A34A),
                  stackId: 'l',
                ),
                SerieDef(
                  key: 'echouees',
                  label: 'Échouées',
                  type: SerieType.bar,
                  unite: ChartUnite.nb,
                  color: Color(0xFFEF4444),
                  stackId: 'l',
                ),
              ],
            ),
    );

    final graphiqueLivreurs = ChartCard(
      titre: 'Taux de réussite par livreur',
      loading: loading,
      error: error,
      vide: data == null || data.parLivreur.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : BarresChart(
              data: [for (final l in data.parLivreur) {'nom': l.nom, 'taux_reussite': l.tauxReussite}],
              labelKey: 'nom',
              valueKey: 'taux_reussite',
              unite: ChartUnite.nb,
              color: const Color(0xFF16A34A),
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_explication, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 16),
        KpiGrid(
          cols: 5,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: 'Livraisons terminées',
              icon: Icons.local_shipping_outlined,
              valeur: t == null ? null : fmtNb(data!.total('livraisons')),
              detail: t == null ? null : '${fmtNb(data!.total('en_cours'))} en cours',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Taux de réussite',
              icon: Icons.check_circle_outline,
              valeur: t == null ? null : fmtPct(data!.total('taux_reussite')),
              couleur: kCouleurHausse,
              detail: t == null ? null : '${fmtNb(data!.total('reussies'))} réussies',
            ),
            ReportKpiCard(
              loading: loading,
              titre: "Taux d'échec",
              icon: Icons.cancel_outlined,
              valeur: t == null ? null : fmtPct(data!.total('taux_echec')),
              couleur: t != null && data!.total('echouees') > 0 ? kCouleurBaisse : null,
              detail: t == null ? null : '${fmtNb(data!.total('echouees'))} retours',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Coût moyen / livraison',
              icon: Icons.account_balance_wallet_outlined,
              valeur: t == null ? null : fmtAr(data!.total('cout_moyen')),
              detail: t == null
                  ? null
                  : 'total ${fmtAr(data!.total('cout_total'))} · marge ${fmtAr(data.total('marge_livraison'))}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Délai moyen',
              icon: Icons.schedule_outlined,
              valeur: t == null ? null : fmtDuree(t['delai_moyen_minutes']),
              detail: t == null ? null : 'sur ${fmtNb(data!.total('nb_delais_mesures'))} livraisons mesurées',
            ),
          ],
        ),
        const SizedBox(height: 16),
        ReportTable<LigneLivreur>(
          titre: 'Comparatif des livreurs',
          colonnes: _colonnesLivreur,
          lignes: data?.parLivreur,
          loading: loading,
          error: error,
          exportNom: 'livraisons_par_livreur',
          rowKey: (r, _) => r.id,
          vide: 'Aucune livraison assignée sur la période.',
        ),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-3` (+ `xl:col-span-2`) : 2/3 – 1/3 côte
        // à côte dès 1280 px (`xl`), une colonne sinon.
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1280) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: graphiqueSerie),
                  const SizedBox(width: 16),
                  Expanded(child: graphiqueLivreurs),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [graphiqueSerie, const SizedBox(height: 16), graphiqueLivreurs],
            );
          },
        ),
        const SizedBox(height: 16),
        ReportTable<LigneZoneLivraison>(
          titre: 'Par zone de livraison',
          colonnes: _colonnesZone,
          lignes: data?.parZone,
          loading: loading,
          error: error,
          pageSize: 10,
          exportNom: 'livraisons_par_zone',
          rowKey: (r, _) => r.zone,
        ),
      ],
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

/// Version imprimable de la section Livraisons : les 5 KPI puis les deux
/// tableaux (comparatif des livreurs, zones) avec les colonnes de l'écran.
ReportPrintable? deliveriesPrintable(DeliveriesData data) {
  return ReportPrintable(
    sectionLabel: ReportSection.deliveries.label,
    sectionDescription: ReportSection.deliveries.description,
    kpis: [
      PrintableKpi('Livraisons terminées', fmtNb(data.total('livraisons')), '${fmtNb(data.total('en_cours'))} en cours'),
      PrintableKpi('Taux de réussite', fmtPct(data.total('taux_reussite')), '${fmtNb(data.total('reussies'))} réussies'),
      PrintableKpi("Taux d'échec", fmtPct(data.total('taux_echec')), '${fmtNb(data.total('echouees'))} retours'),
      PrintableKpi(
        'Coût moyen / livraison',
        fmtAr(data.total('cout_moyen')),
        'total ${fmtAr(data.total('cout_total'))} · marge ${fmtAr(data.total('marge_livraison'))}',
      ),
      PrintableKpi(
        'Délai moyen',
        fmtDuree(data.totaux['delai_moyen_minutes']),
        'sur ${fmtNb(data.total('nb_delais_mesures'))} livraisons mesurées',
      ),
    ],
    tables: [
      PrintableTable(
        titre: 'Comparatif des livreurs',
        headers: [for (final c in _colonnesLivreur) c.label],
        rows: [for (final r in data.parLivreur) _ligneLivreurTexte(r)],
      ),
      PrintableTable(
        titre: 'Par zone de livraison',
        headers: [for (final c in _colonnesZone) c.label],
        rows: [for (final r in data.parZone) _ligneZoneTexte(r)],
      ),
    ],
  );
}
