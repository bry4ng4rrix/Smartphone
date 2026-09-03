/// Rôles utilisateur (§4 README) — droits stricts contrôlés côté backend,
/// répliqués ici pour piloter la navigation et l'affichage.
enum UserRole { gerant, preparateur, livreur, unknown }

extension UserRoleX on UserRole {
  static UserRole fromApi(String? value) {
    switch (value) {
      case 'GERANT':
        return UserRole.gerant;
      case 'PREPARATEUR':
        return UserRole.preparateur;
      case 'LIVREUR':
        return UserRole.livreur;
      default:
        return UserRole.unknown;
    }
  }

  String get apiValue {
    switch (this) {
      case UserRole.gerant:
        return 'GERANT';
      case UserRole.preparateur:
        return 'PREPARATEUR';
      case UserRole.livreur:
        return 'LIVREUR';
      case UserRole.unknown:
        return '';
    }
  }

  String get label {
    switch (this) {
      case UserRole.gerant:
        return 'Gérant';
      case UserRole.preparateur:
        return 'Préparateur';
      case UserRole.livreur:
        return 'Livreur';
      case UserRole.unknown:
        return 'Inconnu';
    }
  }
}

/// Les 6 statuts de commande, dans l'ordre strict du workflow (§5 README).
enum OrderStatus { nouvelle, enPreparation, prete, enLivraison, livre, retour }

extension OrderStatusX on OrderStatus {
  static OrderStatus fromApi(String? value) {
    switch (value) {
      case 'NOUVELLE':
        return OrderStatus.nouvelle;
      case 'EN_PREPARATION':
        return OrderStatus.enPreparation;
      case 'PRETE':
        return OrderStatus.prete;
      case 'EN_LIVRAISON':
        return OrderStatus.enLivraison;
      case 'LIVRE':
        return OrderStatus.livre;
      case 'RETOUR':
        return OrderStatus.retour;
      default:
        return OrderStatus.nouvelle;
    }
  }

  String get apiValue {
    switch (this) {
      case OrderStatus.nouvelle:
        return 'NOUVELLE';
      case OrderStatus.enPreparation:
        return 'EN_PREPARATION';
      case OrderStatus.prete:
        return 'PRETE';
      case OrderStatus.enLivraison:
        return 'EN_LIVRAISON';
      case OrderStatus.livre:
        return 'LIVRE';
      case OrderStatus.retour:
        return 'RETOUR';
    }
  }

  String get label {
    switch (this) {
      case OrderStatus.nouvelle:
        return 'Nouvelle';
      case OrderStatus.enPreparation:
        return 'En préparation';
      case OrderStatus.prete:
        return 'Prête';
      case OrderStatus.enLivraison:
        return 'En livraison';
      case OrderStatus.livre:
        return 'Livrée';
      case OrderStatus.retour:
        return 'Retour';
    }
  }
}

enum DeliveryZone { zone1, zone2, zone3, recuperation }

extension DeliveryZoneX on DeliveryZone {
  static DeliveryZone fromApi(String? value) {
    switch (value) {
      case 'ZONE1':
        return DeliveryZone.zone1;
      case 'ZONE2':
        return DeliveryZone.zone2;
      case 'ZONE3':
        return DeliveryZone.zone3;
      default:
        return DeliveryZone.recuperation;
    }
  }

  String get apiValue {
    switch (this) {
      case DeliveryZone.zone1:
        return 'ZONE1';
      case DeliveryZone.zone2:
        return 'ZONE2';
      case DeliveryZone.zone3:
        return 'ZONE3';
      case DeliveryZone.recuperation:
        return 'RECUPERATION';
    }
  }

  String get label {
    switch (this) {
      case DeliveryZone.zone1:
        return 'Zone 1 (3 000 Ar)';
      case DeliveryZone.zone2:
        return 'Zone 2 (4 000 Ar)';
      case DeliveryZone.zone3:
        return 'Zone 3 (5 000 Ar)';
      case DeliveryZone.recuperation:
        return 'Récupération (0 Ar)';
    }
  }
}

enum StockMovementType { entree, sortie }

extension StockMovementTypeX on StockMovementType {
  static StockMovementType fromApi(String? value) =>
      value == 'SORTIE' ? StockMovementType.sortie : StockMovementType.entree;

  String get apiValue => this == StockMovementType.entree ? 'ENTREE' : 'SORTIE';

  String get label => this == StockMovementType.entree ? 'Entrée' : 'Sortie';
}

enum SupplierOrderStatus { brouillon, commande, recu }

extension SupplierOrderStatusX on SupplierOrderStatus {
  static SupplierOrderStatus fromApi(String? value) {
    switch (value) {
      case 'COMMANDE':
        return SupplierOrderStatus.commande;
      case 'RECU':
        return SupplierOrderStatus.recu;
      default:
        return SupplierOrderStatus.brouillon;
    }
  }

  String get label {
    switch (this) {
      case SupplierOrderStatus.brouillon:
        return 'Brouillon';
      case SupplierOrderStatus.commande:
        return 'Commandé';
      case SupplierOrderStatus.recu:
        return 'Reçu';
    }
  }
}

/// Largeur en dessous de laquelle l'app bascule en layout mobile (drawer)
/// au lieu de la sidebar permanente desktop/tablette.
const double kDesktopBreakpoint = 900;

double dialogWidth(double available, double desired) =>
    desired < available - 48 ? desired : available - 48;
