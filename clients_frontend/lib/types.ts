/**
 * Types de l'API de la boutique en ligne — copie fidèle des structures
 * décrites dans `client_endpoint.md` (../client_endpoint.md). Aucun champ
 * inventé : ce que le backend n'expose pas n'existe pas ici non plus.
 *
 * Il n'y a plus de type de compte ni de jeton : la boutique ne demande pas
 * d'inscription.
 */

// --------------------------------------------------------------------- //
// Catalogue public
// --------------------------------------------------------------------- //

/**
 * Coordonnées du point de vente. Chaînes vides tant que la boutique ne les a
 * pas renseignées — on n'affiche alors rien, plutôt qu'un vide.
 */
export type CoordonneesBoutique = {
  adresse: string;
  telephone: string;
  telephone_2: string;
};

export type Boutique = {
  id: number;
  nom: string;
  description: string | null;
  logo: string | null;
} & CoordonneesBoutique;

export type Zone = {
  code: string;
  nom: string;
  prix: number;
};

/** Le retrait sur place porte, en plus du tarif, l'endroit où venir. */
export type PointRetrait = Zone & { boutique: string } & CoordonneesBoutique;

export type ZonesReponse = {
  boutique: number;
  recuperation: PointRetrait;
  zones: Zone[];
};

export type Categorie = {
  id: number;
  nom: string;
  avec_couleurs: boolean;
  boutique: number;
};

export type SousType = {
  id: number;
  nom: string;
  categorie: number;
  categorie_nom: string;
};

export type Marque = {
  id: number;
  nom: string;
  boutique: number;
};

export type Couleur = {
  id: number;
  nom: string;
  boutique: number;
};

/** Une couleur d'un produit. `disponible` remplace toute quantité chiffrée. */
export type Variante = {
  id: number;
  couleur: string;
  disponible: boolean;
};

export type Produit = {
  id: number;
  nom: string;
  nom_complet: string;
  prix_vente: number;
  photo: string | null;
  categorie: { id: number; nom: string };
  sous_type: { id: number; nom: string };
  marque: { id: number; nom: string };
  boutique: { id: number; nom: string };
  disponible: boolean;
  variantes: Variante[];
};

export type Page<T> = {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
};

// --------------------------------------------------------------------- //
// Commande
// --------------------------------------------------------------------- //

/** Ce que le navigateur envoie. Aucun montant : le serveur les calcule. */
export type CommandeInput = {
  /**
   * Plus envoyé : le serveur déduit la boutique de CHAQUE article et éclate
   * le panier en une commande par boutique concernée. Le navigateur ne
   * choisit pas la destination d'une commande.
   */
  items: { variante: number; quantite: number; prix_attendu?: string | number }[];
  livraison_zone: string;
  client_nom: string;
  telephone: string;
  telephone_2?: string;
  adresse_livraison?: string;
  note?: string;
};

/**
 * Réponse de `POST /commandes/` : UNE commande par boutique concernée.
 *
 * Un panier d'une seule boutique — le cas courant — renvoie une liste d'un
 * seul élément. Un panier mêlant deux boutiques en renvoie deux, chacune avec
 * son numéro, ses frais et ses coordonnées de retrait.
 */
export type CommandesReponse = {
  commandes: Commande[];
};

export type CommandeLigne = {
  id: number;
  produit: { id: number; nom: string; nom_complet: string };
  couleur: string;
  quantite: number;
  prix_unitaire: number;
  total: number;
};

/**
 * Accusé renvoyé APRÈS la commande, pour l'écran de confirmation.
 *
 * Il n'existe pas d'endpoint pour la relire : sans compte, rien ne
 * permettrait d'authentifier celui qui la demanderait. Le gérant rappelle au
 * numéro fourni.
 */
export type Commande = {
  id: number;
  numero: string;
  statut: string;
  statut_label: string;
  date_commande: string;
  boutique: { id: number; nom: string } & CoordonneesBoutique;
  livraison_zone: string;
  adresse_livraison: string | null;
  client_nom: string;
  telephone: string;
  telephone_2: string;
  note: string | null;
  frais_livraison: number;
  total_a_payer: number;
  items: CommandeLigne[];
  created_at: string;
};

// --------------------------------------------------------------------- //
// Commande spéciale (Housse / Cache-écran)
// --------------------------------------------------------------------- //
//
// ATTENTION : ces structures ne sont PAS encore servies par le backend.
// Elles décrivent le contrat spécifié dans `client_endpoint.md`
// (§ « Commande spéciale Housse / Cache-écran ») et restent inutilisées
// tant que `ENVOI_COMMANDE_SPECIALE_ACTIF` est faux.

export const STATUTS_COMMANDE_SPECIALE = [
  "EN_ATTENTE_ACOMPTE",
  "ACOMPTE_PAYE",
  "EN_ATTENTE_VALIDATION",
  "APPROUVEE",
  "REFUSEE",
  "EN_COURS",
  "PRETE",
  "LIVREE",
  "ANNULEE",
] as const;

export type StatutCommandeSpeciale = (typeof STATUTS_COMMANDE_SPECIALE)[number];

export type CommandeSpecialeInput = {
  boutique: number;
  categorie: number;
  telephone_marque: string;
  telephone_modele: string;
  produit_souhaite: string;
  quantite: number;
  contact_nom: string;
  contact_telephone: string;
  precision?: string;
};

export type CommandeSpeciale = {
  id: number;
  numero: string;
  statut: StatutCommandeSpeciale;
  statut_label: string;
  boutique: { id: number; nom: string };
  categorie: { id: number; nom: string };
  telephone_marque: string;
  telephone_modele: string;
  produit_souhaite: string;
  quantite: number;
  contact_nom: string;
  contact_telephone: string;
  precision: string | null;
  /** Chiffrés par la boutique — `null` tant qu'elle n'a pas devisé. */
  prix_unitaire: number | null;
  total: number | null;
  acompte_du: number | null;
  acompte_paye: number;
  reste_a_payer: number | null;
  /** Calculée par le serveur : ne jamais la déduire côté client. */
  date_disponibilite_estimee: string | null;
  created_at: string;
  updated_at: string;
};
