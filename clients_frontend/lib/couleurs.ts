import { normalize } from "./utils";

/**
 * Pastille de couleur affichée à côté du nom de la variante.
 * Le nom vient de l'API ; la correspondance vers une valeur CSS est purement
 * visuelle — aucune donnée n'est inventée, et un nom inconnu reçoit une
 * teinte stable dérivée de ses lettres plutôt qu'un rendu au hasard.
 */
const BASES: Array<[string, string]> = [
  ["noir", "#111114"],
  ["blanc", "#f4f4f5"],
  ["gris", "#9aa0a6"],
  ["argent", "#c9ccd1"],
  ["or", "#d4af37"],
  ["rose", "#f4a6bb"],
  ["rouge", "#dc2626"],
  ["bordeaux", "#7f1d2e"],
  ["orange", "#f97316"],
  ["jaune", "#facc15"],
  ["vert", "#16a34a"],
  ["turquoise", "#14b8a6"],
  ["bleu", "#2563eb"],
  ["violet", "#7c3aed"],
  ["mauve", "#a78bfa"],
  ["marron", "#8b5a2b"],
  ["beige", "#e3d5c3"],
  ["transparent", "#e7e7ea"],
];

const NUANCES: Array<[string, number]> = [
  ["clair", 22],
  ["ciel", 28],
  ["pale", 26],
  ["kely", 18],
  ["fonce", -24],
  ["foncé", -24],
  ["nuit", -30],
  ["be", -12],
];

function eclaircir(hex: string, pourcent: number): string {
  const n = Number.parseInt(hex.slice(1), 16);
  const canal = (decalage: number) => {
    const v = (n >> decalage) & 0xff;
    const cible = pourcent >= 0 ? 255 : 0;
    return Math.round(v + (cible - v) * (Math.abs(pourcent) / 100));
  };
  return `#${[canal(16), canal(8), canal(0)].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
}

export function couleurCss(nom: string): string {
  const n = normalize(nom);
  const base = BASES.find(([cle]) => n.includes(cle));
  if (base) {
    const nuance = NUANCES.find(([cle]) => n.includes(cle));
    return nuance ? eclaircir(base[1], nuance[1]) : base[1];
  }
  // Teinte stable dérivée du nom : deux variantes différentes restent distinctes.
  let hash = 0;
  for (let i = 0; i < n.length; i += 1) hash = (hash * 31 + n.charCodeAt(i)) % 360;
  return `hsl(${hash} 42% 62%)`;
}
