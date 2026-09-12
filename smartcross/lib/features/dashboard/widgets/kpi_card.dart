import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/reports.dart';

/// Port de components/reports/kpi-card.tsx : [VariationBadge], [ReportKpiCard]
/// et [KpiGrid].

/// Couleurs « bonne » / « mauvaise » nouvelle du web (emerald-600 / red-600).
const Color kCouleurHausse = Color(0xFF059669);
const Color kCouleurBaisse = Color(0xFFDC2626);

/// Squelette de chargement (`<Skeleton>` du web).
class ReportSkeleton extends StatelessWidget {
  const ReportSkeleton({super.key, this.height = 16, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// Indicateur d'évolution : flèche + pourcentage. [inverse] pour les
/// indicateurs où une hausse est mauvaise (dépenses, annulations).
class VariationBadge extends StatelessWidget {
  const VariationBadge({super.key, required this.pct, this.inverse = false});

  final num? pct;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = pct;
    if (p == null) {
      return Text('n/a (période préc. = 0)', style: TextStyle(fontSize: 12, color: muted));
    }
    final positif = p > 0;
    final nul = p == 0;
    final bool? bon = nul ? null : (inverse ? !positif : positif);
    final couleur = nul ? muted : (bon! ? kCouleurHausse : kCouleurBaisse);
    final icon = nul ? Icons.remove : (positif ? Icons.north_east : Icons.south_east);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: couleur),
        const SizedBox(width: 2),
        Text(fmtPct(p, signe: true), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: couleur)),
      ],
    );
  }
}

/// `KpiCard` du web : titre, valeur, variation (+ « préc. … »), détail,
/// petite tendance.
class ReportKpiCard extends StatelessWidget {
  const ReportKpiCard({
    super.key,
    required this.titre,
    this.valeur,
    this.detail,
    this.variation,
    this.inverse = false,
    this.icon,
    this.couleur,
    this.serie,
    this.loading = false,
    this.format,
  });

  final String titre;
  final String? valeur;
  final String? detail;

  /// Comparaison avec la période précédente.
  final Variation? variation;

  /// Une hausse est une mauvaise nouvelle (dépenses, annulations…).
  final bool inverse;
  final IconData? icon;

  /// Couleur de la valeur (défaut : couleur du texte).
  final Color? couleur;

  /// Petite tendance (valeurs brutes).
  final List<num>? serie;
  final bool loading;

  /// Pour afficher la valeur précédente (« préc. … »).
  final String Function(num v)? format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    if (loading) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ReportSkeleton(height: 14, width: 96),
              SizedBox(height: 6),
              ReportSkeleton(height: 28, width: 128),
              SizedBox(height: 10),
              ReportSkeleton(height: 12, width: 80),
            ],
          ),
        ),
      );
    }

    final v = variation;
    final pct = v?.variationPct;
    final bool? hausse = (v != null && pct != null && pct != 0) ? (inverse ? pct < 0 : pct > 0) : null;
    final s = serie;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: muted), const SizedBox(width: 6)],
                Expanded(child: Text(titre, style: TextStyle(fontSize: 12, color: muted), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              valeur ?? '—',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: couleur,
              ),
            ),
            if (v != null) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  VariationBadge(pct: pct, inverse: inverse),
                  if (format != null) Text('préc. ${format!(v.precedent)}', style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ],
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail!, style: TextStyle(fontSize: 12, color: muted)),
            ],
            if (s != null && s.length > 1) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: _Sparkline(
                  valeurs: s,
                  couleur: hausse == null ? kCouleurNeutre : (hausse ? const Color(0xFF16A34A) : kCouleurBaisse),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Courbe de tendance sans axes ni info-bulle (`<LineChart>` 32 px du web).
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.valeurs, required this.couleur});

  final List<num> valeurs;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final spots = [for (var i = 0; i < valeurs.length; i++) FlSpot(i.toDouble(), valeurs[i].toDouble())];
    var minY = valeurs.first.toDouble();
    var maxY = minY;
    for (final v in valeurs) {
      if (v < minY) minY = v.toDouble();
      if (v > maxY) maxY = v.toDouble();
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (valeurs.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: couleur,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

/// `KpiGrid` : 1 colonne sur mobile, 2 dès 600 px, [cols] dès 1024 px.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children, this.cols = 4});

  final List<Widget> children;
  final int cols;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final n = w < 600 ? 1 : (w < 1024 ? 2 : cols);
        const gap = 12.0;
        // Cartes d'une même rangée à la même hauteur.
        final rangees = <Widget>[];
        for (var i = 0; i < children.length; i += n) {
          final tranche = children.sublist(i, i + n > children.length ? children.length : i + n);
          rangees.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < n; j++) ...[
                  if (j > 0) const SizedBox(width: gap),
                  Expanded(child: j < tranche.length ? tranche[j] : const SizedBox.shrink()),
                ],
              ],
            ),
          ));
        }
        return Column(
          children: [
            for (var i = 0; i < rangees.length; i++) ...[
              if (i > 0) const SizedBox(height: gap),
              rangees[i],
            ],
          ],
        );
      },
    );
  }
}
