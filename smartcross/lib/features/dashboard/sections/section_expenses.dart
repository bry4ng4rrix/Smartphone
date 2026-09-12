import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';
import '../widgets/kpi_card.dart';
import '../widgets/report_chart.dart';
import '../widgets/report_printable.dart';
import '../widgets/report_table.dart';

/// Libellé de la source d'une dépense (`r.source === 'caisse' ? 'Caisse' :
/// 'Livreur'`).
String _sourceLabel(String source) => source == 'caisse' ? 'Caisse' : 'Livreur';

/// Rendu brut d'un nombre (`String(row[key])` du web) : entier sans
/// séparateur quand la valeur est entière.
String _brut(num v) => v == v.truncate() ? '${v.toInt()}' : '$v';

/// Colonne « Date » du détail : date-heure pour la caisse, date seule pour
/// les tournées livreurs (`fmtDateHeure(`${date}T12:00:00+03:00`).slice(0,
/// 10)`).
String _dateDepense(MouvementDepense r) {
  if (r.source == 'caisse') return fmtDateHeure(r.date);
  final texte = fmtDateHeure('${r.date}T12:00:00+03:00');
  // `.slice(0, 10)` : sans effet sur « — » (date absente).
  return texte.length > 10 ? texte.substring(0, 10) : texte;
}

/// Part d'une catégorie dans le total actuel (1 décimale), `null` si le total
/// est nul.
double? _part(LigneCategorieDepense r, ExpensesTotaux? t) {
  if (t == null || t.total.actuel == 0) return null;
  return double.parse((100 * r.total / t.total.actuel).toStringAsFixed(1));
}

String _partTexte(LigneCategorieDepense r, ExpensesTotaux? t) {
  final p = _part(r, t);
  return p == null ? '—' : '${p.toStringAsFixed(1)} %';
}

/// Lignes de la carte « Livraison : facturé au client vs coût réel »
/// (libellé, valeur formatée) — ordre exact du web ; la 4e (index 3) est la
/// marge, en gras et colorée.
List<(String, String)> _lignesLivraison(Map<String, num> l) => [
  ('Commandes livrées', fmtNb(l['nb_livrees'] ?? 0)),
  ('Frais de livraison facturés au client', fmtAr(l['frais_factures_client'] ?? 0)),
  ('Frais réellement payés (tournées acceptées)', fmtAr(l['cout_reel_livreurs'] ?? 0)),
  ('Marge livraison', fmtAr(l['marge_livraison'] ?? 0)),
  ('Frais moyen facturé par livraison', fmtAr(l['frais_moyen_client'] ?? 0)),
  ('Coût moyen réel par livraison', fmtAr(l['cout_moyen_livraison'] ?? 0)),
];

const String _descriptionCategories =
    "Catégories de caisse (Paramètres › Dépenses) et types de dépense des livreurs. Les achats de stock sont listés mais n'entrent pas dans le bénéfice : la marchandise est comptée à la vente, dans le coût d'achat.";

const String _descriptionLivraison =
    "Frais facturés = frais de livraison des commandes livrées. Coût réel = frais de tournée déclarés par les livreurs et acceptés (carburant, repas…). L'application n'a pas d'agence externe : la livraison est assurée par les livreurs de l'équipe.";

/// « Dépenses » — port de components/reports/section-expenses.tsx : 4 KPI,
/// évolution des dépenses (barres empilées caisse / tournées), anneau par
/// catégorie, tableau par catégorie, carte « Livraison : facturé au client
/// vs coût réel », détail des 300 dernières opérations.
class SectionExpenses extends ConsumerWidget {
  const SectionExpenses({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ReportRequest.pour(
      ReportSection.expenses,
      filter,
      extra: ref.watch(reportExtrasProvider(ReportSection.expenses)),
    );
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : ExpensesData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final t = data?.totaux;
    final l = data?.livraison;
    final margeLivraison = l?['marge_livraison'] ?? 0;

    final graphiqueSerie = ChartCard(
      titre: 'Évolution des dépenses',
      loading: loading,
      error: error,
      vide: data == null || data.serie.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : SerieChart(
              data: data.serie,
              series: const [
                SerieDef(key: 'caisse', label: 'Caisse', type: SerieType.bar, color: Color(0xFFEF4444), stackId: 'd'),
                SerieDef(
                  key: 'livreur',
                  label: 'Tournées livreurs',
                  type: SerieType.bar,
                  color: Color(0xFFF59E0B),
                  stackId: 'd',
                ),
              ],
            ),
    );

    final graphiqueCategories = ChartCard(
      titre: 'Dépenses par catégorie',
      loading: loading,
      error: error,
      vide: data == null || data.parCategorie.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : CamembertChart(
              data: [
                for (final r in data.parCategorie) {'label': r.label, 'total': r.total},
              ],
              labelKey: 'label',
              valueKey: 'total',
              unite: ChartUnite.ar,
            ),
    );

    final tableCategories = ReportTable<LigneCategorieDepense>(
      titre: 'Dépenses par catégorie',
      description: _descriptionCategories,
      colonnes: [
        ReportColumn(
          key: 'label',
          label: 'Catégorie',
          valeur: (r) => r.label,
          render: (r, _) => Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(r.label),
              if (r.horsResultat)
                const _Badge('Achat de stock · hors bénéfice', variante: _BadgeVariante.secondary, petite: true),
            ],
          ),
        ),
        ReportColumn(
          key: 'source',
          label: 'Source',
          valeur: (r) => r.source,
          render: (r, _) => _Badge(_sourceLabel(r.source), variante: _BadgeVariante.outline),
          export: (r) => _sourceLabel(r.source),
        ),
        ReportColumn(
          key: 'nb',
          label: 'Opérations',
          align: TextAlign.right,
          valeur: (r) => r.nb,
          render: (r, _) => Text(_brut(r.nb)),
        ),
        ReportColumn(
          key: 'total',
          label: 'Total',
          align: TextAlign.right,
          valeur: (r) => r.total,
          render: (r, _) => Text(fmtAr(r.total)),
        ),
        ReportColumn(
          key: 'part',
          label: 'Part',
          align: TextAlign.right,
          render: (r, _) => Text(_partTexte(r, t)),
          export: (r) => _part(r, t),
        ),
      ],
      lignes: data?.parCategorie,
      loading: loading,
      error: error,
      exportNom: 'depenses_par_categorie',
      rowKey: (r, _) => '${r.source}-${r.label}',
    );

