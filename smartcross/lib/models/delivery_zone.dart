import 'json_utils.dart';

/// Code réservé du retrait sur place : structurellement à part (pas de
/// livreur, pas de frais), ce n'est pas une zone gérable en CRUD — voir
/// orders/models.py::Order.livraison_zone.
const String kRecuperationCode = 'RECUPERATION';

/// Zone de livraison configurable (nom + prix), gérée en CRUD dans les
/// Paramètres côté web — voir orders/models.py::DeliveryZoneOption. Les
/// commandes stockent `code`, jamais l'id ni le nom : renommer une zone ou
/// changer son prix n'affecte donc pas les commandes déjà passées.
class DeliveryZoneOption {
  const DeliveryZoneOption({
    required this.id,
    required this.code,
    required this.nom,
    required this.prix,
    required this.actif,
  });

  final int id;
  final String code;
  final String nom;
  final double prix;
  final bool actif;

  factory DeliveryZoneOption.fromJson(Map<String, dynamic> json) {
    return DeliveryZoneOption(
      id: asInt(json['id']),
      code: asString(json['code']),
      nom: asString(json['nom']),
      prix: asDouble(json['prix']),
      actif: json['actif'] as bool? ?? true,
    );
  }

  String get label => '$nom (${prix.round()} Ar)';
}

/// Résolution d'un libellé lisible à partir du code stocké sur la commande.
/// Les zones sont chargées via `deliveryZonesProvider` ; ce cache mémoire
/// permet aux widgets non-Riverpod (ex: order_confirm_dialog) d'afficher un
/// nom plutôt qu'un code brut, avec repli sur le code si rien n'est chargé.
class DeliveryZoneCatalog {
  static List<DeliveryZoneOption> zones = const [];

  static DeliveryZoneOption? byCode(String code) {
    for (final z in zones) {
      if (z.code == code) return z;
    }
    return null;
  }

  /// "Zone 1 (3000 Ar)" — pour un écran de détail.
  static String labelFor(String code) {
    if (code == kRecuperationCode) return 'Récupération (0 Ar)';
    return byCode(code)?.label ?? code;
  }

  /// "Zone 1" — pour les listes/cartes/résumés.
  static String shortLabelFor(String code) {
    if (code == kRecuperationCode) return 'Récupération';
    return byCode(code)?.nom ?? code;
  }

  static double fraisFor(String code) {
    if (code == kRecuperationCode) return 0;
    return byCode(code)?.prix ?? 0;
  }
}
