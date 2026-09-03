import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/order.dart';

/// `/api/orders/` — vue filtrée par rôle côté serveur (§7.1/7.2/7.3 README) :
/// le même endpoint `list()` renvoie des champs et un sous-ensemble
/// différents selon que l'appelant est gérant, préparateur ou livreur.
class OrdersRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<Order>> list({String? statut, DateTime? dateDebut, DateTime? dateFin}) async {
    final response = await _dio.get('orders/', queryParameters: {
      if (statut != null) 'statut': statut,
      if (dateDebut != null) 'date_debut': _fmt(dateDebut),
      if (dateFin != null) 'date_fin': _fmt(dateFin),
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
  /// rôle/transition strictes et l'impact stock (déduction à LIVRE).
  Future<Order> changeStatus(int id, String statut, {String note = ''}) async {
    final response = await _dio.post('orders/$id/status/', data: {'statut': statut, 'note': note});
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
