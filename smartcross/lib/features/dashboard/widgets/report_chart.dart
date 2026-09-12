import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/reports.dart';
import 'kpi_card.dart' show ReportSkeleton;

/// Port de components/reports/report-chart.tsx (recharts → fl_chart) :
/// [ChartCard], [SerieChart], [BarresChart], [CamembertChart].

/// Montants en Ar (défaut) ou simple nombre.
enum ChartUnite { ar, nb }

enum SerieType { bar, line }

String _fmt(ChartUnite unite, num v) => unite == ChartUnite.ar ? fmtAr(v) : fmtNb(v);

/// `SerieDef` du web.
class SerieDef {
  const SerieDef({
    required this.key,
    required this.label,
    this.type = SerieType.bar,
    this.color,
    this.unite = ChartUnite.ar,
    this.stackId,
  });

  final String key;
  final String label;
  final SerieType type;
  final Color? color;
  final ChartUnite unite;

  /// Barres empilées entre séries de même [stackId].
  final String? stackId;
}

/// Carte de graphique : titre, description, états chargement / erreur /
/// vide (« Aucune donnée sur la période. »), zone de hauteur fixe.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.titre,
    this.description,
    this.loading = false,
    this.error,
    this.vide = false,
    this.hauteur = 280,
    this.actions,
    required this.child,
  });

  final String titre;
  final String? description;
  final bool loading;
  final String? error;
  final bool vide;
  final double hauteur;
  final Widget? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget corps;
    if (loading) {
      corps = ReportSkeleton(height: hauteur);
    } else if (error != null) {
      corps = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: theme.colorScheme.error)),
        ),
      );
    } else if (vide) {
      corps = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune donnée sur la période.', style: TextStyle(fontSize: 14, color: muted))),
      );
    } else {
      corps = SizedBox(height: hauteur, width: double.infinity, child: child);
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titre, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(description!, style: TextStyle(fontSize: 12, color: muted)),
                      ],
                    ],
                  ),
                ),
                ?actions,
              ],
            ),
            const SizedBox(height: 12),
            corps,
          ],
        ),
      ),
    );
  }
}

/// Légende : pastille de couleur + libellé.
class _Legende extends StatelessWidget {
  const _Legende({required this.entrees});

  final List<(String, Color)> entrees;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (label, color) in entrees)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label, style: TextStyle(fontSize: 12, color: muted), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
      ],
    );
  }
}

/// Info-bulle flottante (`<Tooltip contentStyle={{ fontSize: 12 }}>`).
class _InfoBulle extends StatelessWidget {
  const _InfoBulle({required this.titre, required this.lignes});

