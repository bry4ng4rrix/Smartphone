import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';

/// Notifications système (barre de notifications du téléphone) pour les
/// événements temps réel de l'application : messages privés et notifications
/// métier (nouvelle commande, commande prête, dépense à valider…).
///
/// Le web n'a que le toast de la TopBar ; sur mobile, quand l'application
/// n'est pas au premier plan, l'événement reçu sur `ws/notifications/` est
/// remis au système (son + vibration) et un appui ouvre l'écran concerné.
/// Aucune dépendance à un service tiers : tant que la connexion WebSocket
/// vit (application ouverte ou en arrière-plan), les notifications arrivent.
class PushNotificationsService {
  PushNotificationsService._();
  static final PushNotificationsService instance = PushNotificationsService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;
  int _sequence = 0;

  /// Appelé avec le chemin de destination quand l'utilisateur appuie sur une
  /// notification (posé par le bootstrap une fois le routeur disponible).
  void Function(String path)? onOpen;

  /// Chemin d'une notification sur laquelle l'app a été LANCÉE (appui alors
  /// que l'app était fermée) — consommé par le bootstrap après connexion.
  String? _pendingLaunchPath;

  static const _channelMessages = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'Messages privés de la messagerie interne',
    importance: Importance.high,
  );
  static const _channelEvents = AndroidNotificationChannel(
    'notifications',
    'Notifications',
    description: 'Commandes, dépenses, caisse et autres notifications',
    importance: Importance.high,
  );

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> init() async {
    if (_initialised || !isSupported) return;
    _initialised = true;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_notification'),
      // La permission est demandée explicitement après connexion
      // (voir [requestPermission]), pas au premier lancement.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final path = response.payload;
          if (path == null || path.isEmpty) return;
          final handler = onOpen;
          if (handler != null) {
            handler(path);
          } else {
            _pendingLaunchPath = path;
          }
        },
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(_channelMessages);
        await android.createNotificationChannel(_channelEvents);
      }
      // Application ouverte par un appui sur une notification (app fermée).
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final launchPayload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && launchPayload != null && launchPayload.isNotEmpty) {
        _pendingLaunchPath = launchPayload;
      }
    } catch (e) {
      debugPrint('Notifications système indisponibles : $e');
      _initialised = false;
    }
  }

  /// Chemin en attente (lancement par notification), consommé une seule fois.
  String? takePendingLaunchPath() {
    final p = _pendingLaunchPath;
    _pendingLaunchPath = null;
    return p;
  }

  /// Permission d'afficher des notifications (Android 13+ / iOS) ; sans
  /// effet ailleurs. Renvoie `true` si accordée (ou non requise).
  Future<bool> requestPermission() async {
    if (!_initialised) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? true;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (mac != null) return await mac.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('Permission de notification refusée : $e');
    }
    return false;
  }

  /// Affiche la notification système correspondant à une notification métier
  /// reçue en temps réel.
  Future<void> showAppNotification(AppNotification n) async {
    if (!_initialised) return;
    final isChat = n.type == 'chat';
    final channel = isChat ? _channelMessages : _channelEvents;
    final content = pushContentFor(n);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: isChat ? AndroidNotificationCategory.message : AndroidNotificationCategory.event,
        styleInformation: BigTextStyleInformation(content.body),
        groupKey: channel.id,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
      macOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
    );
    try {
      await _plugin.show(
        id: _nextId(n),
        title: content.title,
        body: content.body,
        notificationDetails: details,
        payload: content.path,
      );
    } catch (e) {
      debugPrint('Notification système non affichée : $e');
    }
  }

  /// Identifiant stable pour une notification persistée (un même événement
  /// reçu deux fois remplace la notification affichée au lieu de la doubler),
  /// séquentiel sinon.
  int _nextId(AppNotification n) {
    if (n.isPersisted) return 100000 + (n.id % 1000000);
    _sequence = (_sequence + 1) % 100000;
    return _sequence;
  }
}

/// Titre, corps et destination d'une notification système.
class PushContent {
  const PushContent({required this.title, required this.body, required this.path});

  final String title;
  final String body;

  /// Destination à l'appui : `/chats` pour un message privé, `order:CMD-…`
  /// (numéro cité dans le message, résolu en fiche de commande par le
  /// bootstrap) ou `/notifications`.
  final String path;
}

final RegExp _messagePriveRegExp = RegExp(r'^Message privé de (.+?) : ?(.*)$', dotAll: true);

/// Dérive le contenu à afficher : un message privé (« Message privé de X :
/// … », users/signals.py) devient une notification « X » / texte du message
/// (« 📷 Photo » si le message n'a pas de texte) qui ouvre la messagerie ;
/// les autres gardent le libellé du type comme titre.
PushContent pushContentFor(AppNotification n) {
  if (n.type == 'chat') {
    final m = _messagePriveRegExp.firstMatch(n.message.trim());
    if (m != null) {
      final body = m.group(2)!.trim();
      return PushContent(title: m.group(1)!.trim(), body: body.isEmpty ? '📷 Photo' : body, path: '/chats');
    }
    return PushContent(title: 'Nouveau message', body: n.message, path: '/chats');
  }
  final numero = n.orderNumero;
  return PushContent(
    title: n.typeLabel,
    body: n.message,
    path: numero != null && numero.isNotEmpty ? 'order:$numero' : '/notifications',
  );
}
