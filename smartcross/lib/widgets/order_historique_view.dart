import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repositories/orders_repository.dart';
import '../models/order.dart';
import 'async_state_widgets.dart';

final _dateFmt = DateFormat('dd/MM/yyyy');

/// Vue "Historique" (préparateur/livreur) : toutes les commandes déjà
/// désignées à l'utilisateur, tous statuts confondus, filtrables par date —
/// § demande. [cardBuilder] laisse chaque rôle afficher ses propres champs.
class OrderHistoriqueView extends StatefulWidget {
  const OrderHistoriqueView({super.key, required this.cardBuilder});
  final Widget Function(BuildContext context, Order order) cardBuilder;

  @override
  State<OrderHistoriqueView> createState() => _OrderHistoriqueViewState();
}

class _OrderHistoriqueViewState extends State<OrderHistoriqueView> {
  final _repo = OrdersRepository();
  DateTime? _from;
  DateTime? _to;
  late Future<List<Order>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Order>> _load() => _repo.list(historique: true, dateFrom: _from, dateTo: _to);

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null,
    );
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
      _future = _load();
    });
  }

  void _reset() {
    setState(() {
      _from = null;
      _to = null;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _from != null && _to != null
                        ? '${_dateFmt.format(_from!)} → ${_dateFmt.format(_to!)}'
                        : 'Filtrer par date',
                  ),
                ),
              ),
              if (_from != null) IconButton(onPressed: _reset, icon: const Icon(Icons.clear)),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Order>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState();
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: 'Erreur de chargement.',
                  onRetry: () => setState(() => _future = _load()),
                );
              }
              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return const EmptyState(message: "Aucune commande dans l'historique.", icon: Icons.history);
              }
              return RefreshIndicator(
                onRefresh: () async => setState(() => _future = _load()),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: orders.length,
                  itemBuilder: (context, i) => widget.cardBuilder(context, orders[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
