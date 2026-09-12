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
///
/// Lecture pour tous (sélecteur de zone) ; les méthodes de modification
/// portent le CRUD de Paramètres > Zones (gérant — `djangoClient.zones`).
/// Reste consommable comme avant : `ref.watch(deliveryZonesProvider)` donne
/// un `AsyncValue<List<DeliveryZoneOption>>`.
class DeliveryZonesNotifier extends AsyncNotifier<List<DeliveryZoneOption>> {
  late final _repo = ref.read(ordersRepositoryProvider);

  Future<List<DeliveryZoneOption>> _fetch() async {
    final zones = await _repo.deliveryZones();
    DeliveryZoneCatalog.zones = zones;
    return zones;
  }

  @override
  Future<List<DeliveryZoneOption>> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Rechargement sans état de chargement intermédiaire (après une action).
  Future<void> _refreshSilencieux() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<DeliveryZoneOption> create({required String nom, required double prix}) async {
    final zone = await _repo.createDeliveryZone(nom: nom, prix: prix);
    await _refreshSilencieux();
    return zone;
  }

  Future<DeliveryZoneOption> updateZone(int id, {String? nom, double? prix, bool? actif}) async {
    final zone = await _repo.updateDeliveryZone(id, nom: nom, prix: prix, actif: actif);
    await _refreshSilencieux();
    return zone;
  }

  /// Bascule actif/inactif (interrupteur de la liste des zones du web).
  Future<DeliveryZoneOption> toggleActif(DeliveryZoneOption zone) => updateZone(zone.id, actif: !zone.actif);

  /// Renvoie la zone désactivée si elle était déjà utilisée par des
  /// commandes (le serveur la désactive au lieu de la supprimer), `null` si
  /// elle a réellement été supprimée.
  Future<DeliveryZoneOption?> delete(int id) async {
    final desactivee = await _repo.deleteDeliveryZone(id);
    await _refreshSilencieux();
    return desactivee;
  }
}

final deliveryZonesProvider =
    AsyncNotifierProvider<DeliveryZonesNotifier, List<DeliveryZoneOption>>(DeliveryZonesNotifier.new);

class OrdersFilter {
  const OrdersFilter({
    this.statut,
    this.dateDebut,
    this.dateFin,
    this.preparateurId,
    this.livraisonZone,
    this.magasinId,
    this.historique = false,
    this.dateFrom,
    this.dateTo,
    this.nonLivree = false,
  });
  final String? statut;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final int? preparateurId;
  // Filtres serveur supplémentaires de `djangoClient.orders.list` (gérant) :
  // code de zone et magasin.
  final String? livraisonZone;
  final int? magasinId;
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
    String? livraisonZone,
    bool clearLivraisonZone = false,
    int? magasinId,
    bool clearMagasinId = false,
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
      livraisonZone: clearLivraisonZone ? null : (livraisonZone ?? this.livraisonZone),
      magasinId: clearMagasinId ? null : (magasinId ?? this.magasinId),
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
///
/// Deux rechargements, comme `fetchOrders(silent)` du web : [refresh] pour
/// le bouton « Rafraîchir » (repasse par l'état de chargement) ; après
/// chaque action la liste est rechargée SILENCIEUSEMENT — les données
/// restent affichées jusqu'à l'arrivée des nouvelles, sans clignotement.
class OrdersNotifier extends AsyncNotifier<List<Order>> {
  late final _repo = ref.read(ordersRepositoryProvider);

  Future<List<Order>> _fetch(OrdersFilter filter) async {
    final commandes = await _repo.list(
      statut: filter.statut,
      dateDebut: filter.dateDebut,
      dateFin: filter.dateFin,
      preparateurId: filter.preparateurId,
      livraisonZone: filter.livraisonZone,
      magasinId: filter.magasinId,
      historique: filter.historique,
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
    );
    // « Pas encore livrée » : filtre CLIENT (`statut !== 'LIVRE'` côté web),
    // le serveur ne connaissant pas cette valeur.
    if (filter.nonLivree) {
      commandes.removeWhere((o) => o.statutCourant == OrderStatus.livre);
    }
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

  /// Rechargement NON silencieux (bouton « Rafraîchir » : réaffiche l'état
  /// de chargement).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(ref.read(ordersFilterProvider)));
  }

  /// Rechargement SILENCIEUX (`fetchOrders(true)` du web) : après une action,
  /// une modification ou un événement — la liste courante reste affichée
  /// pendant l'appel.
  Future<void> refreshSilencieux() async {
    state = await AsyncValue.guard(() => _fetch(ref.read(ordersFilterProvider)));
  }

