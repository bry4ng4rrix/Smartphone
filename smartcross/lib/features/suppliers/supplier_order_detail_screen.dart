import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/supplier.dart';
import '../../state/suppliers_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _dateFmt = DateFormat('dd/MM/yyyy');

class SupplierOrderDetailScreen extends ConsumerWidget {
  const SupplierOrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supplierOrderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Commande fournisseur')),
      body: switch (async) {
        AsyncData(:final value) => _Body(order: value),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.invalidate(supplierOrderDetailProvider(orderId)),
          ),
        _ => const LoadingState(),
      },
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.order});
  final SupplierOrder order;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _receiving = false;

  Future<void> _receive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la réception'),
        content: const Text('Le stock sera incrémenté automatiquement pour chaque ligne de cette commande.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _receiving = true);
    try {
      await ref.read(supplierOrdersProvider.notifier).receive(widget.order.id);
      ref.invalidate(supplierOrderDetailProvider(widget.order.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(order.numero, style: Theme.of(context).textTheme.headlineSmall),
            StatusChip(label: order.statut.label, color: order.isReceived ? Colors.green : Colors.orange),
          ],
        ),
        if (order.description != null && order.description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(order.description!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Row('Date', order.date != null ? _dateFmt.format(order.date!) : '—'),
                _Row('Prix fournisseur', _ar(order.prixFournisseur)),
                _Row('Fret / import', _ar(order.fretImport)),
                _Row('Douane', _ar(order.douane)),
                _Row('Pub Meta Ads', _ar(order.metaAds)),
                const Divider(height: 20),
                _Row('Coût total', _ar(order.coutTotal), emphasize: true),
                _Row('Coût unitaire moyen', _ar(order.coutUnitaire)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Lignes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final line in order.lines)
                ListTile(
                  title: Text('${line.referenceName} — ${line.couleur}'),
                  subtitle: Text('${line.quantite} × ${_ar(line.coutUnitaireCalcule)} · marge unitaire ${_ar(line.margeUnitaire)}'),
                  trailing: Text(_ar(line.totalLigne)),
                ),
            ],
          ),
        ),
        if (!order.isReceived) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _receiving ? null : _receive,
            icon: _receiving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.inventory_outlined),
            label: const Text('Marquer reçue (entrée stock auto.)'),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text(value, style: style)]),
    );
  }
}
