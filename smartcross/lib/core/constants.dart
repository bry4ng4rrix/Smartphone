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
enum OrderStatus { nouvelle, enPreparation, prete, enLivraison, livre, retour, annulee }

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
      case 'ANNULEE':
        return OrderStatus.annulee;
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
      case OrderStatus.annulee:
        return 'ANNULEE';
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
        return 'Livré';
      case OrderStatus.retour:
        return 'Retour';
      case OrderStatus.annulee:
        return 'Annulée';
    }
  }
}

// Les zones de livraison ne sont plus une énumération figée : elles sont
// configurables (nom + prix) dans les Paramètres — voir
// models/delivery_zone.dart (DeliveryZoneOption/DeliveryZoneCatalog) et
// orders/models.py::DeliveryZoneOption côté serveur.

/// Le client paie avant (à la commande) ou à la livraison (contre
/// remboursement) — sans effet sur le stock/statut, juste indicatif pour le
/// livreur/gérant (§ demande). Sans objet pour un retrait sur place.
enum PaymentMode { avant, livraison }

extension PaymentModeX on PaymentMode {
  static PaymentMode fromApi(String? value) => value == 'AVANT' ? PaymentMode.avant : PaymentMode.livraison;

  String get apiValue => this == PaymentMode.avant ? 'AVANT' : 'LIVRAISON';

  String get label => this == PaymentMode.avant ? 'Paiement avant la livraison' : 'Paiement à la livraison';
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
