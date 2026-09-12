// Types échangés entre la bulle assistant (navigateur) et
// app/api/ai/assistant/route.ts (serveur). Aucune dépendance serveur ici.

export interface CommandePayload {
  client_nom: string;
  telephone: string;
  livraison_zone: string;
  adresse_livraison: string;
  mode_paiement: 'AVANT' | 'LIVRAISON';
  note_preparateur: string;
  items: { product_variant: number; quantite: number }[];
}

export interface AjustementStock {
  variant_id: number;
  libelle: string;
  stock_actuel: number;
  nouveau: number;
}

/**
 * Action proposée par l'assistant, à confirmer par l'utilisateur avant
 * exécution. `resume` est ce qu'on lui montre ; le reste est ce qui sera
 * envoyé tel quel à l'API (aucun passage par le modèle à la confirmation).
 */
export type Proposition =
  | { type: 'creer_commande'; resume: string[]; payload: CommandePayload }
  | { type: 'maj_stock'; resume: string[]; fichier: string; ajustements: AjustementStock[] };

export interface ReponseAssistant {
  reponse: string;
  proposition?: Proposition;
}
