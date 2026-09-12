import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/app_time.dart';
import '../../../models/campaign.dart';
import '../../../models/reports.dart';
import '../../../state/campaigns_provider.dart';

/// Dialogues « Nouvelle campagne » / « Modifier la campagne » et
/// « Supprimer la campagne » de components/reports/section-marketing.tsx.
///
/// Les écritures passent par [campaignsProvider] (`campaigns.create / update /
/// delete` du web) qui invalide lui-même le cache des rapports : la section
/// Marketing affichée se recharge alors silencieusement (adaptation du
/// `invalidateReports(); reload();` du web).

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// `String(r.depenses)` du web : entier sans décimale quand la valeur est
/// entière.
String _montantTexte(num v) => v == v.truncate() ? '${v.toInt()}' : '$v';

/// Ouvre le formulaire de campagne ; [campagne] = modification (les champs
/// repartent de la ligne du rapport, la note vide comme sur le web), sinon
/// création. Renvoie `true` si une campagne a été enregistrée.
Future<bool> showCampaignDialog(BuildContext context, {Campagne? campagne}) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => CampaignDialog(campagne: campagne));
  return ok ?? false;
}

/// Ouvre la confirmation de suppression. Renvoie `true` si la campagne a été
/// supprimée.
Future<bool> showCampaignDeleteDialog(BuildContext context, Campagne campagne) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => CampaignDeleteDialog(campagne: campagne));
  return ok ?? false;
}

/// Formulaire `Formulaire` du web : nom, plateforme, dépense, début, fin
/// (facultatif), note.
class CampaignDialog extends ConsumerStatefulWidget {
  const CampaignDialog({super.key, this.campagne});

  final Campagne? campagne;

  @override
  ConsumerState<CampaignDialog> createState() => _CampaignDialogState();
}

class _CampaignDialogState extends ConsumerState<CampaignDialog> {
  late final TextEditingController _nomCtrl;
  late final TextEditingController _montantCtrl;
  late final TextEditingController _noteCtrl;
  late String _plateforme;
  late String _dateDebut;
  late String _dateFin;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    final c = widget.campagne;
    // `vide()` du web : plateforme Facebook, début = aujourd'hui (Antananarivo).
    _nomCtrl = TextEditingController(text: c?.nom ?? '');
    _montantCtrl = TextEditingController(text: c == null ? '' : _montantTexte(c.depenses));
    _noteCtrl = TextEditingController();
    _plateforme = c?.plateforme ?? kPlateformes.first.code;
    _dateDebut = c?.dateDebut ?? formatReportsDate(appToday());
    _dateFin = c?.dateFin ?? '';
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _montantCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// `<Input type="date">` : la fin ne peut précéder le début (`min`).
  Future<void> _choisirDate({required bool debut}) async {
    final min = debut ? DateTime(2020) : (DateTime.tryParse(_dateDebut) ?? DateTime(2020));
    final max = DateTime(2100);
    final courante = DateTime.tryParse(debut ? _dateDebut : _dateFin) ?? appToday();
    final init = courante.isBefore(min) ? min : (courante.isAfter(max) ? max : courante);
    final choix = await showDatePicker(context: context, initialDate: init, firstDate: min, lastDate: max);
    if (choix == null || !mounted) return;
    setState(() {
      if (debut) {
        _dateDebut = formatReportsDate(choix);
      } else {
        _dateFin = formatReportsDate(choix);
      }
    });
  }

  /// `enregistrer` du web.
  Future<void> _enregistrer() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty || _dateDebut.isEmpty) {
      _toast(context, 'Nom et date de début sont requis');
      return;
    }
    setState(() => _enCours = true);
    try {
      final payload = <String, dynamic>{
        'nom': nom,
        'plateforme': _plateforme,
        // `Number(f.montant) || 0`.
        'montant': num.tryParse(_montantCtrl.text.trim()) ?? 0,
        'date_debut': _dateDebut,
        'date_fin': _dateFin.isEmpty ? null : _dateFin,
        'note': _noteCtrl.text,
      };
      final notifier = ref.read(campaignsProvider.notifier);
      final id = widget.campagne?.id;
      if (id != null) {
        await notifier.updateCampaign(id, payload);
      } else {
        await notifier.create(payload);
      }
      if (!mounted) return;
      _toast(context, id != null ? 'Campagne modifiée' : 'Campagne créée');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modification = widget.campagne != null;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.campaign_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(modification ? 'Modifier la campagne' : 'Nouvelle campagne')),
        ],
      ),
      content: SizedBox(
        width: 448,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nomCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom', hintText: 'Ex: Boost coques iPhone – septembre'),
              ),
              const SizedBox(height: 12),
              // `grid-cols-2` du web : plateforme et dépense côte à côte.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _plateforme,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Plateforme'),
                      items: [for (final p in kPlateformes) DropdownMenuItem(value: p.code, child: Text(p.label))],
                      onChanged: (v) {
                        if (v != null) setState(() => _plateforme = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _montantCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      // `type="number" min={0}` : chiffres et point décimal.
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: const InputDecoration(labelText: 'Dépense (Ar)', hintText: '0'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ChampDate(
                      label: 'Début',
                      valeur: _dateDebut,
                      onTap: () => _choisirDate(debut: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ChampDate(
                      label: 'Fin (facultatif)',
                      valeur: _dateFin,
                      onTap: () => _choisirDate(debut: false),
                      onEffacer: _dateFin.isEmpty ? null : () => setState(() => _dateFin = ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                minLines: 2,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _enregistrer,
          child: Text(_enCours ? 'Enregistrement…' : 'Enregistrer'),
        ),
      ],
    );
  }
}

/// `<Input type="date">` : libellé + valeur, ouvre le sélecteur de date ;
/// [onEffacer] (facultatif) vide le champ.
class _ChampDate extends StatelessWidget {
  const _ChampDate({required this.label, required this.valeur, required this.onTap, this.onEffacer});

  final String label;
  final String valeur;
  final VoidCallback onTap;
  final VoidCallback? onEffacer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onEffacer != null
              ? IconButton(
                  tooltip: 'Effacer',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEffacer,
                  icon: const Icon(Icons.close, size: 16),
                )
              : Icon(Icons.calendar_today_outlined, size: 16, color: muted),
        ),
        child: Text(
          valeur.isEmpty ? 'jj/mm/aaaa' : fmtDate(valeur),
          style: TextStyle(color: valeur.isEmpty ? muted : theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

/// Confirmation « Supprimer la campagne « {nom} » ? ».
class CampaignDeleteDialog extends ConsumerStatefulWidget {
  const CampaignDeleteDialog({super.key, required this.campagne});

  final Campagne campagne;

  @override
  ConsumerState<CampaignDeleteDialog> createState() => _CampaignDeleteDialogState();
}

class _CampaignDeleteDialogState extends ConsumerState<CampaignDeleteDialog> {
  bool _enCours = false;

  /// `supprimer` du web.
  Future<void> _supprimer() async {
    setState(() => _enCours = true);
    try {
      await ref.read(campaignsProvider.notifier).delete(widget.campagne.id);
      if (!mounted) return;
      _toast(context, 'Campagne supprimée');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Supprimer la campagne « ${widget.campagne.nom} » ?'),
      content: Text(
        'Les commandes rattachées ne seront pas supprimées, elles perdront seulement leur campagne.',
        style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
      ),
      actions: [
        OutlinedButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _enCours ? null : _supprimer,
          child: const Text('Supprimer'),
        ),
      ],
    );
  }
}
