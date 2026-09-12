import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/expense.dart';
import '../../state/expenses_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;
import '../settings/expense_types_crud.dart'
    show crudErrorMessage, montantEnSaisie, montantInputFormatters, parseMontantOuZero;

/// Couleur du statut d'une dépense — `STATUT_DEPENSE` de la page /bilan du
/// web : ambre en attente, émeraude acceptée, rouge rejetée.
Color expenseStatusColor(BuildContext context, ExpenseStatus statut) {
  switch (statut) {
    case ExpenseStatus.enAttente:
      return const Color(0xFFD97706);
    case ExpenseStatus.accepte:
      return const Color(0xFF059669);
    case ExpenseStatus.rejete:
      return Theme.of(context).colorScheme.error;
  }
}

/// Bloc « Dépenses (n) » du bilan du jour (§ demande) — `DepensesDuJour` de
/// `frontend/app/(app)/bilan/page.tsx`.
///
/// * Le LIVREUR ([peutDeclarer]) en déclare (repas, carburant, enveloppes…)
///   depuis les types configurés dans Paramètres, ou en saisie libre. Elles
///   partent en attente : le gérant est notifié et tranche. Tant qu'elle est
///   en attente, il peut la « Retirer ».
/// * Le GÉRANT ([peutTrancher]) voit ici les dépenses du livreur consulté et
///   les accepte ou les rejette.
///
/// Seules les dépenses ACCEPTÉES viennent diminuer l'argent à remettre. Les
/// actions passent par `expensesProvider(filter).notifier`, qui recharge
/// ensuite toutes les vues de dépenses ouvertes (`onChanged` du web).
class DepensesDuJour extends ConsumerStatefulWidget {
  const DepensesDuJour({
    super.key,
    required this.depenses,
    required this.jour,
    required this.filter,
    this.peutDeclarer = false,
    this.peutTrancher = false,
    this.chargement = false,
    this.erreur,
    this.onRetry,
  });

  /// Dépenses à afficher, tous statuts confondus — déjà restreintes au
  /// livreur consulté quand c'est le gérant qui regarde.
  final List<LivreurExpense> depenses;

  /// Jour de travail auquel rattacher une nouvelle dépense (champ `date`).
  final DateTime jour;

  /// Vue de dépenses dont dépend ce bloc : ses actions passent par le
  /// notifier de `expensesProvider(filter)`.
  final ExpensesFilter filter;

  final bool peutDeclarer;
  final bool peutTrancher;

  /// Chargement initial de la liste (rien à afficher encore).
  final bool chargement;

  /// Erreur de chargement sans aucune donnée à afficher — le web se contente
  /// d'une liste vide, ici l'erreur est montrée avec « Réessayer ».
  final Object? erreur;
  final VoidCallback? onRetry;

  @override
  ConsumerState<DepensesDuJour> createState() => _DepensesDuJourState();
}

class _DepensesDuJourState extends ConsumerState<DepensesDuJour> {
  /// Type choisi dans le sélecteur — `null` = « Autre (saisie libre) »
  /// (`typeId === 'LIBRE'` du web).
  int? _typeId;
  final _libelle = TextEditingController();
  final _montant = TextEditingController();
  final _quantite = TextEditingController(text: '1');
  final _motif = TextEditingController();

  /// `envoi` du web : « Envoyer au gérant » désactivé pendant l'appel.
  bool _envoi = false;

  /// Dépense dont une action (accepter / rejeter / retirer) est en cours :
  /// ses boutons sont désactivés le temps de l'appel.
  int? _actionEnCours;

  @override
  void initState() {
    super.initState();
    if (widget.peutDeclarer) {
      // Le web recharge le catalogue des types à chaque affichage du bloc :
      // un type ajouté entre-temps dans Paramètres apparaît sans redémarrer.
      Future.microtask(() {
        if (mounted) ref.invalidate(expenseTypesProvider);
      });
    }
  }

  @override
  void dispose() {
    _libelle.dispose();
    _montant.dispose();
    _quantite.dispose();
    _motif.dispose();
    super.dispose();
  }

