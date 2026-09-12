/// Centre de rapports (tableau de bord du gérant) — port de
/// `frontend/lib/reports.ts` : sections, périodes, formats et modèles de
/// réponse de `GET /api/orders/reports/{section}/` (orders/reporting.py).
///
/// Les montants sont des `Decimal` côté serveur (rendus en nombre ou en
/// chaîne selon l'encodeur) : tout passe par [asDouble] / [asDoubleOrNull].
library;

import 'package:flutter/material.dart' show Color;

import 'package:intl/intl.dart';

import '../core/app_time.dart';
import 'json_utils.dart';

// ---------------------------------------------------------------------------
// Sections, granularités, préréglages
// ---------------------------------------------------------------------------

/// `SECTIONS` du web — [key] est le segment d'URL de l'API et de l'onglet.
enum ReportSection {
  overview('overview', 'Vue générale', 'KPI, tendances et comparaison avec la période précédente'),
  sales('sales', 'Ventes', 'Chiffre d’affaires, produits, livreurs'),
  financial('financial', 'Financier', 'Marge brute, dépenses, bénéfice net'),
  expenses('expenses', 'Dépenses', 'Caisse, tournées, marge sur livraison'),
  stock('stock', 'Stock', 'État, ruptures, mouvements, stock dormant'),
  orders('orders', 'Commandes', 'Statuts, annulations, zones'),
  deliveries('deliveries', 'Livraisons', 'Performance des livreurs et des zones'),
  marketing('marketing', 'Marketing', 'Campagnes, dépenses publicitaires, ROI');

