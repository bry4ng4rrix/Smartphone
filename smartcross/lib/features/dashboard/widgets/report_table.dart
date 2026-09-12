import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import 'kpi_card.dart' show ReportSkeleton;
import 'report_export.dart';

/// Port de components/reports/report-table.tsx : [ReportColumn] et
/// [ReportTable].

/// `Colonne<T>` du web.
class ReportColumn<T> {
  const ReportColumn({
    required this.key,
    required this.label,
    this.align = TextAlign.left,
    this.render,
    this.export,
    this.valeur,
  });

  final String key;
  final String label;
  final TextAlign align;

  /// Rendu de la cellule ; par défaut la valeur brute ([valeur]).
  final Widget Function(T row, int index)? render;

  /// Valeur exportée (Excel) ; par défaut [valeur].
  final Object? Function(T row)? export;

  /// Valeur brute de la ligne pour cette clé (équivalent de `row[key]` du
  /// web, les lignes étant typées ici).
  final Object? Function(T row)? valeur;

  Object? brute(T row) => valeur?.call(row);
}

/// Tableau de rapport : états chargement / erreur / vide, défilement
/// horizontal, pagination côté client et export Excel.
class ReportTable<T> extends StatefulWidget {
  const ReportTable({
    super.key,
    this.titre,
    this.description,
    required this.colonnes,
    required this.lignes,
    this.loading = false,
    this.error,
    this.vide = 'Aucune donnée sur la période.',
    this.pageSize = 15,
    this.rowKey,
    this.exportNom,
    this.actions,
    this.compact = false,
  });

  final String? titre;
  final String? description;
  final List<ReportColumn<T>> colonnes;
  final List<T>? lignes;
  final bool loading;
  final String? error;
  final String vide;
  final int pageSize;
  final Object Function(T row, int index)? rowKey;

  /// Nom du fichier Excel ; le bouton d'export n'apparaît que s'il est fourni.
  final String? exportNom;
  final Widget? actions;
  final bool compact;

  @override
  State<ReportTable<T>> createState() => _ReportTableState<T>();
}

class _ReportTableState<T> extends State<ReportTable<T>> {
  int _page = 0;
  bool _exporting = false;

  Future<void> _exporter() async {
    final lignes = widget.lignes;
    if (lignes == null || lignes.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = [
        for (final row in lignes)
          [for (final c in widget.colonnes) c.export != null ? c.export!(row) : c.brute(row)],
      ];
      final nom = widget.exportNom ?? widget.titre ?? 'rapport';
      final feuille = widget.titre ?? widget.exportNom ?? 'Rapport';
      await partagerXlsx(
        nomFichier: nom,
        headers: [for (final c in widget.colonnes) c.label],
        rows: rows,
        sheetName: feuille.length > 30 ? feuille.substring(0, 30) : feuille,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final lignes = widget.lignes ?? const [];
    final total = lignes.length;
    final pages = (total / widget.pageSize).ceil().clamp(1, 1 << 30);
    final pageCourante = _page.clamp(0, pages - 1);
    final visibles = lignes.skip(pageCourante * widget.pageSize).take(widget.pageSize).toList();
    final fontSize = widget.compact ? 12.0 : 14.0;
    final enTete = widget.titre != null || widget.actions != null || widget.exportNom != null;

    Widget corps;
    if (widget.loading) {
      corps = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              const ReportSkeleton(height: 32),
            ],
          ],
        ),
      );
    } else if (widget.error != null) {
      corps = Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.error!, style: TextStyle(fontSize: 14, color: theme.colorScheme.error))),
          ],
        ),
      );
    } else if (total == 0) {
      corps = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(widget.vide, style: TextStyle(fontSize: 14, color: muted))),
      );
    } else {
      corps = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: widget.compact ? 32 : 40,
          dataRowMaxHeight: widget.compact ? 48 : 64,
          columnSpacing: 20,
          horizontalMargin: 16,
          headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
          dataTextStyle: TextStyle(fontSize: fontSize, color: theme.colorScheme.onSurface),
          columns: [
            for (final c in widget.colonnes)
              DataColumn(
                headingRowAlignment: switch (c.align) {
                  TextAlign.right || TextAlign.end => MainAxisAlignment.end,
                  TextAlign.center => MainAxisAlignment.center,
                  _ => MainAxisAlignment.start,
                },
                label: Text(c.label, softWrap: false),
              ),
          ],
          rows: [
            for (var i = 0; i < visibles.length; i++)
              DataRow(
                key: widget.rowKey != null
                    ? ValueKey(widget.rowKey!(visibles[i], pageCourante * widget.pageSize + i))
                    : null,
                cells: [
                  for (final c in widget.colonnes)
                    DataCell(
                      Align(
                        alignment: switch (c.align) {
                          TextAlign.right || TextAlign.end => Alignment.centerRight,
                          TextAlign.center => Alignment.center,
                          _ => Alignment.centerLeft,
                        },
                        child: c.render != null
                            ? c.render!(visibles[i], pageCourante * widget.pageSize + i)
                            : Text('${c.brute(visibles[i]) ?? ''}', textAlign: c.align),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (enTete)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.titre != null)
                          Text(widget.titre!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (widget.description != null) ...[
                          const SizedBox(height: 2),
                          Text(widget.description!, style: TextStyle(fontSize: 12, color: muted)),
                        ],
                      ],
                    ),
                  ),
                  ?widget.actions,
                  if (widget.exportNom != null)
                    IconButton(
                      tooltip: 'Exporter en Excel',
                      visualDensity: VisualDensity.compact,
                      onPressed: total == 0 || widget.loading || _exporting ? null : _exporter,
                      icon: _exporting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_outlined, size: 18),
                    ),
                ],
              ),
            ),
          corps,
          if (!widget.loading && widget.error == null && pages > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${pageCourante * widget.pageSize + 1}–${(pageCourante + 1) * widget.pageSize > total ? total : (pageCourante + 1) * widget.pageSize} sur $total',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Page précédente',
                    visualDensity: VisualDensity.compact,
                    onPressed: pageCourante == 0 ? null : () => setState(() => _page = pageCourante - 1),
                    icon: const Icon(Icons.chevron_left, size: 18),
                  ),
                  Text('${pageCourante + 1}/$pages', style: TextStyle(fontSize: 12, color: muted)),
                  IconButton(
                    tooltip: 'Page suivante',
                    visualDensity: VisualDensity.compact,
                    onPressed: pageCourante >= pages - 1 ? null : () => setState(() => _page = pageCourante + 1),
                    icon: const Icon(Icons.chevron_right, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