  final String titre;
  final List<(String, String, Color?)> lignes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(6),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            for (final (label, valeur, color) in lignes)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (color != null) ...[
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                    ],
                    Flexible(child: Text('$label : $valeur', style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Intervalle « rond » d'axe pour une plage donnée (1, 2, 5 × 10ⁿ).
double _intervalleRond(double plage, int pas) {
  if (plage <= 0) return 1;
  final brut = plage / pas;
  final puissance = math.pow(10, (math.log(brut) / math.ln10).floor()).toDouble();
  final r = brut / puissance;
  final facteur = r <= 1 ? 1 : (r <= 2 ? 2 : (r <= 5 ? 5 : 10));
  return facteur * puissance;
}

/// Courbes / barres dans le temps (séries renvoyées par le serveur).
///
/// Adaptation mobile : recharts superpose barres et courbes dans un
/// `ComposedChart` à deux axes ; ici un [BarChart] et un [LineChart] sont
/// empilés avec les mêmes bornes (les groupes `spaceAround` tombent sur les
/// abscisses entières de la courbe). Les séries `nb` sont ramenées à
/// l'échelle des montants pour le dessin, l'axe de droite affiche leur
/// vraie valeur. Un toucher affiche toutes les séries du point.
class SerieChart extends StatefulWidget {
  const SerieChart({super.key, required this.data, required this.series, this.hauteur = 280});

  final List<SeriePoint> data;
  final List<SerieDef> series;

  /// Hauteur demandée par la section (prop `hauteur` du web) ; le dessin
  /// occupe en fait toute la hauteur donnée par [ChartCard].
  final double hauteur;

  @override
  State<SerieChart> createState() => _SerieChartState();
}

class _SerieChartState extends State<SerieChart> {
  int? _selection;

  Color _couleur(int i) => widget.series[i].color ?? kPalette[i % kPalette.length];

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final series = widget.series;
    final n = data.length;
    if (n == 0 || series.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final grille = theme.colorScheme.onSurface.withValues(alpha: 0.12);

    final hasAr = series.any((s) => s.unite == ChartUnite.ar);
    final hasNb = series.any((s) => s.unite == ChartUnite.nb);
    final axeGauche = hasAr ? ChartUnite.ar : ChartUnite.nb;

    // Facteur d'échelle des séries `nb` quand elles cohabitent avec des
    // montants (second axe à droite).
    double maxAbs(ChartUnite u) {
      var m = 0.0;
      for (final s in series.where((s) => s.unite == u)) {
        for (final p in data) {
          m = math.max(m, p.v(s.key).abs().toDouble());
        }
      }
      return m;
    }

    final facteurNb = (hasAr && hasNb) ? (maxAbs(ChartUnite.nb) > 0 ? maxAbs(ChartUnite.ar) / maxAbs(ChartUnite.nb) : 1.0) : 1.0;
    double dessine(SerieDef s, num v) => s.unite == ChartUnite.nb ? v.toDouble() * facteurNb : v.toDouble();

    // Groupes de barres (empilement par stackId).
    final barres = [for (var i = 0; i < series.length; i++) if (series[i].type == SerieType.bar) i];
    final lignes = [for (var i = 0; i < series.length; i++) if (series[i].type == SerieType.line) i];
    final piles = <String, List<int>>{};
    for (final i in barres) {
      piles.putIfAbsent(series[i].stackId ?? '__${series[i].key}', () => []).add(i);
    }

    // Bornes communes aux deux graphiques.
    var minY = 0.0;
    var maxY = 0.0;
    for (final p in data) {
      for (final pile in piles.values) {
        var pos = 0.0;
        var neg = 0.0;
        for (final i in pile) {
          final v = dessine(series[i], p.v(series[i].key));
          if (v >= 0) {
            pos += v;
          } else {
            neg += v;
          }
        }
        maxY = math.max(maxY, pos);
        minY = math.min(minY, neg);
      }
      for (final i in lignes) {
        final v = dessine(series[i], p.v(series[i].key));
        maxY = math.max(maxY, v);
        minY = math.min(minY, v);
      }
    }
    if (maxY == 0 && minY == 0) maxY = 1;
    final intervalle = _intervalleRond(maxY - minY, 4);
    maxY = (maxY / intervalle).ceil() * intervalle;
    minY = (minY / intervalle).floor() * intervalle;
    if (maxY == minY) maxY = minY + intervalle;

    const reserveGauche = 48.0;
    final reserveDroite = (hasAr && hasNb) ? 40.0 : 8.0;
    const reserveBas = 26.0;

    String etiquetteGauche(double v) => axeGauche == ChartUnite.ar ? fmtArCourt(v) : fmtNb(v);
    String etiquetteDroite(double v) => fmtNb(v / facteurNb);

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeur = constraints.maxWidth;
        final zone = largeur - reserveGauche - reserveDroite;
        final creneau = zone / n;
        final pasEtiquette = math.max(1, (n / math.max(1, (zone / 56).floor())).ceil());
        final nbRods = math.max(1, piles.length);
        final largeurBarre = (creneau * 0.7 / nbRods).clamp(2.0, 40.0);

        Widget titreBas(double value, TitleMeta meta) {
          final i = value.round();
          if ((value - i).abs() > 0.01 || i < 0 || i >= n) return const SizedBox.shrink();
          // `interval="preserveStartEnd"` + `minTickGap` : premier, dernier
          // et un point sur `pasEtiquette`.
          final visible = i == 0 || i == n - 1 || (i % pasEtiquette == 0 && i <= n - 1 - pasEtiquette ~/ 2);
          if (!visible) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            space: 4,
            child: Text(data[i].label, style: TextStyle(fontSize: 10, color: muted)),
          );
        }

        Widget titreGauche(double value, TitleMeta meta) => SideTitleWidget(
              meta: meta,
              space: 4,
              child: Text(etiquetteGauche(value), style: TextStyle(fontSize: 10, color: muted)),
            );
        Widget titreDroite(double value, TitleMeta meta) => SideTitleWidget(
              meta: meta,
              space: 4,
              child: Text(etiquetteDroite(value), style: TextStyle(fontSize: 10, color: muted)),
            );
        Widget vide(double value, TitleMeta meta) => const SizedBox.shrink();

        FlTitlesData titres({required bool visibles}) => FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: reserveGauche,
                  interval: intervalle,
                  getTitlesWidget: visibles ? titreGauche : vide,
                ),
              ),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: reserveDroite,
                  interval: intervalle,
                  getTitlesWidget: visibles && hasAr && hasNb ? titreDroite : vide,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: reserveBas,
                  interval: 1,
                  getTitlesWidget: visibles ? titreBas : vide,
                ),
              ),
            );

        // --- Barres ---------------------------------------------------------
        final groupes = <BarChartGroupData>[];
        for (var x = 0; x < n; x++) {
          final rods = <BarChartRodData>[];
          for (final pile in piles.values) {
            if (pile.length == 1) {
              final i = pile.first;
              rods.add(BarChartRodData(
                toY: dessine(series[i], data[x].v(series[i].key)),
                color: _couleur(i),
                width: largeurBarre,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ));
            } else {
              var pos = 0.0;
              var neg = 0.0;
              final items = <BarChartRodStackItem>[];
              for (final i in pile) {
                final v = dessine(series[i], data[x].v(series[i].key));
                if (v >= 0) {
                  items.add(BarChartRodStackItem(pos, pos + v, _couleur(i)));
                  pos += v;
                } else {
                  items.add(BarChartRodStackItem(neg + v, neg, _couleur(i)));
                  neg += v;
                }
              }
              rods.add(BarChartRodData(
                fromY: neg,
                toY: pos,
                width: largeurBarre,
                color: Colors.transparent,
                rodStackItems: items,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ));
            }
          }
          groupes.add(BarChartGroupData(x: x, barRods: rods, barsSpace: 2));
        }

        // --- Courbes --------------------------------------------------------
        final courbes = <LineChartBarData>[
          for (final i in lignes)
            LineChartBarData(
              spots: [for (var x = 0; x < n; x++) FlSpot(x.toDouble(), dessine(series[i], data[x].v(series[i].key)))],
              isCurved: true,
              preventCurveOverShooting: true,
              color: _couleur(i),
              barWidth: 2,
              dotData: FlDotData(show: n <= 31),
            ),
          // Courbe invisible : garantit la détection du toucher même sans
          // série « line ».
          if (lignes.isEmpty)
            LineChartBarData(
              spots: [for (var x = 0; x < n; x++) FlSpot(x.toDouble(), minY)],
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            ),
        ];

        final sel = _selection;

        // La zone de dessin prend toute la hauteur restante (la légende peut
        // occuper une ou deux lignes sur un écran étroit).
        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BarChart(
                      BarChartData(
                        minY: minY,
                        maxY: maxY,
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: groupes,
                        barTouchData: BarTouchData(enabled: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: intervalle,
                          getDrawingHorizontalLine: (_) => FlLine(color: grille, strokeWidth: 1, dashArray: [3, 3]),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: titres(visibles: false),
                      ),
                      duration: Duration.zero,
                    ),
                  ),
                  Positioned.fill(
                    child: LineChart(
                      LineChartData(
                        minX: -0.5,
                        maxX: n - 0.5,
                        minY: minY,
                        maxY: maxY,
                        lineBarsData: courbes,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: titres(visibles: true),
                        extraLinesData: ExtraLinesData(
                          verticalLines: [
                            if (sel != null) VerticalLine(x: sel.toDouble(), color: grille, strokeWidth: 1),
                          ],
                        ),
                        lineTouchData: LineTouchData(
                          enabled: true,
                          handleBuiltInTouches: false,
                          touchSpotThreshold: 1e9,
                          touchCallback: (event, response) {
                            final spots = response?.lineBarSpots;
                            if (event is FlPointerExitEvent) {
                              if (_selection != null) setState(() => _selection = null);
                              return;
                            }
                            if (spots == null || spots.isEmpty) return;
                            final idx = spots.first.spotIndex;
                            if (idx != _selection) setState(() => _selection = idx);
                          },
                        ),
                      ),
                      duration: Duration.zero,
                    ),
                  ),
                  if (sel != null && sel >= 0 && sel < n)
                    Positioned(
                      top: 0,
                      left: (reserveGauche + creneau * (sel + 0.5) - 90).clamp(0.0, math.max(0.0, largeur - 180)),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: _InfoBulle(
                          titre: data[sel].label,
                          lignes: [
                            for (var i = 0; i < series.length; i++)
                              (series[i].label, _fmt(series[i].unite, data[sel].v(series[i].key)), _couleur(i)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _Legende(entrees: [for (var i = 0; i < series.length; i++) (series[i].label, _couleur(i))]),
          ],
        );
      },
    );
  }
}