  const ReportSection(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static ReportSection? fromKey(String? key) {
    for (final s in ReportSection.values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// Ordre d'affichage des onglets.
const List<ReportSection> kReportSections = ReportSection.values;

/// `GRANULARITES` du web.
enum ReportGranularity {
  day('day', 'Jour'),
  week('week', 'Semaine'),
  month('month', 'Mois'),
  year('year', 'Année');

  const ReportGranularity(this.key, this.label);

  final String key;
  final String label;

  static ReportGranularity fromKey(String? key) {
    for (final g in ReportGranularity.values) {
      if (g.key == key) return g;
    }
    return ReportGranularity.day;
  }
}

/// `PRESETS` du web.
enum ReportPreset {
  today('today', "Aujourd'hui"),
  last7('last7', '7 derniers jours'),
  week('week', 'Cette semaine'),
  month('month', 'Ce mois'),
  prevMonth('prev_month', 'Mois précédent'),
  year('year', 'Cette année'),
  prevYear('prev_year', 'Année précédente'),
  custom('custom', 'Personnalisée');

  const ReportPreset(this.key, this.label);

  final String key;
  final String label;
}

// ---------------------------------------------------------------------------
// Périodes
// ---------------------------------------------------------------------------

/// `Period` du web — jours calendaires `AAAA-MM-JJ`. [prevFrom]/[prevTo] :
/// mois/année/semaine calendaires précédents pour les préréglages, sinon la
/// fenêtre de même longueur juste avant.
class ReportPeriod {
  const ReportPeriod({required this.from, required this.to, required this.prevFrom, required this.prevTo});

  final String from;
  final String to;
  final String prevFrom;
  final String prevTo;

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.from == from && other.to == to && other.prevFrom == prevFrom && other.prevTo == prevTo;

  @override
  int get hashCode => Object.hash(from, to, prevFrom, prevTo);

  @override
  String toString() => 'ReportPeriod($from → $to, préc. $prevFrom → $prevTo)';
}

/// `YYYY-MM-DD` d'un jour calendaire — format des paramètres `date_from` /
/// `date_to` envoyés au serveur.
String formatReportsDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Jour calendaire (minuit, sans fuseau) d'une chaîne `AAAA-MM-JJ`.
DateTime _jour(String day) {
  final p = day.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String _addDays(String day, int n) {
  final d = _jour(day);
  return formatReportsDate(DateTime(d.year, d.month, d.day + n));
}

/// Nombre de jours de la plage, bornes comprises.
int _longueur(String from, String to) => _jour(to).difference(_jour(from)).inDays + 1;

({String prevFrom, String prevTo}) _fenetrePrecedente(String from, String to) {
  final longueur = _longueur(from, to);
  final prevTo = _addDays(from, -1);
  return (prevFrom: _addDays(prevTo, -(longueur - 1)), prevTo: prevTo);
}

/// `periodeDepuisPreset` du web — jour métier d'Antananarivo ([appToday]),
/// semaine commençant le lundi, période personnalisée vide = 30 derniers
/// jours, bornes inversées remises dans l'ordre.
ReportPeriod periodeDepuisPreset(ReportPreset preset, {String? customFrom, String? customTo}) {
  final t = appToday();
  final today = formatReportsDate(t);
  final y = t.year;
  final m = t.month; // 1..12
  String jourMois(int yy, int mm, int dd) => formatReportsDate(DateTime(yy, mm, dd));
  int finMois(int yy, int mm) => DateTime(yy, mm + 1, 0).day;

  switch (preset) {
    case ReportPreset.today:
      final hier = _addDays(today, -1);
      return ReportPeriod(from: today, to: today, prevFrom: hier, prevTo: hier);
    case ReportPreset.last7:
      final from = _addDays(today, -6);
      final p = _fenetrePrecedente(from, today);
      return ReportPeriod(from: from, to: today, prevFrom: p.prevFrom, prevTo: p.prevTo);
    case ReportPreset.week:
      // `(getDay() + 6) % 7` : lundi = 0 … dimanche = 6.
      final lundi = _addDays(today, -((t.weekday - 1) % 7));
      return ReportPeriod(from: lundi, to: today, prevFrom: _addDays(lundi, -7), prevTo: _addDays(lundi, -1));
    case ReportPreset.month:
      final pm = m == 1 ? 12 : m - 1;
      final py = m == 1 ? y - 1 : y;
      return ReportPeriod(
        from: jourMois(y, m, 1),
        to: today,
        prevFrom: jourMois(py, pm, 1),
        prevTo: jourMois(py, pm, finMois(py, pm)),
      );
    case ReportPreset.prevMonth:
      final pm = m == 1 ? 12 : m - 1;
      final py = m == 1 ? y - 1 : y;
      final ppm = pm == 1 ? 12 : pm - 1;
      final ppy = pm == 1 ? py - 1 : py;
      return ReportPeriod(
        from: jourMois(py, pm, 1),
        to: jourMois(py, pm, finMois(py, pm)),
        prevFrom: jourMois(ppy, ppm, 1),
        prevTo: jourMois(ppy, ppm, finMois(ppy, ppm)),
      );
    case ReportPreset.year:
      return ReportPeriod(from: '$y-01-01', to: today, prevFrom: '${y - 1}-01-01', prevTo: '${y - 1}-12-31');
    case ReportPreset.prevYear:
      return ReportPeriod(
        from: '${y - 1}-01-01',
        to: '${y - 1}-12-31',
        prevFrom: '${y - 2}-01-01',
        prevTo: '${y - 2}-12-31',
      );
    case ReportPreset.custom:
      final from = (customFrom == null || customFrom.isEmpty) ? _addDays(today, -29) : customFrom;
      final to = (customTo == null || customTo.isEmpty) ? today : customTo;
      final a = from.compareTo(to) <= 0 ? from : to;
      final b = from.compareTo(to) <= 0 ? to : from;
      final p = _fenetrePrecedente(a, b);
      return ReportPeriod(from: a, to: b, prevFrom: p.prevFrom, prevTo: p.prevTo);
  }
}

/// `granulariteAuto` du web : granularité par défaut lisible pour une plage.
ReportGranularity granulariteAuto(ReportPeriod period) {
  final jours = _longueur(period.from, period.to);
  if (jours <= 31) return ReportGranularity.day;
  if (jours <= 120) return ReportGranularity.week;
  if (jours <= 800) return ReportGranularity.month;
  return ReportGranularity.year;
}

// ---------------------------------------------------------------------------
// Formats
// ---------------------------------------------------------------------------

/// `Intl.NumberFormat('fr-MG', { maximumFractionDigits: 0 })` du web.
final NumberFormat _nf = NumberFormat.decimalPattern('fr_FR');

num _num(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

/// « 1 234 Ar » — arrondi à l'entier.
String fmtAr(Object? v) => '${_nf.format(_num(v).round())} Ar';

/// « 1 234 ».
String fmtNb(Object? v) => _nf.format(_num(v).round());

/// « 12.5 % » — « — » si absent ; « + » devant les hausses si [signe].
String fmtPct(num? v, {bool signe = false}) {
  if (v == null || (v is double && v.isNaN)) return '—';
  return '${signe && v > 0 ? '+' : ''}${v.toStringAsFixed(1)} %';
}

/// Axe des montants : « 1.2 M », « 12 k », sinon l'entier.
String fmtArCourt(num v) {
  final n = v.abs();
  if (n >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} M';
  if (n >= 1000) return '${(v / 1000).round()} k';
  return '${v.round()}';
}

String _deuxChiffres(int n) => n.toString().padLeft(2, '0');

/// `AAAA-MM-JJ` (ou ISO complet) → « JJ/MM/AAAA » en heure d'Antananarivo,
/// « — » si absent.
String fmtDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '—';
  if (isoDate.length == 10) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    return '${_deuxChiffres(d.day)}/${_deuxChiffres(d.month)}/${d.year}';
  }
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  final d = appLocal(parsed);
  return '${_deuxChiffres(d.day)}/${_deuxChiffres(d.month)}/${d.year}';
}

/// ISO → « JJ/MM/AAAA HH:mm » en heure d'Antananarivo, « — » si absent.
String fmtDateHeure(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '—';
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  final d = appLocal(parsed);
  return '${_deuxChiffres(d.day)}/${_deuxChiffres(d.month)}/${d.year} ${_deuxChiffres(d.hour)}:${_deuxChiffres(d.minute)}';
}

/// Minutes → « 1 h 05 » / « 12 min », « — » si absent.
String fmtDuree(num? minutes) {
  if (minutes == null) return '—';
  final h = (minutes / 60).floor();
  final m = (minutes % 60).round();
  return h > 0 ? '$h h ${_deuxChiffres(m)}' : '$m min';
}

// ---------------------------------------------------------------------------
// Aides de désérialisation
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _rows(dynamic v) =>
    (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

Map<String, dynamic> _obj(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};

/// `Record<string, number>` → `Map<String, num>` (les clés non numériques,
/// comme `_counts`, sont ignorées).
Map<String, num> _numMap(dynamic v) {
  final out = <String, num>{};
  _obj(v).forEach((k, val) {
    final n = asDoubleOrNull(val);
    if (n != null) out[k] = n;
  });
  return out;
}

/// `Record<string, number | null>` → `Map<String, num?>`.
Map<String, num?> _numOrNullMap(dynamic v) {
  final out = <String, num?>{};
  _obj(v).forEach((k, val) {
    if (val == null || val is num || val is String) out[k] = asDoubleOrNull(val);
  });
  return out;
}

Map<String, Variation> _variationMap(dynamic v) =>
    _obj(v).map((k, val) => MapEntry(k, Variation.fromJson(_obj(val))));

// ---------------------------------------------------------------------------
// Modèles de réponse (voir orders/reporting.py)
// ---------------------------------------------------------------------------

/// `_variation(actuel, precedent)` : [variationPct] est `null` quand la
/// période précédente vaut 0.
class Variation {
  const Variation({required this.actuel, required this.precedent, required this.variation, this.variationPct});

  static const Variation zero = Variation(actuel: 0, precedent: 0, variation: 0);

  final num actuel;
  final num precedent;
  final num variation;
  final num? variationPct;

  factory Variation.fromJson(Map<String, dynamic> json) => Variation(
        actuel: asDouble(json['actuel']),
        precedent: asDouble(json['precedent']),
        variation: asDouble(json['variation']),
        variationPct: asDoubleOrNull(json['variation_pct']),
      );
}

/// `periode` renvoyée par le serveur : bornes effectivement retenues.
class PeriodeInfo {
  const PeriodeInfo({
    required this.from,
    required this.to,
    required this.prevFrom,
    required this.prevTo,
    required this.granularity,
  });

  final String from;
  final String to;
  final String prevFrom;
  final String prevTo;
  final ReportGranularity granularity;

  factory PeriodeInfo.fromJson(Map<String, dynamic> json) => PeriodeInfo(
        from: asString(json['from']),
        to: asString(json['to']),
        prevFrom: asString(json['prev_from']),
        prevTo: asString(json['prev_to']),
        granularity: ReportGranularity.fromKey(asStringOrNull(json['granularity'])),
      );

  /// « jour » / « semaine » / « mois » / « année » — sous-titres des graphiques.
  String get granulariteMot => switch (granularity) {
        ReportGranularity.day => 'jour',
        ReportGranularity.week => 'semaine',
        ReportGranularity.month => 'mois',
        ReportGranularity.year => 'année',
      };
}

/// Un point de série temporelle : `{periode, label, ...valeurs}`.
class SeriePoint {
  const SeriePoint({required this.periode, required this.label, required this.valeurs});

  final String periode;
  final String label;
  final Map<String, num> valeurs;

  /// Valeur d'une clé (0 si absente).
  num v(String cle) => valeurs[cle] ?? 0;

  factory SeriePoint.fromJson(Map<String, dynamic> json) {
    final valeurs = <String, num>{};
    json.forEach((k, val) {
      if (k == 'periode' || k == 'label') return;
      final n = asDoubleOrNull(val);
      if (n != null) valeurs[k] = n;
    });
    return SeriePoint(periode: asString(json['periode']), label: asString(json['label']), valeurs: valeurs);
  }

  static List<SeriePoint> liste(dynamic v) => _rows(v).map(SeriePoint.fromJson).toList();
}

/// Ligne de ventes groupées (`_grouper_ventes`).
class LigneVente {
  const LigneVente({
    required this.label,
    required this.quantite,
    required this.nbCommandes,
    required this.ca,
    required this.cout,
    required this.marge,
    required this.margePct,
  });

  final String label;
  final num quantite;
  final num nbCommandes;
  final num ca;
  final num cout;
  final num marge;
  final num margePct;

  factory LigneVente.fromJson(Map<String, dynamic> json) => LigneVente(
        label: asString(json['label']),
        quantite: asDouble(json['quantite']),
        nbCommandes: asDouble(json['nb_commandes']),
        ca: asDouble(json['ca']),
        cout: asDouble(json['cout']),
        marge: asDouble(json['marge']),
        margePct: asDouble(json['marge_pct']),
      );

  static List<LigneVente> liste(dynamic v) => _rows(v).map(LigneVente.fromJson).toList();
}

/// `{statut, label, nb[, part]}` — répartition des commandes par statut.
class RepartitionStatut {
  const RepartitionStatut({required this.statut, required this.label, required this.nb, this.part = 0});

  final String statut;
  final String label;
  final num nb;
  final num part;

  factory RepartitionStatut.fromJson(Map<String, dynamic> json) => RepartitionStatut(
        statut: asString(json['statut']),
        label: asString(json['label']),
        nb: asDouble(json['nb']),
        part: asDouble(json['part']),
      );
}

// --- 1. Vue générale --------------------------------------------------------

class OverviewData {
  const OverviewData({required this.periode, required this.kpis, required this.series, required this.repartitionStatuts});

  final PeriodeInfo periode;

  /// `ca_total`, `benefice_net`, `nb_commandes`, `panier_moyen`,
  /// `nb_livrees`, `depenses`, `marge_brute`.
  final Map<String, Variation> kpis;
  final List<SeriePoint> series;
  final List<RepartitionStatut> repartitionStatuts;

  Variation kpi(String cle) => kpis[cle] ?? Variation.zero;
  Variation get caTotal => kpi('ca_total');
  Variation get beneficeNet => kpi('benefice_net');
  Variation get nbCommandes => kpi('nb_commandes');
  Variation get panierMoyen => kpi('panier_moyen');
  Variation get nbLivrees => kpi('nb_livrees');
  Variation get depenses => kpi('depenses');
  Variation get margeBrute => kpi('marge_brute');

  factory OverviewData.fromJson(Map<String, dynamic> json) => OverviewData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        kpis: _variationMap(json['kpis']),
        series: SeriePoint.liste(json['series']),
        repartitionStatuts: _rows(json['repartition_statuts']).map(RepartitionStatut.fromJson).toList(),
      );
}

// --- 2. Ventes --------------------------------------------------------------

/// `dimensions: {cle, label}` — axes d'analyse proposés par le serveur.
class DimensionVente {
  const DimensionVente({required this.cle, required this.label});

  final String cle;
  final String label;

  factory DimensionVente.fromJson(Map<String, dynamic> json) =>
      DimensionVente(cle: asString(json['cle']), label: asString(json['label']));
}

/// `par_livreur` du rapport Ventes.
class LigneVenteLivreur {
  const LigneVenteLivreur({
    required this.id,
    required this.nom,
    required this.commandes,
    required this.livrees,
    required this.retours,
    required this.enCours,
    required this.ca,
    required this.tauxReussite,
  });

  final int id;
  final String nom;
  final num commandes;
  final num livrees;
  final num retours;
  final num enCours;
  final num ca;
  final num tauxReussite;

  factory LigneVenteLivreur.fromJson(Map<String, dynamic> json) => LigneVenteLivreur(
        id: asInt(json['id']),
        nom: asString(json['nom']),
        commandes: asDouble(json['commandes']),
        livrees: asDouble(json['livrees']),
        retours: asDouble(json['retours']),
        enCours: asDouble(json['en_cours']),
        ca: asDouble(json['ca']),
        tauxReussite: asDouble(json['taux_reussite']),
      );
}

class SalesData {
  const SalesData({
    required this.periode,
    required this.kpis,
    required this.dimensions,
    required this.par,
    required this.topProduits,
    required this.moinsVendus,
    required this.parLivreur,
    required this.serie,
  });

  final PeriodeInfo periode;

  /// `ca_total`, `ca_produits`, `nb_livrees`, `quantite_vendue`, `panier_moyen`.
  final Map<String, Variation> kpis;
  final List<DimensionVente> dimensions;

  /// Ventes groupées par dimension (`par[cle]`).
  final Map<String, List<LigneVente>> par;
  final List<LigneVente> topProduits;
  final List<LigneVente> moinsVendus;
  final List<LigneVenteLivreur> parLivreur;
  final List<SeriePoint> serie;

  Variation kpi(String cle) => kpis[cle] ?? Variation.zero;

  factory SalesData.fromJson(Map<String, dynamic> json) => SalesData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        kpis: _variationMap(json['kpis']),
        dimensions: _rows(json['dimensions']).map(DimensionVente.fromJson).toList(),
        par: _obj(json['par']).map((k, v) => MapEntry(k, LigneVente.liste(v))),
        topProduits: LigneVente.liste(json['top_produits']),
        moinsVendus: LigneVente.liste(json['moins_vendus']),
        parLivreur: _rows(json['par_livreur']).map(LigneVenteLivreur.fromJson).toList(),
        serie: SeriePoint.liste(json['serie']),
      );
}

// --- 3. Financier -----------------------------------------------------------

class FinancialData {
  const FinancialData({
    required this.periode,
    required this.totaux,
    required this.comparaison,
    required this.parProduit,
    required this.parCategorie,
    required this.parSousType,
    required this.series,
  });

  final PeriodeInfo periode;

  /// `ca_total`, `ca_produits`, `frais_livraison`, `cout_achat`,
  /// `marge_brute`, `depenses_caisse`, `depenses_livreur`, `depenses`,
  /// `benefice_net`, `achats_stock`, `taux_marge_brute`, `taux_benefice`.
  final Map<String, num> totaux;
  final Map<String, Variation> comparaison;
  final List<LigneVente> parProduit;
  final List<LigneVente> parCategorie;
  final List<LigneVente> parSousType;
  final List<SeriePoint> series;

  num total(String cle) => totaux[cle] ?? 0;
  Variation variation(String cle) => comparaison[cle] ?? Variation.zero;

  factory FinancialData.fromJson(Map<String, dynamic> json) => FinancialData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        totaux: _numMap(json['totaux']),
        comparaison: _variationMap(json['comparaison']),
        parProduit: LigneVente.liste(json['par_produit']),
        parCategorie: LigneVente.liste(json['par_categorie']),
        parSousType: LigneVente.liste(json['par_sous_type']),
        series: SeriePoint.liste(json['series']),
      );
}

// --- 4. Dépenses ------------------------------------------------------------

class ExpensesTotaux {
  const ExpensesTotaux({
    required this.total,
    required this.caisse,
    required this.livreur,
    required this.achatsStock,
    required this.charges,
    required this.nbMouvements,
  });

  final Variation total;
  final Variation caisse;
  final Variation livreur;
  final Variation achatsStock;
  final Variation charges;
  final int nbMouvements;

  factory ExpensesTotaux.fromJson(Map<String, dynamic> json) => ExpensesTotaux(
        total: Variation.fromJson(_obj(json['total'])),
        caisse: Variation.fromJson(_obj(json['caisse'])),
        livreur: Variation.fromJson(_obj(json['livreur'])),
        achatsStock: Variation.fromJson(_obj(json['achats_stock'])),
        charges: Variation.fromJson(_obj(json['charges'])),
        nbMouvements: asInt(json['nb_mouvements']),
      );
}

/// `par_categorie` du rapport Dépenses ; [source] vaut `caisse` ou `livreur`.
class LigneCategorieDepense {
  const LigneCategorieDepense({
    required this.label,
    required this.source,
    required this.total,
    required this.nb,
    required this.horsResultat,
  });

  final String label;
  final String source;
  final num total;
  final num nb;

  /// Achats de stock : comptés dans la caisse mais pas dans le résultat.
  final bool horsResultat;

  factory LigneCategorieDepense.fromJson(Map<String, dynamic> json) => LigneCategorieDepense(
        label: asString(json['label']),
        source: asString(json['source']),
        total: asDouble(json['total']),
        nb: asDouble(json['nb']),
        horsResultat: asBool(json['hors_resultat']),
      );
}

/// Un mouvement de dépense (caisse ou tournée livreur).
class MouvementDepense {
  const MouvementDepense({
    required this.date,
    required this.source,
    required this.categorie,
    required this.libelle,
    required this.montant,
    required this.auteur,
  });

  final String date;
  final String source;
  final String categorie;
  final String libelle;
  final num montant;
  final String auteur;

  factory MouvementDepense.fromJson(Map<String, dynamic> json) => MouvementDepense(
        date: asString(json['date']),
        source: asString(json['source']),
        categorie: asString(json['categorie']),
        libelle: asString(json['libelle']),
        montant: asDouble(json['montant']),
        auteur: asString(json['auteur']),
      );
}

class ExpensesData {
  const ExpensesData({
    required this.periode,
    required this.totaux,
    required this.parCategorie,
    required this.serie,
    required this.livraison,
    required this.mouvements,
  });

  final PeriodeInfo periode;
  final ExpensesTotaux totaux;
  final List<LigneCategorieDepense> parCategorie;
  final List<SeriePoint> serie;

  /// `frais_factures_client`, `cout_reel_livreurs`, `marge_livraison`,
  /// `nb_livrees`, `frais_moyen_client`, `cout_moyen_livraison`.
  final Map<String, num> livraison;
  final List<MouvementDepense> mouvements;

  factory ExpensesData.fromJson(Map<String, dynamic> json) => ExpensesData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        totaux: ExpensesTotaux.fromJson(_obj(json['totaux'])),
        parCategorie: _rows(json['par_categorie']).map(LigneCategorieDepense.fromJson).toList(),
        serie: SeriePoint.liste(json['serie']),
        livraison: _numMap(json['livraison']),
        mouvements: _rows(json['mouvements']).map(MouvementDepense.fromJson).toList(),
      );
}

// --- 5. Stock ---------------------------------------------------------------

class LigneStock {
  const LigneStock({
    required this.variantId,
    required this.produit,
    required this.variante,
    required this.stock,
    required this.seuil,
    required this.prixAchat,
    required this.prixVente,
  });

