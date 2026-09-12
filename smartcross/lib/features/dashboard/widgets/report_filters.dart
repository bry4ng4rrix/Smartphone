import 'package:flutter/material.dart';

import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';

/// Port de components/reports/report-filters.tsx : période rapide ou
/// personnalisée, granularité des séries, bouton Actualiser. Empilé
/// proprement sur mobile.
///
/// Adaptation mobile : les `<input type="date">` deviennent des champs qui
/// ouvrent un sélecteur de date.
class ReportFilters extends StatelessWidget {
  const ReportFilters({
    super.key,
    required this.filter,
    required this.period,
    required this.onPreset,
    required this.onCustomFrom,
    required this.onCustomTo,
    required this.onGranularity,
    required this.onReload,
    this.loading = false,
  });

  final ReportsFilter filter;
  final ReportPeriod period;
  final ValueChanged<ReportPreset> onPreset;
  final ValueChanged<String> onCustomFrom;
  final ValueChanged<String> onCustomTo;
  final ValueChanged<ReportGranularity?> onGranularity;
  final VoidCallback onReload;
  final bool loading;

  Future<void> _choisirDate(BuildContext context, {required bool debut}) async {
    final custom = filter.preset == ReportPreset.custom;
    final valeur = debut ? (custom ? filter.customFrom : period.from) : (custom ? filter.customTo : period.to);
    final initiale = DateTime.tryParse(valeur) ?? DateTime.now();
    // `max` du champ Du / `min` du champ Au en période personnalisée.
    DateTime? borneMin;
    DateTime? borneMax;
    if (custom) {
      if (debut) borneMax = DateTime.tryParse(filter.customTo);
      if (!debut) borneMin = DateTime.tryParse(filter.customFrom);
    }
    final first = borneMin ?? DateTime(2020);
    final last = borneMax ?? DateTime(2100);
    final init = initiale.isBefore(first) ? first : (initiale.isAfter(last) ? last : initiale);
    final choix = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: last);
    if (choix == null) return;
    final iso = formatReportsDate(choix);
    if (debut) {
      onCustomFrom(iso);
    } else {
      onCustomTo(iso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final custom = filter.preset == ReportPreset.custom;
    final du = custom ? filter.customFrom : period.from;
    final au = custom ? filter.customTo : period.to;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in ReportPreset.values)
              ChoiceChip(
                label: Text(p.label, style: const TextStyle(fontSize: 12)),
                selected: filter.preset == p,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onPreset(p),
              ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final large = constraints.maxWidth >= 640;
            final champs = [
              _ChampDate(label: 'Du', valeur: du, onTap: () => _choisirDate(context, debut: true)),
              _ChampDate(label: 'Au', valeur: au, onTap: () => _choisirDate(context, debut: false)),
            ];
            final granularite = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Granularité', style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(height: 4),
                Container(
                  width: large ? 150 : double.infinity,
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReportGranularity?>(
                      value: filter.granularity,
                      isDense: true,
                      isExpanded: true,
                      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                      items: [
                        const DropdownMenuItem<ReportGranularity?>(value: null, child: Text('Automatique')),
                        for (final g in ReportGranularity.values)
                          DropdownMenuItem<ReportGranularity?>(value: g, child: Text(g.label)),
                      ],
                      onChanged: onGranularity,
                    ),
                  ),
                ),
              ],
            );
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
                  SizedBox(width: 150, child: champs[0]),
                  SizedBox(width: 150, child: champs[1]),
                  granularite,
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
                Row(
                  children: [
                    Expanded(child: champs[0]),
                    const SizedBox(width: 8),
                    Expanded(child: champs[1]),
                  ],
                ),
                const SizedBox(height: 8),
                granularite,
                const SizedBox(height: 8),
                Row(children: [Expanded(child: resume), const SizedBox(width: 8), actualiser]),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Champ « Du » / « Au » : libellé + valeur `AAAA-MM-JJ`, ouvre le sélecteur.
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
