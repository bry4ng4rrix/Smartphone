import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/app_time.dart';
import '../models/order.dart';
import '../state/orders_provider.dart';
import '../state/realtime_provider.dart';
import 'async_state_widgets.dart';

final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Filtres de statut de l'historique personnel (`HISTORIQUE_STATUT_FILTERS`
/// de page.tsx) : tous les statuts déjà traversés par SES commandes, états
/// terminaux compris. « À récupérer » = PRETE, libellé métier du livreur.
/// `null` = tous les statuts.
const kHistoriqueStatutFilters = <({String? value, String label})>[
  (value: null, label: 'Tous les statuts'),
  (value: 'LIVRE', label: 'Livrées'),
  (value: 'RETOUR', label: 'Retours'),
  (value: 'ANNULEE', label: 'Annulées'),
  (value: 'EN_LIVRAISON', label: 'En livraison'),
  (value: 'PRETE', label: 'À récupérer'),
  (value: 'EN_PREPARATION', label: 'En préparation'),
  (value: 'NOUVELLE', label: 'Nouvelles'),
];

/// Filtres de l'onglet Historique (§ demande) : bornes date + heure « au
/// mur » (heure d'Antananarivo, converties en instants absolus à l'envoi —
/// `appDatetimeLocalToIso` du web) et statut. Sert de clé au provider de
/// l'historique : deux filtres égaux partagent la même requête.
class OrderHistoriqueFiltre {
  const OrderHistoriqueFiltre({this.from, this.to, this.statut});

  /// Bornes « Du » / « Au », `null` = borne ouverte.
  final DateTime? from;
  final DateTime? to;

  /// Code de statut serveur, `null` = tous les statuts.
  final String? statut;

  /// Valeur par défaut : le JOUR J, de 00:00 à 23:59 — la journée de
  /// travail en cours à Antananarivo (`${appToday()}T00:00` / `T23:59` du
  /// web). « Réinitialiser » y ramène.
  factory OrderHistoriqueFiltre.jourJ() {
    final j = appToday();
    return OrderHistoriqueFiltre(
      from: DateTime(j.year, j.month, j.day),
      to: DateTime(j.year, j.month, j.day, 23, 59),
    );
  }

  bool get estParDefaut => this == OrderHistoriqueFiltre.jourJ();

  OrderHistoriqueFiltre copyWith({DateTime? from, DateTime? to, String? statut, bool clearStatut = false}) {
    return OrderHistoriqueFiltre(
      from: from ?? this.from,
      to: to ?? this.to,
      statut: clearStatut ? null : (statut ?? this.statut),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderHistoriqueFiltre && other.from == from && other.to == to && other.statut == statut);

  @override
  int get hashCode => Object.hash(from, to, statut);
}

/// Historique personnel du préparateur / du livreur (`historique=1` +
/// `date_from` / `date_to` / `statut` — voir orders/views.py::get_queryset) :
/// toutes les commandes qui lui ont été désignées, tous statuts confondus.
///
/// Rechargé SILENCIEUSEMENT à chaque événement temps réel, comme la liste
/// active (`useRealtimeRefresh` → `fetchOrders(true)` du web) : la liste
/// affichée reste en place jusqu'à l'arrivée des nouvelles données. Après une
/// action jouée depuis une carte, `ref.invalidate(orderHistoriqueProvider)`
/// recharge la famille entière — c'est le `fetchOrders(true)` d'après action.
///
/// Classé la plus récemment CRÉÉE en tête (même ordre que les trois rôles
/// côté web, `displayedOrders`).
final orderHistoriqueProvider = FutureProvider.autoDispose.family<List<Order>, OrderHistoriqueFiltre>((
  ref,
  filtre,
) async {
  ref.watch(realtimeTickProvider);
  final commandes = await ref.watch(ordersRepositoryProvider).list(
        historique: true,
        // Les bornes saisies sont des heures « au mur » d'Antananarivo :
        // converties en instants absolus pour le serveur (core/app_time.dart).
        dateFrom: filtre.from == null ? null : appWallClockToUtc(filtre.from!),
        dateTo: filtre.to == null ? null : appWallClockToUtc(filtre.to!),
        statut: filtre.statut,
      );
  int creeLe(Order o) => o.createdAt?.millisecondsSinceEpoch ?? 0;
  commandes.sort((a, b) => creeLe(b).compareTo(creeLe(a)));
  return commandes;
});

/// Vue "Historique" (préparateur/livreur) : toutes les commandes déjà
/// désignées à l'utilisateur, tous statuts confondus, filtrables par date ET
/// heure (« Du » / « Au ») et par statut — § demande. Les filtres s'ouvrent
/// sur le jour J et « Réinitialiser » y ramène. [cardBuilder] laisse chaque
/// rôle afficher ses propres champs et actions.
class OrderHistoriqueView extends ConsumerStatefulWidget {
  const OrderHistoriqueView({super.key, required this.cardBuilder});
  final Widget Function(BuildContext context, Order order) cardBuilder;