  final int variantId;
  final String produit;
  final String variante;
  final num stock;
  final num seuil;
  final num prixAchat;
  final num prixVente;

  factory LigneStock.fromJson(Map<String, dynamic> json) => LigneStock(
        variantId: asInt(json['variant_id']),
        produit: asString(json['produit']),
        variante: asString(json['variante']),
        stock: asDouble(json['stock']),
        seuil: asDouble(json['seuil']),
        prixAchat: asDouble(json['prix_achat']),
        prixVente: asDouble(json['prix_vente']),
      );

  static List<LigneStock> liste(dynamic v) => _rows(v).map(LigneStock.fromJson).toList();
}

class LigneCategorieStock {
  const LigneCategorieStock({required this.label, required this.quantite, required this.valeurAchat, required this.nbVariantes});

  final String label;
  final num quantite;
  final num valeurAchat;
  final num nbVariantes;

  factory LigneCategorieStock.fromJson(Map<String, dynamic> json) => LigneCategorieStock(
        label: asString(json['label']),
        quantite: asDouble(json['quantite']),
        valeurAchat: asDouble(json['valeur_achat']),
        nbVariantes: asDouble(json['nb_variantes']),
      );
}

/// `mouvements_resume` : par origine, nombre, entrées et sorties.
class MouvementStockResume {
  const MouvementStockResume({
    required this.origine,
    required this.label,
    required this.nb,
    required this.entrees,
    required this.sorties,
  });

