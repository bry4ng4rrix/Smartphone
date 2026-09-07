import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/orders_repository.dart';
import '../models/order.dart';
import 'realtime_provider.dart';

final ordersRepositoryProvider = Provider((ref) => OrdersRepository());

class OrdersFilter {
  const OrdersFilter({
    this.statut,
    this.dateDebut,
    this.dateFin,
    this.preparateurId,
    this.historique = false,
    this.dateFrom,
    this.dateTo,
  });
  final String? statut;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final int? preparateurId;
  final bool historique;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  OrdersFilter copyWith({
    String? statut,
    bool clearStatut = false,
    DateTime? dateDebut,
    DateTime? dateFin,
    int? preparateurId,
    bool clearPreparateurId = false,
    bool? historique,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    return OrdersFilter(
      statut: clearStatut ? null : (statut ?? this.statut),
      dateDebut: dateDebut ?? this.dateDebut,
      dateFin: dateFin ?? this.dateFin,
      preparateurId: clearPreparateurId ? null : (preparateurId ?? this.preparateurId),
      historique: historique ?? this.historique,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
    );
  }
}

class OrdersFilterNotifier extends Notifier<OrdersFilter> {
  @override
  OrdersFilter build() => const OrdersFilter();

  void set(OrdersFilter filter) => state = filter;
}

final ordersFilterProvider = NotifierProvider<OrdersFilterNotifier, OrdersFilter>(OrdersFilterNotifier.new);

/// Liste des commandes — vue filtrée par rôle côté serveur (§7.1/7.2/7.3
/// README). Se rafraîchit automatiquement à chaque événement temps réel
/// (nouvelle commande, changement de statut) via [realtimeTickProvider].
class OrdersNotifier extends AsyncNotifier<List<Order>> {
  late final _repo = ref.read(ordersRepositoryProvider);

  Future<List<Order>> _fetch(OrdersFilter filter) {
    return _repo.list(
      statut: filter.statut,
      dateDebut: filter.dateDebut,
      dateFin: filter.dateFin,
      preparateurId: filter.preparateurId,
      historique: filter.historique,
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
    );
  }

  @override
  Future<List<Order>> build() {
    ref.watch(realtimeTickProvider);
    final filter = ref.watch(ordersFilterProvider);
    return _fetch(filter);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(ref.read(ordersFilterProvider)));
  }

  Future<Order> create({
    required String clientNom,
    required String telephone,
    required String livraisonZone,
    required List<OrderItemDraft> items,
    String note = '',
    String adresseLivraison = '',
    DateTime? dateCommande,
  }) async {
    final order = await _repo.create(
      clientNom: clientNom,
      telephone: telephone,
      livraisonZone: livraisonZone,
      items: items,
      note: note,
      adresseLivraison: adresseLivraison,
      dateCommande: dateCommande,
    );
    await refresh();
    return order;
  }

  Future<Order> changeStatus(
    int id,
    String statut, {
    String note = '',
    int? preparateurId,
    int? livreurId,
    DateTime? assignedAt,
  }) async {
    final order = await _repo.changeStatus(
      id,
      statut,
      note: note,
      preparateurId: preparateurId,
      livreurId: livreurId,
      assignedAt: assignedAt,
    );
    await refresh();
    return order;
  }

  Future<Order> cancel(int id, {String note = ''}) async {
    final order = await _repo.cancel(id, note: note);
    await refresh();
    return order;
  }

  Future<List<StaffOption>> availableStaff(String role) => _repo.availableStaff(role);
}

final ordersProvider = AsyncNotifierProvider<OrdersNotifier, List<Order>>(OrdersNotifier.new);

final orderDetailProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) {
  ref.watch(realtimeTickProvider);
  return ref.read(ordersRepositoryProvider).detail(id);
});
