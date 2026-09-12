import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';

/// Un préparateur/livreur du magasin, pour le sélecteur d'affectation du
/// gérant (`available` = indicatif seulement, ne bloque plus la sélection —
/// voir orders/services.py::_resolve_assignee côté serveur).
class StaffOption {
  StaffOption({required this.id, required this.fullName, required this.available, this.magasinId});

  final int id;
  final String fullName;
  final bool available;
  final int? magasinId;

  factory StaffOption.fromJson(Map<String, dynamic> json) {
    return StaffOption(
      id: json['id'] as int,
      fullName: json['full_name'] as String? ?? '',
      available: json['available'] as bool? ?? true,
      magasinId: json['magasin_id'] as int?,
    );
  }
}

/// Cibles du partage d'une commande dans la messagerie
/// (`POST /orders/{id}/share-chat/`). Le salon Général a été retiré de la
/// messagerie côté web : seule la cible « livreur » est encore proposée.
const String kShareChatLivreur = 'livreur';

/// `/api/orders/` — vue filtrée par rôle côté serveur (§7.1/7.2/7.3 README) :
/// le même endpoint `list()` renvoie des champs et un sous-ensemble
/// différents selon que l'appelant est gérant, préparateur ou livreur.
class OrdersRepository {
  Dio get _dio => ApiClient.instance.dio;

