import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

/// Module Livreur (§7.3 README) : UX ultra simplifiée, orientée tournée.
/// Le serveur ne renvoie que PRETE (à récupérer) et EN_LIVRAISON (du jour).
class TourneeScreen extends ConsumerWidget {
  const TourneeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ma tournée')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
        child: switch (async) {
          AsyncData(:final value) => value.isEmpty
              ? const EmptyState(message: 'Aucune commande en tournée.', icon: Icons.local_shipping_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _TourneeCard(order: value[i]),
                ),
          AsyncError(:final error) => ErrorState(
              message: ApiClient.messageFromError(error),
              onRetry: () => ref.read(ordersProvider.notifier).refresh(),
            ),
          _ => const LoadingState(),
        },
      ),
    );
  }
}

class _TourneeCard extends ConsumerStatefulWidget {
  const _TourneeCard({required this.order});
  final Order order;

  @override
  ConsumerState<_TourneeCard> createState() => _TourneeCardState();
}

class _TourneeCardState extends ConsumerState<_TourneeCard> {
  bool _loading = false;

  Future<void> _changeStatus(OrderStatus target, {String note = ''}) async {
    setState(() => _loading = true);
    try {
      await ref.read(ordersProvider.notifier).changeStatus(widget.order.id, target.apiValue, note: note);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmWithNote(OrderStatus target) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(title: target == OrderStatus.livre ? 'Confirmer la livraison' : 'Confirmer le retour'),
    );
    if (note != null) _changeStatus(target, note: note);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPrete = order.statutCourant == OrderStatus.prete;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.numero, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                OrderStatusBadge(status: order.statutCourant),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.clientNom, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (order.telephone != null)
              InkWell(
                onTap: () => launchUrl(Uri.parse('tel:${order.telephone}')),
                child: Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(order.telephone!, style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            for (final item in order.items) Text('• ${item.referenceName} — ${item.couleur} (x${item.quantite})'),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 16),
                const SizedBox(width: 6),
                Text(order.livraisonZone.label),
              ],
            ),
            if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(order.adresseLivraison!)),
                  ],
                ),
              ),
            if (order.totalAPayer != null) ...[
              const SizedBox(height: 4),
              Text('Total à encaisser : ${_ar(order.totalAPayer!)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (isPrete)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _changeStatus(OrderStatus.enLivraison),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Récupérer le colis'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _confirmWithNote(OrderStatus.livre),
                      icon: const Icon(Icons.check),
                      label: const Text('Livré'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmWithNote(OrderStatus.retour),
                      icon: const Icon(Icons.undo),
                      label: const Text('Retour'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title});
  final String title;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Note (optionnel)', hintText: 'ex : client absent'),
        maxLines: 2,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Confirmer')),
      ],
    );
  }
}
