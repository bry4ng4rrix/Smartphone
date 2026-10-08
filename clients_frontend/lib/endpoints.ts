/**
 * Toutes les routes de `client_endpoint.md`, une fonction par endpoint.
 * Aucun appel `fetch` ailleurs dans l'application.
 *
 * Tout est public : la boutique ne demande ni compte ni connexion.
 */
import { api, mediaUrl, type RequeteOptions } from "./api";
import type {
  Boutique,
  Categorie,
  CommandeInput,
  CommandesReponse,
  CommandeSpeciale,
  CommandeSpecialeInput,
  Couleur,
  Marque,
  Page,
  Produit,
  SousType,
  ZonesReponse,
} from "./types";

// --------------------------------------------------------------------- //
// Catalogue public
// --------------------------------------------------------------------- //

const CATALOGUE_CACHE = 60; // secondes — le catalogue bouge peu

function normaliserProduit(p: Produit): Produit {
  return { ...p, photo: mediaUrl(p.photo) };
}

export const catalogue = {
  boutiques: async (opts?: RequeteOptions): Promise<Boutique[]> => {
    const liste = await api<Boutique[]>("/boutiques/", { revalidate: CATALOGUE_CACHE, ...opts });
    return liste.map((b) => ({ ...b, logo: mediaUrl(b.logo) }));
  },

  zones: (boutiqueId: number, opts?: RequeteOptions) =>
    api<ZonesReponse>(`/boutiques/${boutiqueId}/zones/`, { revalidate: CATALOGUE_CACHE, ...opts }),

  categories: (boutique?: number, opts?: RequeteOptions) =>
    api<Categorie[]>("/categories/", { params: { boutique }, revalidate: CATALOGUE_CACHE, ...opts }),

  sousTypes: (params?: { boutique?: number; category?: number }, opts?: RequeteOptions) =>
    api<SousType[]>("/sous-type/", { params, revalidate: CATALOGUE_CACHE, ...opts }),

  marques: (boutique?: number, opts?: RequeteOptions) =>
    api<Marque[]>("/marque/", { params: { boutique }, revalidate: CATALOGUE_CACHE, ...opts }),

  couleurs: (boutique?: number, opts?: RequeteOptions) =>
    api<Couleur[]>("/couleurs/", { params: { boutique }, revalidate: CATALOGUE_CACHE, ...opts }),

  produits: async (
    params: {
      search?: string;
      boutique?: number;
      category?: number;
      sous_type?: number;
      brand?: number;
      couleur?: string;
      available?: string;
      page?: number;
      page_size?: number;
    } = {},
    opts?: RequeteOptions,
  ): Promise<Page<Produit>> => {
    const page = await api<Page<Produit>>("/produit/", { params, revalidate: CATALOGUE_CACHE, ...opts });
    return { ...page, results: page.results.map(normaliserProduit) };
  },

  produit: async (id: number | string, opts?: RequeteOptions): Promise<Produit> =>
    normaliserProduit(await api<Produit>(`/produit/${id}/`, { revalidate: CATALOGUE_CACHE, ...opts })),
};

// --------------------------------------------------------------------- //
// Commande
// --------------------------------------------------------------------- //

export const commandes = {
  /**
   * Passe la commande. Écriture seule : il n'y a pas d'endpoint pour la
   * relire ensuite, et le corps ne porte aucun montant — le serveur calcule
   * les frais et le total.
   *
   * Renvoie UNE commande PAR BOUTIQUE : le serveur éclate le panier selon le
   * magasin propriétaire de chaque article.
   */
  creer: (data: CommandeInput) =>
    api<CommandesReponse>("/commandes/", { method: "POST", body: data }),
};

// --------------------------------------------------------------------- //
// Commandes spéciales (Housse / Cache-écran)
// --------------------------------------------------------------------- //

/**
 * ENDPOINT À IMPLÉMENTER CÔTÉ BACKEND — spécifié dans `client_endpoint.md`
 * (§ « Commande spéciale Housse / Cache-écran »). Rien ici n'est appelé tant
 * que `ENVOI_COMMANDE_SPECIALE_ACTIF` (lib/compatibilite.ts) est faux : cette
 * fonction décrit le contrat attendu, elle ne le simule pas.
 */
export const commandesSpeciales = {
  creer: (data: CommandeSpecialeInput) =>
    api<CommandeSpeciale>("/commandes-speciales/", { method: "POST", body: data }),
};
