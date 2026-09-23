/**
 * Types de l'API client — copie fidèle des structures décrites dans
 * `client_endpoint.md` (../client_endpoint.md). Aucun champ inventé :
 * ce que le backend n'expose pas n'existe pas ici non plus.
 */

// --------------------------------------------------------------------- //
// Catalogue public
// --------------------------------------------------------------------- //

export type Boutique = {
  id: number;
  nom: string;
  description: string | null;
  logo: string | null;
};

export type Zone = {
  code: string;
  nom: string;
  prix: number;
};

export type ZonesReponse = {
  boutique: number;
  recuperation: Zone;
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
// Compte client
// --------------------------------------------------------------------- //

export type ClientProfil = {
  id: number;
  email: string;
  nom: string;
  telephone: string;
  adresse: string;
  created_at: string;
  last_login: string | null;
};

export type Tokens = { access: string; refresh: string };

export type AuthReponse = Tokens & { client: ClientProfil };

// --------------------------------------------------------------------- //
// Commandes
// --------------------------------------------------------------------- //

export const STATUTS = [
  "EN_ATTENTE_APPROBATION",
  "NOUVELLE",
  "EN_PREPARATION",
  "PRETE",
  "EN_LIVRAISON",
  "LIVRE",
  "RETOUR",
  "ANNULEE",
] as const;

export type Statut = (typeof STATUTS)[number];

export type ModePaiement = "LIVRAISON" | "AVANT";

export type LigneCommande = {
  id: number;
  produit: { id: number; nom: string; nom_complet: string };
  variante: { id: number; couleur: string };
  quantite: number;
  prix_unitaire: number;
  total: number;
  retourne: boolean;
};

export type Commande = {
  id: number;
  numero: string;
  statut: Statut;
  statut_label: string;
  date_commande: string;
  /** Date et heure de livraison souhaitées par le client (= `date_commande`). */
  date_livraison_souhaitee: string;
  boutique: { id: number; nom: string };
  livraison_zone: string;
  adresse_livraison: string | null;
  telephone: string;
  telephone_2: string;
  mode_paiement: ModePaiement;
  note: string | null;
  frais_livraison: number;
  total_a_payer: number;
  items: LigneCommande[];
  /** Droits calculés par le serveur — ne jamais les déduire du statut. */
  peut_modifier: boolean;
  peut_annuler: boolean;
  created_at: string;
  updated_at: string;
};

export type CommandeItemInput = {
  variante: number;
  quantite: number;
  prix_attendu?: string | number;
};

export type CommandeInput = {
  boutique: number;
  items: CommandeItemInput[];
  livraison_zone: string;
  /** ISO local (`2026-09-22T14:00`) — la boutique peut l'ajuster. */
  date_livraison_souhaitee?: string;
  adresse_livraison?: string;
  telephone?: string;
  telephone_2?: string;
  mode_paiement?: ModePaiement;
  note?: string;
};

export type CommandeUpdate = Partial<{
  date_livraison_souhaitee: string;
  adresse_livraison: string;
  telephone: string;
  telephone_2: string;
  livraison_zone: string;
  mode_paiement: ModePaiement;
  note: string;
}>;

// --------------------------------------------------------------------- //
// Commande spéciale (Housse / Cache-écran)
// --------------------------------------------------------------------- //
//
// ATTENTION : ces structures ne sont PAS encore servies par le backend.
// Elles décrivent le contrat spécifié dans `client_endpoint.md`
// (§ « Commande spéciale Housse / Cache-écran ») et restent inutilisées
// tant que `ENVOI_COMMANDE_SPECIALE_ACTIF` est faux. Aucun champ inventé
// au-delà de ce que ce document demande.

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
