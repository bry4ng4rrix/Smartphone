import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_time.dart';
import '../../../models/reports.dart';
import '../../movements/movement_view_data.dart';
import 'report_printable.dart';

/// `exporterExcel(feuilles, nomFichier)` de components/reports/export.ts.
///
/// Adaptation mobile : le web déclenche le téléchargement d'un `.xlsx`
/// (lib JS `xlsx`) ; ici le classeur est construit avec le constructeur
/// maison de la page Mouvements ([buildMovementsXlsx]) puis partagé via la
/// feuille de partage du système. Nom : `{nom}_{AAAA-MM-JJ}.xlsx`
/// (`nomFichier.replace(/\s+/g, '_') + date`).
Future<void> partagerXlsx({
  required String nomFichier,
  required List<String> headers,
  required List<List<Object?>> rows,
  String? sheetName,
}) async {
  if (rows.isEmpty) return;
  final feuille = (sheetName ?? nomFichier).replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
  final bytes = buildMovementsXlsx(
    headers: headers,
    rows: rows,
    sheetName: feuille.length > 31 ? feuille.substring(0, 31) : feuille,
  );
  final nom = '${nomFichier.replaceAll(RegExp(r'\s+'), '_')}_${formatReportsDate(appToday())}.xlsx';
  final file = XFile.fromData(bytes, name: nom, mimeType: kXlsxMimeType);
  await SharePlus.instance.share(ShareParams(files: [file], text: nomFichier));
}

/// Police par défaut du paquet pdf (Helvetica, encodage WinAnsi) : les
/// flèches et le signe moins typographique n'y existent pas, on les remplace.
String _t(String s) => s.replaceAll('→', '->').replaceAll('−', '-').replaceAll('↗', '+').replaceAll('↘', '-');

/// « Imprimer / PDF » — `window.print()` du web devient un PDF A4 de la
/// section affichée : en-tête « Tableau de bord », ligne de période
/// (`Période du {from} au {to} (comparée à {prev_from} → {prev_to})`, le
/// bloc `print:block` du web), section, grille de KPI puis tableaux.
Future<void> imprimerRapport(ReportPrintable rapport, ReportPeriod period) async {
  final doc = pw.Document(title: 'Tableau de bord — ${rapport.sectionLabel}');
  final gris = PdfColor.fromInt(0xFF64748B);
  final bordure = PdfColor.fromInt(0xFFE2E8F0);

  pw.Widget kpi(PrintableKpi k) => pw.Container(
        width: 120,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: bordure), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_t(k.titre), style: pw.TextStyle(fontSize: 8, color: gris)),
            pw.SizedBox(height: 2),
            pw.Text(_t(k.valeur), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if (k.detail != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(_t(k.detail!), style: pw.TextStyle(fontSize: 7, color: gris)),
            ],
          ],
        ),
      );

  List<pw.Widget> table(PrintableTable t) => [
        pw.SizedBox(height: 12),
        pw.Text(_t(t.titre), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        if (t.rows.isEmpty)
          pw.Text('Aucune donnée sur la période.', style: pw.TextStyle(fontSize: 8, color: gris))
        else
          pw.TableHelper.fromTextArray(
            headers: t.headers.map(_t).toList(),
            data: [for (final r in t.rows) r.map(_t).toList()],
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
            border: pw.TableBorder.all(color: bordure, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          ),
      ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text('Tableau de bord', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(
          _t('Période du ${period.from} au ${period.to} (comparée à ${period.prevFrom} → ${period.prevTo})'),
          style: pw.TextStyle(fontSize: 8, color: gris),
        ),
        pw.SizedBox(height: 6),
        pw.RichText(
          text: pw.TextSpan(
            style: pw.TextStyle(fontSize: 10, color: gris),
            children: [
              pw.TextSpan(
                text: _t(rapport.sectionLabel),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
              pw.TextSpan(text: _t(' — ${rapport.sectionDescription}')),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        if (rapport.kpis.isNotEmpty) pw.Wrap(spacing: 8, runSpacing: 8, children: rapport.kpis.map(kpi).toList()),
        for (final t in rapport.tables) ...table(t),
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) => doc.save(),
    name: 'tableau_de_bord_${rapport.sectionLabel.replaceAll(RegExp(r'\s+'), '_')}_${formatReportsDate(appToday())}.pdf',
  );
}
