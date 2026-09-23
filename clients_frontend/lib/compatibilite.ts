/**
 * Parcours « trouvez le produit adapté à votre téléphone » — Housse et
 * Cache-écran.
 *
 * Point de départ de la conception : le catalogue est DÉJÀ structuré par
 * téléphone. Une référence produit porte une marque (`marque.nom` = Samsung)
 * et un nom qui est le modèle du téléphone (`nom` = « Galaxy A15 ») — voir
 * `ProductReference` côté serveur : « une référence de téléphone pour une
 * marque donnée ». La compatibilité se lit donc dans les relations
 * existantes ; aucune table de correspondance à inventer, et surtout pas de
 * recherche textuelle approximative.
 *
 * Ce module ne fait AUCUN appel réseau : il ne contient que les règles, pour
 * qu'elles restent hors des composants (voir `hooks/use-modeles-telephone`).
 */
import { normalize } from "./utils";
import type { Categorie, Produit } from "./types";

// --------------------------------------------------------------------- //
// Quelles catégories passent par le questionnaire
// --------------------------------------------------------------------- //

/**
 * Les catégories sont créées librement par chaque boutique : on les
 * reconnaît sur leur nom normalisé, comme le fait déjà la page d'accueil
 * pour ses tuiles. `motif` est cherché dans le nom sans accent ni casse
 * (« CACHE ÉCRAN » → « cache ecran » contient « cache »).
 */
const PARCOURS = [
  { slug: "housse", motif: "housse", libelle: "Housse", accroche: "housses" },
  { slug: "cache-ecran", motif: "cache", libelle: "Cache-écran", accroche: "cache-écrans" },
] as const;

export type SlugParcours = (typeof PARCOURS)[number]["slug"];

/** Le slug du parcours téléphone pour cette catégorie, ou `null` si elle
 *  garde le listing classique (chargeur, santé…). */
export function slugParcours(nomCategorie: string): SlugParcours | null {
  const nom = normalize(nomCategorie);
  return PARCOURS.find((p) => nom.includes(p.motif))?.slug ?? null;
}

export function libelleParcours(slug: string): string | null {
  return PARCOURS.find((p) => p.slug === slug)?.libelle ?? null;
}

/** « housses », « cache-écrans » — pour les phrases au pluriel. */
export function accrocheParcours(slug: string): string {
  return PARCOURS.find((p) => p.slug === slug)?.accroche ?? "produits";
}

/**
 * Où mène un clic sur une catégorie. Point UNIQUE de cette décision :
 * la barre de navigation et les tuiles de l'accueil l'appellent toutes les
 * deux, elles ne peuvent donc pas diverger.
 */
export function lienCategorie(categorie: Pick<Categorie, "id" | "nom">): string {
  const slug = slugParcours(categorie.nom);
  return slug ? `/compatibilite/${slug}` : `/catalogue?category=${categorie.id}`;
}

/** Retrouve la catégorie de la boutique qui correspond à un slug d'URL. */
export function categorieDuSlug(categories: Categorie[], slug: string): Categorie | undefined {
  return categories.find((c) => slugParcours(c.nom) === slug);
}

// --------------------------------------------------------------------- //
// Modèles de téléphone
// --------------------------------------------------------------------- //

/** Un modèle de téléphone, avec les produits de la catégorie qui lui vont. */
export type ModeleTelephone = {
  /** Libellé tel que la boutique l'a saisi (« Galaxy A15 »). */
  nom: string;
  produits: Produit[];
  /** Vrai dès qu'au moins un produit compatible est en stock. */
  disponible: boolean;
};

/**
 * Regroupe les références d'une marque par modèle de téléphone.
 *
 * Un même modèle porte souvent plusieurs produits (une housse Flip cover ET
 * une housse silicone pour le Galaxy A15) : ce sont des sous-types différents
 * d'une même compatibilité.
 */
