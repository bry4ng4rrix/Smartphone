import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push_notifications_service.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'state/push_notifications_provider.dart';
import 'state/realtime_provider.dart';
import 'state/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Notifications système (messages, commandes…) — canaux Android et
  // gestion d'un lancement par appui sur une notification.
  await PushNotificationsService.instance.init();
  runApp(const ProviderScope(child: SmartphoneMgApp()));
}

class SmartphoneMgApp extends ConsumerWidget {
  const SmartphoneMgApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instancie le bootstrap WebSocket une seule fois à la racine — il
    // écoute lui-même les changements d'auth pour se (dé)connecter.
    ref.watch(realtimeBootstrapProvider);
    // Relaie le flux temps réel vers la barre de notifications du téléphone
    // quand l'app n'est pas au premier plan.
    ref.watch(pushNotificationsBootstrapProvider);
    final router = ref.watch(routerProvider);
    // Clair / sombre / système — bouton Soleil / Lune de la TopBar.
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Smartphone.Mg',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
