import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_time.dart';
import '../core/constants.dart';
import 'auth_provider.dart';
import '../data/repositories/orders_repository.dart';
import '../models/delivery_zone.dart';
import '../models/order.dart';
import 'realtime_provider.dart';

final ordersRepositoryProvider = Provider((ref) => OrdersRepository());

/// Zones de livraison configurables (nom + prix) — § demande. Remplit aussi
/// le cache mémoire utilisé pour afficher un libellé à partir du code stocké
/// sur la commande (voir DeliveryZoneCatalog).
final deliveryZonesProvider = FutureProvider<List<DeliveryZoneOption>>((ref) async {
  final zones = await ref.read(ordersRepositoryProvider).deliveryZones();
  DeliveryZoneCatalog.zones = zones;
  return zones;
});

class OrdersFilter {
  const OrdersFilter({
    this.statut,
    this.dateDebut,
    this.dateFin,
    this.preparateurId,
    this.historique = false,
    this.dateFrom,
    this.dateTo,
    this.nonLivree = false,
  });
  final String? statut;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final int? preparateurId;
  final bool historique;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  // "Pas encore livrée" (page.tsx statutFilter === 'NON_LIVREE') — pas une
  // vraie valeur de statut serveur, filtré côté client (voir _fetch).
  final bool nonLivree;

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
    bool? nonLivree,
  }) {
    return OrdersFilter(
      statut: clearStatut ? null : (statut ?? this.statut),
      dateDebut: dateDebut ?? this.dateDebut,
      dateFin: dateFin ?? this.dateFin,
      preparateurId: clearPreparateurId ? null : (preparateurId ?? this.preparateurId),
      historique: historique ?? this.historique,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      nonLivree: nonLivree ?? this.nonLivree,
    );
  }
}

/// Filtre par défaut : le JOUR J, c'est-à-dire la date du jour à
/// Antananarivo (§ demande — même règle que le web). Gérant, préparateur et
/// livreur arrivent ainsi sur la journée de travail en cours ; ils restent
/// libres de changer de date, et « Effacer » les ramène ici.
///
/// La fenêtre va d'aujourd'hui au dernier jour déjà ouvert POUR CE RÔLE : à
/// partir de 19h00 le préparateur voit déjà les commandes du lendemain, qui
/// viennent d'être débloquées pour lui (core/app_time.dart::ouvertureActions).
/// Sans cette borne elles seraient actionnables mais invisibles. Le livreur,
/// lui, ne les voit qu'à partir du jour de livraison.
OrdersFilter jourJFilter(UserRole role) {
  // Le LIVREUR fait exception : il voit TOUTES ses commandes, y compris
  // celles des jours suivants (planning) — § demande. Seules ses ACTIONS
  // restent bloquées hors jour J, pas l'affichage.
  if (role == UserRole.livreur) return const OrdersFilter();
  return OrdersFilter(dateDebut: appToday(), dateFin: dernierJourOuvert(role));
}

class OrdersFilterNotifier extends Notifier<OrdersFilter> {
  @override
  OrdersFilter build() =>
      jourJFilter(ref.read(authProvider).user?.role ?? UserRole.unknown);

  void set(OrdersFilter filter) => state = filter;
}

final ordersFilterProvider = NotifierProvider<OrdersFilterNotifier, OrdersFilter>(OrdersFilterNotifier.new);

/// Liste des commandes — vue filtrée par rôle côté serveur (§7.1/7.2/7.3
/// README). Se rafraîchit automatiquement à chaque événement temps réel
/// (nouvelle commande, changement de statut) via [realtimeTickProvider].
class OrdersNotifier extends AsyncNotifier<List<Order>> {
  late final _repo = ref.read(ordersRepositoryProvider);

  Future<List<Order>> _fetch(OrdersFilter filter) async {
    final commandes = await _repo.list(
      statut: filter.statut,
      dateDebut: filter.dateDebut,
      dateFin: filter.dateFin,
      preparateurId: filter.preparateurId,
      historique: filter.historique,
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
    );
    // Ordre d'affichage commun aux trois rôles (§ demande) : la commande la
    // plus récemment CRÉÉE en haut. La tournée du livreur y ajoute son propre
    // regroupement (jour J d'abord — voir tournee_screen.dart).
    commandes.sort((a, b) {
      final ac = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bc = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bc.compareTo(ac);
    });
    return commandes;
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
    String notePreparateur = '',
    String noteLivreur = '',
    String adresseLivraison = '',
    String modePaiement = 'LIVRAISON',
    DateTime? dateCommande,
  }) async {
    final order = await _repo.create(
      clientNom: clientNom,
      telephone: telephone,
      livraisonZone: livraisonZone,
      items: items,
      notePreparateur: notePreparateur,
      noteLivreur: noteLivreur,
      adresseLivraison: adresseLivraison,
      modePaiement: modePaiement,
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
    String? photoPath,
  }) async {
    final order = await _repo.changeStatus(
      id,
      statut,
      note: note,
      preparateurId: preparateurId,
      livreurId: livreurId,
      assignedAt: assignedAt,
      photoPath: photoPath,
    );
    await refresh();
    return order;
  }

  Future<Order> cancel(int id, {String note = ''}) async {
    final order = await _repo.cancel(id, note: note);
    await refresh();
    return order;
  }

  Future<Order> updateOrder(
    int id, {
    String? clientNom,
    String? telephone,
    String? livraisonZone,
    String? adresseLivraison,
    String? modePaiement,
    DateTime? dateCommande,
    String? notePreparateur,
    String? noteLivreur,
    List<OrderItemDraft>? items,
  }) async {
    final order = await _repo.update(
      id,
      clientNom: clientNom,
      telephone: telephone,
      livraisonZone: livraisonZone,
      adresseLivraison: adresseLivraison,
      modePaiement: modePaiement,
      dateCommande: dateCommande,
      notePreparateur: notePreparateur,
      noteLivreur: noteLivreur,
      items: items,
    );
    await refresh();
    return order;
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    await refresh();
  }

  Future<List<StaffOption>> availableStaff(String role, {DateTime? dateCommande}) =>
      _repo.availableStaff(role, dateCommande: dateCommande);

  Future<Order> assignLivreur(int id, int livreurId) async {
    final order = await _repo.assignLivreur(id, livreurId);
    await refresh();
    return order;
  }

  Future<Order> assignPreparateur(int id, int preparateurId) async {
    final order = await _repo.assignPreparateur(id, preparateurId);
    await refresh();
    return order;
  }
}

final ordersProvider = AsyncNotifierProvider<OrdersNotifier, List<Order>>(OrdersNotifier.new);

final orderDetailProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) {
  ref.watch(realtimeTickProvider);
  return ref.read(ordersRepositoryProvider).detail(id);
});
