import 'package:flutter/material.dart';

import '../../../core/app_time.dart';
import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';

/// Port de components/reports/report-filters.tsx : période (liste
/// déroulante, à la place de l'ancien choix de granularité — les séries
/// suivent la granularité automatique), date(s), bouton Actualiser. Empilé
/// proprement sur mobile.
///
/// Les préréglages déduisent leur plage d'UNE SEULE date de référence :
/// « Ce mois » au 15/08 va du 1er au 15 août. « Personnalisée » est le seul
/// cas où l'utilisateur borne les deux extrémités — on y affiche donc deux
/// champs, « Du » et « Au », et un seul partout ailleurs (§ demande).
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
    required this.onDateFin,
    required this.onReload,
    this.loading = false,
  });

  final ReportsFilter filter;
  final ReportPeriod period;
  final ValueChanged<ReportPreset> onPreset;

  /// Date de référence, « Du » en personnalisé (AAAA-MM-JJ).
  final ValueChanged<String> onDate;

  /// Borne « Au » — personnalisé seulement (AAAA-MM-JJ).
  final ValueChanged<String> onDateFin;
  final VoidCallback onReload;
  final bool loading;

  /// Ouvre le sélecteur sur [valeur], en bornant la plage proposée pour
  /// qu'on ne puisse pas composer un intervalle à l'envers.
  Future<void> _choisirDate(
    BuildContext context, {
    required String valeur,
    required ValueChanged<String> onChoix,
    DateTime? premier,
    DateTime? dernier,
  }) async {
    final initiale = DateTime.tryParse(valeur) ?? appToday();
    final min = premier ?? DateTime(2020);
    final max = dernier ?? DateTime(2100);
    final choix = await showDatePicker(
      context: context,
      initialDate: initiale.isBefore(min) ? min : (initiale.isAfter(max) ? max : initiale),
      firstDate: min,
      lastDate: max,
    );
    if (choix == null) return;
    onChoix(formatReportsDate(choix));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final personnalisee = filter.estPersonnalisee;
    // Le repli ne désigne pas la même chose selon le mode : en personnalisé
    // le champ EST la borne de début, ailleurs c'est la date de référence
    // dont le préréglage déduit sa plage (qui se termine donc sur elle).
    final dateRef = filter.date.isNotEmpty ? filter.date : (personnalisee ? period.from : period.to);
    final dateFin = filter.dateFin.isNotEmpty ? filter.dateFin : dateRef;

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
        final date = _ChampDate(
          label: personnalisee ? 'Du' : 'Date',
          valeur: dateRef,
          onTap: () => _choisirDate(
            context,
            valeur: dateRef,
            onChoix: onDate,
            dernier: personnalisee ? DateTime.tryParse(dateFin) : null,
          ),
        );
        final champFin = !personnalisee
            ? null
            : _ChampDate(
                label: 'Au',
                valeur: dateFin,
                onTap: () => _choisirDate(
                  context,
                  valeur: dateFin,
                  onChoix: onDateFin,
                  premier: DateTime.tryParse(dateRef),
                ),
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
              periode,
              SizedBox(width: 150, child: date),
              if (champFin != null) SizedBox(width: 150, child: champFin),
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
            if (champFin != null) ...[const SizedBox(height: 8), champFin],
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
