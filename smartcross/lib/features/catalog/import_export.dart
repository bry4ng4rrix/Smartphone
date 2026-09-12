import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/catalog_provider.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

void _toast(BuildContext context, String message, {Duration? duration}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: duration ?? const Duration(seconds: 4)),
  );
}

/// Remplace le téléchargement navigateur (`<a download>`) : le fichier est
/// remis au système via la feuille de partage (enregistrer dans Fichiers,
/// envoyer par e-mail/WhatsApp, ouvrir dans Excel…).
Future<void> _shareXlsx(Uint8List bytes, String filename, String text) {
  final file = XFile.fromData(bytes, name: filename, mimeType: _xlsxMime);
  return SharePlus.instance.share(ShareParams(files: [file], text: text));
}

/// `GET catalog/references/export-excel/` → fichier .xlsx (une ligne par
/// variante) remis à la feuille de partage. Erreur → toast
/// « Erreur lors de l'export » (ou le message serveur).
Future<void> exportCatalogExcel(BuildContext context, WidgetRef ref) async {
  try {
    final result = await ref.read(catalogHubProvider).exportExcel();
    await _shareXlsx(result.bytes, result.filename, 'Export catalogue');
  } catch (e) {
    if (context.mounted) _toast(context, catalogErrorMessage(e, "Erreur lors de l'export"));
  }
}

/// Ce que la revue post-import renvoie à l'écran (tous les cas ferment la
/// revue ; seul « Annuler l'import » a fait un appel réseau).
enum ImportReviewAction {
  /// « Enregistrer » : l'import est conservé tel quel.
  keep,

  /// « Modifier » : l'import est conservé ET la recherche doit être
  /// préremplie sur [ImportReviewOutcome.searchPrefill].
  edit,

  /// « Annuler l'import » : le lot a été défait côté serveur.
  cancelled,
}

class ImportReviewOutcome {
  const ImportReviewOutcome(this.action, {this.searchPrefill});

  final ImportReviewAction action;
  final String? searchPrefill;
}

/// Sélectionne un .xlsx, l'envoie à `POST catalog/references/import-excel/`,
/// repartage le fichier annoté (colonnes Statut + Date par ligne, pour
/// reprendre l'import plus tard sans repartir du début), signale les lignes
/// en erreur, puis ouvre la revue post-import (« Résumé de l'import »).
///
/// [existingNames] : « Marque Référence » des références déjà chargées
/// AVANT l'import — sert à repérer les quasi-doublons parmi les nouvelles.
///
/// Renvoie `null` si l'utilisateur n'a pas choisi de fichier ou si l'import
/// a échoué (toast affiché), sinon la décision prise dans la revue.
Future<ImportReviewOutcome?> importCatalogExcel(
  BuildContext context,
  WidgetRef ref, {
  required List<String> existingNames,
}) async {
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
  } catch (e) {
    if (context.mounted) _toast(context, "Impossible d'ouvrir le sélecteur de fichiers.");
    return null;
  }
  if (picked == null) return null; // Annulé par l'utilisateur.

  final ExcelImportResult result;
  try {
    final bytes = await picked.readAsBytes();
    // L'import est déjà enregistré en base au retour de cet appel (voir
    // catalog/views.py::import_excel) ; le catalogue complet est rechargé
    // par le hub.
    result = await ref.read(catalogHubProvider).importExcel(bytes, picked.name);
  } catch (e) {
    if (context.mounted) _toast(context, catalogErrorMessage(e, "Erreur lors de l'import"));
    return null;
  }
  if (!context.mounted) return null;

  if (result.errorsCount > 0) {
    _toast(
      context,
      '${result.errorsCount} ligne(s) en erreur — voir la colonne "Statut" du fichier téléchargé.',
      duration: const Duration(seconds: 10),
    );
  }

  // Le fichier renvoyé porte une colonne Statut + Date sur chaque ligne
  // traitée — le repartager permet de reprendre plus tard sans revenir au
  // début (les lignes déjà marquées seront sautées).
  try {
    await _shareXlsx(result.bytes, result.filename, "Résultat de l'import catalogue");
  } catch (_) {
    // Partage refusé/indisponible : l'import reste valide, la revue suit.
  }
  if (!context.mounted) return null;

  // Fermer la revue sans choisir = « Enregistrer » (l'import est déjà en
  // base, aucun appel réseau).
  final outcome = await showDialog<ImportReviewOutcome>(
    context: context,
    builder: (_) => ImportReviewDialog(result: result, existingNames: existingNames),
  );
  return outcome ?? const ImportReviewOutcome(ImportReviewAction.keep);
}

