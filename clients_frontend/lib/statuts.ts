import type { Statut } from "./types";

/**
 * Libellés, description et ordre d'avancement des statuts renvoyés par
 * l'API. L'API fournit déjà `statut_label` ; la description et la position
 * dans la timeline sont de la présentation, pas de la donnée métier.
 */
export const ETAPES_SUIVI: Statut[] = [
  "EN_ATTENTE_APPROBATION",
  "NOUVELLE",
  "EN_PREPARATION",
  "PRETE",
  "EN_LIVRAISON",
  "LIVRE",
];

export const DESCRIPTION_STATUT: Record<Statut, string> = {
  EN_ATTENTE_APPROBATION: "Commande envoyée, la boutique doit la valider.",
  NOUVELLE: "Validée par la boutique, vos articles sont réservés.",
  EN_PREPARATION: "Vos articles sont en cours d'emballage.",
  PRETE: "Prête à partir, ou à retirer sur place.",
  EN_LIVRAISON: "Le livreur est en route.",
  LIVRE: "Commande livrée. Merci !",
  RETOUR: "La livraison n'a pas abouti, le colis est revenu en boutique.",
  ANNULEE: "Commande annulée.",
};

type Ton = "attente" | "encours" | "succes" | "neutre" | "alerte";

export const TON_STATUT: Record<Statut, Ton> = {
  EN_ATTENTE_APPROBATION: "attente",
  NOUVELLE: "encours",
  EN_PREPARATION: "encours",
  PRETE: "encours",
  EN_LIVRAISON: "encours",
  LIVRE: "succes",
  RETOUR: "alerte",
  ANNULEE: "neutre",
};

export const CLASSES_TON: Record<Ton, string> = {
  attente: "bg-amber-500/12 text-amber-700 ring-amber-500/25 dark:text-amber-300",
  encours: "bg-sky-500/12 text-sky-700 ring-sky-500/25 dark:text-sky-300",
  succes: "bg-emerald-500/12 text-emerald-700 ring-emerald-500/25 dark:text-emerald-300",
  alerte: "bg-rose-500/12 text-rose-700 ring-rose-500/25 dark:text-rose-300",
  neutre: "bg-foreground/8 text-muted ring-foreground/12",
};

/** Un statut terminal ne bouge plus : la timeline s'arrête. */
export const EST_TERMINAL: Record<Statut, boolean> = {
  EN_ATTENTE_APPROBATION: false,
  NOUVELLE: false,
  EN_PREPARATION: false,
  PRETE: false,
  EN_LIVRAISON: false,
  LIVRE: true,
  RETOUR: true,
  ANNULEE: true,
};
