import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../models/campaign.dart';
import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';
import '../widgets/kpi_card.dart';
import '../widgets/report_chart.dart';
import '../widgets/report_printable.dart';
import '../widgets/report_table.dart';
import 'campaign_dialogs.dart';

/// Valeur « Toutes plateformes » du sélecteur (`useState('ALL')` du web).
const String _toutesPlateformes = 'ALL';

/// `#16a34a` des barres « CA généré par plateforme ».
const Color _vert = Color(0xFF16A34A);

/// `roiCouleur` du web : vert si ≥ 0, rouge sinon, couleur du texte si `null`.
Color? _roiCouleur(num? roi) => roi == null ? null : (roi >= 0 ? kCouleurHausse : kCouleurBaisse);

/// Colonne « Période » : `{début} → {fin}` ou `{début} → en cours`.
String _periodeTexte(Campagne r) =>
    '${fmtDate(r.dateDebut)}${r.dateFin != null && r.dateFin!.isNotEmpty ? ' → ${fmtDate(r.dateFin)}' : ' → en cours'}';

/// Colonne « Commandes » : `{n} ({livrées} livrées)`.
String _commandesTexte(Campagne r) => '${fmtNb(r.commandes)} (${fmtNb(r.commandesLivrees)} livrées)';

/// ROI du tableau des campagnes : `n/a (coût 0)` sans coût.
String _roiCampagneTexte(num? roi) => roi == null ? 'n/a (coût 0)' : fmtPct(roi, signe: true);

/// ROI des autres tableaux / KPI : `n/a` sans coût.
String _roiTexte(num? roi) => roi == null ? 'n/a' : fmtPct(roi, signe: true);

const String _texteRoi =
    "ROI = (CA généré − coût de la campagne) / coût × 100. Le CA généré vient des commandes rattachées à la campagne (champ « Campagne » à la création d'une commande) et livrées sur la période. Bénéfice attribué = marge produits de ces commandes − coût de la campagne.";

/// Colonnes communes des tableaux « plus / moins rentables ».
final List<ReportColumn<Campagne>> _colonnesRentabilite = [
  ReportColumn(key: 'nom', label: 'Campagne', valeur: (r) => r.nom),
  ReportColumn(key: 'plateforme_label', label: 'Plateforme', valeur: (r) => r.plateformeLabel),
  ReportColumn(
    key: 'depenses',
    label: 'Dépenses',
    align: TextAlign.right,
    valeur: (r) => r.depenses,
    render: (r, _) => Text(fmtAr(r.depenses)),
  ),
  ReportColumn(key: 'ca', label: 'CA', align: TextAlign.right, valeur: (r) => r.ca, render: (r, _) => Text(fmtAr(r.ca))),
  ReportColumn(
    key: 'roi_pct',
    label: 'ROI',
    align: TextAlign.right,
    valeur: (r) => r.roiPct,
    render: (r, _) => Text(fmtPct(r.roiPct, signe: true), style: TextStyle(color: _roiCouleur(r.roiPct))),
  ),
];

const List<String> _enTetesRentabilite = ['Campagne', 'Plateforme', 'Dépenses', 'CA', 'ROI'];

List<String> _ligneRentabilite(Campagne r) =>
    [r.nom, r.plateformeLabel, fmtAr(r.depenses), fmtAr(r.ca), fmtPct(r.roiPct, signe: true)];

