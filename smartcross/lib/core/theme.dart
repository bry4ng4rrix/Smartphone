import 'package:flutter/material.dart';

/// Bleu Smartphone.Mg — couleur de seed du thème Material 3.
const Color kSeedColor = Color(0xFF2563EB);

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kSeedColor, brightness: Brightness.light);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
    ),
  );
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kSeedColor, brightness: Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
    ),
  );
}

/// Palette fixe pour les graphiques du dashboard.
const List<Color> kChartPalette = [
  Color(0xFF2563EB),
  Color(0xFF06B6D4),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF64748B),
];

/// Couleurs de statut de commande (§5 README) — réutilisées par les badges.
Color statusColor(BuildContext context, String apiStatus) {
  switch (apiStatus) {
    case 'NOUVELLE':
      return const Color(0xFF64748B);
    case 'EN_PREPARATION':
      return const Color(0xFFF59E0B);
    case 'PRETE':
      return const Color(0xFF2563EB);
    case 'EN_LIVRAISON':
      return const Color(0xFF8B5CF6);
    case 'LIVRE':
      return const Color(0xFF10B981);
    case 'RETOUR':
      return const Color(0xFFEF4444);
    default:
      return Theme.of(context).colorScheme.outline;
  }
}