    final carteLivraison = _LivraisonCard(livraison: l, loading: loading, margeLivraison: margeLivraison);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(
          cols: 4,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: 'Total des sorties',
              icon: Icons.account_balance_wallet_outlined,
              valeur: t == null ? null : fmtAr(t.total.actuel),
              variation: t?.total,
              inverse: true,
              format: fmtAr,
              detail: t == null ? null : '${fmtNb(t.nbMouvements)} opérations · charges ${fmtAr(t.charges.actuel)}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Sorties de caisse',
              icon: Icons.account_balance_outlined,
              valeur: t == null ? null : fmtAr(t.caisse.actuel),
              variation: t?.caisse,
              inverse: true,
              format: fmtAr,
              detail: t == null
                  ? null
                  : (t.achatsStock.actuel != 0
                        ? 'dont achats de stock ${fmtAr(t.achatsStock.actuel)} (hors bénéfice)'
                        : 'salaires, pub, autres'),
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Frais de tournée (livreurs)',
              icon: Icons.local_shipping_outlined,
              valeur: t == null ? null : fmtAr(t.livreur.actuel),
              variation: t?.livreur,
              inverse: true,
              format: fmtAr,
              detail: 'dépenses acceptées par le gérant',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Marge sur livraison',
              icon: Icons.receipt_long_outlined,
              valeur: l == null ? null : fmtAr(margeLivraison),
              couleur: l == null ? null : (margeLivraison < 0 ? kCouleurBaisse : kCouleurHausse),
              detail: l == null
                  ? null
                  : 'facturé ${fmtAr(l['frais_factures_client'] ?? 0)} − coût réel ${fmtAr(l['cout_reel_livreurs'] ?? 0)}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-3` : 2/3 – 1/3 côte à côte dès 1280 px
        // (`xl`), une colonne sinon.
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1280) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: graphiqueSerie),
                  const SizedBox(width: 16),
                  Expanded(child: graphiqueCategories),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [graphiqueSerie, const SizedBox(height: 16), graphiqueCategories],
            );
          },
        ),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-2`.
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1280) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tableCategories),
                  const SizedBox(width: 16),
                  Expanded(child: carteLivraison),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [tableCategories, const SizedBox(height: 16), carteLivraison],
            );
          },
        ),
        const SizedBox(height: 16),
        ReportTable<MouvementDepense>(
          titre: 'Détail des dépenses',
          description: 'Les 300 opérations les plus récentes de la période.',
          colonnes: [
            ReportColumn(
              key: 'date',
              label: 'Date',
              valeur: (r) => r.date,
              render: (r, _) => Text(_dateDepense(r)),
              export: (r) => r.date,
            ),
            ReportColumn(
              key: 'source',
              label: 'Source',
              valeur: (r) => r.source,
              render: (r, _) => _Badge(_sourceLabel(r.source), variante: _BadgeVariante.outline),
              export: (r) => _sourceLabel(r.source),
            ),
            ReportColumn(key: 'categorie', label: 'Catégorie', valeur: (r) => r.categorie),
            ReportColumn(key: 'libelle', label: 'Libellé', valeur: (r) => r.libelle),
            ReportColumn(key: 'auteur', label: 'Par', valeur: (r) => r.auteur),
            ReportColumn(
              key: 'montant',
              label: 'Montant',
              align: TextAlign.right,
              valeur: (r) => r.montant,
              render: (r, _) => Text(fmtAr(r.montant)),
            ),
          ],
          lignes: data?.mouvements,
          loading: loading,
          error: error,
          pageSize: 20,
          exportNom: 'detail_depenses',
          compact: true,
        ),
      ],
    );
  }
}

/// Carte « Livraison : facturé au client vs coût réel » : 6 lignes, la marge
/// en gras (verte ou rouge). Comme le web, squelettes tant qu'il n'y a pas de
/// données (`loading || !l`).
class _LivraisonCard extends StatelessWidget {
  const _LivraisonCard({required this.livraison, required this.loading, required this.margeLivraison});

  final Map<String, num>? livraison;
  final bool loading;
  final num margeLivraison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final l = livraison;

    Widget corps;
    if (loading || l == null) {
      corps = Column(
        children: [
          for (var i = 0; i < 4; i++) ...[if (i > 0) const SizedBox(height: 8), const ReportSkeleton(height: 28)],
        ],
      );
    } else {
      final lignes = _lignesLivraison(l);
      corps = Column(
        children: [
          for (var i = 0; i < lignes.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: i == lignes.length - 1 ? null : Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        lignes[i].$1,
                        style: TextStyle(fontSize: 14, fontWeight: i == 3 ? FontWeight.w600 : null),
                      ),
                    ),
                  ),
                  Text(
                    lignes[i].$2,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == 3 ? FontWeight.w600 : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: i == 3 ? (margeLivraison < 0 ? kCouleurBaisse : kCouleurHausse) : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Livraison : facturé au client vs coût réel',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(_descriptionLivraison, style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 12),
            corps,
          ],
        ),
      ),
    );
  }
}

enum _BadgeVariante { outline, secondary }

/// `<Badge variant="outline|secondary">` du web.
class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.variante, this.petite = false});

  final String label;
  final _BadgeVariante variante;

  /// `text-[10px]` du badge « Achat de stock · hors bénéfice ».
  final bool petite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outline = variante == _BadgeVariante.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: outline ? null : scheme.secondaryContainer,
        border: outline ? Border.all(color: scheme.outline) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: petite ? 10 : 12,
          fontWeight: FontWeight.w500,
          color: outline ? scheme.onSurface : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Version imprimable des dépenses : les 4 KPI, le tableau par catégorie,
/// la carte livraison (facturé vs coût réel) et le détail des opérations,
/// avec les colonnes de l'écran.
ReportPrintable? expensesPrintable(ExpensesData data) {
  final t = data.totaux;
  final l = data.livraison;
  final margeLivraison = l['marge_livraison'] ?? 0;
  return ReportPrintable(
    sectionLabel: ReportSection.expenses.label,
    sectionDescription: ReportSection.expenses.description,
    kpis: [
      PrintableKpi(
        'Total des sorties',
        fmtAr(t.total.actuel),
        '${fmtNb(t.nbMouvements)} opérations · charges ${fmtAr(t.charges.actuel)} · préc. ${fmtAr(t.total.precedent)}',
      ),
      PrintableKpi(
        'Sorties de caisse',
        fmtAr(t.caisse.actuel),
        '${t.achatsStock.actuel != 0 ? 'dont achats de stock ${fmtAr(t.achatsStock.actuel)} (hors bénéfice)' : 'salaires, pub, autres'} · préc. ${fmtAr(t.caisse.precedent)}',
      ),
      PrintableKpi(
        'Frais de tournée (livreurs)',
        fmtAr(t.livreur.actuel),
        'dépenses acceptées par le gérant · préc. ${fmtAr(t.livreur.precedent)}',
      ),
      PrintableKpi(
        'Marge sur livraison',
        fmtAr(margeLivraison),
        'facturé ${fmtAr(l['frais_factures_client'] ?? 0)} − coût réel ${fmtAr(l['cout_reel_livreurs'] ?? 0)}',
      ),
    ],
    tables: [
      PrintableTable(
        titre: 'Dépenses par catégorie',
        headers: const ['Catégorie', 'Source', 'Opérations', 'Total', 'Part'],
        rows: [
          for (final r in data.parCategorie)
            [
              r.horsResultat ? '${r.label} (Achat de stock · hors bénéfice)' : r.label,
              _sourceLabel(r.source),
              _brut(r.nb),
              fmtAr(r.total),
              _partTexte(r, t),
            ],
        ],
      ),
      PrintableTable(
        titre: 'Livraison : facturé au client vs coût réel',
        headers: const ['Indicateur', 'Valeur'],
        rows: [
          for (final (label, valeur) in _lignesLivraison(l)) [label, valeur],
        ],
      ),
      PrintableTable(
        titre: 'Détail des dépenses',
        headers: const ['Date', 'Source', 'Catégorie', 'Libellé', 'Par', 'Montant'],
        rows: [
          for (final r in data.mouvements)
            [_dateDepense(r), _sourceLabel(r.source), r.categorie, r.libelle, r.auteur, fmtAr(r.montant)],
        ],
      ),
    ],
  );
}
