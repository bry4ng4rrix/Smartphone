/**
 * Règles du tunnel de commande.
 *
 * La boutique ne demande pas de compte : tout ce que le gérant utilisera pour
 * rappeler le client est saisi ici, et doit donc être vérifié ici. Ces
 * fonctions sont pures — la validation côté serveur reste la seule qui fasse
 * foi, celle-ci ne sert qu'à prévenir tôt et clairement.
 */
// `import type` seulement : effacé à la compilation, ce module reste pur et
// n'entraîne pas le provider dans son sillage.
import type { LignePanier } from "@/providers/cart-provider";
import type { PointRetrait } from "./types";

// --------------------------------------------------------------------- //
// Étapes
// --------------------------------------------------------------------- //

export const ETAPES = [
  { cle: "coordonnees", titre: "Vos coordonnées", resume: "Qui commande" },
  { cle: "livraison", titre: "Livraison", resume: "Où et comment" },
  { cle: "verification", titre: "Vérification", resume: "Tout relire" },
  { cle: "confirmation", titre: "Confirmation", resume: "Valider" },
] as const;

export type Etape = (typeof ETAPES)[number]["cle"];

export function indexEtape(etape: Etape): number {
  return ETAPES.findIndex((e) => e.cle === etape);
}

// --------------------------------------------------------------------- //
// Saisies
// --------------------------------------------------------------------- //

export type ModeRemise = "EN_LIGNE" | "RECUPERATION";

export type Coordonnees = {
  nom: string;
  telephone: string;
  telephone2: string;
};

export type Remise = {
  mode: ModeRemise;
  adresse: string;
  note: string;
};

export const COORDONNEES_VIDES: Coordonnees = { nom: "", telephone: "", telephone2: "" };
export const REMISE_VIDE: Remise = { mode: "EN_LIGNE", adresse: "", note: "" };

/** Même format que le backend (`TELEPHONE_REGEX`) : +261 puis 9 chiffres. */
const TELEPHONE = /^\+261\d{9}$/;
export const TELEPHONE_AIDE = "Format attendu : +261 suivi de 9 chiffres.";

export type Erreurs = Partial<Record<string, string>>;

/**
 * Normalise une saisie téléphonique courante à Madagascar.
 *
 * `034 00 000 00`, `0340000000` et `+261 34 00 000 00` désignent le même
 * numéro : on les ramène tous à `+261340000000` plutôt que de renvoyer le
 * client à son clavier pour une histoire d'espaces ou de zéro initial.
 */
export function normaliserTelephone(saisie: string): string {
  const brut = saisie.replace(/[\s.\-()]/g, "");
  if (!brut) return "";
  if (brut.startsWith("+261")) return brut;
  if (brut.startsWith("261")) return `+${brut}`;
  if (brut.startsWith("0")) return `+261${brut.slice(1)}`;
  return brut;
}

export function validerCoordonnees(c: Coordonnees): Erreurs {
  const e: Erreurs = {};
  if (!c.nom.trim()) e.nom = "Indiquez le nom de la personne à contacter.";
  const tel = normaliserTelephone(c.telephone);
  if (!tel) e.telephone = "Indiquez un numéro de téléphone.";
  else if (!TELEPHONE.test(tel)) e.telephone = TELEPHONE_AIDE;
  const tel2 = normaliserTelephone(c.telephone2);
  if (tel2 && !TELEPHONE.test(tel2)) e.telephone2 = TELEPHONE_AIDE;
  else if (tel2 && tel2 === tel) e.telephone2 = "Ce numéro est identique au premier.";
  return e;
}

export function validerRemise(r: Remise): Erreurs {
  const e: Erreurs = {};
  if (r.mode === "EN_LIGNE" && !r.adresse.trim()) {
    e.adresse = "Indiquez l'adresse de livraison.";
  }
  return e;
}

export const aucuneErreur = (e: Erreurs) => Object.keys(e).length === 0;

// --------------------------------------------------------------------- //
// Panier multi-boutiques
// --------------------------------------------------------------------- //

/** Les lignes d'une même boutique, et ce qu'elles pèsent. */
export type GroupeBoutique = {
  id: number;
  nom: string;
  lignes: LignePanier[];
  sousTotal: number;
};

/**
 * Un groupe enrichi de ce que SA boutique facture et de l'endroit où y
 * retirer. `null` quand l'appel `/zones/` a échoué : l'interface affiche
 * alors « — » plutôt qu'un montant inventé.
 */
export type BoutiqueDuPanier = GroupeBoutique & {
  prixLivraison: number | null;
  pointRetrait: PointRetrait | null;
};

/**
 * Regroupe le panier par boutique propriétaire des articles.
 *
 * Le site présente le catalogue de toutes les boutiques, et le panier accepte
 * de les mêler. À la commande, le serveur l'éclate de la même façon : une
 * commande par boutique (clients/services.py::magasins_des_items). Ce
 * regroupement existe pour que le client voie, AVANT d'envoyer, ce que chaque
 * boutique lui livrera et lui facturera.
 *
 * L'ordre suit la première apparition dans le panier — stable d'un rendu à
 * l'autre, et conforme à ce que le client a construit.
 */
export function grouperParBoutique(lignes: LignePanier[]): GroupeBoutique[] {
  const groupes = new Map<number, GroupeBoutique>();
  for (const ligne of lignes) {
    const groupe = groupes.get(ligne.boutiqueId);
    if (groupe) {
      groupe.lignes.push(ligne);
      groupe.sousTotal += ligne.prix * ligne.quantite;
    } else {
      groupes.set(ligne.boutiqueId, {
        id: ligne.boutiqueId,
        nom: ligne.boutiqueNom,
        lignes: [ligne],
        sousTotal: ligne.prix * ligne.quantite,
      });
    }
  }
  return [...groupes.values()];
}
