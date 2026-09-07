import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/status_badge.dart';

/// Module Dépôt — Préparateur (§7.2 README) : UX mobile simplifiée, lecture
/// seule sauf statut. Le serveur ne renvoie déjà que NOUVELLE/EN_PREPARATION
/// pour ce rôle, sans aucune donnée financière (serializer restreint).
class DepotScreen extends ConsumerWidget {
  const DepotScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dépôt — Commandes à préparer')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
        child: switch (async) {
          AsyncData(:final value) => value.isEmpty
              ? const EmptyState(message: 'Aucune commande à préparer.', icon: Icons.inventory_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _DepotCard(order: value[i]),
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

class _DepotCard extends ConsumerStatefulWidget {
  const _DepotCard({required this.order});
  final Order order;

  @override
  ConsumerState<_DepotCard> createState() => _DepotCardState();
}

class _DepotCardState extends ConsumerState<_DepotCard> {
  bool _loading = false;

  Future<void> _advance() async {
    final order = widget.order;
    final target = order.statutCourant == OrderStatus.nouvelle ? OrderStatus.enPreparation : OrderStatus.prete;
    final note = await showOrderConfirmDialog(context, title: 'Confirmer : ${target.label}', order: order);
    if (note == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(ordersProvider.notifier).changeStatus(order.id, target.apiValue, note: note);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isNouvelle = order.statutCourant == OrderStatus.nouvelle;
    final dueToday = isJourJ(order.dateCommande);

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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_loading || !dueToday) ? null : _advance,
                icon: _loading
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(
                  !dueToday && order.dateCommande != null
                      ? 'Disponible le ${dueDateLabel(order.dateCommande!)}'
                      : (isNouvelle ? 'Commencer la préparation' : 'Commande prête'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
