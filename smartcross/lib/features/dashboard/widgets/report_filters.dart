import 'package:flutter/material.dart';

import '../../../core/app_time.dart';
import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';

/// Port de components/reports/report-filters.tsx : période (liste
/// déroulante, à la place de l'ancien choix de granularité — les séries
/// suivent la granularité automatique), date de référence unique, bouton
/// Actualiser. Empilé proprement sur mobile.
///
/// Adaptation mobile : le `<input type="date">` devient un champ qui ouvre
/// un sélecteur de date.
class ReportFilters extends StatelessWidget {
  const ReportFilters({
    super.key,
    required this.filter,
    required this.period,
    required this.onPreset,
    required this.onDate,
    required this.onReload,
    this.loading = false,
  });

  final ReportsFilter filter;
  final ReportPeriod period;
  final ValueChanged<ReportPreset> onPreset;

  /// Date de référence (AAAA-MM-JJ).
  final ValueChanged<String> onDate;
  final VoidCallback onReload;
  final bool loading;

  Future<void> _choisirDate(BuildContext context) async {
    final valeur = filter.date.isNotEmpty ? filter.date : period.to;
    final initiale = DateTime.tryParse(valeur) ?? appToday();
    final choix = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (choix == null) return;
    onDate(formatReportsDate(choix));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final dateRef = filter.date.isNotEmpty ? filter.date : period.to;

    return LayoutBuilder(
      builder: (context, constraints) {
        final large = constraints.maxWidth >= 640;
        final periode = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Période', style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 4),
            Container(
              width: large ? 190 : double.infinity,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ReportPreset>(
                  value: filter.preset,
                  isDense: true,
                  isExpanded: true,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                  items: [
                    for (final p in ReportPreset.values) DropdownMenuItem<ReportPreset>(value: p, child: Text(p.label)),
                  ],
                  onChanged: (p) {
                    if (p != null) onPreset(p);
                  },
                ),
              ),
            ),
          ],
        );
        final date = _ChampDate(label: 'Date', valeur: dateRef, onTap: () => _choisirDate(context));
        final resume = Text(
          '${fmtDate(period.from)} → ${fmtDate(period.to)} · comparé à ${fmtDate(period.prevFrom)} → ${fmtDate(period.prevTo)}',
          style: TextStyle(fontSize: 12, color: muted),
        );
        final actualiser = SizedBox(
          width: 36,
          height: 36,
          child: IconButton.outlined(
            tooltip: 'Actualiser',
            padding: EdgeInsets.zero,
            onPressed: loading ? null : onReload,
            icon: loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 18),
          ),
        );

        if (large) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              periode,
              SizedBox(width: 150, child: date),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [resume, const SizedBox(width: 8), actualiser]),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            periode,
            const SizedBox(height: 8),
            date,
            const SizedBox(height: 8),
            Row(children: [Expanded(child: resume), const SizedBox(width: 8), actualiser]),
          ],
        );
      },
    );
  }
}

/// Champ « Date » : libellé + valeur `AAAA-MM-JJ`, ouvre le sélecteur.
class _ChampDate extends StatelessWidget {
  const _ChampDate({required this.label, required this.valeur, required this.onTap});

  final String label;
  final String valeur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    valeur.isEmpty ? 'jj/mm/aaaa' : fmtDate(valeur),
                    style: TextStyle(fontSize: 13, color: valeur.isEmpty ? muted : theme.colorScheme.onSurface),
                  ),
                ),
                Icon(Icons.calendar_today_outlined, size: 14, color: muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