  @override
  ConsumerState<OrderHistoriqueView> createState() => _OrderHistoriqueViewState();
}

class _OrderHistoriqueViewState extends ConsumerState<OrderHistoriqueView> {
  OrderHistoriqueFiltre _filtre = OrderHistoriqueFiltre.jourJ();

  /// Date ET heure, comme les champs "Du"/"Au" du web (§ demande) : le
  /// sélecteur de date est suivi d'un sélecteur d'heure, l'heure est
  /// facultative (annuler garde le début/la fin de journée par défaut).
  /// Toutes les bornes sont des dates métier, calées sur Antananarivo.
  Future<DateTime?> _pickDateTime({required DateTime? current, required bool finDeJournee}) async {
    final today = appToday();
    final first = today.subtract(const Duration(days: 365));
    final last = today.add(const Duration(days: 365));
    var initial = current ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay.fromDateTime(current)
          : (finDeJournee ? const TimeOfDay(hour: 23, minute: 59) : const TimeOfDay(hour: 0, minute: 0)),
    );
    if (time == null) {
      return finDeJournee ? DateTime(date.year, date.month, date.day, 23, 59) : DateTime(date.year, date.month, date.day);
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickFrom() async {
    final picked = await _pickDateTime(current: _filtre.from, finDeJournee: false);
    if (picked == null || !mounted) return;
    setState(() => _filtre = _filtre.copyWith(from: picked));
  }

  Future<void> _pickTo() async {
    final picked = await _pickDateTime(current: _filtre.to, finDeJournee: true);
    if (picked == null || !mounted) return;
    setState(() => _filtre = _filtre.copyWith(to: picked));
  }

  void _setStatut(String? statut) =>
      setState(() => _filtre = statut == null ? _filtre.copyWith(clearStatut: true) : _filtre.copyWith(statut: statut));

  /// « Réinitialiser » : retour au jour J (00:00 → 23:59), tous les statuts.
  void _reset() => setState(() => _filtre = OrderHistoriqueFiltre.jourJ());

  Future<void> _reload() async {
    final provider = orderHistoriqueProvider(_filtre);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      // L'état d'erreur est déjà porté par le provider (toast ou ErrorState).
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = orderHistoriqueProvider(_filtre);
    final async = ref.watch(provider);
    // Erreur d'un rechargement silencieux (temps réel, après action) : la
    // liste garde son contenu précédent et l'erreur est annoncée par un
    // toast, comme `toast.error(err.message || 'Erreur de chargement des
    // commandes')` côté web.
    ref.listen<AsyncValue<List<Order>>>(provider, (previous, next) {
      if (next.hasError && next.hasValue && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(next.error!))));
      }
    });
    final orders = async.value;

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
                    _filtre.from != null ? 'Du ${_dateTimeFmt.format(_filtre.from!)}' : 'Du…',
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
                    _filtre.to != null ? 'Au ${_dateTimeFmt.format(_filtre.to!)}' : 'Au…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // « Réinitialiser » n'apparaît que si l'un des trois filtres
              // s'écarte du jour J.
              if (!_filtre.estParDefaut)
                IconButton(tooltip: 'Réinitialiser', onPressed: _reset, icon: const Icon(Icons.clear)),
            ],
          ),
        ),
        // Filtres de statut : livrées, retours, annulées… (§ demande).
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: kHistoriqueStatutFilters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final f = kHistoriqueStatutFilters[i];
              return ChoiceChip(
                label: Text(f.label),
                selected: _filtre.statut == f.value,
                onSelected: (_) => _setStatut(f.value),
              );
            },
          ),
        ),
        // Rechargement silencieux en cours : la liste reste affichée, un
        // filet de progression le signale.
        if (async.isLoading && orders != null) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: orders != null
              ? RefreshIndicator(
                  onRefresh: _reload,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (orders.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            message: 'Aucune commande trouvée pour cette recherche.',
                            icon: Icons.history,
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          sliver: SliverList.builder(
                            itemCount: orders.length,
                            itemBuilder: (context, i) => widget.cardBuilder(context, orders[i]),
                          ),
                        ),
                    ],
                  ),
                )
              : async.hasError
                  ? ErrorState(message: ApiClient.messageFromError(async.error!), onRetry: _reload)
                  : const LoadingState(),
        ),
      ],
    );
  }
}
