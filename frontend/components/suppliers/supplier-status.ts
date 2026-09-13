/**
 * Constantes et helpers partagés du module Fournisseurs / Approvisionnements
 * (page liste `/suppliers` et page détail `/suppliers/[id]`).
 *
 * Les libellés reprennent exactement les `choices` du backend
 * (suppliers/models.py) : le serveur renvoie aussi `statut_label`, mais on
 * garde une table côté client pour les filtres, les couleurs des badges et
 * l'ordre du workflow.
 */

export type Statut =
  | 'BROUILLON'
  | 'COMMANDE'
  | 'PARTIELLEMENT_PAYE'
  | 'PAYE'
  | 'PREPARE'
  | 'EN_TRANSIT'
  | 'ARRIVE'
  | 'PARTIELLEMENT_RECU'
  | 'RECU'
  | 'COUT_FINALISE';

export type Devise = 'MGA' | 'USD' | 'EUR' | 'CNY';

export interface StatutInfo {
  label: string;
  /** Classes Tailwind du badge (fond + texte), lisibles en clair et en sombre. */
  color: string;
}

/** Ordre logique du workflow (identique à `SupplierOrder.STATUT_ORDER`). */
export const STATUTS: { value: Statut; label: string; color: string }[] = [
  { value: 'BROUILLON', label: 'Brouillon', color: 'bg-slate-100 text-slate-800 dark:bg-slate-800 dark:text-slate-200' },
  { value: 'COMMANDE', label: 'Commandé', color: 'bg-blue-100 text-blue-800 dark:bg-blue-900/50 dark:text-blue-200' },
  { value: 'PARTIELLEMENT_PAYE', label: 'Partiellement payé', color: 'bg-amber-100 text-amber-800 dark:bg-amber-900/50 dark:text-amber-200' },
  { value: 'PAYE', label: 'Payé', color: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/50 dark:text-emerald-200' },
  { value: 'PREPARE', label: 'Préparé par le fournisseur', color: 'bg-indigo-100 text-indigo-800 dark:bg-indigo-900/50 dark:text-indigo-200' },
  { value: 'EN_TRANSIT', label: 'En transit', color: 'bg-violet-100 text-violet-800 dark:bg-violet-900/50 dark:text-violet-200' },
  { value: 'ARRIVE', label: 'Arrivé à Madagascar', color: 'bg-cyan-100 text-cyan-800 dark:bg-cyan-900/50 dark:text-cyan-200' },
  { value: 'PARTIELLEMENT_RECU', label: 'Partiellement réceptionné', color: 'bg-orange-100 text-orange-800 dark:bg-orange-900/50 dark:text-orange-200' },
  { value: 'RECU', label: 'Réceptionné', color: 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-200' },
  { value: 'COUT_FINALISE', label: 'Coût finalisé', color: 'bg-teal-100 text-teal-900 dark:bg-teal-900/50 dark:text-teal-200' },
];

const STATUT_MAP: Record<string, StatutInfo> = Object.fromEntries(
  STATUTS.map((s) => [s.value, { label: s.label, color: s.color }]),
);

/** Libellé + couleur d'un statut (statut inconnu → affiché tel quel, gris). */
export function statutInfo(statut: string | null | undefined): StatutInfo {
  if (!statut) return { label: '—', color: 'bg-muted text-muted-foreground' };
  return STATUT_MAP[statut] ?? { label: statut, color: 'bg-muted text-muted-foreground' };
}

/** Position d'un statut dans le workflow (−1 si inconnu). */
export function statutIndex(statut: string | null | undefined): number {
  return STATUTS.findIndex((s) => s.value === statut);
}

/** Statuts « en cours » = ni brouillon, ni finalisé. */
export const STATUTS_EN_COURS: Statut[] = [
  'COMMANDE', 'PARTIELLEMENT_PAYE', 'PAYE', 'PREPARE', 'EN_TRANSIT', 'ARRIVE', 'PARTIELLEMENT_RECU', 'RECU',
];

export const DEVISES: { value: Devise; label: string; symbole: string }[] = [
  { value: 'MGA', label: 'Ariary (MGA)', symbole: 'Ar' },
  { value: 'USD', label: 'Dollar US (USD)', symbole: '$' },
  { value: 'EUR', label: 'Euro (EUR)', symbole: '€' },
  { value: 'CNY', label: 'Yuan (CNY)', symbole: '¥' },
];

export const TYPES_FRAIS: { value: string; label: string }[] = [
  { value: 'TRANSPORT', label: 'Transport / expédition' },
  { value: 'DOUANE', label: 'Douane' },
  { value: 'TAXES', label: 'Taxes' },
  { value: 'TRANSIT', label: 'Frais de transit' },
  { value: 'TRANSPORT_LOCAL', label: 'Transport local' },
  { value: 'PORTUAIRE', label: 'Frais portuaires' },
  { value: 'DOSSIER', label: 'Frais de dossier' },
  { value: 'AGENCE', label: "Frais d'agence" },
  { value: 'ASSURANCE', label: 'Assurance' },
  { value: 'MANUTENTION', label: 'Manutention' },
  { value: 'AUTRE', label: 'Autres frais' },
];

export const TYPES_PAIEMENT: { value: string; label: string }[] = [
  { value: 'ACOMPTE', label: 'Acompte' },
  { value: 'SOLDE', label: 'Solde' },
  { value: 'PARTIEL', label: 'Paiement partiel' },
  { value: 'AUTRE', label: 'Autre' },
];

export const METHODES_PAIEMENT: { value: string; label: string }[] = [
  { value: 'VIREMENT', label: 'Virement bancaire' },
  { value: 'MOBILE_MONEY', label: 'Mobile money' },
  { value: 'ESPECES', label: 'Espèces' },
  { value: 'CARTE', label: 'Carte' },
  { value: 'AUTRE', label: 'Autre' },
];

export const MODES_TRANSPORT: { value: string; label: string }[] = [
  { value: 'AERIEN', label: 'Aérien' },
  { value: 'MARITIME', label: 'Maritime' },
  { value: 'ROUTIER', label: 'Routier' },
  { value: 'EXPRESS', label: 'Express / colis' },
  { value: 'AUTRE', label: 'Autre' },
];

export const METHODES_ALLOCATION: { value: 'VALEUR' | 'QUANTITE' | 'MANUEL'; label: string; description: string }[] = [
  {
    value: 'VALEUR',
    label: "Proportionnelle à la valeur d'achat",
    description: 'Les frais sont répartis au prorata de la valeur d\'achat de chaque ligne (recommandé).',
  },
  {
    value: 'QUANTITE',
    label: 'Proportionnelle à la quantité',
    description: 'Chaque pièce reçoit la même part de frais, quel que soit son prix.',
  },
  {
    value: 'MANUEL',
    label: 'Manuelle (par ligne)',
    description: 'Vous saisissez le montant de frais (Ar) alloué à chaque ligne.',
  },
];

/** Libellé d'une constante à partir de sa valeur (repli : la valeur brute). */
export function labelOf(list: { value: string; label: string }[], value: string | null | undefined): string {
  if (!value) return '—';
  return list.find((x) => x.value === value)?.label ?? value;
}

const fmtAriary = new Intl.NumberFormat('fr-MG', { maximumFractionDigits: 0 });
const fmtDeux = new Intl.NumberFormat('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** Montant en ariary arrondi : « 1 250 000 Ar ». */
export function fmtAr(n: number | string | null | undefined): string {
  const v = Number(n);
  if (n === null || n === undefined || n === '' || Number.isNaN(v)) return '0 Ar';
  return fmtAriary.format(Math.round(v)) + ' Ar';
}

/** Montant dans sa devise : « 1 250 000 Ar », « 1 200,00 $ », « 350,00 € », « 8 500,00 ¥ ». */
export function fmtDevise(montant: number | string | null | undefined, devise: string | null | undefined): string {
  if (!devise || devise === 'MGA') return fmtAr(montant);
  const v = Number(montant);
  const symbole = DEVISES.find((d) => d.value === devise)?.symbole ?? devise;
  if (montant === null || montant === undefined || montant === '' || Number.isNaN(v)) return `0,00 ${symbole}`;
  return `${fmtDeux.format(v)} ${symbole}`;
}

/** Nombre entier avec séparateurs : « 1 250 ». */
export function fmtNombre(n: number | string | null | undefined): string {
  const v = Number(n);
  if (Number.isNaN(v)) return '0';
  return fmtAriary.format(Math.round(v));
}

/** Pourcentage : « 45 % ». */
export function fmtPourcent(n: number | string | null | undefined): string {
  const v = Number(n);
  if (Number.isNaN(v)) return '0 %';
  return `${Math.round(v)} %`;
}

/** Date `YYYY-MM-DD` ou ISO → « 10/09/2026 ». */
export function fmtDate(value?: string | null): string {
  if (!value) return '—';
  // Une date pure (YYYY-MM-DD) doit être affichée telle quelle, sans décalage
  // de fuseau horaire.
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (m) return `${m[3]}/${m[2]}/${m[1]}`;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('fr-FR', { timeZone: 'Indian/Antananarivo' });
}

/** Message lisible d'une erreur API (djangoClient) ou générique. */
export function messageErreur(err: unknown, defaut = 'Une erreur est survenue'): string {
  if (err && typeof err === 'object' && 'message' in err) {
    const m = (err as { message?: unknown }).message;
    if (typeof m === 'string' && m.trim()) return m;
  }
  return defaut;
}
