import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/permissions.dart';
import '../core/push_notifications_service.dart';
import '../core/router.dart';
import '../models/app_notification.dart';
import 'auth_provider.dart';
import 'notifications_provider.dart';

/// Branche les notifications système sur le flux temps réel
/// (`ws/notifications/`, déjà utilisé par la cloche et le toast de la
/// TopBar) :
///
/// * application AU PREMIER PLAN : rien ici, le toast in-app de la TopBar
///   (comme le `toast.info` du web) suffit ;
/// * application en arrière-plan (autre appli, écran éteint) : chaque
///   notification reçue — message privé, nouvelle commande, commande prête,
///   dépense à valider… — est remise à la barre de notifications du
///   téléphone, avec son ;
/// * appui sur la notification : ouverture de la messagerie, de la fiche de
///   la commande citée ou de la page Notifications (y compris quand l'app
///   était fermée et est lancée par cet appui) ;
/// * la permission (Android 13+, iOS) est demandée une fois connecté.
///
/// À instancier une seule fois à la racine (voir `main.dart`), comme
/// [realtimeBootstrapProvider].
class PushNotificationsBootstrap {
  PushNotificationsBootstrap(this.ref) {
    final service = PushNotificationsService.instance;
    service.onOpen = (path) => unawaited(_open(path));

    ref.listen(authProvider, (previous, next) {
      final connecte = next.status == AuthStatus.authenticated;
      if (connecte && previous?.status != AuthStatus.authenticated) {
        unawaited(service.requestPermission());
        final pending = service.takePendingLaunchPath();
        if (pending != null) unawaited(_open(pending));
      }
    }, fireImmediately: true);

    ref.listen<AsyncValue<AppNotification>>(incomingNotificationProvider, (previous, next) {
      // Une trame = un AsyncData ; un état d'erreur/chargement peut encore
      // porter la valeur précédente, qu'il ne faut pas ré-annoncer.
      if (next is! AsyncData<AppNotification>) return;
      if (_auPremierPlan) return;
      unawaited(service.showAppNotification(next.value));
    });
  }

  final Ref ref;

  /// `resumed` (ou état inconnu au tout premier rendu) = l'utilisateur voit
  /// l'application : le toast de la TopBar prend le relais.
  bool get _auPremierPlan {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Destination d'un appui : `/chats`, `/notifications` ou `order:CMD-…`
  /// (numéro résolu en identifiant, comme « Voir la commande » de la page
  /// Notifications ; repli sur la page Notifications si introuvable).
  Future<void> _open(String path) async {
    if (ref.read(authProvider).status != AuthStatus.authenticated) {
      // Pas encore connecté (lancement par notification) : le bootstrap
      // rejouera le chemin après connexion.
      PushNotificationsService.instance.onOpen = null;
      return;
    }
    final router = ref.read(routerProvider);
    if (!path.startsWith('order:')) {
      router.go(path);
      return;
    }
    final numero = path.substring('order:'.length);
    try {
      final user = ref.read(authProvider).user;
      final employe = user != null && (user.isPreparateur || user.isLivreur);
      final id = await ref.read(notificationsRepositoryProvider).findOrderIdByNumero(numero, employe: employe);
      if (id != null) {
        router.go('/orders');
        router.push('/orders/$id');
        return;
      }
    } catch (_) {
      // Résolution impossible (réseau, droits) : page Notifications.
    }
    router.go('/notifications');
  }
}

final pushNotificationsBootstrapProvider = Provider<PushNotificationsBootstrap>((ref) {
  return PushNotificationsBootstrap(ref);
});
