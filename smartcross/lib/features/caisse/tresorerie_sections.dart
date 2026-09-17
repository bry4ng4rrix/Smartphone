import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../models/finance.dart';
import '../../state/campaigns_provider.dart';
import '../../state/finance_provider.dart';
import '../../widgets/async_state_widgets.dart';

/// Sections « Trésorerie » de la caisse — port de
/// frontend/components/caisse/{indicateurs, section-gain, section-encaissements,
/// section-livraison, section-journal, section-epargne, section-boost}.tsx.
/// Tous les montants viennent de l'API ; l'app n'en recalcule aucun.

final _ar = NumberFormat('#,##0', 'fr_FR');
String fmtAr(num v) => '${_ar.format(v.round()).replaceAll(',', ' ')} Ar';
final _dayFmt = DateFormat('dd/MM/yyyy');
final _dateHeureFmt = DateFormat('dd/MM/yyyy HH:mm');
String fmtIso(String v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  return m == null ? v : '${m[3]}/${m[2]}/${m[1]}';
}

const kPos = Color(0xFF059669);
const kNeg = Color(0xFFDC2626);
const kWarn = Color(0xFFD97706);

Color _etatColor(String etat) => etat == 'perte' ? kNeg : etat == 'benefice' ? kPos : Colors.grey;

/// Carte titrée commune.
class _Carte extends StatelessWidget {
  const _Carte({required this.titre, this.description, this.action, required this.child});
  final String titre;
  final String? description;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                ?action,
              ],
            ),
            if (description != null) Padding(padding: const EdgeInsets.only(top: 2, bottom: 8), child: Text(description!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
            if (description == null) const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _ligne(BuildContext context, String label, String valeur, {String? op, bool fort = false, Color? couleur}) {
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        if (op != null) SizedBox(width: 16, child: Text(op, style: TextStyle(color: muted))),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: fort ? null : muted, fontWeight: fort ? FontWeight.w700 : null))),
        const SizedBox(width: 8),
        Text(valeur, style: TextStyle(fontSize: fort ? 15 : 13, fontWeight: fort ? FontWeight.w800 : FontWeight.w500, color: couleur)),
      ],
    ),
  );
}

// ----------------------------------------------------------------------------- //
// Indicateurs
// ----------------------------------------------------------------------------- //

class TresorerieIndicateurs extends StatelessWidget {
  const TresorerieIndicateurs({super.key, required this.ind});
  final FinanceIndicateurs ind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tuile(String titre, String valeur, String detail, {Color? couleur}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(valeur, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: couleur)),
                Text(detail, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
    return Column(
      children: [
        Row(children: [
          tuile('Espèces disponibles', fmtAr(ind.especeDisponible), 'solde de caisse − épargne', couleur: ind.especeDisponible < 0 ? kNeg : null),
          const SizedBox(width: 8),
          tuile('Solde de caisse', fmtAr(ind.soldeCaisse), ind.sessionOuverte ? 'session ouverte' : 'dernier montant compté'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          tuile('Argent en attente', fmtAr(ind.argentEnAttente), 'livreurs ${fmtAr(ind.attenteLivreurs)} · comptoir ${fmtAr(ind.attenteAEnregistrer)}', couleur: ind.argentEnAttente > 0 ? kWarn : null),
          const SizedBox(width: 8),
          tuile('Épargne accumulée', fmtAr(ind.epargne), ind.epargneCouverte ? 'couverte par la caisse' : 'NON couverte par la caisse', couleur: ind.epargneCouverte ? kPos : kNeg),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          tuile('Valeur du stock (achat)', fmtAr(ind.valeurStock), '${ind.quantiteStock} pièces · vente ${fmtAr(ind.valeurStockVente)}'),
        ]),
      ],
    );
  }
}

// ----------------------------------------------------------------------------- //
// Gain réel
// ----------------------------------------------------------------------------- //

class SectionGain extends StatelessWidget {
  const SectionGain({super.key, required this.d});
  final FinanceDashboard d;

