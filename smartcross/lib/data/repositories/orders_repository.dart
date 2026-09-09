import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';

/// Un préparateur/livreur du magasin, pour le sélecteur d'affectation du
/// gérant (`available` = indicatif seulement, ne bloque plus la sélection —
/// voir orders/services.py::_resolve_assignee côté serveur).
class StaffOption {
  StaffOption({required this.id, required this.fullName, required this.available});

  final int id;
  final String fullName;
  final bool available;

  factory StaffOption.fromJson(Map<String, dynamic> json) {
    return StaffOption(
      id: json['id'] as int,
      fullName: json['full_name'] as String? ?? '',
      available: json['available'] as bool? ?? true,
    );
  }
}

/// `/api/orders/` — vue filtrée par rôle côté serveur (§7.1/7.2/7.3 README) :
/// le même endpoint `list()` renvoie des champs et un sous-ensemble
/// différents selon que l'appelant est gérant, préparateur ou livreur.
class OrdersRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<Order>> list({
    String? statut,
    DateTime? dateDebut,
    DateTime? dateFin,
    int? preparateurId,
    bool historique = false,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final response = await _dio.get('orders/', queryParameters: {
      if (statut != null) 'statut': statut,
      if (dateDebut != null) 'date_debut': _fmt(dateDebut),
      if (dateFin != null) 'date_fin': _fmt(dateFin),
      if (preparateurId != null) 'preparateur_id': preparateurId,
      if (historique) 'historique': '1',
      if (dateFrom != null) 'date_from': dateFrom.toUtc().toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toUtc().toIso8601String(),
    });
    return (response.data as List).map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> detail(int id) async {
    final response = await _dio.get('orders/$id/');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Formulaire Nouvelle commande (§6 README) — prix/frais/total calculés
  /// côté serveur, jamais côté client. [dateCommande] vide -> le serveur
  /// prend maintenant (heure précise) ; [adresseLivraison] complète la zone
  /// (qui ne sert qu'au calcul des frais) pour que le livreur trouve le client.
  Future<Order> create({
    required String clientNom,
    required String telephone,
    required String livraisonZone,
    required List<OrderItemDraft> items,
    // Deux notes distinctes, chacune destinée à un seul rôle (§ demande).
    String notePreparateur = '',
    String noteLivreur = '',
    String adresseLivraison = '',
    String modePaiement = 'LIVRAISON',
    DateTime? dateCommande,
  }) async {
    final response = await _dio.post('orders/', data: {
      'client_nom': clientNom,
      'telephone': telephone,
      'livraison_zone': livraisonZone,
      'adresse_livraison': adresseLivraison,
      'mode_paiement': modePaiement,
      'note_preparateur': notePreparateur,
      'note_livreur': noteLivreur,
      'items': items.map((e) => e.toJson()).toList(),
      if (dateCommande != null) 'date_commande': dateCommande.toUtc().toIso8601String(),
    });
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Transition de statut (§5 README) — le serveur applique les règles de
  /// rôle/transition strictes et l'impact stock (déduction à EN_PREPARATION).
  /// [preparateurId]/[livreurId] : désignation par le gérant (requise pour
  /// lui — auto-affectation sinon). [assignedAt] : heure manuelle optionnelle
  /// pour l'affectation (vide = maintenant, voir services.change_order_status).
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
  }) async {
    if (photoPath != null) {
      final formData = FormData.fromMap({
        'statut': statut,
        'note': note,
        if (preparateurId != null) 'preparateur_id': preparateurId,
        if (livreurId != null) 'livreur_id': livreurId,
        if (assignedAt != null) 'assigned_at': assignedAt.toUtc().toIso8601String(),
        'photo': await MultipartFile.fromFile(photoPath),
      });
      final response = await _dio.post('orders/$id/status/', data: formData);
      return Order.fromJson(response.data as Map<String, dynamic>);
    }
    final response = await _dio.post('orders/$id/status/', data: {
      'statut': statut,
      'note': note,
      if (preparateurId != null) 'preparateur_id': preparateurId,
      if (livreurId != null) 'livreur_id': livreurId,
      if (assignedAt != null) 'assigned_at': assignedAt.toUtc().toIso8601String(),
    });
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Annulation gérant (restitue le stock si déjà déduit) — voir
  /// orders/services.py::cancel_order.
  Future<Order> cancel(int id, {String note = ''}) async {
    final response = await _dio.post('orders/$id/cancel/', data: {'note': note});
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Modification (gérant, uniquement tant que "Nouvelle") — les articles
  /// restent modifiables à ce stade puisque rien n'est encore déduit du
  /// stock, voir orders/views.py::partial_update.
  Future<Order> update(
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
    final response = await _dio.patch('orders/$id/', data: {
      if (clientNom != null) 'client_nom': clientNom,
      if (telephone != null) 'telephone': telephone,
      if (livraisonZone != null) 'livraison_zone': livraisonZone,
      if (adresseLivraison != null) 'adresse_livraison': adresseLivraison,
      if (modePaiement != null) 'mode_paiement': modePaiement,
      if (dateCommande != null) 'date_commande': dateCommande.toUtc().toIso8601String(),
      if (notePreparateur != null) 'note_preparateur': notePreparateur,
      if (noteLivreur != null) 'note_livreur': noteLivreur,
      if (items != null) 'items': items.map((e) => e.toJson()).toList(),
    });
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Suppression (gérant, uniquement tant que "Nouvelle").
  Future<void> delete(int id) => _dio.delete('orders/$id/');

  /// Liste des préparateurs/livreurs du magasin pour le sélecteur
  /// d'affectation du gérant — voir orders/views.py::available_staff.
  /// [dateCommande] (LIVREUR uniquement) : signale (sans bloquer) un conflit
  /// d'horaire avec une autre commande déjà (pré-)assignée à ce livreur le
  /// même jour/heure.
  Future<List<StaffOption>> availableStaff(String role, {DateTime? dateCommande}) async {
    final response = await _dio.get('orders/available-staff/', queryParameters: {
      'role': role,
      if (dateCommande != null) 'date_commande': dateCommande.toUtc().toIso8601String(),
    });
    return (response.data as List).map((e) => StaffOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Pré-assigne un livreur avant que la commande soit Prête, sans changer
  /// son statut — réutilisé automatiquement au passage "En livraison" (voir
  /// orders/services.py::assign_livreur_early/_resolve_assignee).
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

  /// Zones de livraison configurables (nom + prix) — CRUD côté Paramètres
  /// web, lecture seule ici pour peupler le sélecteur de zone (voir
  /// orders/views.py::DeliveryZoneOptionViewSet).
  Future<List<DeliveryZoneOption>> deliveryZones() async {
    final response = await _dio.get('orders/delivery-zones/');
    return (response.data as List)
        .map((e) => DeliveryZoneOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
