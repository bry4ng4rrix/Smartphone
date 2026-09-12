import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thème clair / sombre — portage du `ThemeProvider` de next-themes du web
/// (`frontend/app/layout.tsx` : `defaultTheme="system"`, `enableSystem`) et
/// du bouton Soleil / Lune de la TopBar (`setTheme(theme === 'dark' ?
/// 'light' : 'dark')`).
///
/// Le choix est mémorisé sur l'appareil (le web le garde en localStorage) ;
/// tant que l'utilisateur n'a rien choisi, l'app suit le système.
const _kThemeModeKey = 'theme_mode';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kThemeModeKey);
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null && mode != state) state = mode;
    } catch (_) {
      // Préférence illisible : on reste sur le thème système.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, mode.name);
    } catch (_) {
      // Non bloquant : le thème est appliqué même s'il n'est pas mémorisé.
    }
  }

  /// Le bouton de la TopBar : sombre -> clair, sinon -> sombre. Quand le
  /// thème suit le système, on part de ce que l'écran affiche réellement
  /// ([Brightness] courante) — exactement `theme === 'dark'` de next-themes,
  /// qui résout « system » avec `prefers-color-scheme`.
  Future<void> toggle(Brightness platformBrightness) {
    final isDark = switch (state) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    return set(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