  @override
  Widget build(BuildContext context) {
    final g = d.gain;
    final perte = g.gainReel < 0;
    final scheme = Theme.of(context).colorScheme;
    return _Carte(
      titre: 'Gain réel',
      description: '${fmtIso(d.periodeFrom)} → ${fmtIso(d.periodeTo)} · (prix de vente + livraison client) − prix d\'achat − frais de livraison acceptés (LIVRAISON 3K / 4K / 5K…) − part de boost.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${g.nbVentes} vente(s) livrée(s) · ${g.nbArticles} article(s)${g.nbPertes > 0 ? ' · ${g.nbPertes} à perte' : ''}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          _ligne(context, "Chiffre d'affaires (produits)", fmtAr(g.caProduits)),
          _ligne(context, 'Livraison facturée au client', fmtAr(g.livraisonClient), op: '+'),
          _ligne(context, "Coût d'achat", fmtAr(g.coutAchat), op: '−'),
          _ligne(context, 'Frais de livraison acceptés (LIVRAISON 3K / 4K / 5K…)', fmtAr(g.fraisAgence), op: '−'),
          _ligne(context, 'Boost / publicité (montant réparti sur les articles livrés de la période)', fmtAr(g.partBoost), op: '−'),
          Divider(color: scheme.outlineVariant),
          _ligne(context, perte ? 'PERTE RÉELLE' : 'GAIN RÉEL', fmtAr(g.gainReel), fort: true, couleur: perte ? kNeg : kPos),
          const SizedBox(height: 10),
          Text('Répartition (${d.pctReappro.round()} / ${d.pctEpargne.round()} / ${d.pctDepenses.round()} %)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          _ligne(context, 'Réapprovisionnement', fmtAr(g.reappro)),
          _ligne(context, 'Épargne (versée automatiquement)', fmtAr(g.epargne)),
          _ligne(context, 'Dépenses courantes', fmtAr(g.depenses)),
          if (perte) Text('Gain ≤ 0 : aucune part, aucun versement d\'épargne.', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------- //
// Encaissements en attente → remise en caisse
// ----------------------------------------------------------------------------- //

class SectionEncaissements extends ConsumerStatefulWidget {
  const SectionEncaissements({super.key, required this.enc, required this.magasinId, required this.sessionOuverte, required this.onChanged});
  final FinanceEncaissements enc;
  final int? magasinId;
  final bool sessionOuverte;
  final VoidCallback onChanged;

  @override
  ConsumerState<SectionEncaissements> createState() => _SectionEncaissementsState();
}

class _SectionEncaissementsState extends ConsumerState<SectionEncaissements> {
  int? _busy;

  Future<void> _remettre(EncaissementParLivreur l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remettre en caisse — ${l.nom}'),
        content: Text('${l.nb} vente(s) · brut ${fmtAr(l.brut)} − frais de tournée acceptés ${fmtAr(l.depenses)} = net ${fmtAr(l.net)}.\nUne entrée « Vente » par commande et une sortie par dépense seront ajoutées à la session ouverte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remettre')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = l.livreurId ?? 0);
    try {
      final r = await ref.read(financeRepositoryProvider).remise(magasinId: widget.magasinId, livreurId: l.livreurId, encaissementIds: l.livreurId == null ? [for (final e in widget.enc.lignes.where((e) => e.livreurId == null)) e.id] : null);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r.nb} vente(s) remise(s) — net ${fmtAr(r.net)}')));
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enc = widget.enc;
    final scheme = Theme.of(context).colorScheme;
    return _Carte(
      titre: 'Argent en attente (${fmtAr(enc.total)})',
      description: "Ventes livrées pas encore remises en caisse : chez les livreurs ${fmtAr(enc.chezLivreurs)} · comptoir / payé d'avance ${fmtAr(enc.aEnregistrer)}.${widget.sessionOuverte ? '' : ' Ouvrez une session de caisse pour remettre.'}",
      child: enc.parLivreur.isEmpty
          ? Text('Rien en attente.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
          : Column(
              children: [
                for (final l in enc.parLivreur)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${l.nb} vente(s) · brut ${fmtAr(l.brut)} · dépenses ${fmtAr(l.depenses)}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              Text('Net à remettre : ${fmtAr(l.net)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: widget.sessionOuverte && _busy == null ? () => _remettre(l) : null,
                          child: _busy == (l.livreurId ?? 0) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Remettre'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ----------------------------------------------------------------------------- //
// Résultats livraison
// ----------------------------------------------------------------------------- //

class SectionLivraison extends StatelessWidget {
  const SectionLivraison({super.key, required this.d});
  final FinanceDashboard d;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bloc(String titre, StatsLivraison s) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${s.nb} livraison(s)', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                _ligne(context, 'Facturé', fmtAr(s.facturee)),
                _ligne(context, 'Frais de livraison acceptés', fmtAr(s.agence)),
                _ligne(context, 'Résultat', fmtAr(s.resultat), fort: true, couleur: _etatColor(s.etat)),
              ],
            ),
          ),
        );
    return _Carte(
      titre: 'Résultats livraison',
      description: 'Livraison facturée au client − frais de livraison acceptés (dépenses des livreurs de type LIVRAISON 3K / 4K / 5K… validées par le gérant).',
      child: Column(
        children: [
          Row(children: [bloc("Aujourd'hui", d.livraisonJour), const SizedBox(width: 8), bloc('Semaine', d.livraisonSemaine)]),
          const SizedBox(height: 8),
          Row(children: [bloc('Mois', d.livraisonMois), const SizedBox(width: 8), bloc('Période', d.livraisonPeriode)]),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------- //
// Journal de caisse (avec filtres)
// ----------------------------------------------------------------------------- //

class SectionJournal extends StatefulWidget {
  const SectionJournal({super.key, required this.async, required this.onRetry});
  final AsyncValue<List<JournalLigne>> async;
  final VoidCallback onRetry;

  @override
  State<SectionJournal> createState() => _SectionJournalState();
}

enum _Sens { tous, entrees, sorties }

class _SectionJournalState extends State<SectionJournal> {
  DateTime? _date;
  _Sens _sens = _Sens.tous;
  String? _origine;
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _q = TextEditingController();

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _q.dispose();
    super.dispose();
  }

  bool get _actif => _date != null || _sens != _Sens.tous || _origine != null || _min.text.isNotEmpty || _max.text.isNotEmpty || _q.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return widget.async.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(message: ApiClient.messageFromError(e), onRetry: widget.onRetry),
      data: (toutes) {
        final origines = <String, String>{for (final l in toutes) l.origine: l.origineLabel};
        final q = _q.text.trim().toLowerCase();
        final min = double.tryParse(_min.text.replaceAll(' ', ''));
        final max = double.tryParse(_max.text.replaceAll(' ', ''));
        final lignes = toutes.where((l) {
          if (_date != null) {
            final d = l.date;
            if (d == null) return false;
            final jour = appDay(d);
            if (jour.year != _date!.year || jour.month != _date!.month || jour.day != _date!.day) return false;
          }
          if (_sens == _Sens.entrees && !l.isIn) return false;
          if (_sens == _Sens.sorties && l.isIn) return false;
          if (_origine != null && l.origine != _origine) return false;
          if (min != null && l.montant < min) return false;
          if (max != null && l.montant > max) return false;
          if (q.isNotEmpty && ![l.libelle, l.reference, l.categorie, l.auteur, l.origineLabel, l.montant.toStringAsFixed(0)].join(' ').toLowerCase().contains(q)) return false;
          return true;
        }).toList();
        final entrees = lignes.where((l) => l.isIn).fold<double>(0, (a, l) => a + l.montant);
        final sorties = lignes.where((l) => !l.isIn).fold<double>(0, (a, l) => a + l.montant);
        Widget champ(Widget c, {double width = 150}) => SizedBox(width: width, child: c);
        return _Carte(
          titre: 'Journal des mouvements de caisse',
          description: "Entrées et sorties de la période avec le solde après chaque mouvement (le solde repart du fond d'ouverture à chaque session).",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  champ(OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: _date ?? appToday(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (d != null) setState(() => _date = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_date == null ? 'Date' : _dayFmt.format(_date!)),
                  )),
                  champ(DropdownButtonFormField<_Sens>(
                    key: ValueKey('sens-$_sens'),
                    initialValue: _sens,
                    decoration: const InputDecoration(labelText: 'Sens', isDense: true),
                    items: const [
                      DropdownMenuItem(value: _Sens.tous, child: Text('Entrées + sorties')),
                      DropdownMenuItem(value: _Sens.entrees, child: Text('Entrées')),
                      DropdownMenuItem(value: _Sens.sorties, child: Text('Sorties')),
                    ],
                    onChanged: (v) => setState(() => _sens = v ?? _Sens.tous),
                  )),
                  champ(DropdownButtonFormField<String?>(
                    key: ValueKey('type-$_origine'),
                    initialValue: _origine,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tous les types')),
                      for (final e in origines.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _origine = v),
                  ), width: 190),
                  champ(TextField(controller: _min, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant min (Ar)', isDense: true), onChanged: (_) => setState(() {})), width: 140),
                  champ(TextField(controller: _max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant max (Ar)', isDense: true), onChanged: (_) => setState(() {})), width: 140),
                  champ(TextField(controller: _q, decoration: const InputDecoration(labelText: 'Recherche', hintText: 'Nom, n° de commande, référence, auteur…', isDense: true, prefixIcon: Icon(Icons.search, size: 18)), onChanged: (_) => setState(() {})), width: 260),
                  if (_actif)
                    TextButton.icon(
                      onPressed: () => setState(() { _date = null; _sens = _Sens.tous; _origine = null; _min.clear(); _max.clear(); _q.clear(); }),
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Réinitialiser'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('${lignes.length} mouvement(s)${_actif ? ' sur ${toutes.length}' : ''} · entrées +${fmtAr(entrees)} · sorties −${fmtAr(sorties)}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              if (lignes.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Center(child: Text(_actif ? 'Aucun mouvement ne correspond à ces filtres.' : 'Aucun mouvement de caisse sur la période.', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))))
              else
                for (final l in lignes)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(l.isIn ? Icons.arrow_circle_up : Icons.arrow_circle_down, size: 20, color: l.isIn ? kPos : kNeg),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.libelle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              Text('${l.date == null ? '' : _dateHeureFmt.format(appLocal(l.date!))}${l.auteur.isNotEmpty ? ' · ${l.auteur}' : ''}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              Wrap(
                                spacing: 6,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: l.automatique ? scheme.primary : null, border: Border.all(color: l.automatique ? scheme.primary : scheme.outlineVariant), borderRadius: BorderRadius.circular(999)),
                                    child: Text(l.origineLabel, style: TextStyle(fontSize: 10, color: l.automatique ? scheme.onPrimary : null)),
                                  ),
                                  if (l.categorie.isNotEmpty) Text(l.categorie, style: const TextStyle(fontSize: 10)),
                                  if (l.reference.isNotEmpty) Text(l.reference, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${l.isIn ? '+' : '−'}${fmtAr(l.montant)}', style: TextStyle(fontWeight: FontWeight.w700, color: l.isIn ? kPos : kNeg)),
                            Text('Solde ${fmtAr(l.soldeApres)}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------- //
// Ventes (résultat par vente)
// ----------------------------------------------------------------------------- //

class SectionVentes extends StatelessWidget {
  const SectionVentes({super.key, required this.async, required this.onRetry});
  final AsyncValue<List<VenteLigne>> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(message: ApiClient.messageFromError(e), onRetry: onRetry),
      data: (ventes) => _Carte(
        titre: 'Ventes de la période (${ventes.length})',
        description: 'Gain réel de chaque vente livrée et sa répartition.',
        child: ventes.isEmpty
            ? Text('Aucune vente livrée sur la période.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
            : Column(
                children: [
                  for (final v in ventes)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('${v.numero} — ${v.client}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, decoration: v.annule ? TextDecoration.lineThrough : null))),
                              Text(fmtAr(v.gainReel), style: TextStyle(fontWeight: FontWeight.w800, color: _etatColor(v.etat))),
                            ],
                          ),
                          Text('${fmtIso(v.dateVente)}${v.livreur.isNotEmpty ? ' · ${v.livreur}' : ''} · ${v.nbArticles} article(s)${v.encaissement.isNotEmpty ? ' · ${v.encaissement}' : ''}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          Text('Client ${fmtAr(v.totalClient)} − achat ${fmtAr(v.coutAchat)} − livraison ${fmtAr(v.fraisAgence)} − boost ${fmtAr(v.partBoost)}', style: const TextStyle(fontSize: 11)),
                          Text('Réappro ${fmtAr(v.partReappro)} · épargne ${fmtAr(v.partEpargne)} · dépenses ${fmtAr(v.partDepenses)}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- //
// Épargne
// ----------------------------------------------------------------------------- //

class SectionEpargne extends ConsumerStatefulWidget {
  const SectionEpargne({super.key, required this.magasinId, required this.async, required this.versePeriode, required this.retirePeriode, required this.onChanged});
  final int? magasinId;
  final AsyncValue<({double solde, List<EpargneMouvement> historique})> async;
  final double versePeriode;
  final double retirePeriode;
  final VoidCallback onChanged;

  @override
  ConsumerState<SectionEpargne> createState() => _SectionEpargneState();
}

class _SectionEpargneState extends ConsumerState<SectionEpargne> {
  Future<void> _retrait(double solde) async {
    final montant = TextEditingController();
    final motif = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Retrait d'épargne"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Solde disponible : ${fmtAr(solde)}. Le retrait sort de l\'épargne (pas de la caisse).', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(controller: montant, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Montant (Ar)', isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: motif, decoration: const InputDecoration(labelText: 'Motif', isDense: true)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    final m = double.tryParse(montant.text.replaceAll(' ', ''));
    if (m == null || m <= 0) return;
    try {
      await ref.read(financeRepositoryProvider).retraitEpargne(magasinId: widget.magasinId, montant: m, motif: motif.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retrait de ${fmtAr(m)} enregistré')));
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return widget.async.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(message: ApiClient.messageFromError(e), onRetry: widget.onChanged),
      data: (ep) => _Carte(
        titre: 'Épargne',
        description: 'Part d\'épargne de chaque vente versée automatiquement. Période : versé ${fmtAr(widget.versePeriode)} · retiré ${fmtAr(widget.retirePeriode)}.',
        action: OutlinedButton.icon(onPressed: ep.solde > 0 ? () => _retrait(ep.solde) : null, icon: const Icon(Icons.savings_outlined, size: 18), label: const Text('Retrait')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fmtAr(ep.solde), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPos)),
            const SizedBox(height: 8),
            if (ep.historique.isEmpty) Text('Aucun mouvement d\'épargne.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            for (final m in ep.historique.take(50))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m.typeLabel}${m.orderNumero.isNotEmpty ? ' · ${m.orderNumero}' : ''}${m.motif.isNotEmpty ? ' · ${m.motif}' : ''}', style: const TextStyle(fontSize: 13)),
                          Text('${m.createdAt == null ? '' : _dateHeureFmt.format(appLocal(m.createdAt!))}${m.createdByName.isNotEmpty ? ' · ${m.createdByName}' : ''}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${m.montant >= 0 ? '+' : '−'}${fmtAr(m.montant.abs())}', style: TextStyle(fontWeight: FontWeight.w700, color: m.montant >= 0 ? kPos : kNeg)),
                        Text('Solde ${fmtAr(m.soldeApres)}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- //
// Boost / publicité
// ----------------------------------------------------------------------------- //

class SectionBoost extends ConsumerStatefulWidget {
  const SectionBoost({super.key, required this.boosts, required this.magasinId, required this.sessionOuverte, required this.onChanged});
  final List<FinanceBoost> boosts;
  final int? magasinId;
  final bool sessionOuverte;
  final VoidCallback onChanged;

  @override
  ConsumerState<SectionBoost> createState() => _SectionBoostState();
}

class _SectionBoostState extends ConsumerState<SectionBoost> {
  Future<void> _nouveau() async {
    final nom = TextEditingController();
    final montant = TextEditingController();
    String plateforme = 'FACEBOOK';
    var debut = appToday();
    DateTime? fin;
    var enCaisse = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nouveau boost'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Les commandes entre les deux dates seront rattachées automatiquement au boost ; le coût par article se calcule seul.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 10),
                TextField(controller: nom, autofocus: true, decoration: const InputDecoration(labelText: 'Nom', hintText: 'Ex : Boost Facebook semaine 37', isDense: true)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: plateforme,
                  decoration: const InputDecoration(labelText: 'Plateforme', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'FACEBOOK', child: Text('Facebook')),
                    DropdownMenuItem(value: 'INSTAGRAM', child: Text('Instagram')),
                    DropdownMenuItem(value: 'TIKTOK', child: Text('TikTok')),
                    DropdownMenuItem(value: 'GOOGLE', child: Text('Google')),
                    DropdownMenuItem(value: 'AUTRE', child: Text('Autre')),
                  ],
                  onChanged: (v) => setD(() => plateforme = v ?? 'FACEBOOK'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(context: ctx, initialDate: debut, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (d != null) setD(() => debut = d);
                        },
                        child: Text('Début ${_dayFmt.format(debut)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(context: ctx, initialDate: fin ?? debut, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (d != null) setD(() => fin = d);
                        },
                        child: Text(fin == null ? 'Fin : en cours' : 'Fin ${_dayFmt.format(fin!)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: montant, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant total du boost (Ar)', isDense: true)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Enregistrer la sortie en caisse', style: TextStyle(fontSize: 13)),
                  subtitle: Text(widget.sessionOuverte ? 'Une sortie « Boost » sera ajoutée à la session ouverte.' : 'Caisse fermée : impossible maintenant.', style: const TextStyle(fontSize: 11)),
                  value: enCaisse,
                  onChanged: widget.sessionOuverte ? (v) => setD(() => enCaisse = v ?? false) : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final m = double.tryParse(montant.text.replaceAll(' ', ''));
    if (nom.text.trim().isEmpty || m == null || m <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nom et montant sont requis.')));
      return;
    }
    try {
      await ref.read(campaignsRepositoryProvider).create({
        'nom': nom.text.trim(),
        'plateforme': plateforme,
        'montant': m,
        'date_debut': debut.toIso8601String().substring(0, 10),
        'date_fin': fin?.toIso8601String().substring(0, 10),
        'type_periode': 'PERSONNALISE',
        'en_caisse': enCaisse,
        'magasin_id': ?widget.magasinId,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Boost enregistré — les gains de la période sont recalculés')));
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Carte(
      titre: 'Boost / publicité',
      description: 'Une dépense globale par période, rattachée automatiquement aux commandes de la période et répartie sur les articles réellement livrés (coût par article = montant / articles livrés).',
      action: FilledButton.icon(onPressed: _nouveau, icon: const Icon(Icons.add, size: 18), label: const Text('Nouveau')),
      child: widget.boosts.isEmpty
          ? Text('Aucun boost sur la période.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
          : Column(
              children: [
                for (final b in widget.boosts)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(b.nom, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(fmtAr(b.montant), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        Text('${b.plateformeLabel} · ${fmtIso(b.dateDebut)} → ${b.dateFin == null ? 'en cours' : fmtIso(b.dateFin!)}${b.enCaisse ? ' · sortie en caisse' : ' · hors caisse'}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        Text('${b.nbCommandes} commande(s) concernée(s) (${b.nbLivrees} livrées) · CA ${fmtAr(b.ca)}${b.coutParCommande != null ? ' · ${fmtAr(b.coutParCommande!)} / commande' : ''}', style: const TextStyle(fontSize: 12)),
                        Text('${b.articlesVendus} article(s) vendu(s) · coût / article : ${b.articlesVendus > 0 ? fmtAr(b.coutParArticle) : 'aucun article vendu'}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
