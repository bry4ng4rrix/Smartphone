import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';
import '../widgets/kpi_card.dart';
import '../widgets/report_chart.dart';
import '../widgets/report_printable.dart';
import '../widgets/report_table.dart';

/// `DORMANT_CHOIX` du web.
const List<int> _dormantChoix = [30, 60, 90];

/// Valeur par défaut du sélecteur de stock dormant (`useState(30)`).
const int _dormantDefaut = 30;

/// `text-amber-600` du web.
const Color _couleurAmbre = Color(0xFFD97706);

/// Rendu brut d'un nombre (`String(row[key])` du web) : entier sans
/// séparateur quand la valeur est entière.
String _brut(num v) => v == v.truncate() ? '${v.toInt()}' : '$v';

/// Colonne « Produit » de l'historique : `${produit}${variante ? ` (${variante})` : ''}`.
String _produitVariante(MouvementStock r) => r.variante.isNotEmpty ? '${r.produit} (${r.variante})' : r.produit;

String _typeLabel(MouvementStock r) => r.type == 'ENTREE' ? 'Entrée' : 'Sortie';

/// `jours` du web (`Math.max(1, Number(dormantCustom) || 30)`) : la saisie
/// personnalisée, 30 si elle est invalide ou nulle, sinon le choix du
/// sélecteur.
int _joursEffectifs(int dormantJours, String dormantCustom) {
  if (dormantCustom.isEmpty) return dormantJours;
  final n = int.tryParse(dormantCustom) ?? 0;
  return math.max(1, n == 0 ? _dormantDefaut : n);
}

const String _descriptionDormant =
    "Variantes en stock sans sortie pour une commande depuis la durée choisie. Valeur immobilisée = stock × prix d'achat.";

/// `COLONNES_ETAT` du web (ruptures, réapprovisionnement).
final List<ReportColumn<LigneStock>> _colonnesEtat = [
  ReportColumn(key: 'produit', label: 'Produit', valeur: (r) => r.produit),
  ReportColumn(
    key: 'variante',
    label: 'Variante',
    valeur: (r) => r.variante,
    render: (r, _) => r.variante.isNotEmpty ? Text(r.variante) : const _TexteAttenue('—'),
  ),
  ReportColumn(
    key: 'stock',
    label: 'Stock',
    align: TextAlign.right,
    valeur: (r) => r.stock,
    render: (r, _) => Text(
      fmtNb(r.stock),
      style: r.stock <= 0 ? const TextStyle(color: kCouleurBaisse, fontWeight: FontWeight.w500) : null,
    ),
  ),
  ReportColumn(
    key: 'seuil',
    label: "Seuil d'alerte",
    align: TextAlign.right,
    valeur: (r) => r.seuil,
    render: (r, _) => Text(_brut(r.seuil)),
  ),
  ReportColumn(
    key: 'prix_achat',
    label: "Prix d'achat",
    align: TextAlign.right,
    valeur: (r) => r.prixAchat,
    render: (r, _) => Text(fmtAr(r.prixAchat)),
  ),
];

const List<String> _enTetesEtat = ['Produit', 'Variante', 'Stock', "Seuil d'alerte", "Prix d'achat"];

List<String> _ligneEtat(LigneStock r) => [
  r.produit,
  r.variante.isNotEmpty ? r.variante : '—',
  fmtNb(r.stock),
  _brut(r.seuil),
  fmtAr(r.prixAchat),
];

