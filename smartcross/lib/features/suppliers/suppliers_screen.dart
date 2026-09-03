import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/supplier.dart';
import '../../state/suppliers_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

/// Module Commandes Fournisseur (§7.6 README) : coût de revient réel =
/// marchandise + fret/import + douane + Meta Ads.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supplierOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fournisseurs')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(supplierOrdersProvider.notifier).refresh(),
        child: switch (async) {
          AsyncData(:final value) => value.isEmpty
              ? const EmptyState(message: 'Aucune commande fournisseur.', icon: Icons.local_shipping_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _SupplierOrderTile(order: value[i]),
                ),
          AsyncError(:final error) => ErrorState(
              message: ApiClient.messageFromError(error),
              onRetry: () => ref.read(supplierOrdersProvider.notifier).refresh(),
            ),
          _ => const LoadingState(),
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/suppliers/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle commande'),
      ),
    );
  }
}

class _SupplierOrderTile extends StatelessWidget {
  const _SupplierOrderTile({required this.order});
  final SupplierOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => context.push('/suppliers/${order.id}'),
        title: Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${order.description?.isNotEmpty == true ? order.description! : 'Sans description'} · ${order.totalQty} article(s)'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip(label: order.statut.label, color: order.isReceived ? Colors.green : Colors.orange),
            const SizedBox(height: 4),
            Text(_ar(order.coutTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