// =============================================================================
// Revue post-import
// =============================================================================

/// Alerte de quasi-doublon : une référence créée par l'import ressemble à
/// une référence déjà présente.
class DuplicateWarning {
  const DuplicateWarning({required this.nouvelle, required this.ressembleA, required this.raison});

  final String nouvelle;
  final String ressembleA;
  final String raison;
}

String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_./]+'), '');

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = math.min(math.min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Repère, parmi les références nouvellement créées, celles qui ressemblent
/// fortement à une référence existante : même nom à un espace/tiret près,
/// modèle très proche (« A05 » vs « A05S »), ou faute de frappe probable.
///
/// La correspondance exacte/insensible à la casse est déjà gérée côté
/// serveur (`_match_ci`) : il ne reste que les quasi-doublons qu'une
/// comparaison stricte ne voit pas. Au plus une alerte par nouvelle
/// référence (la plus proche).
List<DuplicateWarning> findNearDuplicates(List<String> newNames, List<String> existingNames) {
  final warnings = <DuplicateWarning>[];
  final existing = [
    for (final e in existingNames)
      if (e.trim().isNotEmpty) (raw: e, norm: _normalize(e)),
  ];

  for (final nouvelle in newNames) {
    final n = _normalize(nouvelle);
    if (n.isEmpty) continue;
    DuplicateWarning? best;
    var bestScore = 1 << 30;

    for (final e in existing) {
      final String raison;
      final int score;
      if (e.norm == n) {
        raison = 'même nom à un espace, un tiret ou une casse près';
        score = 0;
      } else {
        final shorter = e.norm.length < n.length ? e.norm : n;
        final longer = identical(shorter, n) ? e.norm : n;
        final diff = longer.length - shorter.length;
        if (diff >= 1 && diff <= 2 && longer.startsWith(shorter) && shorter.length >= 3) {
          raison = 'modèle très proche (« ${e.raw} » / « $nouvelle ») — variante réelle ou erreur de saisie ?';
          score = diff;
        } else {
          final maxDistance = n.length >= 8 ? 2 : 1;
          final distance = _levenshtein(n, e.norm);
          if (distance <= maxDistance) {
            raison = 'faute de frappe probable ($distance caractère${distance > 1 ? 's' : ''} de différence)';
            score = distance;
          } else {
            continue;
          }
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = DuplicateWarning(nouvelle: nouvelle, ressembleA: e.raw, raison: raison);
      }
    }
    if (best != null) warnings.add(best);
  }
  return warnings;
}

enum _AnalysisStatus { loading, done, skipped }

/// « Résumé de l'import » : ce qui vient d'être créé/mis à jour (déjà en
/// base), les lignes ignorées/en erreur, l'analyse des quasi-doublons, puis
/// trois décisions — Annuler l'import (défait le lot côté serveur),
/// Modifier (garde et préremplit la recherche), Enregistrer (garde).
class ImportReviewDialog extends ConsumerStatefulWidget {
  const ImportReviewDialog({super.key, required this.result, required this.existingNames});

  final ExcelImportResult result;
  final List<String> existingNames;

  @override
  ConsumerState<ImportReviewDialog> createState() => _ImportReviewDialogState();
}

class _ImportReviewDialogState extends ConsumerState<ImportReviewDialog> {
  _AnalysisStatus _status = _AnalysisStatus.loading;
  List<DuplicateWarning> _warnings = const [];
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    if (widget.result.newReferenceNames.isEmpty) {
      _status = _AnalysisStatus.skipped;
    } else {
      // Analyse locale (pas d'inférence distante) : lancée hors du build
      // pour que la revue s'affiche d'abord avec « Analyse en cours… ».
      Future<List<DuplicateWarning>>(
        () => findNearDuplicates(widget.result.newReferenceNames, widget.existingNames),
      ).then((warnings) {
        if (!mounted) return;
        setState(() {
          _warnings = warnings;
          _status = _AnalysisStatus.done;
        });
      }).catchError((_) {
        // Analyse non concluante : l'import reste valide.
        if (mounted) setState(() => _status = _AnalysisStatus.done);
      });
    }
  }

  Future<void> _cancelImport() async {
    final batchId = widget.result.batchId;
    if (batchId == null) {
      Navigator.of(context).pop(const ImportReviewOutcome(ImportReviewAction.keep));
      return;
    }
    setState(() => _cancelling = true);
    try {
      await ref.read(catalogHubProvider).cancelImportBatch(batchId);
      if (!mounted) return;
      _toast(context, 'Import annulé — les données ajoutées/modifiées ont été retirées de la base.');
      Navigator.of(context).pop(const ImportReviewOutcome(ImportReviewAction.cancelled));
    } catch (e) {
      if (mounted) _toast(context, catalogErrorMessage(e, "Erreur lors de l'annulation de l'import"));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _keep() {
    _toast(context, 'Import conservé.');
    Navigator.of(context).pop(const ImportReviewOutcome(ImportReviewAction.keep));
  }

  void _edit() {
    // Idem « Enregistrer » côté base (déjà écrit) — en plus, la recherche
    // est préremplie sur la première référence touchée pour la corriger
    // directement.
    final touched = <String>{...widget.result.newReferenceNames, ...widget.result.updatedReferenceNames};
    final first = touched.isEmpty ? null : touched.first;
    if (first != null) {
      _toast(context, 'Import conservé — recherche préremplie sur les références touchées, ajustez-la pour voir les autres.');
    }
    Navigator.of(context).pop(ImportReviewOutcome(ImportReviewAction.edit, searchPrefill: first));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final r = widget.result;

    Widget countCard(String title, Color color, int refs, int variants) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                Text('$refs référence(s)'),
                Text('$variants couleur(s)'),
              ],
            ),
          ),
        );

    return AlertDialog(
      title: const Text("Résumé de l'import"),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Déjà enregistré en base. Vérifiez, puis confirmez, modifiez ou annulez (l'annulation retire ces changements de la base).",
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  countCard('Ajouté', Colors.green.shade700, r.createdReferences, r.createdVariants),
                  const SizedBox(width: 12),
                  countCard('Mis à jour', Colors.blue.shade700, r.updatedReferences, r.updatedVariants),
                ],
              ),
              if (r.newReferenceNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Nouvelles références :', style: TextStyle(color: muted)),
                Text(r.newReferenceNames.join(', '), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              if (r.updatedReferenceNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Références mises à jour :', style: TextStyle(color: muted)),
                Text(r.updatedReferenceNames.join(', '), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              if (r.skippedCount > 0) ...[
                const SizedBox(height: 12),
                Text('${r.skippedCount} ligne(s) déjà traitée(s) ignorée(s).', style: TextStyle(color: muted)),
              ],
              if (r.errorsCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${r.errorsCount} ligne(s) en erreur — voir le fichier téléchargé.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Analyse des quasi-doublons', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    switch (_status) {
                      _AnalysisStatus.loading => Text('Analyse en cours…', style: TextStyle(color: muted)),
                      _AnalysisStatus.skipped => Text('Aucune nouvelle référence à vérifier.', style: TextStyle(color: muted)),
                      _AnalysisStatus.done when _warnings.isEmpty => Text('Aucun doublon suspect détecté.', style: TextStyle(color: muted)),
                      _AnalysisStatus.done => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final w in _warnings)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: '"${w.nouvelle}"', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const TextSpan(text: ' ressemble à '),
                                      TextSpan(text: '"${w.ressembleA}"', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (w.raison.isNotEmpty) TextSpan(text: ' — ${w.raison}'),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                    },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: _cancelling ? null : _cancelImport,
          child: Text(_cancelling ? 'Annulation...' : "Annuler l'import"),
        ),
        OutlinedButton(onPressed: _cancelling ? null : _edit, child: const Text('Modifier')),
        FilledButton(onPressed: _cancelling ? null : _keep, child: const Text('Enregistrer')),
      ],
    );
  }
}
