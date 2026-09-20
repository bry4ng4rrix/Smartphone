/**
 * Toutes les routes de `client_endpoint.md`, une fonction par endpoint.
 * Aucun appel `fetch` ailleurs dans l'application.
 */
import { api, mediaUrl, type RequeteOptions } from "./api";
import type {
  AuthReponse,
  Boutique,
  Categorie,
  ClientProfil,
  Commande,
  CommandeInput,
  CommandeUpdate,
  Couleur,
  Marque,
  Page,
  Produit,
  SousType,
  Statut,
  ZonesReponse,
} from "./types";

// --------------------------------------------------------------------- //
// Catalogue public (sans jeton)
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
      min_price?: number;
      max_price?: number;
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
// Compte client
// --------------------------------------------------------------------- //

export const compte = {
  inscription: (data: { email: string; password: string; nom: string; telephone: string; adresse?: string }) =>
    api<AuthReponse>("/client/register/", { method: "POST", body: data }),

  connexion: (data: { email: string; password: string }) =>
    api<AuthReponse>("/client/login/", { method: "POST", body: data }),

  moi: () => api<ClientProfil>("/client/me/", { auth: true }),

  majProfil: (data: Partial<Pick<ClientProfil, "nom" | "telephone" | "adresse">>) =>
    api<ClientProfil>("/client/me/", { method: "PATCH", body: data, auth: true }),

  changerMotDePasse: (data: { ancien_mot_de_passe: string; nouveau_mot_de_passe: string }) =>
    api<{ detail: string }>("/client/change-password/", { method: "POST", body: data, auth: true }),
};

// --------------------------------------------------------------------- //
// Commandes du client
// --------------------------------------------------------------------- //

export const commandes = {
  liste: (statut?: Statut[] | string) =>
    api<Commande[]>("/client/orders/", {
      auth: true,
      params: { statut: Array.isArray(statut) ? statut.join(",") : statut },
    }),

  detail: (id: number | string) => api<Commande>(`/client/orders/${id}/`, { auth: true }),

  creer: (data: CommandeInput) => api<Commande>("/client/orders/", { method: "POST", body: data, auth: true }),

  modifier: (id: number | string, data: CommandeUpdate) =>
    api<Commande>(`/client/orders/${id}/`, { method: "PATCH", body: data, auth: true }),

  annuler: (id: number | string, note?: string) =>
    api<Commande>(`/client/orders/${id}/cancel/`, { method: "POST", body: { note: note ?? "" }, auth: true }),
};