export function grouperParModele(produits: Produit[]): ModeleTelephone[] {
  const parCle = new Map<string, ModeleTelephone>();
  for (const produit of produits) {
    const cle = normalize(produit.nom);
    if (!cle) continue;
    const existant = parCle.get(cle);
    if (existant) {
      existant.produits.push(produit);
      existant.disponible ||= produit.disponible;
    } else {
      parCle.set(cle, { nom: produit.nom, produits: [produit], disponible: produit.disponible });
    }
  }
  return [...parCle.values()].sort((a, b) => a.nom.localeCompare(b.nom, "fr", { numeric: true }));
}

/**
 * Le modèle correspondant à ce que l'utilisateur a choisi ou saisi.
 *
 * Correspondance exacte d'abord (cas normal : il a pris la proposition de la
 * liste). À défaut seulement, on tolère une saisie approchée — « a15 » pour
 * « Galaxy A15 » — afin qu'une frappe libre ne bascule pas en commande
 * spéciale alors que le produit existe.
 */
export function trouverModele(modeles: ModeleTelephone[], saisie: string): ModeleTelephone | null {
  const cherche = normalize(saisie);
  if (!cherche) return null;
  const exact = modeles.find((m) => normalize(m.nom) === cherche);
  if (exact) return exact;
  const approchants = modeles.filter((m) => normalize(m.nom).includes(cherche));
  // Plusieurs candidats : le choix appartient à l'utilisateur, pas à nous.
  return approchants.length === 1 ? approchants[0] : null;
}

// --------------------------------------------------------------------- //
// Commande spéciale
// --------------------------------------------------------------------- //

/** Part du total demandée à la commande. Règle métier, pas une préférence. */
export const TAUX_ACOMPTE = 0.5;

/** Délai annoncé pour une commande spéciale, en jours. */
export const DELAI_COMMANDE_SPECIALE_JOURS = 15;

/**
 * Découpe un total en acompte / solde.
 *
 * ATTENTION : purement indicatif, pour que le client sache à quoi s'attendre.
 * Le montant qui fait foi est celui que la boutique confirme — le front
 * n'est jamais la source de vérité d'un paiement (voir client_endpoint.md,
 * § « Commande spéciale Housse / Cache-écran »).
 */
export function repartirAcompte(total: number): { acompte: number; solde: number } {
  const acompte = Math.round(total * TAUX_ACOMPTE);
  return { acompte, solde: Math.max(0, Math.round(total) - acompte) };
}

/** Date estimée de mise à disposition, calculée depuis une date de départ. */
export function dateEstimee(depuis: Date = new Date()): Date {
  const d = new Date(depuis);
  d.setDate(d.getDate() + DELAI_COMMANDE_SPECIALE_JOURS);
  return d;
}

/**
 * Prix de départ indicatif pour une commande spéciale.
 *
 * Quand des produits compatibles existent mais sont tous épuisés, leur prix
 * donne un ordre de grandeur honnête. Sans aucun produit compatible, on ne
 * devine rien : la boutique chiffrera.
 */
export function prixIndicatif(produits: Produit[]): number | null {
  const prix = produits.map((p) => p.prix_vente).filter((n) => Number.isFinite(n) && n > 0);
  return prix.length ? Math.min(...prix) : null;
}

/**
 * Le backend n'expose PAS encore d'endpoint de commande spéciale : il n'y a
 * ni modèle, ni acompte, ni paiement côté serveur (vérifié sur `orders/`,
 * `clients/` et `finance/`). Tant que cette variable n'est pas activée, le
 * formulaire va jusqu'au récapitulatif sans prétendre enregistrer quoi que
 * ce soit — on ne simule pas une commande, encore moins un paiement.
 *
 * Le contrat attendu est spécifié dans client_endpoint.md ; le jour où il
 * existe, `NEXT_PUBLIC_COMMANDE_SPECIALE=1` suffit à brancher l'envoi.
 */
export const ENVOI_COMMANDE_SPECIALE_ACTIF = process.env.NEXT_PUBLIC_COMMANDE_SPECIALE === "1";
