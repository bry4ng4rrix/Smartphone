// Types échangés entre la bulle assistant (navigateur) et
// app/api/assistant/route.ts (serveur). Aucune dépendance serveur ici.

/** Un article résolu dans le catalogue, prêt à rejoindre le panier local. */
export type ArticlePropose = {
  varianteId: number;
  produitId: number;
  nom: string;
  nomComplet: string;
  couleur: string;
  prix: number;
  photo: string | null;
  boutiqueId: number;
  boutiqueNom: string;
  quantite: number;
};

/**
 * Action proposée par l'assistant, à confirmer par le client avant d'être
 * appliquée. `resume` est ce qu'on lui montre ; `articles` est ajouté tel
 * quel au panier local (aucun appel serveur : le panier n'existe que dans
 * le navigateur, voir providers/cart-provider.tsx).
 */
export type Proposition = {
  type: "ajouter_panier";
  resume: string[];
  articles: ArticlePropose[];
};

export interface ReponseAssistant {
  reponse: string;
  proposition?: Proposition;
}
