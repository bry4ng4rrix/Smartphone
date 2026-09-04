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
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Statuts atteignables depuis le statut courant (miroir client de
/// `orders/services.py::TRANSITIONS`, §5 README).
List<OrderStatus> _nextOptions(OrderStatus current) {
  switch (current) {
    case OrderStatus.nouvelle:
      return [OrderStatus.enPreparation];
    case OrderStatus.enPreparation:
      return [OrderStatus.prete];
    case OrderStatus.prete:
      return [OrderStatus.enLivraison];
    case OrderStatus.enLivraison:
      return [OrderStatus.livre, OrderStatus.retour];
    case OrderStatus.livre:
    case OrderStatus.retour:
      return [];
  }
}

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Détail commande')),
      body: switch (async) {
        AsyncData(:final value) => _OrderDetailBody(order: value),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
          ),
        _ => const LoadingState(),
      },
    );
  }
}

class _OrderDetailBody extends ConsumerStatefulWidget {
  const _OrderDetailBody({required this.order});
  final Order order;

  @override
  ConsumerState<_OrderDetailBody> createState() => _OrderDetailBodyState();
}

class _OrderDetailBodyState extends ConsumerState<_OrderDetailBody> {
  bool _changing = false;

  Future<void> _changeStatus(OrderStatus target) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(title: 'Confirmer : ${target.label}'),
    );
    if (note == null) return;
    setState(() => _changing = true);
    try {
      await ref.read(ordersProvider.notifier).changeStatus(widget.order.id, target.apiValue, note: note);
      ref.invalidate(orderDetailProvider(widget.order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final nextOptions = _nextOptions(order.statutCourant);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(order.numero, style: Theme.of(context).textTheme.headlineSmall),
            OrderStatusBadge(status: order.statutCourant),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(icon: Icons.person_outline, label: 'Client', value: order.clientNom),
                if (order.telephone != null)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Téléphone',
                    value: order.telephone!,
                    onTap: () => launchUrl(Uri.parse('tel:${order.telephone}')),
                  ),
                _InfoRow(icon: Icons.local_shipping_outlined, label: 'Livraison', value: order.livraisonZone.label),
                if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
                  _InfoRow(icon: Icons.place_outlined, label: 'Adresse', value: order.adresseLivraison!),
                if (order.dateCommande != null)
                  _InfoRow(icon: Icons.event_outlined, label: 'Date commande', value: DateFormat('dd/MM/yyyy HH:mm').format(order.dateCommande!.toLocal())),
                if (order.note != null && order.note!.isNotEmpty) _InfoRow(icon: Icons.notes_outlined, label: 'Note', value: order.note!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Articles', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final item in order.items)
                ListTile(
                  title: Text('${item.referenceName} — ${item.couleur}'),
                  subtitle: item.prixUnitaire != null ? Text('${item.quantite} × ${_ar(item.prixUnitaire!)}') : Text('Quantité : ${item.quantite}'),
                  trailing: item.prixUnitaire != null ? Text(_ar(item.prixUnitaire! * item.quantite)) : null,
                ),
            ],
          ),
        ),
        if (order.fraisLivraison != null || order.totalAPayer != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  if (order.fraisLivraison != null)
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Frais de livraison'), Text(_ar(order.fraisLivraison!))]),
                  if (order.totalAPayer != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total à payer', style: Theme.of(context).textTheme.titleMedium),
                        Text(_ar(order.totalAPayer!), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (nextOptions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            children: [
              for (final target in nextOptions)
                FilledButton.icon(
                  onPressed: _changing ? null : () => _changeStatus(target),
                  icon: Icon(target == OrderStatus.retour ? Icons.undo : Icons.check),
                  label: Text(target.label),
                  style: target == OrderStatus.retour ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
                ),
            ],
          ),
        ],
        if (order.statusHistory.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Chronologie', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _OrderTimelineCard(order: order),
          const SizedBox(height: 20),
          Text('Historique détaillé', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final h in order.statusHistory)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 20),
              title: Text('${h.ancienStatut?.label ?? '—'} → ${h.nouveauStatut.label}'),
              subtitle: Text([
                if (h.changedByName != null) h.changedByName!,
                if (h.timestamp != null) _dateFmt.format(h.timestamp!),
                if (h.note != null && h.note!.isNotEmpty) h.note!,
              ].join(' · ')),
            ),
        ],
      ],
    );
  }
}

/// Résumé "Prête le / En livraison depuis le / Livrée le" — une ligne par
/// statut effectivement atteint, dérivée de l'historique complet, pour une
/// lecture immédiate sans avoir à parcourir la liste détaillée en dessous.
class _OrderTimelineCard extends StatelessWidget {
  const _OrderTimelineCard({required this.order});
  final Order order;

  static const _milestones = [
    (OrderStatus.enPreparation, Icons.build_outlined, 'Préparation commencée le'),
    (OrderStatus.prete, Icons.inventory_2_outlined, 'Prête le'),
    (OrderStatus.enLivraison, Icons.local_shipping_outlined, 'En livraison depuis le'),
    (OrderStatus.livre, Icons.check_circle_outline, 'Livrée le'),
    (OrderStatus.retour, Icons.undo, 'Retour le'),
  ];

  @override
  Widget build(BuildContext context) {
    final timestamps = <OrderStatus, DateTime>{};
    for (final h in order.statusHistory) {
      timestamps.putIfAbsent(h.nouveauStatut, () => h.timestamp ?? DateTime.now());
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TimelineRow(
              icon: Icons.add_shopping_cart_outlined,
              label: 'Commande créée le',
              date: order.dateCommande ?? order.createdAt,
              reached: true,
            ),
            for (final (status, icon, label) in _milestones)
              _TimelineRow(
                icon: icon,
                label: label,
                date: timestamps[status],
                reached: timestamps.containsKey(status),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.icon, required this.label, required this.date, required this.reached});
  final IconData icon;
  final String label;
  final DateTime? date;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    if (!reached) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label ', style: Theme.of(context).textTheme.bodyMedium),
                  TextSpan(
                    text: date != null ? _dateFmt.format(date!.toLocal()) : '—',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 10),
            Text('$label : ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: onTap != null ? Theme.of(context).colorScheme.primary : null,
                  decoration: onTap != null ? TextDecoration.underline : null,
                ),
              ),
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