  final String origine;
  final String label;
  final num nb;
  final num entrees;
  final num sorties;

  factory MouvementStockResume.fromJson(Map<String, dynamic> json) => MouvementStockResume(
        origine: asString(json['origine']),
        label: asString(json['label']),
        nb: asDouble(json['nb']),
        entrees: asDouble(json['entrees']),
        sorties: asDouble(json['sorties']),
      );
}

class MouvementStock {
  const MouvementStock({
    required this.id,
    required this.date,
    required this.produit,
    required this.variante,
    required this.quantite,
    required this.type,
    required this.origine,
    required this.origineLabel,
    required this.reference,
    required this.note,
    required this.utilisateur,
  });

  final int id;
  final String date;
  final String produit;
  final String variante;
  final num quantite;
  final String type;
  final String origine;
  final String origineLabel;
  final String reference;
  final String note;
  final String utilisateur;

  factory MouvementStock.fromJson(Map<String, dynamic> json) => MouvementStock(
        id: asInt(json['id']),
        date: asString(json['date']),
        produit: asString(json['produit']),
        variante: asString(json['variante']),
        quantite: asDouble(json['quantite']),
        type: asString(json['type']),
        origine: asString(json['origine']),
        origineLabel: asString(json['origine_label']),
        reference: asString(json['reference']),
        note: asString(json['note']),
        utilisateur: asString(json['utilisateur']),
      );
}

class LigneDormant {
  const LigneDormant({
    required this.variantId,
    required this.produit,
    required this.variante,
    required this.stock,
    required this.derniereVente,
    required this.joursSansVente,
    required this.valeurImmobilisee,
  });