/// « Stock » — port de components/reports/section-stock.tsx : état du jour
/// (5 KPI), entrées / sorties, valeur par catégorie, ruptures, réappro,
/// stock dormant (durée réglable), mouvements par origine et historique.
///
/// Le nombre de jours du stock dormant est un état local (comme le
/// `useState` du web) recopié dans `reportExtrasProvider(stock)` sous la
/// clé `dormant_days` : l'écran reconstruit ainsi la même requête que la
/// section (impression, indicateur de chargement).
class SectionStock extends ConsumerStatefulWidget {
  const SectionStock({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  ConsumerState<SectionStock> createState() => _SectionStockState();
}

class _SectionStockState extends ConsumerState<SectionStock> {
  int _dormantJours = _dormantDefaut;
  String _dormantCustom = '';
  late final TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    // Durée conservée d'une visite précédente (extras de la section, 30 par
    // défaut — `dormant_days` est toujours envoyé, comme sur le web) : on en
    // repart, sans réécrire la requête.
    final memo = int.tryParse(ref.read(reportExtrasProvider(ReportSection.stock))['dormant_days'] ?? '');
    if (memo != null && memo >= 1) {
      if (_dormantChoix.contains(memo)) {
        _dormantJours = memo;
      } else {
        _dormantCustom = '$memo';
      }
    }
    _customCtrl = TextEditingController(text: _dormantCustom);
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  int get _jours => _joursEffectifs(_dormantJours, _dormantCustom);

  /// Recopie la durée effective dans les extras de la section (nouvelle clé
  /// de cache → nouvelle requête, comme le `useReport` du web).
  void _publierJours() => ref.read(reportExtrasProvider(ReportSection.stock).notifier).set('dormant_days', '$_jours');

  /// `onValueChange` du sélecteur : « Personnalisé » ouvre le champ avec 45,
  /// un préréglage efface la saisie.
  void _choisir(String v) {
    setState(() {
      if (v == 'custom') {
        _dormantCustom = '45';
      } else {
        _dormantCustom = '';
        _dormantJours = int.parse(v);
      }
      _customCtrl.text = _dormantCustom;
    });
    _publierJours();
  }

  void _saisir(String v) {
    setState(() => _dormantCustom = v);
    _publierJours();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final jours = _jours;
    final request = ReportRequest.pour(
      ReportSection.stock,
      widget.filter,
      extra: ref.watch(reportExtrasProvider(ReportSection.stock)),
    );
    final async = ref.watch(reportsProvider(request));
    final brut = async.value;
    final data = brut == null ? null : StockData.fromJson(brut);
    // Chargement plein seulement sans valeur (un rechargement silencieux
    // garde les données affichées) ; l'erreur prime sur les données.
    final loading = async.isLoading && !async.hasValue;
    final error = async.hasError ? ApiClient.messageFromError(async.error!) : null;
    final e = data?.etat;

    final graphiqueSerie = ChartCard(
      titre: 'Entrées et sorties de stock',
      description: 'Quantités par période',
      loading: loading,
      error: error,
      vide: data == null || data.serie.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : SerieChart(
              data: data.serie,
              series: const [
                SerieDef(
                  key: 'entrees',
                  label: 'Entrées',
                  type: SerieType.bar,
                  unite: ChartUnite.nb,
                  color: Color(0xFF16A34A),
                ),
                SerieDef(
                  key: 'sorties',
                  label: 'Sorties',
                  type: SerieType.bar,
                  unite: ChartUnite.nb,
                  color: Color(0xFFEF4444),
                ),
              ],
            ),
    );

    final graphiqueCategories = ChartCard(
      titre: 'Valeur du stock par catégorie',
      loading: loading,
      error: error,
      vide: data == null || data.parCategorie.isEmpty,
      child: data == null
          ? const SizedBox.shrink()
          : BarresChart(
              data: [
                for (final r in data.parCategorie.take(10)) {'label': r.label, 'valeur_achat': r.valeurAchat},
              ],
              labelKey: 'label',
              valueKey: 'valeur_achat',
            ),
    );

    final tableRuptures = ReportTable<LigneStock>(
      titre: 'Ruptures de stock',
      description: 'Variantes à 0.',
      colonnes: _colonnesEtat,
      lignes: data?.ruptures,
      loading: loading,
      error: error,
      pageSize: 10,
      exportNom: 'ruptures',
      rowKey: (r, _) => r.variantId,
      vide: 'Aucune rupture.',
    );

    final tableReappro = ReportTable<LigneStock>(
      titre: 'À réapprovisionner',
      description: "Stock ≤ seuil d'alerte (ruptures comprises).",
      colonnes: _colonnesEtat,
      lignes: data?.reappro,
      loading: loading,
      error: error,
      pageSize: 10,
      exportNom: 'reapprovisionnement',
      rowKey: (r, _) => r.variantId,
      vide: 'Rien à réapprovisionner.',
    );

    final tableOrigines = ReportTable<MouvementStockResume>(
      titre: 'Mouvements par origine',
      colonnes: [
        ReportColumn(key: 'label', label: 'Origine', valeur: (r) => r.label),
        ReportColumn(
          key: 'nb',
          label: 'Nb',
          align: TextAlign.right,
          valeur: (r) => r.nb,
          render: (r, _) => Text(_brut(r.nb)),
        ),
        ReportColumn(
          key: 'entrees',
          label: 'Entrées',
          align: TextAlign.right,
          valeur: (r) => r.entrees,
          render: (r, _) => Text(_brut(r.entrees)),
        ),
        ReportColumn(
          key: 'sorties',
          label: 'Sorties',
          align: TextAlign.right,
          valeur: (r) => r.sorties,
          render: (r, _) => Text(_brut(r.sorties)),
        ),
      ],
      lignes: data?.mouvementsResume,
      loading: loading,
      error: error,
      pageSize: 10,
      rowKey: (r, _) => r.origine,
    );

    final tableHistorique = ReportTable<MouvementStock>(
      titre: 'Historique des mouvements',
      description: data == null
          ? null
          : '${fmtNb(data.nbMouvements)} mouvements sur la période (300 plus récents affichés).',
      colonnes: [
        ReportColumn(key: 'date', label: 'Date', valeur: (r) => r.date, render: (r, _) => Text(fmtDateHeure(r.date))),
        ReportColumn(
          key: 'produit',
          label: 'Produit',
          valeur: (r) => r.produit,
          render: (r, _) => Text(_produitVariante(r)),
        ),
        ReportColumn(
          key: 'type',
          label: 'Type',
          valeur: (r) => r.type,
          render: (r, _) =>
              _Badge(_typeLabel(r), variante: r.type == 'ENTREE' ? _BadgeVariante.primaire : _BadgeVariante.destructif),
        ),
        ReportColumn(
          key: 'quantite',
          label: 'Qté',
          align: TextAlign.right,
          valeur: (r) => r.quantite,
          render: (r, _) => Text(_brut(r.quantite)),
        ),
        ReportColumn(key: 'origine_label', label: 'Origine', valeur: (r) => r.origineLabel),
        ReportColumn(
          key: 'reference',
          label: 'Réf.',
          valeur: (r) => r.reference,
          render: (r, _) => Text(r.reference.isNotEmpty ? r.reference : r.note),
        ),
        ReportColumn(key: 'utilisateur', label: 'Par', valeur: (r) => r.utilisateur),
      ],
      lignes: data?.mouvements,
      loading: loading,
      error: error,
      pageSize: 15,
      exportNom: 'mouvements_stock',
      rowKey: (r, _) => r.id,
      compact: true,
      vide: 'Aucun mouvement sur la période.',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "L'état du stock est celui d'aujourd'hui ; l'historique des mouvements suit la période sélectionnée.",
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 16),
        KpiGrid(
          cols: 5,
          children: [
            ReportKpiCard(
              loading: loading,
              titre: 'Quantité en stock',
              icon: Icons.inventory_2_outlined,
              valeur: e == null ? null : fmtNb(data!.etatValeur('quantite_totale')),
              detail: e == null
                  ? null
                  : '${fmtNb(data!.etatValeur('nb_variantes'))} variantes · ${fmtNb(data.etatValeur('nb_references'))} références',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Valeur du stock (achat)',
              icon: Icons.account_balance_wallet_outlined,
              valeur: e == null ? null : fmtAr(data!.etatValeur('valeur_achat')),
              detail: e == null ? null : 'valeur de vente ${fmtAr(data!.etatValeur('valeur_vente'))}',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Produits en rupture',
              icon: Icons.remove_shopping_cart_outlined,
              valeur: e == null ? null : fmtNb(data!.etatValeur('nb_ruptures')),
              couleur: e != null && data!.etatValeur('nb_ruptures') > 0 ? kCouleurBaisse : null,
              detail: 'stock à 0',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'À réapprovisionner',
              icon: Icons.warning_amber_outlined,
              valeur: e == null ? null : fmtNb(data!.etatValeur('nb_reappro')),
              couleur: e != null && data!.etatValeur('nb_reappro') > 0 ? _couleurAmbre : null,
              detail: e == null ? null : 'stock ≤ seuil (dont ${fmtNb(data!.etatValeur('nb_stock_bas'))} en stock bas)',
            ),
            ReportKpiCard(
              loading: loading,
              titre: 'Stock dormant ($jours j)',
              icon: Icons.schedule_outlined,
              valeur: data == null ? null : fmtNb(data.dormant.nb),
              detail: data == null ? null : '${fmtAr(data.dormant.valeurImmobilisee)} immobilisés',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-3` : 2/3 – 1/3 côte à côte dès 1280 px
        // (`xl`), une colonne sinon.
        _Grille(gauche: graphiqueSerie, droite: graphiqueCategories, flexGauche: 2),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-2`.
        _Grille(gauche: tableRuptures, droite: tableReappro),
        const SizedBox(height: 16),
        ReportTable<LigneDormant>(
          titre: 'Stock dormant — sans vente depuis $jours jours',
          description: _descriptionDormant,
          actions: _SelecteurDormant(
            valeur: _dormantCustom.isNotEmpty ? 'custom' : '$_dormantJours',
            custom: _dormantCustom.isNotEmpty,
            controller: _customCtrl,
            onChoix: _choisir,
            onSaisie: _saisir,
          ),
          colonnes: [
            ReportColumn(key: 'produit', label: 'Produit', valeur: (r) => r.produit),
            ReportColumn(
              key: 'variante',
              label: 'Variante',
              valeur: (r) => r.variante,
              render: (r, _) => Text(r.variante.isNotEmpty ? r.variante : '—'),
            ),
            ReportColumn(
              key: 'stock',
              label: 'Stock restant',
              align: TextAlign.right,
              valeur: (r) => r.stock,
              render: (r, _) => Text(_brut(r.stock)),
            ),
            ReportColumn(
              key: 'derniere_vente',
              label: 'Dernière vente',
              valeur: (r) => r.derniereVente,
              render: (r, _) => r.derniereVente != null && r.derniereVente!.isNotEmpty
                  ? Text(fmtDate(r.derniereVente))
                  : const _Badge('Jamais', variante: _BadgeVariante.outline),
              export: (r) => (r.derniereVente == null || r.derniereVente!.isEmpty) ? 'Jamais' : r.derniereVente,
            ),
            ReportColumn(
              key: 'jours_sans_vente',
              label: 'Jours sans vente',
              align: TextAlign.right,
              valeur: (r) => r.joursSansVente,
              render: (r, _) => Text(_brut(r.joursSansVente)),
            ),
            ReportColumn(
              key: 'valeur_immobilisee',
              label: 'Valeur immobilisée',
              align: TextAlign.right,
              valeur: (r) => r.valeurImmobilisee,
              render: (r, _) => Text(fmtAr(r.valeurImmobilisee)),
            ),
          ],
          lignes: data?.dormant.lignes,
          loading: loading,
          error: error,
          pageSize: 15,
          exportNom: 'stock_dormant',
          rowKey: (r, _) => r.variantId,
          vide: 'Aucun produit dormant sur cette durée.',
        ),
        const SizedBox(height: 16),
        // `grid-cols-1 xl:grid-cols-3` : origines (1/3) – historique (2/3).
        _Grille(gauche: tableOrigines, droite: tableHistorique, flexDroite: 2),
        const SizedBox(height: 8),
        // `<Button variant="link">` vers la page Mouvements.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.go('/movements'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Voir tous les mouvements →'),
          ),
        ),
      ],
    );
  }
}

/// `grid-cols-1 xl:grid-cols-N` du web : deux cartes côte à côte dès 1280 px
/// (`xl`, proportions [flexGauche] / [flexDroite]), l'une sous l'autre sinon.
class _Grille extends StatelessWidget {
  const _Grille({required this.gauche, required this.droite, this.flexGauche = 1, this.flexDroite = 1});

