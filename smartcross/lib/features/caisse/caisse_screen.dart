import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/caisse.dart';
import '../../state/caisse_provider.dart';
import '../../widgets/async_state_widgets.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Module Caisse : ouverture/fermeture de session et mouvements d'espèces —
/// infrastructure conservée telle quelle (indépendante du cahier des charges).
class CaisseScreen extends StatelessWidget {
  const CaisseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Caisse'),
          bottom: const TabBar(tabs: [Tab(text: 'Session en cours'), Tab(text: 'Historique')]),
        ),
        body: const TabBarView(children: [_CurrentTab(), _HistoryTab()]),
      ),
    );
  }
}

class _CurrentTab extends ConsumerWidget {
  const _CurrentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(currentCaisseProvider);

    return switch (async) {
      AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.read(currentCaisseProvider.notifier).refresh(),
          child: value == null ? _ClosedView(scrollable: true) : _OpenView(session: value),
        ),
      AsyncError(:final error) => ErrorState(
          message: ApiClient.messageFromError(error),
          onRetry: () => ref.read(currentCaisseProvider.notifier).refresh(),
        ),
      _ => const LoadingState(),
    };
  }
}

class _ClosedView extends ConsumerWidget {
  const _ClosedView({this.scrollable = false});
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.point_of_sale_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Aucune session de caisse ouverte.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const _OpenDialog()),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Ouvrir la caisse'),
            ),
          ],
        ),
      ),
    );
    return scrollable
        ? ListView(children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.5, child: content)])
        : content;
  }
}

class _OpenView extends ConsumerWidget {
  const _OpenView({required this.session});
  final CaisseSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_open_outlined, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('Session ouverte', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Fond de départ : ${_ar(session.openingBalance)}'),
                Text('Solde actuel estimé : ${_ar(session.soldeCourant)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (session.openedAt != null) Text('Ouverte le ${_dateFmt.format(session.openedAt!.toLocal())}${session.openedByName != null ? ' · ${session.openedByName}' : ''}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _MovementDialog(movementType: 'in')),
                icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                label: const Text('Entrée'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _MovementDialog(movementType: 'out')),
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                label: const Text('Sortie'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Mouvements de cette session', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (session.movements.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Aucun mouvement pour l\'instant.'))
        else
          for (final m in session.movements.reversed) _MovementTile(movement: m),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => _CloseDialog(session: session)),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Fermer la caisse'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
        ),
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});
  final CaisseMovement movement;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: (movement.isIn ? Colors.green : Colors.red).withValues(alpha: 0.15),
        child: Icon(movement.isIn ? Icons.arrow_downward : Icons.arrow_upward, color: movement.isIn ? Colors.green : Colors.red, size: 18),
      ),
      title: Text(movement.reason),
      subtitle: Text([
        if (movement.createdAt != null) _dateFmt.format(movement.createdAt!.toLocal()),
        if (movement.createdByName != null) movement.createdByName!,
      ].join(' · ')),
      trailing: Text(
        '${movement.isIn ? '+' : '-'}${_ar(movement.amount)}',
        style: TextStyle(fontWeight: FontWeight.w700, color: movement.isIn ? Colors.green : Colors.red),
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(caisseHistoryProvider);

    return switch (async) {
      AsyncData(:final value) => value.isEmpty
          ? const EmptyState(message: 'Aucune session de caisse.', icon: Icons.history)
          : RefreshIndicator(
              onRefresh: () => ref.refresh(caisseHistoryProvider.future),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: value.length,
                itemBuilder: (context, i) {
                  final s = value[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(s.isOpen ? Icons.lock_open_outlined : Icons.lock_outline, color: s.isOpen ? Colors.green : null),
                      title: Text(s.openedAt != null ? _dateFmt.format(s.openedAt!.toLocal()) : 'Session #${s.id}'),
                      subtitle: Text(
                        s.isOpen
                            ? 'Ouverte · fond ${_ar(s.openingBalance)}'
                            : 'Fermée · attendu ${_ar(s.expectedBalance ?? 0)} · compté ${_ar(s.closingBalance ?? 0)}'
                                '${s.difference != null && s.difference != 0 ? ' · écart ${_ar(s.difference!)}' : ''}',
                      ),
                    ),
                  );
                },
              ),
            ),
      AsyncError(:final error) => ErrorState(message: ApiClient.messageFromError(error), onRetry: () => ref.invalidate(caisseHistoryProvider)),
      _ => const LoadingState(),
    };
  }
}

class _OpenDialog extends ConsumerStatefulWidget {
  const _OpenDialog();

  @override
  ConsumerState<_OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends ConsumerState<_OpenDialog> {
  final _amountController = TextEditingController(text: '0');
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount < 0) {
      setState(() => _error = 'Montant invalide');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(currentCaisseProvider.notifier).open(openingBalance: amount, openingNote: _noteController.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ouvrir la caisse'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), const SizedBox(height: 8)],
          TextField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Fond de départ (Ar)')),
          const SizedBox(height: 10),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note (optionnel)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _submit, child: const Text('Ouvrir')),
      ],
    );
  }
}

class _CloseDialog extends ConsumerStatefulWidget {
  const _CloseDialog({required this.session});
  final CaisseSession session;

  @override
  ConsumerState<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends ConsumerState<_CloseDialog> {
  late final _amountController = TextEditingController(text: widget.session.soldeCourant.toStringAsFixed(0));
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount < 0) {
      setState(() => _error = 'Montant invalide');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(currentCaisseProvider.notifier).close(closingBalance: amount, closingNote: _noteController.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fermer la caisse'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), const SizedBox(height: 8)],
          Text('Solde attendu (estimation) : ${_ar(widget.session.soldeCourant)}'),
          const SizedBox(height: 10),
          TextField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Montant compté (Ar)')),
          const SizedBox(height: 10),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note (optionnel)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _MovementDialog extends ConsumerStatefulWidget {
  const _MovementDialog({required this.movementType});
  final String movementType;

  @override
  ConsumerState<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends ConsumerState<_MovementDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0 || _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Montant et motif requis');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(currentCaisseProvider.notifier).addMovement(
            movementType: widget.movementType,
            amount: amount,
            reason: _reasonController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIn = widget.movementType == 'in';
    return AlertDialog(
      title: Text(isIn ? 'Entrée de caisse' : 'Sortie de caisse'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), const SizedBox(height: 8)],
          TextField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Montant (Ar)'), autofocus: true),
          const SizedBox(height: 10),
          TextField(controller: _reasonController, decoration: const InputDecoration(labelText: 'Motif', hintText: 'Ex: appoint, dépense essence…')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