  final int variantId;
  final String produit;
  final String variante;
  final num stock;
  final String? derniereVente;
  final num joursSansVente;
  final num valeurImmobilisee;

  factory LigneDormant.fromJson(Map<String, dynamic> json) => LigneDormant(
        variantId: asInt(json['variant_id']),
        produit: asString(json['produit']),
        variante: asString(json['variante']),
        stock: asDouble(json['stock']),
        derniereVente: asStringOrNull(json['derniere_vente']),
        joursSansVente: asDouble(json['jours_sans_vente']),
        valeurImmobilisee: asDouble(json['valeur_immobilisee']),
      );
}

class DormantData {
  const DormantData({required this.jours, required this.nb, required this.valeurImmobilisee, required this.lignes});

  final int jours;
  final int nb;
  final num valeurImmobilisee;
  final List<LigneDormant> lignes;

  factory DormantData.fromJson(Map<String, dynamic> json) => DormantData(
        jours: asInt(json['jours']),
        nb: asInt(json['nb']),
        valeurImmobilisee: asDouble(json['valeur_immobilisee']),
        lignes: _rows(json['lignes']).map(LigneDormant.fromJson).toList(),
      );
}

class StockData {
  const StockData({
    required this.periode,
    required this.etat,
    required this.ruptures,
    required this.reappro,
    required this.parCategorie,
    required this.mouvementsResume,
    required this.mouvements,
    required this.nbMouvements,
    required this.serie,
    required this.dormant,
  });

