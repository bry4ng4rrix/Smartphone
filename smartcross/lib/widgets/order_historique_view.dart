import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_time.dart';
import '../data/repositories/orders_repository.dart';
import '../models/order.dart';
import 'async_state_widgets.dart';

final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Filtres de statut de l'historique (§ demande — page livreur : livrées,
/// à récupérer, retours…). `null` = tous les statuts.
const _statutFilters = <({String? value, String label})>[
  (value: null, label: 'Tous'),
  (value: 'LIVRE', label: 'Livrées'),
  (value: 'RETOUR', label: 'Retours'),
  (value: 'ANNULEE', label: 'Annulées'),
  (value: 'EN_LIVRAISON', label: 'En livraison'),
  (value: 'PRETE', label: 'À récupérer'),
  (value: 'EN_PREPARATION', label: 'En préparation'),
];

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
  String? _statut;
  late Future<List<Order>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Order>> _load() => _repo.list(
        historique: true,
        // Les bornes saisies sont des heures « au mur » d'Antananarivo :
        // converties en instants absolus pour le serveur (core/app_time.dart).
        dateFrom: _from == null ? null : appWallClockToUtc(_from!),
        dateTo: _to == null ? null : appWallClockToUtc(_to!),
        statut: _statut,
      );

  /// Date ET heure, comme les champs "Du"/"Au" du web (§ demande) : le
  /// sélecteur de date est suivi d'un sélecteur d'heure, l'heure est
  /// facultative (annuler garde le début/la fin de journée par défaut).
  Future<DateTime?> _pickDateTime({required DateTime? current, required bool finDeJournee}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay.fromDateTime(current)
          : (finDeJournee ? const TimeOfDay(hour: 23, minute: 59) : const TimeOfDay(hour: 0, minute: 0)),
    );
    if (time == null) {
      return finDeJournee
          ? DateTime(date.year, date.month, date.day, 23, 59, 59)
          : DateTime(date.year, date.month, date.day);
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickFrom() async {
    final picked = await _pickDateTime(current: _from, finDeJournee: false);
    if (picked == null) return;
    setState(() {
      _from = picked;
      _future = _load();
    });
  }

  Future<void> _pickTo() async {
    final picked = await _pickDateTime(current: _to, finDeJournee: true);
    if (picked == null) return;
    setState(() {
      _to = picked;
      _future = _load();
    });
  }

  void _reset() {
    setState(() {
      _from = null;
      _to = null;
      _statut = null;
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
                  onPressed: _pickFrom,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _from != null ? 'Du ${_dateTimeFmt.format(_from!)}' : 'Du…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTo,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _to != null ? 'Au ${_dateTimeFmt.format(_to!)}' : 'Au…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_from != null || _to != null || _statut != null)
                IconButton(onPressed: _reset, icon: const Icon(Icons.clear)),
            ],
          ),
        ),
        // Filtres de statut : livrées, à récupérer, retours… (§ demande).
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _statutFilters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final f = _statutFilters[i];
              return ChoiceChip(
                label: Text(f.label),
                selected: _statut == f.value,
                onSelected: (_) => setState(() {
                  _statut = f.value;
                  _future = _load();
                }),
              );
            },
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
