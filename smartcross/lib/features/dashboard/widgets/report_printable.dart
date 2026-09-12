/// Modèle imprimable d'une section du tableau de bord.
///
/// Adaptation mobile : le bouton « Imprimer / PDF » du web appelle
/// `window.print()` sur la page affichée ; ici chaque section décrit son
/// contenu (KPI + tableaux, avec les mêmes colonnes que l'écran) et
/// `imprimerRapport` (report_export.dart) en fait un PDF.
library;

/// Un indicateur : titre, valeur, détail facultatif.
class PrintableKpi {
  const PrintableKpi(this.titre, this.valeur, [this.detail]);

  final String titre;
  final String valeur;
  final String? detail;
}

/// Un tableau : titre, en-têtes, lignes de cellules déjà formatées.
class PrintableTable {
  const PrintableTable({required this.titre, required this.headers, required this.rows});

  final String titre;
  final List<String> headers;
  final List<List<String>> rows;
}

class ReportPrintable {
  const ReportPrintable({
    required this.sectionLabel,
    required this.sectionDescription,
    this.kpis = const [],
    this.tables = const [],
  });

  final String sectionLabel;
  final String sectionDescription;
  final List<PrintableKpi> kpis;
  final List<PrintableTable> tables;
}