  final PeriodeInfo periode;

  /// `quantite_totale`, `valeur_achat`, `valeur_vente`, `nb_variantes`,
  /// `nb_references`, `nb_ruptures`, `nb_reappro`, `nb_stock_bas`.
  final Map<String, num> etat;
  final List<LigneStock> ruptures;
  final List<LigneStock> reappro;
  final List<LigneCategorieStock> parCategorie;
  final List<MouvementStockResume> mouvementsResume;
  final List<MouvementStock> mouvements;
  final int nbMouvements;
  final List<SeriePoint> serie;
  final DormantData dormant;

  num etatValeur(String cle) => etat[cle] ?? 0;

  factory StockData.fromJson(Map<String, dynamic> json) => StockData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        etat: _numMap(json['etat']),
        ruptures: LigneStock.liste(json['ruptures']),
        reappro: LigneStock.liste(json['reappro']),
        parCategorie: _rows(json['par_categorie']).map(LigneCategorieStock.fromJson).toList(),
        mouvementsResume: _rows(json['mouvements_resume']).map(MouvementStockResume.fromJson).toList(),
        mouvements: _rows(json['mouvements']).map(MouvementStock.fromJson).toList(),
        nbMouvements: asInt(json['nb_mouvements']),
        serie: SeriePoint.liste(json['serie']),
        dormant: DormantData.fromJson(_obj(json['dormant'])),
      );
}

// --- 6. Commandes -----------------------------------------------------------

class LigneZoneCommandes {
  const LigneZoneCommandes({required this.zone, required this.nb, required this.livrees, required this.ca, required this.frais});

  final String zone;
  final num nb;
  final num livrees;
  final num ca;
  final num frais;

  factory LigneZoneCommandes.fromJson(Map<String, dynamic> json) => LigneZoneCommandes(
        zone: asString(json['zone']),
        nb: asDouble(json['nb']),
        livrees: asDouble(json['livrees']),
        ca: asDouble(json['ca']),
        frais: asDouble(json['frais']),
      );
}

class LignePaiement {
  const LignePaiement({required this.mode, required this.label, required this.nb, required this.ca});

  final String mode;
  final String label;
  final num nb;
  final num ca;

  factory LignePaiement.fromJson(Map<String, dynamic> json) => LignePaiement(
        mode: asString(json['mode']),
        label: asString(json['label']),
        nb: asDouble(json['nb']),
        ca: asDouble(json['ca']),
      );
}

class OrdersData {
  const OrdersData({
    required this.periode,
    required this.kpis,
    required this.comparaison,
    required this.repartition,
    required this.parZone,
    required this.parPaiement,
    required this.serie,
    required this.montantAnnule,
    required this.montantRetourne,
  });