  ExpensesNotifier get _notifier => ref.read(expensesProvider(widget.filter).notifier);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  ExpenseType? _typeChoisi(List<ExpenseType> types) {
    final id = _typeId;
    if (id == null) return null;
    for (final t in types) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// `Number(quantite) || 1` du web : vide, non numérique ou 0 -> 1.
  int get _quantiteSaisie {
    final q = int.tryParse(_quantite.text.trim()) ?? 0;
    return q < 1 ? 1 : q;
  }

  /// Choisir un type pré-remplit le libellé et le montant, qui restent
  /// modifiables : le prix du catalogue n'est qu'une valeur par défaut.
  void _choisirType(int? id, List<ExpenseType> types) {
    setState(() {
      _typeId = id;
      final t = id == null ? null : _typeChoisi(types);
      if (t != null) {
        _libelle.text = t.nom;
        _montant.text = montantEnSaisie(t.prixUnitaire);
        _quantite.text = '1';
      }
    });
  }

  Future<void> _declarer(List<ExpenseType> types) async {
    final libelle = _libelle.text.trim();
    if (libelle.isEmpty) {
      _toast('Indiquez la nature de la dépense.');
      return;
    }
    final montant = parseMontantOuZero(_montant.text);
    if (!(montant > 0)) {
      _toast('Le montant doit être supérieur à 0.');
      return;
    }
    final typeChoisi = _typeChoisi(types);
    setState(() => _envoi = true);
    try {
      await _notifier.declarer(
        typeDepenseId: typeChoisi?.id,
        libelle: libelle,
        prixUnitaire: montant,
        quantite: _quantiteSaisie,
        motif: _motif.text.trim(),
        date: widget.jour,
      );
      if (!mounted) return;
      _toast('Dépense envoyée au gérant pour validation');
      setState(() {
        _typeId = null;
        _libelle.clear();
        _montant.clear();
        _quantite.text = '1';
        _motif.clear();
      });
    } catch (e) {
      _toast(crudErrorMessage(e, 'Envoi impossible'));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Gérant : « Accepter » / « Rejeter » — immédiat, comme sur le web.
  Future<void> _trancher(LivreurExpense d, ExpenseStatus statut) async {
    setState(() => _actionEnCours = d.id);
    try {
      await _notifier.resoudre(d.id, statut.apiValue);
      _toast(statut == ExpenseStatus.accepte ? 'Dépense acceptée' : 'Dépense rejetée');
    } catch (e) {
      _toast(crudErrorMessage(e, 'Action impossible'));
    } finally {
      if (mounted) setState(() => _actionEnCours = null);
    }
  }

  /// Livreur : « Retirer » une dépense encore en attente.
  Future<void> _supprimer(LivreurExpense d) async {
    setState(() => _actionEnCours = d.id);
    try {
      await _notifier.retirer(d.id);
      _toast('Dépense retirée');
    } catch (e) {
      _toast(crudErrorMessage(e, 'Suppression impossible'));
    } finally {
      if (mounted) setState(() => _actionEnCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final depenses = widget.depenses;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Dépenses (${depenses.length})',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.peutDeclarer
                  ? "Déclarez vos frais de tournée : ils seront déduits de l'argent à remettre une fois validés par le gérant."
                  : 'Frais déclarés par le livreur. Seuls ceux que vous acceptez sont déduits de son bilan.',
              style: muted,
            ),
            const SizedBox(height: 12),
            if (widget.chargement)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (widget.erreur != null)
              ErrorState(message: crudErrorMessage(widget.erreur!, 'Erreur de chargement'), onRetry: widget.onRetry)
            else if (depenses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('Aucune dépense ce jour-là.', style: muted)),
              )
            else
              for (final d in depenses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DepenseTile(
                    depense: d,
                    peutDeclarer: widget.peutDeclarer,
                    peutTrancher: widget.peutTrancher,
                    enCours: _actionEnCours == d.id,
                    onAccepter: () => _trancher(d, ExpenseStatus.accepte),
                    onRejeter: () => _trancher(d, ExpenseStatus.rejete),
                    onRetirer: () => _supprimer(d),
                  ),
                ),
            if (widget.peutDeclarer) _buildFormulaire(context),
          ],
        ),
      ),
    );
  }

  /// « Nouvelle dépense » — type (ou saisie libre), nature, montant,
  /// quantité (si le type se compte à l'unité, ou en saisie libre), total
  /// calculé, motif, puis « Envoyer au gérant ».
  Widget _buildFormulaire(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    // Uniquement les types actifs (`l.filter((t) => t.actif)` du web) ;
    // échec silencieux -> aucun type proposé, la saisie libre reste possible.
    final types = ref.watch(activeExpenseTypesProvider).value ?? const <ExpenseType>[];
    final typeChoisi = _typeChoisi(types);
    // Un type sélectionné mais absent de la liste (catalogue rechargé,
    // type désactivé entre-temps) retombe en saisie libre dans le sélecteur.
    final valeurSelecteur = typeChoisi?.id;
    final quantiteVisible = typeChoisi == null || typeChoisi.parUnite;
    final total = parseMontantOuZero(_montant.text) * _quantiteSaisie;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text('Nouvelle dépense', style: muted),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Type de dépense', isDense: true),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: valeurSelecteur,
              isExpanded: true,
              isDense: true,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Autre (saisie libre)')),
                for (final t in types)
                  DropdownMenuItem<int?>(
                    value: t.id,
                    child: Text(
                      '${t.nom} — ${arFmt(t.prixUnitaire)}${t.parUnite ? ' /u' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _envoi ? null : (v) => _choisirType(v, types),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _libelle,
          enabled: !_envoi,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nature', hintText: 'Nature (ex: Repas)'),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _montant,
                enabled: !_envoi,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: montantInputFormatters,
                decoration: const InputDecoration(labelText: 'Montant (Ar)', hintText: 'Montant (Ar)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (quantiteVisible) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _quantite,
                  enabled: !_envoi,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Quantité', hintText: 'Quantité'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text('= ${arFmt(total)}', style: muted),
        const SizedBox(height: 8),
        TextField(
          controller: _motif,
          enabled: !_envoi,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Motif', hintText: 'Motif (pourquoi cette dépense ?)'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _envoi ? null : () => _declarer(types),
            icon: _envoi
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 18),
            label: Text(_envoi ? 'Envoi…' : 'Envoyer au gérant'),
          ),
        ),
      ],
    );
  }
}

