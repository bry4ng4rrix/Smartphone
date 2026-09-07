import 'package:dio/dio.dart';

import '../../core/api_client.dart';
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
    String note = '',
    String adresseLivraison = '',
    DateTime? dateCommande,
  }) async {
    final response = await _dio.post('orders/', data: {
      'client_nom': clientNom,
      'telephone': telephone,
      'livraison_zone': livraisonZone,
      'adresse_livraison': adresseLivraison,
      'note': note,
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
  }) async {
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

  /// Liste des préparateurs/livreurs du magasin pour le sélecteur
  /// d'affectation du gérant — voir orders/views.py::available_staff.
  Future<List<StaffOption>> availableStaff(String role) async {
    final response = await _dio.get('orders/available-staff/', queryParameters: {'role': role});
    return (response.data as List).map((e) => StaffOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