/// Barres horizontales pour un classement (catégories, zones, livreurs…).
///
/// Adaptation mobile : fl_chart n'a pas de barres horizontales ; chaque
/// ligne est dessinée directement (libellé à gauche, barre proportionnelle
/// au maximum, valeur formatée à droite — l'info-bulle du web). Défilement
/// vertical si les lignes ne tiennent pas dans [hauteur].
class BarresChart extends StatelessWidget {
  const BarresChart({
    super.key,
    required this.data,
    required this.labelKey,
    required this.valueKey,
    this.unite = ChartUnite.ar,
    this.hauteur = 280,
    this.color,
    this.colors,
  });

  final List<Map<String, dynamic>> data;
  final String labelKey;
  final String valueKey;
  final ChartUnite unite;
  final double hauteur;
  final Color? color;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final grille = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    final valeurs = [for (final d in data) (num.tryParse('${d[valueKey]}') ?? 0)];
    final maxAbs = valeurs.fold<double>(0, (m, v) => math.max(m, v.abs().toDouble()));
    final n = data.length;
    if (n == 0) return const SizedBox.shrink();
    final hauteurLigne = (hauteur / n).clamp(22.0, 34.0);

    return ListView.builder(
      physics: n * hauteurLigne > hauteur ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: n,
      itemExtent: hauteurLigne,
      itemBuilder: (context, i) {
        final v = valeurs[i];
        final c = colors != null ? colors![i % colors!.length] : (color ?? kPalette[0]);
        final part = maxAbs > 0 ? (v.abs() / maxAbs) : 0.0;
        return Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(
                '${data[i][labelKey] ?? ''}',
                style: TextStyle(fontSize: 11, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: '${data[i][labelKey] ?? ''} : ${_fmt(unite, v)}',
                child: Container(
                  height: hauteurLigne - 8,
                  decoration: BoxDecoration(color: grille, borderRadius: BorderRadius.circular(3)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: part.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                unite == ChartUnite.ar ? fmtArCourt(v) : fmtNb(v),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Répartition (statuts, plateformes, catégories de dépenses) — anneau
/// (`innerRadius="45%"`, `outerRadius="75%"`), valeurs > 0 seulement, légende.
/// Un toucher affiche libellé et valeur au centre de l'anneau.
class CamembertChart extends StatefulWidget {
  const CamembertChart({
    super.key,
    required this.data,
    required this.labelKey,
    required this.valueKey,
    this.unite = ChartUnite.nb,
    this.hauteur = 280,
    this.colors,
  });

  final List<Map<String, dynamic>> data;
  final String labelKey;
  final String valueKey;
  final ChartUnite unite;
  final double hauteur;
  final List<Color>? colors;

  @override
  State<CamembertChart> createState() => _CamembertChartState();
}

class _CamembertChartState extends State<CamembertChart> {
  int? _selection;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final filtres = widget.data.where((d) => (num.tryParse('${d[widget.valueKey]}') ?? 0) > 0).toList();
    if (filtres.isEmpty) return const SizedBox.shrink();
    final palette = widget.colors ?? kPalette;
    Color couleur(int i) => palette[i % palette.length];
    num valeur(int i) => num.tryParse('${filtres[i][widget.valueKey]}') ?? 0;
    String label(int i) => '${filtres[i][widget.labelKey] ?? ''}';
    final total = [for (var i = 0; i < filtres.length; i++) valeur(i)].fold<num>(0, (a, b) => a + b);
    final sel = _selection;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final taille = math.min(constraints.maxWidth, constraints.maxHeight);
              final externe = taille / 2 * 0.75;
              final interne = taille / 2 * 0.45;
              return Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      centerSpaceRadius: interne,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          final idx = response?.touchedSection?.touchedSectionIndex;
                          if (event is FlPointerExitEvent) {
                            if (_selection != null) setState(() => _selection = null);
                            return;
                          }
                          if (idx == null || idx < 0) return;
                          if (idx != _selection) setState(() => _selection = idx);
                        },
                      ),
                      sections: [
                        for (var i = 0; i < filtres.length; i++)
                          PieChartSectionData(
                            value: valeur(i).toDouble(),
                            color: couleur(i),
                            radius: (externe - interne) + (sel == i ? 6 : 0),
                            showTitle: false,
                          ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
                  if (sel != null && sel < filtres.length)
                    SizedBox(
                      width: interne * 1.8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label(sel),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          Text(
                            _fmt(widget.unite, valeur(sel)),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          if (total > 0)
                            Text(
                              fmtPct(valeur(sel) / total * 100),
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        _Legende(entrees: [for (var i = 0; i < filtres.length; i++) (label(i), couleur(i))]),
      ],
    );
  }
}