  final PeriodeInfo periode;

  /// `total`, `nouvelles`, `en_preparation`, `pretes`, `en_cours`,
  /// `en_livraison`, `livrees`, `annulees`, `retournees`, `taux_annulation`,
  /// `taux_livraison`, `taux_retour`.
  final Map<String, num> kpis;
  final Map<String, Variation> comparaison;
  final List<RepartitionStatut> repartition;
  final List<LigneZoneCommandes> parZone;
  final List<LignePaiement> parPaiement;
  final List<SeriePoint> serie;
  final num montantAnnule;
  final num montantRetourne;

  num kpi(String cle) => kpis[cle] ?? 0;
  Variation variation(String cle) => comparaison[cle] ?? Variation.zero;

  factory OrdersData.fromJson(Map<String, dynamic> json) => OrdersData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        kpis: _numMap(json['kpis']),
        comparaison: _variationMap(json['comparaison']),
        repartition: _rows(json['repartition']).map(RepartitionStatut.fromJson).toList(),
        parZone: _rows(json['par_zone']).map(LigneZoneCommandes.fromJson).toList(),
        parPaiement: _rows(json['par_paiement']).map(LignePaiement.fromJson).toList(),
        serie: SeriePoint.liste(json['serie']),
        montantAnnule: asDouble(json['montant_annule']),
        montantRetourne: asDouble(json['montant_retourne']),
      );
}

// --- 7. Livraisons ----------------------------------------------------------

class LigneLivreur {
  const LigneLivreur({
    required this.id,
    required this.nom,
    required this.assignees,
    required this.livraisons,
    required this.reussies,
    required this.echouees,
    required this.enCours,
    required this.coutTotal,
    required this.coutMoyen,
    required this.fraisFactures,
    required this.margeLivraison,
    required this.ca,
    required this.tauxReussite,
    required this.tauxEchec,
    required this.delaiMoyenMinutes,
  });

  final int id;
  final String nom;
  final num assignees;
  final num livraisons;
  final num reussies;
  final num echouees;
  final num enCours;
  final num coutTotal;
  final num coutMoyen;
  final num fraisFactures;
  final num margeLivraison;
  final num ca;
  final num tauxReussite;
  final num tauxEchec;
  final num? delaiMoyenMinutes;

  factory LigneLivreur.fromJson(Map<String, dynamic> json) => LigneLivreur(
        id: asInt(json['id']),
        nom: asString(json['nom']),
        assignees: asDouble(json['assignees']),
        livraisons: asDouble(json['livraisons']),
        reussies: asDouble(json['reussies']),
        echouees: asDouble(json['echouees']),
        enCours: asDouble(json['en_cours']),
        coutTotal: asDouble(json['cout_total']),
        coutMoyen: asDouble(json['cout_moyen']),
        fraisFactures: asDouble(json['frais_factures']),
        margeLivraison: asDouble(json['marge_livraison']),
        ca: asDouble(json['ca']),
        tauxReussite: asDouble(json['taux_reussite']),
        tauxEchec: asDouble(json['taux_echec']),
        delaiMoyenMinutes: asDoubleOrNull(json['delai_moyen_minutes']),
      );
}

class LigneZoneLivraison {
  const LigneZoneLivraison({
    required this.zone,
    required this.livraisons,
    required this.reussies,
    required this.echouees,
    required this.frais,
    required this.tauxReussite,
  });

  final String zone;
  final num livraisons;
  final num reussies;
  final num echouees;
  final num frais;
  final num tauxReussite;

  factory LigneZoneLivraison.fromJson(Map<String, dynamic> json) => LigneZoneLivraison(
        zone: asString(json['zone']),
        livraisons: asDouble(json['livraisons']),
        reussies: asDouble(json['reussies']),
        echouees: asDouble(json['echouees']),
        frais: asDouble(json['frais']),
        tauxReussite: asDouble(json['taux_reussite']),
      );
}

class DeliveriesData {
  const DeliveriesData({
    required this.periode,
    required this.totaux,
    required this.parLivreur,
    required this.parZone,
    required this.serie,
  });

  final PeriodeInfo periode;

  /// `livraisons`, `reussies`, `echouees`, `en_cours`, `taux_reussite`,
  /// `taux_echec`, `cout_total`, `cout_moyen`, `frais_factures`,
  /// `marge_livraison`, `delai_moyen_minutes` (nullable), `nb_delais_mesures`.
  final Map<String, num?> totaux;
  final List<LigneLivreur> parLivreur;
  final List<LigneZoneLivraison> parZone;
  final List<SeriePoint> serie;

  num total(String cle) => totaux[cle] ?? 0;

  factory DeliveriesData.fromJson(Map<String, dynamic> json) => DeliveriesData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        totaux: _numOrNullMap(json['totaux']),
        parLivreur: _rows(json['par_livreur']).map(LigneLivreur.fromJson).toList(),
        parZone: _rows(json['par_zone']).map(LigneZoneLivraison.fromJson).toList(),
        serie: SeriePoint.liste(json['serie']),
      );
}

// --- 8. Marketing -----------------------------------------------------------