  final Widget gauche;
  final Widget droite;
  final int flexGauche;
  final int flexDroite;

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
              Expanded(flex: flexDroite, child: droite),
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

/// Sélecteur « 30 / 60 / 90 jours / Personnalisé » + champ nombre (≥ 1)
/// affiché tant que la saisie personnalisée n'est pas vide — actions du
/// tableau « Stock dormant ».
class _SelecteurDormant extends StatelessWidget {
  const _SelecteurDormant({
    required this.valeur,
    required this.custom,
    required this.controller,
    required this.onChoix,
    required this.onSaisie,
  });

  final String valeur;
  final bool custom;
  final TextEditingController controller;
  final ValueChanged<String> onChoix;
  final ValueChanged<String> onSaisie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bordure = BoxDecoration(
      border: Border.all(color: theme.colorScheme.outline),
      borderRadius: BorderRadius.circular(4),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 128,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: bordure,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: valeur,
              isDense: true,
              isExpanded: true,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
              items: [
                for (final j in _dormantChoix) DropdownMenuItem(value: '$j', child: Text('$j jours')),
                const DropdownMenuItem(value: 'custom', child: Text('Personnalisé')),
              ],
              onChanged: (v) {
                if (v != null) onChoix(v);
              },
            ),
          ),
        ),
        if (custom) ...[
          const SizedBox(width: 4),
          Container(
            width: 80,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: bordure,
            alignment: Alignment.center,
            child: Semantics(
              label: 'Nombre de jours',
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onSaisie,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// `text-muted-foreground` sur une cellule (« — » d'une variante absente).
class _TexteAttenue extends StatelessWidget {
  const _TexteAttenue(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) =>
      Text(texte, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
}

enum _BadgeVariante { outline, primaire, destructif }

/// `<Badge variant="outline|default|destructive">` du web.
class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.variante});

  final String label;
  final _BadgeVariante variante;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color? fond, Color texte, Color? bord) = switch (variante) {
      _BadgeVariante.outline => (null, scheme.onSurface, scheme.outline),
      _BadgeVariante.primaire => (scheme.primary, scheme.onPrimary, null),
      _BadgeVariante.destructif => (scheme.error, scheme.onError, null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fond,
        border: bord == null ? null : Border.all(color: bord),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: texte),
      ),
    );
  }
}

