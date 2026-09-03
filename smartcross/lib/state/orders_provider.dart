import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/orders_repository.dart';
import '../models/order.dart';
import 'realtime_provider.dart';

final ordersRepositoryProvider = Provider((ref) => OrdersRepository());

class OrdersFilter {
  const OrdersFilter({this.statut, this.dateDebut, this.dateFin});
  final String? statut;
  final DateTime? dateDebut;
  final DateTime? dateFin;

  OrdersFilter copyWith({String? statut, bool clearStatut = false, DateTime? dateDebut, DateTime? dateFin}) {
    return OrdersFilter(
      statut: clearStatut ? null : (statut ?? this.statut),
      dateDebut: dateDebut ?? this.dateDebut,
      dateFin: dateFin ?? this.dateFin,
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

  @override
  Future<List<Order>> build() {
    ref.watch(realtimeTickProvider);
    final filter = ref.watch(ordersFilterProvider);
    return _repo.list(statut: filter.statut, dateDebut: filter.dateDebut, dateFin: filter.dateFin);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final filter = ref.read(ordersFilterProvider);
      return _repo.list(statut: filter.statut, dateDebut: filter.dateDebut, dateFin: filter.dateFin);
    });
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

  Future<Order> changeStatus(int id, String statut, {String note = ''}) async {
    final order = await _repo.changeStatus(id, statut, note: note);
    await refresh();
    return order;
  }
}

final ordersProvider = AsyncNotifierProvider<OrdersNotifier, List<Order>>(OrdersNotifier.new);

final orderDetailProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) {
  ref.watch(realtimeTickProvider);
  return ref.read(ordersRepositoryProvider).detail(id);
});
