import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../models/supplier.dart';
import '../../state/suppliers_provider.dart';
import '../../widgets/async_state_widgets.dart';
import 'supplier_order_card.dart';
import 'supplier_status.dart';

/// Fiche d'un approvisionnement (§ 16) + actions du cycle : Commande →
/// Acompte payé → Préparation → Entièrement payé → Expédié → En transit →
/// Arrivé à Madagascar → Frais + Douane → Coût finalisé (module indépendant
/// du stock : l'appro porte sur un sous-type).
/// Miroir de frontend/app/(app)/suppliers/[id]/page.tsx.
class SupplierOrderDetailScreen extends ConsumerStatefulWidget {
  const SupplierOrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  @override
  ConsumerState<SupplierOrderDetailScreen> createState() => _SupplierOrderDetailScreenState();
}

class _SupplierOrderDetailScreenState extends ConsumerState<SupplierOrderDetailScreen> {
  bool _busy = false;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Joue une action, remplace la fiche par la réponse de l'API.
  Future<void> _action(Future<SupplierOrder> Function() fn, String succes) async {
    setState(() => _busy = true);
    try {
      final o = await fn();
      ref.read(supplierOrdersProvider.notifier).remplacer(o);
      ref.invalidate(supplierOrderDetailProvider(widget.orderId));
      ref.invalidate(supplierKpisProvider);
      _snack(succes);
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supplierOrderDetailProvider(widget.orderId));
    final repo = ref.read(suppliersRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.numero ?? 'Approvisionnement')),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(message: ApiClient.messageFromError(e), onRetry: () => ref.invalidate(supplierOrderDetailProvider(widget.orderId))),
        data: (o) {
          final ouvert = o.modifiable;
          final scheme = Theme.of(context).colorScheme;
          final idx = SupplierOrderStatus.values.indexOf(o.statut);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(supplierOrderDetailProvider(widget.orderId)),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                // Progression du cycle (§ 15)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final (i, s) in SupplierOrderStatus.values.indexed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: i == idx ? supplierStatusColor(s).withValues(alpha: 0.16) : null,
                          border: Border.all(color: i == idx ? supplierStatusColor(s) : scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${i < idx ? '✓ ' : ''}${s.label}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500,
                            color: i == idx ? supplierStatusColor(s) : (i < idx ? scheme.onSurfaceVariant : scheme.outline),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (ouvert)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (actionPossible('commander', o.statut))
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _action(() => repo.commander(o.id), 'Commande passée au fournisseur'),
                          icon: const Icon(Icons.inventory_2_outlined, size: 18),
                          label: const Text('Commander'),
                        ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _dialoguePaiement(o),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: Text(o.payments.isEmpty ? 'Premier paiement (acompte)' : 'Nouveau paiement'),
                      ),
                      if (actionPossible('preparer', o.statut))
                        OutlinedButton(onPressed: _busy ? null : () => _action(() => repo.preparer(o.id), 'Marchandise en préparation'), child: const Text('Préparation')),
                      if (actionPossible('expedier', o.statut))
                        OutlinedButton.icon(onPressed: _busy ? null : () => _dialogueTransport(o, expedier: true), icon: const Icon(Icons.flight_takeoff, size: 18), label: const Text('Départ Chine')),
                      if (actionPossible('transit', o.statut))
                        OutlinedButton.icon(onPressed: _busy ? null : () => _dialogueTransport(o, expedier: false), icon: const Icon(Icons.directions_boat_outlined, size: 18), label: const Text('En transit')),
                      if (actionPossible('arriver', o.statut))
                        OutlinedButton.icon(onPressed: _busy ? null : () => _dialogueArrivee(o), icon: const Icon(Icons.local_shipping_outlined, size: 18), label: const Text('Arrivée Madagascar')),
                      if (o.statut == SupplierOrderStatus.arrive)
                        OutlinedButton.icon(onPressed: _busy ? null : () => _dialogueFrais(o), icon: const Icon(Icons.calculate_outlined, size: 18), label: const Text('Frais + Douane')),
                      if (actionPossible('finaliser', o.statut))
                        FilledButton.icon(onPressed: _busy ? null : () => _dialogueFinaliser(o), icon: const Icon(Icons.check_circle_outline, size: 18), label: const Text('Finaliser le coût')),
                      if (ouvert)
                        TextButton.icon(onPressed: _busy ? null : () => _dialogueModifier(o), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Modifier')),
                    ],
                  )
                else
                  Text(
                    'Coût finalisé le ${o.finaliseAt == null ? '—' : appLocal(o.finaliseAt!).toString().substring(0, 10).split('-').reversed.join('/')} — ${o.quantiteRecue} pièce(s) reçue(s). Ce coût est historique : il ne change plus.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 12),
                SupplierOrderCard(order: o),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Paiements (${o.payments.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        if (o.payments.isEmpty)
                          Text("Aucun paiement. Le premier paiement (acompte) fait passer l'approvisionnement à « Acompte payé ».", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        for (final (i, p) in o.payments.indexed)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Paiement ${i + 1} · ${p.typeLabel} · ${fmtDateIso(p.date)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      Text(
                                        [p.methodeLabel, if (p.reference.isNotEmpty) p.reference, if (o.caissePaiements.contains(p.id)) 'en caisse'].join(' · '),
                                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                      ),
                                      if (p.commentaire.isNotEmpty) Text(p.commentaire, style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(fmtDevise(p.montant, p.devise), style: const TextStyle(fontWeight: FontWeight.w700)),
                                    if (p.devise != 'MGA') Text('taux ${fmtTaux(p.tauxChange)}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                    Text('= ${fmtAr(p.montantMga)}', style: const TextStyle(fontSize: 12)),
                                    if (ouvert)
                                      TextButton(
                                        onPressed: _busy ? null : () => _supprimerPaiement(o, p),
                                        style: TextButton.styleFrom(foregroundColor: Colors.red, visualDensity: VisualDensity.compact),
                                        child: const Text('Supprimer'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(child: Text('Total fournisseur (MGA)', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
                            Text(fmtAr(o.totalPaiementsMga), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- dialogues ------------------------------------------------------------ //

  Future<void> _supprimerPaiement(SupplierOrder o, SupplierPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce paiement ?'),
        content: Text("${fmtDevise(p.montant, p.devise)} du ${fmtDateIso(p.date)} — le coût total sera recalculé. Une sortie de caisse déjà enregistrée n'est pas annulée."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await _action(() => ref.read(suppliersRepositoryProvider).deletePayment(o.id, p.id), 'Paiement supprimé');
  }

  Future<void> _dialoguePaiement(SupplierOrder o) async {
    final r = await showDialog<_PaiementResult>(context: context, builder: (_) => _PaiementDialog(order: o));
    if (r == null) return;
    await _action(
      () => ref.read(suppliersRepositoryProvider).addPayment(
            o.id, montant: r.montant, devise: r.devise, tauxChange: r.taux, date: r.date, typePaiement: r.type,
            methode: r.methode, reference: r.reference, commentaire: r.commentaire, enCaisse: r.enCaisse,
          ),
      'Paiement enregistré : ${fmtDevise(r.montant, r.devise)} → ${fmtAr(r.montant * (r.devise == 'MGA' ? 1 : r.taux))}',
    );
  }

  Future<void> _dialogueTransport(SupplierOrder o, {required bool expedier}) async {
    final r = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _TransportDialog(order: o, expedier: expedier));
    if (r == null) return;
    final repo = ref.read(suppliersRepositoryProvider);
    await _action(() => expedier ? repo.expedier(o.id, r) : repo.transit(o.id, r), expedier ? 'Marchandise expédiée depuis la Chine' : 'Marchandise en transit');
  }

  Future<void> _dialogueArrivee(SupplierOrder o) async {
    final r = await showDialog<({String date, double? frais})>(context: context, builder: (_) => _ArriveeDialog(order: o));
    if (r == null) return;
    await _action(() => ref.read(suppliersRepositoryProvider).arriver(o.id, dateArrivee: r.date, fraisDouaneMga: r.frais), 'Marchandise arrivée à Madagascar');
  }

  Future<void> _dialogueFrais(SupplierOrder o) async {
    final r = await showDialog<({double montant, bool enCaisse})>(context: context, builder: (_) => _FraisDialog(order: o));
    if (r == null) return;
    await _action(() => ref.read(suppliersRepositoryProvider).fraisDouane(o.id, montant: r.montant, enCaisse: r.enCaisse), 'Frais + Douane enregistrés');
  }

  Future<void> _dialogueFinaliser(SupplierOrder o) async {
    final r = await showDialog<({int quantite, bool majPrix})>(context: context, builder: (_) => _FinaliserDialog(order: o));
    if (r == null) return;
    await _action(
      () => ref.read(suppliersRepositoryProvider).finaliser(o.id, mettreAJourPrixAchat: r.majPrix, quantiteRecue: r.quantite),
      'Coût finalisé — ${r.quantite} pièce(s) reçue(s)',
    );
  }

  Future<void> _dialogueModifier(SupplierOrder o) async {
    final r = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ModifierDialog(order: o));
    if (r == null) return;
    await _action(() => ref.read(suppliersRepositoryProvider).update(o.id, r), 'Approvisionnement modifié');
  }
}

// ----------------------------------------------------------------------------- //
// Dialogues
// ----------------------------------------------------------------------------- //

String _today() => appToday().toString().substring(0, 10);

Future<String?> _pickDate(BuildContext context, String initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: DateTime.tryParse(initial) ?? appToday(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  return d?.toString().substring(0, 10);
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onChanged});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final d = await _pickDate(context, value);
        if (d != null) onChanged(d);
      },
      icon: const Icon(Icons.event_outlined, size: 18),
      label: Text('$label : ${fmtDateIso(value)}'),
    );
  }
}

double? _num(String s) => double.tryParse(s.replaceAll(' ', '').replaceAll(',', '.'));

class _PaiementResult {
  const _PaiementResult({required this.montant, required this.devise, required this.taux, required this.date, required this.type, required this.methode, required this.reference, required this.commentaire, required this.enCaisse});
  final double montant, taux;
  final String devise, date, type, methode, reference, commentaire;
  final bool enCaisse;
}

class _PaiementDialog extends StatefulWidget {
  const _PaiementDialog({required this.order});
  final SupplierOrder order;
  @override
  State<_PaiementDialog> createState() => _PaiementDialogState();
}

class _PaiementDialogState extends State<_PaiementDialog> {
  final _montant = TextEditingController();
  final _taux = TextEditingController();
  final _reference = TextEditingController();
  final _commentaire = TextEditingController();
  late String _devise = widget.order.devise;
  late String _date = _today();
  late String _type = widget.order.payments.isEmpty ? 'ACOMPTE' : 'SOLDE';
  String _methode = 'VIREMENT';
  bool _enCaisse = false;

  @override
  void dispose() {
    for (final c in [_montant, _taux, _reference, _commentaire]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final m = _num(_montant.text);
    final t = _devise == 'MGA' ? 1.0 : _num(_taux.text);
    final apercu = (m != null && t != null && m > 0 && t > 0) ? m * t : null;
    return AlertDialog(
      title: Text('Nouveau paiement — ${o.numero}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chaque paiement garde son propre taux : montant MGA = montant × taux du jour.${o.montantPrevu > 0 ? ' Prévu ${fmtDevise(o.montantPrevu, o.devise)} · payé ${fmtDevise(o.totalPayeDevise, o.devise)} · reste ${fmtDevise(o.resteAPayerDevise, o.devise)}.' : ''}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              TextField(controller: _montant, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Montant', isDense: true), onChanged: (_) => setState(() {}), autofocus: true),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('dev-$_devise'),
                      initialValue: _devise,
                      decoration: const InputDecoration(labelText: 'Devise', isDense: true),
                      items: [for (final d in kDevises) DropdownMenuItem(value: d.value, child: Text(d.value))],
                      onChanged: (v) => setState(() => _devise = v ?? 'USD'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _taux,
                      enabled: _devise != 'MGA',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Taux du jour (Ar / 1 $_devise)', hintText: 'Ex : 4500', isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (apercu != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('= ${fmtAr(apercu)}', style: const TextStyle(fontWeight: FontWeight.w700))),
              const SizedBox(height: 10),
              _DateField(label: 'Date', value: _date, onChanged: (d) => setState(() => _date = d)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true),
                      items: [for (final d in kTypesPaiement) DropdownMenuItem(value: d.value, child: Text(d.label, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _type = v ?? 'ACOMPTE'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _methode,
                      decoration: const InputDecoration(labelText: 'Mode', isDense: true),
                      items: [for (final d in kMethodesPaiement) DropdownMenuItem(value: d.value, child: Text(d.label, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _methode = v ?? 'VIREMENT'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Référence (virement, reçu…)', isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: _commentaire, decoration: const InputDecoration(labelText: 'Commentaire', isDense: true)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Enregistrer la sortie en caisse', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Achat de stock — session ouverte requise', style: TextStyle(fontSize: 11)),
                value: _enCaisse,
                onChanged: (v) => setState(() => _enCaisse = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final montant = _num(_montant.text);
            if (montant == null || montant <= 0) return;
            final taux = _devise == 'MGA' ? 1.0 : _num(_taux.text);
            if (taux == null || taux <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Indiquez le taux de change du jour.')));
              return;
            }
            Navigator.of(context).pop(_PaiementResult(montant: montant, devise: _devise, taux: taux, date: _date, type: _type, methode: _methode, reference: _reference.text.trim(), commentaire: _commentaire.text.trim(), enCaisse: _enCaisse));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _TransportDialog extends StatefulWidget {
  const _TransportDialog({required this.order, required this.expedier});
  final SupplierOrder order;
  final bool expedier;
  @override
  State<_TransportDialog> createState() => _TransportDialogState();
}

class _TransportDialogState extends State<_TransportDialog> {
  late final _transporteur = TextEditingController(text: widget.order.transporteur);
  late final _tracking = TextEditingController(text: widget.order.tracking);
  late final _colis = TextEditingController(text: widget.order.numeroColis);
  late final _commentaire = TextEditingController(text: widget.order.commentaireTransport);
  late String _date = widget.order.dateExpedition ?? _today();
  late String _mode = widget.order.modeTransport;

  @override
  void dispose() {
    for (final c in [_transporteur, _tracking, _colis, _commentaire]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.expedier ? 'Départ de Chine' : 'En transit'} — ${widget.order.numero}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.expedier) ...[
                _DateField(label: 'Date de départ', value: _date, onChanged: (d) => setState(() => _date = d)),
                const SizedBox(height: 10),
              ],
              TextField(controller: _transporteur, decoration: const InputDecoration(labelText: 'Transporteur', hintText: 'Ex : DHL, MSC…', isDense: true)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _mode.isEmpty ? null : _mode,
                decoration: const InputDecoration(labelText: 'Mode de transport', isDense: true),
                items: [for (final d in kModesTransport) DropdownMenuItem(value: d.value, child: Text(d.label))],
                onChanged: (v) => setState(() => _mode = v ?? ''),
              ),
              const SizedBox(height: 10),
              TextField(controller: _tracking, decoration: const InputDecoration(labelText: 'Tracking / référence', isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: _colis, decoration: const InputDecoration(labelText: 'Numéro de colis', isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: _commentaire, decoration: const InputDecoration(labelText: 'Commentaire', isDense: true)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            if (widget.expedier) 'date_expedition': _date,
            'transporteur': _transporteur.text.trim(),
            if (_mode.isNotEmpty) 'mode_transport': _mode,
            'tracking': _tracking.text.trim(),
            'numero_colis': _colis.text.trim(),
            'commentaire_transport': _commentaire.text.trim(),
          }),
          child: Text(widget.expedier ? 'Marquer expédié' : 'Marquer en transit'),
        ),
      ],
    );
  }
}

class _ArriveeDialog extends StatefulWidget {
  const _ArriveeDialog({required this.order});
  final SupplierOrder order;
  @override
  State<_ArriveeDialog> createState() => _ArriveeDialogState();
}

class _ArriveeDialogState extends State<_ArriveeDialog> {
  late String _date = _today();
  late final _frais = TextEditingController(text: widget.order.fraisDouaneMga > 0 ? widget.order.fraisDouaneMga.toStringAsFixed(0) : '');

  @override
  void dispose() {
    _frais.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Arrivée à Madagascar — ${widget.order.numero}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateField(label: "Date d'arrivée", value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 10),
          TextField(controller: _frais, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Frais + Douane (Ar) — facultatif', hintText: 'Ex : 5000000', isDense: true)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((date: _date, frais: _frais.text.trim().isEmpty ? null : _num(_frais.text))),
          child: const Text('Marquer arrivé'),
        ),
      ],
    );
  }
}

class _FraisDialog extends StatefulWidget {
  const _FraisDialog({required this.order});
  final SupplierOrder order;
  @override
  State<_FraisDialog> createState() => _FraisDialogState();
}

class _FraisDialogState extends State<_FraisDialog> {
  late final _frais = TextEditingController(text: widget.order.fraisDouaneMga > 0 ? widget.order.fraisDouaneMga.toStringAsFixed(0) : '');
  bool _enCaisse = false;

  @override
  void dispose() {
    _frais.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final f = _num(_frais.text);
    final total = f == null ? null : o.totalPaiementsMga + f;
    return AlertDialog(
      title: Text('Frais + Douane — ${o.numero}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Un seul montant, en ariary, ajouté au total des paiements pour obtenir le coût total rendu Madagascar.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(controller: _frais, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Frais + Douane (Ar)', hintText: 'Ex : 5000000', isDense: true), onChanged: (_) => setState(() {})),
          if (total != null) ...[
            const SizedBox(height: 10),
            Text('Paiements ${fmtAr(o.totalPaiementsMga)} + frais ${fmtAr(f!)} = ${fmtAr(total)}', style: const TextStyle(fontSize: 12)),
            Text('÷ ${o.quantite} pièces = ${fmtAr(o.quantite > 0 ? total / o.quantite : 0)} / pièce', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(o.caisseFraisDouane ? 'Sortie déjà enregistrée en caisse' : 'Enregistrer la sortie en caisse', style: const TextStyle(fontSize: 13)),
            value: _enCaisse,
            onChanged: o.caisseFraisDouane ? null : (v) => setState(() => _enCaisse = v ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: f == null || f < 0 ? null : () => Navigator.of(context).pop((montant: f, enCaisse: _enCaisse)),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _FinaliserDialog extends StatefulWidget {
  const _FinaliserDialog({required this.order});
  final SupplierOrder order;
  @override
  State<_FinaliserDialog> createState() => _FinaliserDialogState();
}

class _FinaliserDialogState extends State<_FinaliserDialog> {
  late final _quantite = TextEditingController(text: '${widget.order.quantite}');
  bool _majPrix = true;

  @override
  void dispose() {
    _quantite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return AlertDialog(
      title: Text('Finaliser le coût — ${o.numero}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paiements ${fmtAr(o.totalPaiementsMga)} + Frais + Douane ${fmtAr(o.fraisDouaneMga)} = ${fmtAr(o.coutTotalMga)}', style: const TextStyle(fontSize: 12)),
          Text('÷ ${o.quantite} pièces = ${fmtAr(o.coutUnitaireMga)} / pièce', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (o.fraisDouaneMga == 0)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aucun montant Frais + Douane saisi : le coût ne comprend que les paiements.', style: TextStyle(fontSize: 12, color: Color(0xFFD97706)))),
          const SizedBox(height: 10),
          TextField(controller: _quantite, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pièces réellement reçues', isDense: true)),
          // Uniquement pour un ancien appro qui connaît sa variante : le
          // stock est alors réceptionné et le prix d'achat mis à jour.
          if (o.produit != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Mettre à jour le prix d'achat de référence (moyenne pondérée)", style: TextStyle(fontSize: 13)),
              value: _majPrix,
              onChanged: (v) => setState(() => _majPrix = v ?? true),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final q = int.tryParse(_quantite.text.trim());
            if (q == null || q < 0 || q > o.quantite) return;
            Navigator.of(context).pop((quantite: q, majPrix: _majPrix));
          },
          child: const Text('Finaliser et réceptionner'),
        ),
      ],
    );
  }
}

class _ModifierDialog extends StatefulWidget {
  const _ModifierDialog({required this.order});
  final SupplierOrder order;
  @override
  State<_ModifierDialog> createState() => _ModifierDialogState();
}

class _ModifierDialogState extends State<_ModifierDialog> {
  late final _quantite = TextEditingController(text: '${widget.order.quantite}');
  late final _prevu = TextEditingController(text: widget.order.montantPrevu > 0 ? widget.order.montantPrevu.toString() : '');
  late final _description = TextEditingController(text: widget.order.description ?? '');
  late String _devise = widget.order.devise;

  @override
  void dispose() {
    for (final c in [_quantite, _prevu, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Modifier — ${widget.order.numero}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Sous-type : ${widget.order.produitLibelle} (ne change pas : créez un autre approvisionnement).', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(controller: _quantite, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantité', isDense: true)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _devise,
                  decoration: const InputDecoration(labelText: 'Devise', isDense: true),
                  items: [for (final d in kDevises) DropdownMenuItem(value: d.value, child: Text(d.value))],
                  onChanged: (v) => setState(() => _devise = v ?? 'USD'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: _prevu, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Montant prévu', isDense: true))),
            ],
          ),
          const SizedBox(height: 10),
          TextField(controller: _description, decoration: const InputDecoration(labelText: 'Description', isDense: true)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final q = int.tryParse(_quantite.text.trim());
            if (q == null || q < 1) return;
            Navigator.of(context).pop({'quantite': q, 'devise': _devise, 'montant_prevu': _num(_prevu.text) ?? 0, 'description': _description.text.trim()});
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
