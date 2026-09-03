import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'state/realtime_provider.dart';

void main() {
  runApp(const ProviderScope(child: SmartphoneMgApp()));
}

class SmartphoneMgApp extends ConsumerWidget {
  const SmartphoneMgApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instancie le bootstrap WebSocket une seule fois à la racine — il
    // écoute lui-même les changements d'auth pour se (dé)connecter.
    ref.watch(realtimeBootstrapProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Smartphone.Mg',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