/// Une dépense de la liste : libellé (× quantité), montant, motif, statut,
/// et — tant qu'elle est en attente — Accepter / Rejeter (gérant) ou
/// Retirer (livreur).
class _DepenseTile extends StatelessWidget {
  const _DepenseTile({
    required this.depense,
    required this.peutDeclarer,
    required this.peutTrancher,
    required this.enCours,
    required this.onAccepter,
    required this.onRejeter,
    required this.onRetirer,
  });

  final LivreurExpense depense;
  final bool peutDeclarer;
  final bool peutTrancher;
  final bool enCours;
  final VoidCallback onAccepter;
  final VoidCallback onRejeter;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = depense;
    final statutColor = expenseStatusColor(context, d.statut);
    final erreur = scheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.libelleAvecQuantite,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(arFmt(d.montant), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  d.motif ?? 'Sans motif',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                d.statut.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: statutColor),
              ),
            ],
          ),
          if (d.estRejetee && d.motifRejet != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Motif du rejet : ${d.motifRejet}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          if (d.estEnAttente && (peutTrancher || peutDeclarer)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (peutTrancher) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: enCours ? null : onAccepter,
                      icon: enCours
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Accepter'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enCours ? null : onRejeter,
                      style: OutlinedButton.styleFrom(foregroundColor: erreur),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Rejeter'),
                    ),
                  ),
                ],
                if (peutDeclarer) ...[
                  if (peutTrancher) const SizedBox(width: 8),
                  TextButton(
                    onPressed: enCours ? null : onRetirer,
                    style: TextButton.styleFrom(foregroundColor: erreur),
                    child: enCours
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Retirer'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
