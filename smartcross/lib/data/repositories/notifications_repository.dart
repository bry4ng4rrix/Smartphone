import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../models/app_notification.dart';
import '../../models/order.dart';
import 'orders_repository.dart';

/// `/api/users/notifications/` — notifications de l'utilisateur connecté,
/// filtrées par rôle côté serveur (users/views.py::NotificationViewSet.
/// get_queryset : admin -> ses magasins + les siennes, gérant -> son
/// magasin + les siennes, employé -> son magasin + les siennes). Miroir de
/// `djangoClient.notifications` (frontend/lib/django-client.ts). Le flux
/// temps réel est géré par `core/notifications_socket_service.dart`.
class NotificationsRepository {
  NotificationsRepository({OrdersRepository? orders}) : _orders = orders ?? OrdersRepository();

  Dio get _dio => ApiClient.instance.dio;
  final OrdersRepository _orders;

  /// GET — tri imposé par le serveur (`ordering = ['-created_at']`, la plus
  /// récente en premier). Sans pagination côté serveur, mais on accepte
  /// aussi l'enveloppe `{results: [...]}` comme le fait le web.
  Future<List<AppNotification>> list() async {
    final response = await _dio.get('users/notifications/');
    return _rows(response.data).map(AppNotification.fromJson).toList();
  }

  /// PATCH `{is_read}` — le serveur (partial_update) ne modifie que ce champ
  /// et renvoie la notification. `djangoClient.notifications.markRead(id,
  /// isRead)` : sert au marquage lu ET au retour en « non lue ».
  Future<AppNotification> setRead(int id, bool isRead) async {
    final response = await _dio.patch('users/notifications/$id/', data: {'is_read': isRead});
    return AppNotification.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AppNotification> markRead(int id) => setRead(id, true);

  /// POST mark-all-read — toutes les notifications visibles par l'appelant.
  Future<void> markAllRead() async {
    await _dio.post('users/notifications/mark-all-read/');
  }

  /// POST bulk-read `{ids}` — sélection marquée lue.
  Future<void> bulkRead(List<int> ids) async {
    if (ids.isEmpty) return;
    await _dio.post('users/notifications/bulk-read/', data: {'ids': ids});
  }

  /// DELETE — le serveur peut refuser (403 `Permission refusée`) une
  /// notification qui n'appartient ni à l'utilisateur ni à son magasin.
  Future<void> delete(int id) async {
    await _dio.delete('users/notifications/$id/');
  }

  /// POST bulk-delete `{ids}` — sélection supprimée (204).
  Future<void> bulkDelete(List<int> ids) async {
    if (ids.isEmpty) return;
    await _dio.post('users/notifications/bulk-delete/', data: {'ids': ids});
  }

  /// POST delete-all — supprime EN BASE toutes les notifications visibles
  /// (204). Irréversible.
  Future<void> deleteAll() async {
    await _dio.post('users/notifications/delete-all/');
  }

  /// Deep-link « voir la commande » : retrouve l'identifiant d'une commande à
  /// partir de son numéro `CMD-{magasin}-{AAAAMMJJ}-{seq}` (le seul lien que
  /// porte une notification, dans son message — pas de clé étrangère, et
  /// aucune recherche par numéro côté API).
  ///
  /// Le numéro date de la CRÉATION de la commande ; sa date de livraison
  /// (`date_commande`, seul critère de filtre du serveur) peut être
  /// postérieure. On interroge donc d'abord une fenêtre de 31 jours à partir
  /// de cette date, puis la liste complète accessible à l'utilisateur.
  /// Pour un préparateur/livreur ([employe]) la liste « historique » (toutes
  /// les commandes qui lui ont été confiées, tous statuts) est la plus
  /// complète ; la file du jour vient ensuite.
  ///
  /// Renvoie `null` si la commande n'est pas trouvée — ou pas accessible à ce
  /// rôle (ex : préparateur pas encore assigné à cette commande).
  Future<int?> findOrderIdByNumero(String numero, {bool employe = false}) async {
    final cible = numero.trim().toUpperCase();
    if (cible.isEmpty) return null;

    int? chercher(List<Order> commandes) {
      for (final o in commandes) {
        if (o.numero.toUpperCase() == cible) return o.id;
      }
      return null;
    }

    final tentatives = <Future<List<Order>> Function()>[
      if (employe) () => _orders.list(historique: true),
      () {
        final jour = _dateFromNumero(cible);
        if (jour == null) return _orders.list();
        return _orders.list(dateDebut: jour, dateFin: jour.add(const Duration(days: 31)));
      },
      () => _orders.list(),
    ];

    for (final tentative in tentatives) {
      final id = chercher(await tentative());
      if (id != null) return id;
    }
    return null;
  }

  /// `CMD-1-20260912-0003` -> 12/09/2026 (jour calendaire d'Antananarivo,
  /// comme `timezone.localdate()` côté serveur).
  static DateTime? _dateFromNumero(String numero) {
    final match = RegExp(r'^CMD-\d+-(\d{4})(\d{2})(\d{2})-\d+$').firstMatch(numero);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  /// DRF renvoie soit une liste brute, soit une enveloppe paginée
  /// `{results: [...]}` — les deux sont acceptées
  /// (`Array.isArray(data) ? data : data.results || []` du web).
  List<Map<String, dynamic>> _rows(dynamic data) {
    final list = data is List
        ? data
        : data is Map
            ? (data['results'] as List? ?? const [])
            : const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
}

/// Identifiants « effacés » localement par « Tout effacer » de la cloche
/// (frontend/components/notifications.tsx) : la notification RESTE en base,
/// elle est seulement retirée de la liste récente du menu déroulant — et de
/// son compteur. Même clé, même plafond que le `localStorage` du web : au-delà
/// de 200 identifiants, les plus anciens ressortent de l'oubli.
class DismissedNotificationsStore {
  static const String key = 'stockv2_dismissed_notification_ids';
  static const int maxIds = 200;

  /// Lecture défensive (`loadDismissed()` du web) : vide si rien n'est
  /// enregistré ou si le contenu est invalide.
  Future<Set<int>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return <int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>{};
      return decoded.map((e) => e is num ? e.toInt() : int.tryParse('$e')).whereType<int>().toSet();
    } catch (_) {
      return <int>{};
    }
  }

  /// Écriture bornée aux [maxIds] derniers (`ids.slice(-200)` du web).
  Future<void> save(Iterable<int> ids) async {
    final list = ids.toList();
    final kept = list.length > maxIds ? list.sublist(list.length - maxIds) : list;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(kept));
    } catch (_) {
      // Stockage indisponible : la liste reste effacée pour la session en
      // cours, elle réapparaîtra au prochain lancement.
    }
  }
}
