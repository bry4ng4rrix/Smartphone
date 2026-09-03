import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

/// Module Commandes (§7.1 README) : liste filtrable par statut/date.
class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider);
    final filter = ref.watch(ordersFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commandes'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: 'Filtrer par statut',
            icon: const Icon(Icons.filter_list),
            onSelected: (statut) => ref.read(ordersFilterProvider.notifier).set(
                  filter.copyWith(statut: statut, clearStatut: statut == null),
                ),
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('Tous les statuts')),
              for (final s in OrderStatus.values) PopupMenuItem(value: s.apiValue, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
        child: switch (async) {
          AsyncData(:final value) => value.isEmpty
              ? const EmptyState(message: 'Aucune commande.', icon: Icons.receipt_long_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _OrderTile(order: value[i]),
                ),
          AsyncError(:final error) => ErrorState(
              message: ApiClient.messageFromError(error),
              onRetry: () => ref.read(ordersProvider.notifier).refresh(),
            ),
          _ => const LoadingState(),
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle commande'),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => context.push('/orders/${order.id}'),
        title: Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${order.clientNom} · ${order.livraisonZone.label}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            OrderStatusBadge(status: order.statutCourant),
            if (order.totalAPayer != null) ...[
              const SizedBox(height: 4),
              Text(_ar(order.totalAPayer!), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