/// Version imprimable du stock : les 5 KPI puis tous les tableaux de la
/// section (ruptures, réappro, dormant, origines, historique) avec les
/// colonnes de l'écran.
ReportPrintable? stockPrintable(StockData data) {
  final e = data.etatValeur;
  final jours = data.dormant.jours;
  return ReportPrintable(
    sectionLabel: ReportSection.stock.label,
    sectionDescription: ReportSection.stock.description,
    kpis: [
      PrintableKpi(
        'Quantité en stock',
        fmtNb(e('quantite_totale')),
        '${fmtNb(e('nb_variantes'))} variantes · ${fmtNb(e('nb_references'))} références',
      ),
      PrintableKpi('Valeur du stock (achat)', fmtAr(e('valeur_achat')), 'valeur de vente ${fmtAr(e('valeur_vente'))}'),
      PrintableKpi('Produits en rupture', fmtNb(e('nb_ruptures')), 'stock à 0'),
      PrintableKpi(
        'À réapprovisionner',
        fmtNb(e('nb_reappro')),
        'stock ≤ seuil (dont ${fmtNb(e('nb_stock_bas'))} en stock bas)',
      ),
      PrintableKpi(
        'Stock dormant ($jours j)',
        fmtNb(data.dormant.nb),
        '${fmtAr(data.dormant.valeurImmobilisee)} immobilisés',
      ),
    ],
    tables: [
      PrintableTable(
        titre: 'Ruptures de stock',
        headers: _enTetesEtat,
        rows: [for (final r in data.ruptures) _ligneEtat(r)],
      ),
      PrintableTable(
        titre: 'À réapprovisionner',
        headers: _enTetesEtat,
        rows: [for (final r in data.reappro) _ligneEtat(r)],
      ),
      PrintableTable(
        titre: 'Stock dormant — sans vente depuis $jours jours',
        headers: const [
          'Produit',
          'Variante',
          'Stock restant',
          'Dernière vente',
          'Jours sans vente',
          'Valeur immobilisée',
        ],
        rows: [
          for (final r in data.dormant.lignes)
            [
              r.produit,
              r.variante.isNotEmpty ? r.variante : '—',
              _brut(r.stock),
              (r.derniereVente == null || r.derniereVente!.isEmpty) ? 'Jamais' : fmtDate(r.derniereVente),
              _brut(r.joursSansVente),
              fmtAr(r.valeurImmobilisee),
            ],
        ],
      ),
      PrintableTable(
        titre: 'Mouvements par origine',
        headers: const ['Origine', 'Nb', 'Entrées', 'Sorties'],
        rows: [
          for (final r in data.mouvementsResume) [r.label, _brut(r.nb), _brut(r.entrees), _brut(r.sorties)],
        ],
      ),
      PrintableTable(
        titre: 'Historique des mouvements',
        headers: const ['Date', 'Produit', 'Type', 'Qté', 'Origine', 'Réf.', 'Par'],
        rows: [
          for (final r in data.mouvements)
            [
              fmtDateHeure(r.date),
              _produitVariante(r),
              _typeLabel(r),
              _brut(r.quantite),
              r.origineLabel,
              r.reference.isNotEmpty ? r.reference : r.note,
              r.utilisateur,
            ],
        ],
      ),
    ],
  );
}