  Future<Order> create({
    required String clientNom,
    required String telephone,
    required String livraisonZone,
    required List<OrderItemDraft> items,
    String telephone2 = '',
    String notePreparateur = '',
    String noteLivreur = '',
    String adresseLivraison = '',
    String modePaiement = 'LIVRAISON',
    DateTime? dateCommande,
  }) async {
    final order = await _repo.create(
      clientNom: clientNom,
      telephone: telephone,
      telephone2: telephone2,
      livraisonZone: livraisonZone,
      items: items,
      notePreparateur: notePreparateur,
      noteLivreur: noteLivreur,
      adresseLivraison: adresseLivraison,
      modePaiement: modePaiement,
      dateCommande: dateCommande,
    );
    await refreshSilencieux();
    return order;
  }

  /// Transition de statut. [itemsLivres] : livraison partielle au passage
  /// "Livré" — ids des articles réellement remis ; `null` = tout remis ;
  /// liste vide = rien remis, la commande devient un Retour (voir
  /// OrdersRepository.changeStatus).
  Future<Order> changeStatus(
    int id,
    String statut, {
    String note = '',
    int? preparateurId,
    int? livreurId,
    DateTime? assignedAt,
    String? photoPath,
    List<int>? itemsLivres,
  }) async {
    final order = await _repo.changeStatus(
      id,
      statut,
      note: note,
      preparateurId: preparateurId,
      livreurId: livreurId,
      assignedAt: assignedAt,
      photoPath: photoPath,
      itemsLivres: itemsLivres,
    );
    await refreshSilencieux();
    return order;
  }

  /// Corrige l'état d'une commande close (gérant) : LIVRE <-> RETOUR, avec
  /// remise en cohérence du stock côté serveur. [statut] = 'LIVRE'|'RETOUR'.
  Future<Order> corrigerStatut(int id, String statut, {String note = ''}) async {
    final order = await _repo.corrigerStatut(id, statut, note: note);
    await refreshSilencieux();
    return order;
  }

  /// Partage la commande (résumé + photo de préparation) au livreur assigné
  /// dans la messagerie — gérant et préparateur. Ne modifie pas la commande :
  /// aucun rechargement de la liste.
  Future<void> shareToChat(int id, {String cible = kShareChatLivreur}) => _repo.shareToChat(id, cible: cible);

  Future<Order> cancel(int id, {String note = ''}) async {
    final order = await _repo.cancel(id, note: note);
    await refreshSilencieux();
    return order;
  }

  Future<Order> updateOrder(
    int id, {
    String? clientNom,
    String? telephone,
    String? telephone2,
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
      telephone2: telephone2,
      livraisonZone: livraisonZone,
      adresseLivraison: adresseLivraison,
      modePaiement: modePaiement,
      dateCommande: dateCommande,
      notePreparateur: notePreparateur,
      noteLivreur: noteLivreur,
      items: items,
    );
    await refreshSilencieux();
    return order;
  }

  /// Régime restreint de « Modifier » au-delà de "En préparation"
  /// (`livraisonSeule` du web) : seuls le paiement, la zone, l'adresse et la
  /// note du livreur partent — le serveur refuserait tout autre champ.
  Future<Order> updateLivraison(
    int id, {
    String? modePaiement,
    String? livraisonZone,
    String? adresseLivraison,
    String? noteLivreur,
  }) {
    return updateOrder(
      id,
      modePaiement: modePaiement,
      livraisonZone: livraisonZone,
      adresseLivraison: adresseLivraison,
      noteLivreur: noteLivreur,
    );
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    await refreshSilencieux();
  }

  Future<List<StaffOption>> availableStaff(String role, {int? magasinId, DateTime? dateCommande}) =>
      _repo.availableStaff(role, magasinId: magasinId, dateCommande: dateCommande);

  Future<Order> assignLivreur(int id, int livreurId) async {
    final order = await _repo.assignLivreur(id, livreurId);
    await refreshSilencieux();
    return order;
  }

  Future<Order> assignPreparateur(int id, int preparateurId) async {
    final order = await _repo.assignPreparateur(id, preparateurId);
    await refreshSilencieux();
    return order;
  }
}

final ordersProvider = AsyncNotifierProvider<OrdersNotifier, List<Order>>(OrdersNotifier.new);

final orderDetailProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) {
  ref.watch(realtimeTickProvider);
  return ref.read(ordersRepositoryProvider).detail(id);
});

/// Liste des préparateurs pour le filtre « Préparateur » du gérant
/// (`availableStaff('PREPARATEUR')` chargé une fois côté web). Échec
/// silencieux comme sur le web : liste vide.
final preparateurFilterListProvider = FutureProvider.autoDispose<List<StaffOption>>((ref) async {
  try {
    return await ref.read(ordersRepositoryProvider).availableStaff('PREPARATEUR');
  } catch (_) {
    return const <StaffOption>[];
  }
});