  /// Mêmes filtres que `djangoClient.orders.list` : [statut] (une valeur, ou
  /// plusieurs séparées par une virgule côté préparateur/livreur),
  /// [dateDebut]/[dateFin] (jours calendaires), [preparateurId],
  /// [livraisonZone], [magasinId] (gérant), et pour l'historique personnel
  /// du préparateur/livreur [historique] + [dateFrom]/[dateTo] (instants).
  Future<List<Order>> list({
    String? statut,
    DateTime? dateDebut,
    DateTime? dateFin,
    int? preparateurId,
    String? livraisonZone,
    int? magasinId,
    bool historique = false,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final response = await _dio.get('orders/', queryParameters: {
      if (statut != null && statut.isNotEmpty) 'statut': statut,
      if (dateDebut != null) 'date_debut': _fmt(dateDebut),
      if (dateFin != null) 'date_fin': _fmt(dateFin),
      'preparateur_id': ?preparateurId,
      if (livraisonZone != null && livraisonZone.isNotEmpty) 'livraison_zone': livraisonZone,
      'magasin_id': ?magasinId,
      if (historique) 'historique': '1',
      if (dateFrom != null) 'date_from': dateFrom.toUtc().toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toUtc().toIso8601String(),
    });
    return _rows(response.data).map(Order.fromJson).toList();
  }

  Future<Order> detail(int id) async {
    final response = await _dio.get('orders/$id/');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Formulaire Nouvelle commande (§6 README) — prix/frais/total calculés
  /// côté serveur, jamais côté client. [dateCommande] vide -> le serveur
  /// prend maintenant (heure précise) ; [adresseLivraison] complète la zone
  /// (qui ne sert qu'au calcul des frais) pour que le livreur trouve le client.
  /// [telephone2] : second numéro facultatif, même format +261XXXXXXXXX
  /// (chaîne vide = aucun). [campagne] : campagne marketing d'origine
  /// (facultative, gérant) — envoyée seulement si choisie, comme
  /// `...(campagneId ? { campagne } : {})` côté web ; le serveur refuse une
  /// campagne d'un autre magasin (« Cette campagne n'appartient pas au
  /// magasin de la commande. »).
  Future<Order> create({
    required String clientNom,
    required String telephone,
    required String livraisonZone,
    required List<OrderItemDraft> items,
    String telephone2 = '',
    // Deux notes distinctes, chacune destinée à un seul rôle (§ demande).
    String notePreparateur = '',
    String noteLivreur = '',
    String adresseLivraison = '',
    String modePaiement = 'LIVRAISON',
    DateTime? dateCommande,
    int? campagne,
    // Admin multi-magasins : magasin cible (facultatif, `magasin_id` du web).
    int? magasinId,
  }) async {
    final response = await _dio.post('orders/', data: {
      'magasin_id': ?magasinId,
      'client_nom': clientNom,
      'telephone': telephone,
      'telephone_2': telephone2.trim(),
      'livraison_zone': livraisonZone,
      'adresse_livraison': adresseLivraison,
      'mode_paiement': modePaiement,
      'note_preparateur': notePreparateur,
      'note_livreur': noteLivreur,
      'items': items.map((e) => e.toJson()).toList(),
      if (dateCommande != null) 'date_commande': dateCommande.toUtc().toIso8601String(),
      'campagne': ?campagne,
    });
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Transition de statut (§5 README) — le serveur applique les règles de
  /// rôle/transition strictes et l'impact stock (déduction à EN_PREPARATION).
  /// [preparateurId]/[livreurId] : désignation par le gérant (requise pour
  /// lui — auto-affectation sinon). [assignedAt] : heure manuelle optionnelle
  /// pour l'affectation (vide = maintenant, voir services.change_order_status).
  ///
  /// [itemsLivres] — livraison partielle (§ demande) : identifiants des
  /// articles RÉELLEMENT remis au client au passage "Livré". `null` = tout
  /// est remis. Liste vide = rien n'a été livré, le serveur bascule la
  /// commande en « Retour ». Les articles non listés sont marqués
  /// `retourne`, remis en stock, et `total_a_payer` est recalculé.
  Future<Order> changeStatus(
    int id,
    String statut, {
    String note = '',
    int? preparateurId,
    int? livreurId,
    DateTime? assignedAt,
    // Preuve que la préparation est faite — jointe au passage "Prête"
    // (§ demande), chemin local du fichier choisi via image_picker.
    String? photoPath,
    List<int>? itemsLivres,
  }) async {
    if (photoPath != null) {
      // Multipart : `items_livres` est répété autant de fois qu'il y a
      // d'articles (ListFormat.multi), comme `fd.append` côté web — c'est la
      // forme que DRF lit via `QueryDict.getlist`. Une liste vide n'a pas de
      // représentation multipart : on applique ici la règle du serveur
      // (rien de remis = Retour) pour ne pas la perdre en route.
      final rienRemis = statut == 'LIVRE' && itemsLivres != null && itemsLivres.isEmpty;
      final formData = FormData.fromMap({
        'statut': rienRemis ? 'RETOUR' : statut,
        'note': note,
        'preparateur_id': ?preparateurId,
        'livreur_id': ?livreurId,
        if (assignedAt != null) 'assigned_at': assignedAt.toUtc().toIso8601String(),
        if (itemsLivres != null && itemsLivres.isNotEmpty) 'items_livres': itemsLivres.map((i) => '$i').toList(),
        'photo': await MultipartFile.fromFile(photoPath),
      });
      final response = await _dio.post('orders/$id/status/', data: formData);
      return Order.fromJson(response.data as Map<String, dynamic>);
    }
    final response = await _dio.post('orders/$id/status/', data: {
      'statut': statut,
      'note': note,
      'preparateur_id': ?preparateurId,
      'livreur_id': ?livreurId,
      if (assignedAt != null) 'assigned_at': assignedAt.toUtc().toIso8601String(),
      // Une liste VIDE doit partir telle quelle : c'est elle qui signifie
      // « rien n'a été remis » (-> Retour).
      'items_livres': ?itemsLivres,
    });
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Corrige le statut final d'une commande close (gérant uniquement) —
  /// typiquement un « Retour » touché par erreur alors que la livraison
  /// était faite. [statut] = 'LIVRE' | 'RETOUR'. Le serveur rétablit le
  /// stock en conséquence et trace la correction dans l'historique
  /// (voir orders/services.py::corriger_statut).
  Future<Order> corrigerStatut(int id, String statut, {String note = ''}) async {
    final response = await _dio.post('orders/$id/corriger-statut/', data: {
      'statut': statut,
      'note': note,
    });
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Partage la commande dans la messagerie (gérant et préparateur) : résumé
  /// + photo de préparation, envoyés au livreur assigné. Tout est composé
  /// côté serveur — la photo y est déjà, rien ne redescend puis ne remonte
  /// par le téléphone. Refusé par le serveur si aucun livreur n'est assigné
  /// (voir orders/views.py::share_chat).
  Future<void> shareToChat(int id, {String cible = kShareChatLivreur}) async {
    await _dio.post('orders/$id/share-chat/', data: {'cible': cible});
  }

  /// Annulation gérant (restitue le stock si déjà déduit) — voir
  /// orders/services.py::cancel_order.
  Future<Order> cancel(int id, {String note = ''}) async {
    final response = await _dio.post('orders/$id/cancel/', data: {'note': note});
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Modification (gérant). Deux régimes, mêmes règles que
  /// orders/services.py::update_order :
  ///
  /// * "Nouvelle" / "En préparation" — tout est modifiable (articles compris,
  ///   le stock est réajusté) ;
  /// * "Prête" / "En livraison" — seuls [modePaiement], [livraisonZone],
  ///   [adresseLivraison] et [noteLivreur] sont acceptés (frais et total
  ///   recalculés) ; tout autre champ est refusé par le serveur.
  /// * Statut terminal — refus.
  ///
  /// Seuls les champs non nuls sont envoyés ; [telephone2] vide = effacer le
  /// second numéro.
  Future<Order> update(
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
    final response = await _dio.patch('orders/$id/', data: {
      'client_nom': ?clientNom,
      'telephone': ?telephone,
      if (telephone2 != null) 'telephone_2': telephone2.trim(),
      'livraison_zone': ?livraisonZone,
      'adresse_livraison': ?adresseLivraison,
      'mode_paiement': ?modePaiement,
      if (dateCommande != null) 'date_commande': dateCommande.toUtc().toIso8601String(),
      'note_preparateur': ?notePreparateur,
      'note_livreur': ?noteLivreur,
      if (items != null) 'items': items.map((e) => e.toJson()).toList(),
    });
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Suppression (gérant, uniquement tant que "Nouvelle").
  Future<void> delete(int id) => _dio.delete('orders/$id/');

  /// Liste des préparateurs/livreurs pour le sélecteur d'affectation du
  /// gérant — voir orders/views.py::available_staff. [magasinId] restreint
  /// au magasin de la commande (`order.magasin` côté web). [dateCommande]
  /// (LIVREUR uniquement) : signale (sans bloquer) un conflit d'horaire avec
  /// une autre commande déjà (pré-)assignée à ce livreur le même jour/heure.
  Future<List<StaffOption>> availableStaff(String role, {int? magasinId, DateTime? dateCommande}) async {
    final response = await _dio.get('orders/available-staff/', queryParameters: {
      'role': role,
      'magasin_id': ?magasinId,
      if (dateCommande != null) 'date_commande': dateCommande.toUtc().toIso8601String(),
    });
    return _rows(response.data).map(StaffOption.fromJson).toList();
  }

  /// Pré-assigne un livreur sans changer le statut — assignable à tout
  /// statut non terminal, réutilisé automatiquement au passage "En
  /// livraison" (voir orders/services.py::assign_livreur_early).
  Future<Order> assignLivreur(int id, int livreurId) async {
    final response = await _dio.post('orders/$id/assign-livreur/', data: {'livreur_id': livreurId});
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Pré-assigne un préparateur sans faire progresser le statut — la
  /// commande reste "Nouvelle" (en attente) jusqu'à ce que ce préparateur
  /// clique lui-même "Commencer la préparation" (§ demande — voir
  /// orders/services.py::assign_preparateur_early).
  Future<Order> assignPreparateur(int id, int preparateurId) async {
    final response = await _dio.post('orders/$id/assign-preparateur/', data: {'preparateur_id': preparateurId});
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  // -----------------------------------------------------------------------
  // Zones de livraison (`djangoClient.zones`) — nom + prix, partagées par
  // toute la société. Lecture ouverte à tous (sélecteur de zone), écriture
  // réservée au gérant (CRUD Paramètres) — voir
  // orders/views.py::DeliveryZoneOptionViewSet.
  // -----------------------------------------------------------------------

  Future<List<DeliveryZoneOption>> deliveryZones() async {
    final response = await _dio.get('orders/delivery-zones/');
    return _rows(response.data).map(DeliveryZoneOption.fromJson).toList();
  }

  Future<DeliveryZoneOption> createDeliveryZone({required String nom, required double prix}) async {
    final response = await _dio.post('orders/delivery-zones/', data: {'nom': nom, 'prix': prix});
    return DeliveryZoneOption.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DeliveryZoneOption> updateDeliveryZone(int id, {String? nom, double? prix, bool? actif}) async {
    final response = await _dio.patch('orders/delivery-zones/$id/', data: {
      'nom': ?nom,
      'prix': ?prix,
      'actif': ?actif,
    });
    return DeliveryZoneOption.fromJson(response.data as Map<String, dynamic>);
  }

  /// Une zone déjà utilisée par des commandes n'est pas vraiment supprimée
  /// côté serveur — elle est désactivée et renvoyée (200) ; sinon 204.
  /// Renvoie la zone désactivée dans le premier cas, `null` si supprimée.
  Future<DeliveryZoneOption?> deleteDeliveryZone(int id) async {
    final response = await _dio.delete('orders/delivery-zones/$id/');
    final data = response.data;
    if (data is Map) return DeliveryZoneOption.fromJson(data.cast<String, dynamic>());
    return null;
  }

  /// DRF renvoie soit une liste brute, soit une enveloppe paginée
  /// `{results: [...]}` — les deux sont acceptées.
  List<Map<String, dynamic>> _rows(dynamic data) {
    final list = data is List
        ? data
        : data is Map
            ? (data['results'] as List? ?? const [])
            : const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