/// « Marketing » — port de components/reports/section-marketing.tsx :
/// 4 KPI, tableau des campagnes (création / modification / suppression),
/// répartition par plateforme, campagnes les plus et les moins rentables.
///
/// La plateforme filtrée est un état local (comme le `useState('ALL')` du
/// web) recopié dans `reportExtrasProvider(marketing)` sous la clé
/// `platform` (absente pour « Toutes plateformes ») : l'écran reconstruit
/// ainsi la même requête que la section (impression, indicateur de
/// chargement).
class SectionMarketing extends ConsumerStatefulWidget {
  const SectionMarketing({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  ConsumerState<SectionMarketing> createState() => _SectionMarketingState();
}

class _SectionMarketingState extends ConsumerState<SectionMarketing> {
  String _plateforme = _toutesPlateformes;

  @override
  void initState() {
    super.initState();
    // Plateforme conservée d'une visite précédente (extras de la section).
    final memo = ref.read(reportExtrasProvider(ReportSection.marketing))['platform'];
    if (memo != null && kPlateformes.any((p) => p.code == memo)) _plateforme = memo;
  }

  void _choisirPlateforme(String v) {
    setState(() => _plateforme = v);
    ref
        .read(reportExtrasProvider(ReportSection.marketing).notifier)
        .set('platform', v == _toutesPlateformes ? null : v);
  }

  Future<void> _modifier(Campagne? campagne) => showCampaignDialog(context, campagne: campagne);

  Future<void> _supprimer(Campagne campagne) => showCampaignDeleteDialog(context, campagne);

  /// Colonnes du tableau « Campagnes » (`colonnes` du web).
  List<ReportColumn<Campagne>> get _colonnesCampagnes => [
    ReportColumn(
      key: 'nom',
      label: 'Campagne',
      valeur: (r) => r.nom,
      render: (r, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(r.nom, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (!r.actif) ...[const SizedBox(width: 8), const _BadgeOutline('Inactive')],
        ],
      ),
    ),
    ReportColumn(key: 'plateforme_label', label: 'Plateforme', valeur: (r) => r.plateformeLabel),
    ReportColumn(
      key: 'periode',
      label: 'Période',
      valeur: (r) => _periodeTexte(r),
      render: (r, _) => Text(_periodeTexte(r)),
      export: (r) => '${r.dateDebut} → ${r.dateFin ?? ''}',
    ),
    ReportColumn(
      key: 'depenses',
      label: 'Dépenses',
      align: TextAlign.right,
      valeur: (r) => r.depenses,
      render: (r, _) => Text(fmtAr(r.depenses)),
    ),
    ReportColumn(
      key: 'commandes',
      label: 'Commandes',
      align: TextAlign.right,
      valeur: (r) => r.commandes,
      render: (r, _) => Text(_commandesTexte(r)),
      export: (r) => r.commandes,
    ),
    ReportColumn(
      key: 'ca',
      label: 'CA généré',
      align: TextAlign.right,
      valeur: (r) => r.ca,
      render: (r, _) => Text(fmtAr(r.ca)),
    ),
    ReportColumn(
      key: 'marge_produits',
      label: 'Marge produits',
      align: TextAlign.right,
      valeur: (r) => r.margeProduits,
      render: (r, _) => Text(fmtAr(r.margeProduits)),
    ),
    ReportColumn(
      key: 'benefice',
      label: 'Bénéfice attribué',
      align: TextAlign.right,
      valeur: (r) => r.benefice,
      render: (r, _) => Text(fmtAr(r.benefice), style: TextStyle(color: r.benefice < 0 ? kCouleurBaisse : null)),
    ),
    ReportColumn(
      key: 'roi_pct',
      label: 'ROI',
      align: TextAlign.right,
      valeur: (r) => r.roiPct,
      render: (r, _) => Text(
        _roiCampagneTexte(r.roiPct),
        style: TextStyle(fontWeight: FontWeight.w500, color: _roiCouleur(r.roiPct)),
      ),
      export: (r) => r.roiPct,
    ),
    // `print:hidden` : absente de la version PDF ([marketingPrintable]) ;
    // exportée vide comme sur le web.
    ReportColumn(
      key: 'actions',
      label: '',
      align: TextAlign.right,
      render: (r, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Modifier',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            onPressed: () => _modifier(r),
            icon: const Icon(Icons.edit_outlined, size: 14),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Supprimer',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            onPressed: () => _supprimer(r),
            icon: Icon(Icons.delete_outline, size: 14, color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
      export: (_) => null,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final request = ReportRequest.pour(
      ReportSection.marketing,
      widget.filter,
      extra: ref.watch(reportExtrasProvider(ReportSection.marketing)),
    );
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : MarketingData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final t = data?.totaux;
    final roiGlobal = t?['roi_pct'];
    final sansCampagne = data?.total('commandes_sans_campagne') ?? 0;

    final actions = _ActionsCampagnes(
      plateforme: _plateforme,
      onPlateforme: _choisirPlateforme,
      onNouvelle: () => _modifier(null),
    );

    final parPlateforme = [
      for (final r in data?.parPlateforme ?? const <LignePlateforme>[])
        {'label': r.label, 'depenses': r.depenses, 'ca': r.ca},
    ];

    final graphiqueDepenses = ChartCard(
      titre: 'Dépenses par plateforme',
      loading: loading,
      error: error,
      vide: data == null || data.parPlateforme.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : CamembertChart(data: parPlateforme, labelKey: 'label', valueKey: 'depenses', unite: ChartUnite.ar),
    );

    final graphiqueCa = ChartCard(
      titre: 'CA généré par plateforme',
      loading: loading,
      error: error,
      vide: data == null || data.parPlateforme.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : BarresChart(data: parPlateforme, labelKey: 'label', valueKey: 'ca', color: _vert),
    );

    final tablePlateformes = ReportTable<LignePlateforme>(
      titre: 'Par plateforme',
      colonnes: [
        ReportColumn(key: 'label', label: 'Plateforme', valeur: (r) => r.label),
        ReportColumn(
          key: 'nb_campagnes',
          label: 'Camp.',
          align: TextAlign.right,
          valeur: (r) => r.nbCampagnes,
          render: (r, _) => Text(_brut(r.nbCampagnes)),
        ),
        ReportColumn(
          key: 'depenses',
          label: 'Dépenses',
          align: TextAlign.right,
          valeur: (r) => r.depenses,
          render: (r, _) => Text(fmtAr(r.depenses)),
        ),
        ReportColumn(
          key: 'commandes',
          label: 'Cmd',
          align: TextAlign.right,
          valeur: (r) => r.commandes,
          render: (r, _) => Text(_brut(r.commandes)),
        ),
        ReportColumn(
          key: 'ca',
          label: 'CA',
          align: TextAlign.right,
          valeur: (r) => r.ca,
          render: (r, _) => Text(fmtAr(r.ca)),
        ),
        ReportColumn(
          key: 'roi_pct',
          label: 'ROI',
          align: TextAlign.right,
          valeur: (r) => r.roiPct,
          render: (r, _) => Text(_roiTexte(r.roiPct), style: TextStyle(color: _roiCouleur(r.roiPct))),
          export: (r) => r.roiPct,
        ),
      ],
      lignes: data?.parPlateforme,
      loading: loading,
      error: error,
      pageSize: 10,
      rowKey: (r, _) => r.plateforme,
      compact: true,
    );

    final avecRentabilite = data != null && (data.plusRentables.isNotEmpty || data.moinsRentables.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$_texteRoi${sansCampagne > 0 ? ' ${fmtNb(sansCampagne)} commandes de la période ne sont rattachées à aucune campagne.' : ''}',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 16),
        KpiGrid(
          cols: 4,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: 'Dépenses de campagnes',
              icon: Icons.account_balance_wallet_outlined,
              valeur: data == null ? null : fmtAr(data.total('depenses_campagnes')),
              detail: data == null
                  ? null
                  : '${fmtNb(data.total('nb_campagnes'))} campagnes · Pub en caisse : ${fmtAr(data.total('depenses_pub_caisse'))}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Commandes générées',
              icon: Icons.shopping_cart_outlined,
              valeur: data == null ? null : fmtNb(data.total('commandes')),
              detail: data == null ? null : '${fmtNb(data.total('commandes_livrees'))} livrées',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'CA généré',
              icon: Icons.paid_outlined,
              valeur: data == null ? null : fmtAr(data.total('ca')),
              detail: data == null ? null : 'marge produits ${fmtAr(data.total('marge_produits'))}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'ROI global',
              icon: Icons.percent,
              valeur: data == null ? null : _roiTexte(roiGlobal),
              couleur: data == null ? null : _roiCouleur(roiGlobal),
              detail: data != null && roiGlobal == null ? 'aucune dépense de campagne' : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Adaptation mobile : les actions (sélecteur de plateforme + bouton
        // « Campagne ») tiennent dans l'en-tête du tableau dès 600 px ; en
        // dessous elles passent sur une ligne au-dessus du tableau.
        LayoutBuilder(
          builder: (context, constraints) {
            final large = constraints.maxWidth >= 600;
            final table = ReportTable<Campagne>(
              titre: 'Campagnes',
              description: 'Campagnes actives sur la période. Créez-les ici, puis rattachez les commandes concernées.',
              actions: large ? actions : null,
              colonnes: _colonnesCampagnes,
              lignes: data?.campagnes,
              loading: loading,
              error: error,
              exportNom: 'campagnes_marketing',
              rowKey: (r, _) => r.id,
              vide: 'Aucune campagne sur la période. Cliquez sur « Campagne » pour en enregistrer une.',
            );
            if (large) return table;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Align(alignment: Alignment.centerRight, child: actions), const SizedBox(height: 8), table],
            );
          },
        ),
        const SizedBox(height: 16),
        _Grille(enfants: [graphiqueDepenses, graphiqueCa, tablePlateformes]),
        if (avecRentabilite) ...[
          const SizedBox(height: 16),
          _Grille(
            enfants: [
              ReportTable<Campagne>(
                titre: 'Campagnes les plus rentables',
                colonnes: _colonnesRentabilite,
                lignes: data.plusRentables,
                rowKey: (r, _) => r.id,
                pageSize: 5,
              ),
              ReportTable<Campagne>(
                titre: 'Campagnes les moins rentables',
                colonnes: _colonnesRentabilite,
                lignes: data.moinsRentables,
                rowKey: (r, _) => r.id,
                pageSize: 5,
                vide: 'Il faut au moins deux campagnes avec un coût pour comparer.',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Rendu brut d'un nombre (`String(row[key])` du web) : entier sans
/// séparateur quand la valeur est entière.
String _brut(num v) => v == v.truncate() ? '${v.toInt()}' : '$v';

/// Actions du tableau « Campagnes » : sélecteur de plateforme
/// (« Toutes plateformes » + plateformes) et bouton « Campagne ».
class _ActionsCampagnes extends StatelessWidget {
  const _ActionsCampagnes({required this.plateforme, required this.onPlateforme, required this.onNouvelle});

  final String plateforme;
  final ValueChanged<String> onPlateforme;
  final VoidCallback onNouvelle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 144,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: plateforme,
              isDense: true,
              isExpanded: true,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
              items: [
                const DropdownMenuItem(value: _toutesPlateformes, child: Text('Toutes plateformes')),
                for (final p in kPlateformes) DropdownMenuItem(value: p.code, child: Text(p.label)),
              ],
              onChanged: (v) {
                if (v != null) onPlateforme(v);
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 32,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            onPressed: onNouvelle,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Campagne'),
          ),
        ),
      ],
    );
  }
}

/// `grid-cols-1 xl:grid-cols-2/3` : colonnes égales côte à côte dès 1280 px
/// (`xl`), l'une sous l'autre sinon.
class _Grille extends StatelessWidget {
  const _Grille({required this.enfants});

  final List<Widget> enfants;

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
                Expanded(child: enfants[i]),
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

/// `<Badge variant="outline">` du web (« Inactive »).
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

/// Version imprimable du marketing : les 4 KPI puis les tableaux de la
/// section (campagnes sans la colonne d'actions, par plateforme, plus et
/// moins rentables quand le web les affiche) avec les colonnes de l'écran.
ReportPrintable? marketingPrintable(MarketingData data) {
  final roiGlobal = data.totaux['roi_pct'];
  final avecRentabilite = data.plusRentables.isNotEmpty || data.moinsRentables.isNotEmpty;
  return ReportPrintable(
    sectionLabel: ReportSection.marketing.label,
    sectionDescription: ReportSection.marketing.description,
    kpis: [
      PrintableKpi(
        'Dépenses de campagnes',
        fmtAr(data.total('depenses_campagnes')),
        '${fmtNb(data.total('nb_campagnes'))} campagnes · Pub en caisse : ${fmtAr(data.total('depenses_pub_caisse'))}',
      ),
      PrintableKpi('Commandes générées', fmtNb(data.total('commandes')), '${fmtNb(data.total('commandes_livrees'))} livrées'),
      PrintableKpi('CA généré', fmtAr(data.total('ca')), 'marge produits ${fmtAr(data.total('marge_produits'))}'),
      PrintableKpi('ROI global', _roiTexte(roiGlobal), roiGlobal == null ? 'aucune dépense de campagne' : null),
    ],
    tables: [
      PrintableTable(
        titre: 'Campagnes',
        headers: const [
          'Campagne',
          'Plateforme',
          'Période',
          'Dépenses',
          'Commandes',
          'CA généré',
          'Marge produits',
          'Bénéfice attribué',
          'ROI',
        ],
        rows: [
          for (final r in data.campagnes)
            [
              r.actif ? r.nom : '${r.nom} (Inactive)',
              r.plateformeLabel,
              _periodeTexte(r),
              fmtAr(r.depenses),
              _commandesTexte(r),
              fmtAr(r.ca),
              fmtAr(r.margeProduits),
              fmtAr(r.benefice),
              _roiCampagneTexte(r.roiPct),
            ],
        ],
      ),
      PrintableTable(
        titre: 'Par plateforme',
        headers: const ['Plateforme', 'Camp.', 'Dépenses', 'Cmd', 'CA', 'ROI'],
        rows: [
          for (final r in data.parPlateforme)
            [r.label, _brut(r.nbCampagnes), fmtAr(r.depenses), _brut(r.commandes), fmtAr(r.ca), _roiTexte(r.roiPct)],
        ],
      ),
      if (avecRentabilite) ...[
        PrintableTable(
          titre: 'Campagnes les plus rentables',
          headers: _enTetesRentabilite,
          rows: [for (final r in data.plusRentables) _ligneRentabilite(r)],
        ),
        PrintableTable(
          titre: 'Campagnes les moins rentables',
          headers: _enTetesRentabilite,
          rows: [for (final r in data.moinsRentables) _ligneRentabilite(r)],
        ),
      ],
    ],
  );
}
