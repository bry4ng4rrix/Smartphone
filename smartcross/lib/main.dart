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
  await PushNotificationsService.instance.init();
  runApp(const ProviderScope(child: SmartphoneMgApp()));
}

class SmartphoneMgApp extends ConsumerWidget {
  const SmartphoneMgApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeBootstrapProvider);
    ref.watch(pushNotificationsBootstrapProvider);
    final router = ref.watch(routerProvider);
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
