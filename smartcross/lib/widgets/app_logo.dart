import 'package:flutter/material.dart';

/// Logo Smartphone.Mg (assets/logo.png) — même image que l'icône de
/// l'application et que le favicon du web. Carré arrondi, fond blanc du
/// logo conservé (il porte le nom et le slogan).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.radius = 18});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'Smartphone.Mg',
      ),
    );
  }
}
