import 'dart:async';

import 'ws_manager.dart';

/// Événement de synchronisation de données (`DataSyncEvent` de
/// frontend/lib/contexts/DataSyncContext.tsx) : le serveur pousse
/// `{model, action, id, magasin_id}` à chaque création / modification /
/// suppression d'un modèle suivi (users/broadcast.py::broadcast_data_event) —
/// product_variant, stock_movement, order, order_status_history,
/// supplier_order, caisse_session, caisse_movement.
class DataSyncEvent {
  const DataSyncEvent({required this.model, required this.action, this.id, this.magasinId});

  final String model;
  final String action;
  final int? id;
  final int? magasinId;

  static DataSyncEvent? fromJson(Map<String, dynamic> json) {
    final model = json['model'];
    if (model is! String || model.isEmpty) return null;
    return DataSyncEvent(
      model: model,
      action: json['action'] is String ? json['action'] as String : '',
      id: json['id'] is num ? (json['id'] as num).toInt() : null,
      magasinId: json['magasin_id'] is num ? (json['magasin_id'] as num).toInt() : null,
    );
  }
}

/// Client de `ws/data/` — le second canal temps réel du web (le premier,
/// `ws/notifications/`, ne porte que les notifications). Sans lui, une
/// transition de commande, un mouvement de stock ou un mouvement de caisse
/// qui ne génère PAS de notification n'était jamais répercuté sur les
/// écrans ouverts.
class DataSyncSocketService extends WsManager {
  DataSyncSocketService._();
  static final DataSyncSocketService instance = DataSyncSocketService._();

  final _controller = StreamController<DataSyncEvent>.broadcast();
  Stream<DataSyncEvent> get events => _controller.stream;

  @override
  void onMessage(Map<String, dynamic> data) {
    final event = DataSyncEvent.fromJson(data);
    if (event != null) _controller.add(event);
  }
}
