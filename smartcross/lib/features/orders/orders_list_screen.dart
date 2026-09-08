import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../data/repositories/orders_repository.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _dateFmt = DateFormat('dd/MM/yyyy');

/// Module Commandes (§7.1 README) : liste filtrable par statut/date/préparateur.
class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});

  Future<void> _pickDateRange(BuildContext context, WidgetRef ref, OrdersFilter filter) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: filter.dateDebut != null && filter.dateFin != null
          ? DateTimeRange(start: filter.dateDebut!, end: filter.dateFin!)
          : null,
    );
    if (range == null) return;
    ref.read(ordersFilterProvider.notifier).set(filter.copyWith(dateDebut: range.start, dateFin: range.end));
  }

  Future<void> _pickPreparateur(BuildContext context, WidgetRef ref, OrdersFilter filter) async {
    final selected = await showDialog<int?>(
      context: context,
      builder: (context) => _PreparateurPickerDialog(
        loadStaff: () => ref.read(ordersProvider.notifier).availableStaff('PREPARATEUR'),
      ),
    );
    if (selected == null && filter.preparateurId == null) return;
    ref.read(ordersFilterProvider.notifier).set(
          filter.copyWith(preparateurId: selected, clearPreparateurId: selected == null),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider);
    final filter = ref.watch(ordersFilterProvider);
    final hasActiveFilter =
        filter.statut != null || filter.dateDebut != null || filter.preparateurId != null || filter.nonLivree;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commandes'),
        actions: [
          IconButton(
            tooltip: 'Filtrer par date',
            icon: const Icon(Icons.date_range_outlined),
            onPressed: () => _pickDateRange(context, ref, filter),
          ),
          IconButton(
            tooltip: 'Filtrer par préparateur',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => _pickPreparateur(context, ref, filter),
          ),
          PopupMenuButton<String?>(
            tooltip: 'Filtrer par statut',
            icon: const Icon(Icons.filter_list),
            onSelected: (statut) => statut == 'NON_LIVREE'
                ? ref.read(ordersFilterProvider.notifier).set(filter.copyWith(clearStatut: true, nonLivree: true))
                : ref.read(ordersFilterProvider.notifier).set(
                      filter.copyWith(statut: statut, clearStatut: statut == null, nonLivree: false),
                    ),
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('Tous les statuts')),
              const PopupMenuItem(value: 'NON_LIVREE', child: Text('Pas encore livrée')),
              for (final s in OrderStatus.values) PopupMenuItem(value: s.apiValue, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (hasActiveFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (filter.statut != null)
                    Chip(
                      label: Text(OrderStatusX.fromApi(filter.statut).label),
                      onDeleted: () => ref.read(ordersFilterProvider.notifier).set(filter.copyWith(clearStatut: true)),
                    ),
                  if (filter.dateDebut != null && filter.dateFin != null)
                    Chip(
                      label: Text('${_dateFmt.format(filter.dateDebut!)} → ${_dateFmt.format(filter.dateFin!)}'),
                      onDeleted: () => ref.read(ordersFilterProvider.notifier).set(
                            OrdersFilter(statut: filter.statut, preparateurId: filter.preparateurId),
                          ),
                    ),
                  if (filter.preparateurId != null)
                    Chip(
                      label: const Text('Préparateur'),
                      onDeleted: () => ref.read(ordersFilterProvider.notifier).set(filter.copyWith(clearPreparateurId: true)),
                    ),
                  if (filter.nonLivree)
                    Chip(
                      label: const Text('Pas encore livrée'),
                      onDeleted: () => ref.read(ordersFilterProvider.notifier).set(filter.copyWith(nonLivree: false)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
              child: switch (async) {
                AsyncData(value: final rawValue) => (() {
                    final value = filter.nonLivree
                        ? rawValue.where((o) => o.statutCourant != OrderStatus.livre).toList()
                        : rawValue;
                    return value.isEmpty
                        ? const EmptyState(message: 'Aucune commande.', icon: Icons.receipt_long_outlined)
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: value.length,
                            itemBuilder: (context, i) => _OrderTile(order: value[i]),
                          );
                  })(),
                AsyncError(:final error) => ErrorState(
                    message: ApiClient.messageFromError(error),
                    onRetry: () => ref.read(ordersProvider.notifier).refresh(),
                  ),
                _ => const LoadingState(),
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle commande'),
      ),
    );
  }
}

class _PreparateurPickerDialog extends StatefulWidget {
  const _PreparateurPickerDialog({required this.loadStaff});
  final Future<List<StaffOption>> Function() loadStaff;

  @override
  State<_PreparateurPickerDialog> createState() => _PreparateurPickerDialogState();
}

class _PreparateurPickerDialogState extends State<_PreparateurPickerDialog> {
  List<StaffOption>? _staff;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.loadStaff().then((staff) {
      if (mounted) setState(() { _staff = staff; _loading = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filtrer par préparateur'),
      content: SizedBox(
        width: 320,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Tous'),
                    onTap: () => Navigator.of(context).pop(null),
                  ),
                  for (final s in _staff ?? [])
                    ListTile(
                      title: Text(s.fullName),
                      onTap: () => Navigator.of(context).pop(s.id),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
      ],
    );
  }
}

final _shortDateFmt = DateFormat('dd/MM HH:mm');

DateTime? _historyAt(Order order, OrderStatus statut) {
  for (final h in order.statusHistory) {
    if (h.nouveauStatut == statut) return h.timestamp;
  }
  return null;
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final preparedAt = _historyAt(order, OrderStatus.enPreparation);
    final livreurAt = order.statutCourant == OrderStatus.livre
        ? _historyAt(order, OrderStatus.livre)
        : _historyAt(order, OrderStatus.enLivraison);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => context.push('/orders/${order.id}'),
        title: Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${order.clientNom} · ${order.livraisonZone.shortLabel}'),
            if (order.preparateurName != null)
              Text(
                'Préparateur : ${order.preparateurName}${preparedAt != null ? ' · ${_shortDateFmt.format(preparedAt.toLocal())}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (order.livreurName != null)
              Text(
                'Livreur : ${order.livreurName}'
                '${livreurAt != null ? ' · ${order.statutCourant == OrderStatus.livre ? 'Livré le ' : ''}${_shortDateFmt.format(livreurAt.toLocal())}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
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