/// Ligne « campagne » du rapport Marketing (avec ses résultats).
class Campagne {
  const Campagne({
    required this.id,
    required this.nom,
    required this.plateforme,
    required this.plateformeLabel,
    required this.dateDebut,
    required this.dateFin,
    required this.actif,
    required this.depenses,
    required this.commandes,
    required this.commandesLivrees,
    required this.ca,
    required this.margeProduits,
    required this.benefice,
    required this.roiPct,
    required this.coutParCommande,
  });

  final int id;
  final String nom;
  final String plateforme;
  final String plateformeLabel;
  final String dateDebut;
  final String? dateFin;
  final bool actif;
  final num depenses;
  final num commandes;
  final num commandesLivrees;
  final num ca;
  final num margeProduits;
  final num benefice;
  final num? roiPct;
  final num? coutParCommande;

  factory Campagne.fromJson(Map<String, dynamic> json) => Campagne(
        id: asInt(json['id']),
        nom: asString(json['nom']),
        plateforme: asString(json['plateforme']),
        plateformeLabel: asString(json['plateforme_label']),
        dateDebut: asString(json['date_debut']),
        dateFin: asStringOrNull(json['date_fin']),
        actif: asBool(json['actif']),
        depenses: asDouble(json['depenses']),
        commandes: asDouble(json['commandes']),
        commandesLivrees: asDouble(json['commandes_livrees']),
        ca: asDouble(json['ca']),
        margeProduits: asDouble(json['marge_produits']),
        benefice: asDouble(json['benefice']),
        roiPct: asDoubleOrNull(json['roi_pct']),
        coutParCommande: asDoubleOrNull(json['cout_par_commande']),
      );

  static List<Campagne> liste(dynamic v) => _rows(v).map(Campagne.fromJson).toList();
}

class LignePlateforme {
  const LignePlateforme({
    required this.plateforme,
    required this.label,
    required this.depenses,
    required this.commandes,
    required this.commandesLivrees,
    required this.ca,
    required this.nbCampagnes,
    required this.roiPct,
  });

  final String plateforme;
  final String label;
  final num depenses;
  final num commandes;
  final num commandesLivrees;
  final num ca;
  final num nbCampagnes;
  final num? roiPct;

  factory LignePlateforme.fromJson(Map<String, dynamic> json) => LignePlateforme(
        plateforme: asString(json['plateforme']),
        label: asString(json['label']),
        depenses: asDouble(json['depenses']),
        commandes: asDouble(json['commandes']),
        commandesLivrees: asDouble(json['commandes_livrees']),
        ca: asDouble(json['ca']),
        nbCampagnes: asDouble(json['nb_campagnes']),
        roiPct: asDoubleOrNull(json['roi_pct']),
      );
}

/// `plateformes: {code, label}` — choix du formulaire de campagne.
class PlateformeChoix {
  const PlateformeChoix({required this.code, required this.label});

  final String code;
  final String label;

  factory PlateformeChoix.fromJson(Map<String, dynamic> json) =>
      PlateformeChoix(code: asString(json['code']), label: asString(json['label']));
}

class MarketingData {
  const MarketingData({
    required this.periode,
    required this.totaux,
    required this.campagnes,
    required this.parPlateforme,
    required this.plusRentables,
    required this.moinsRentables,
    required this.plateformes,
  });

  final PeriodeInfo periode;

  /// `depenses_campagnes`, `depenses_pub_caisse`, `commandes`,
  /// `commandes_livrees`, `ca`, `marge_produits`, `roi_pct` (nullable),
  /// `nb_campagnes`, `commandes_sans_campagne`.
  final Map<String, num?> totaux;
  final List<Campagne> campagnes;
  final List<LignePlateforme> parPlateforme;
  final List<Campagne> plusRentables;
  final List<Campagne> moinsRentables;
  final List<PlateformeChoix> plateformes;

  num total(String cle) => totaux[cle] ?? 0;

  factory MarketingData.fromJson(Map<String, dynamic> json) => MarketingData(
        periode: PeriodeInfo.fromJson(_obj(json['periode'])),
        totaux: _numOrNullMap(json['totaux']),
        campagnes: Campagne.liste(json['campagnes']),
        parPlateforme: _rows(json['par_plateforme']).map(LignePlateforme.fromJson).toList(),
        plusRentables: Campagne.liste(json['plus_rentables']),
        moinsRentables: Campagne.liste(json['moins_rentables']),
        plateformes: _rows(json['plateformes']).map(PlateformeChoix.fromJson).toList(),
      );
}

// ---------------------------------------------------------------------------
// Couleurs
// ---------------------------------------------------------------------------

/// `STATUT_COULEURS` du web.
const Map<String, Color> kStatutCouleurs = {
  'NOUVELLE': Color(0xFF3B82F6),
  'EN_PREPARATION': Color(0xFFF59E0B),
  'PRETE': Color(0xFF8B5CF6),
  'EN_LIVRAISON': Color(0xFF06B6D4),
  'LIVRE': Color(0xFF22C55E),
  'RETOUR': Color(0xFFF97316),
  'ANNULEE': Color(0xFFEF4444),
};

/// `PALETTE` du web.
const List<Color> kPalette = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
  Color(0xFFF97316),
  Color(0xFF64748B),
];

/// Couleur de repli (`#64748b`) quand un statut n'a pas de couleur.
const Color kCouleurNeutre = Color(0xFF64748B);
