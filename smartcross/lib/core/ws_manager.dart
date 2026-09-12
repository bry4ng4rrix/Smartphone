import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connexion WebSocket authentifiée par token en query string, avec
/// reconnexion automatique après 3s. [buildUri] est rappelé à chaque
/// tentative (y compris les reconnexions) pour inclure un token à jour.
abstract class WsManager {
  Future<Uri> Function()? _buildUri;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _closedByUser = false;
  bool _connecting = false;

  bool get isConnected => _channel != null;

  void connect(Future<Uri> Function() buildUri) {
    _buildUri = buildUri;
    if (_connecting || isConnected) return;
    _closedByUser = false;
    _doConnect();
  }

  Future<void> _doConnect() async {
    final builder = _buildUri;
    if (builder == null) return;
    _connecting = true;
    Uri? uri;
    try {
      uri = await builder();
      // Ping toutes les 30 s (mobile) : une connexion tuée en silence par le
      // système (appli en arrière-plan, changement de réseau) est détectée
      // et rouverte, au lieu de rester « connectée » sans plus rien recevoir.
      final WebSocketChannel channel = kIsWeb
          ? WebSocketChannel.connect(uri)
          : IOWebSocketChannel.connect(uri, pingInterval: const Duration(seconds: 30));
      await channel.ready;
      _channel = channel;
      onStatusChange(true);
      _sub = channel.stream.listen(
        (event) {
          try {
            final data = jsonDecode(event as String) as Map<String, dynamic>;
            onMessage(data);
          } catch (_) {
            // message non JSON, ignoré
          }
        },
        onDone: () {
          debugPrint('[WsManager] connexion fermée ($uri, code=${channel.closeCode})');
          _handleDisconnect();
        },
        onError: (e) {
          debugPrint('[WsManager] erreur sur le flux WS ($uri) : $e');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
      _connecting = false;
    } catch (e) {
      _connecting = false;
      debugPrint('[WsManager] échec de connexion à $uri : $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _channel = null;
    onStatusChange(false);
    if (_closedByUser || _buildUri == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _doConnect);
  }

  /// Envoie une trame texte brute sur la connexion active (no-op si fermée).
  void send(String data) {
    _channel?.sink.add(data);
  }

  /// Rouvre immédiatement la connexion si elle est tombée (retour de
  /// l'application au premier plan) — sans attendre le délai de reconnexion.
  void ensureConnected() {
    if (_closedByUser || _buildUri == null || _connecting || isConnected) return;
    _reconnectTimer?.cancel();
    _doConnect();
  }

  void disconnect() {
    _closedByUser = true;
    _buildUri = null;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    onStatusChange(false);
  }

  /// Appelé pour chaque message JSON reçu du serveur.
  void onMessage(Map<String, dynamic> data);

  /// Appelé à chaque changement d'état de connexion (badge "Temps réel").
  void onStatusChange(bool connected) {}
}
