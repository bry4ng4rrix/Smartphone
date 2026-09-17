/**
 * Constantes et helpers partagés du module Fournisseurs / Approvisionnements
 * (page liste `/suppliers` et page détail `/suppliers/[id]`).
 *
 * Un approvisionnement = 1 fournisseur + 1 produit + 1 quantité + N
 * paiements + 1 expédition + 1 montant Frais + Douane + 1 coût total + 1
 * coût par pièce. Les libellés reprennent les `choices` du backend
 * (suppliers/models.py).
 */

export type Statut =
  | 'BROUILLON'
  | 'COMMANDE'
  | 'ACOMPTE_PAYE'
  | 'PREPARATION'
  | 'PAYE'
  | 'EXPEDIE'
  | 'EN_TRANSIT'
  | 'ARRIVE'
  | 'COUT_FINALISE';

export type Devise = 'MGA' | 'USD' | 'EUR' | 'CNY';

export interface StatutInfo {
  label: string;
  /** Classes Tailwind du badge (fond + texte), lisibles en clair et en sombre. */
  color: string;
}

/** Ordre logique du workflow (identique à `SupplierOrder.STATUT_ORDER`). */
export const STATUTS: { value: Statut; label: string; color: string }[] = [
  { value: 'BROUILLON', label: 'Brouillon', color: 'bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-200' },
  { value: 'COMMANDE', label: 'Commande', color: 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-200' },
  { value: 'ACOMPTE_PAYE', label: 'Acompte payé', color: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200' },
  { value: 'PREPARATION', label: 'Préparation', color: 'bg-violet-100 text-violet-800 dark:bg-violet-900/40 dark:text-violet-200' },
  { value: 'PAYE', label: 'Entièrement payé', color: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-200' },
  { value: 'EXPEDIE', label: 'Expédié', color: 'bg-cyan-100 text-cyan-800 dark:bg-cyan-900/40 dark:text-cyan-200' },
  { value: 'EN_TRANSIT', label: 'En transit', color: 'bg-sky-100 text-sky-800 dark:bg-sky-900/40 dark:text-sky-200' },
  { value: 'ARRIVE', label: 'Arrivé à Madagascar', color: 'bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-200' },
  { value: 'COUT_FINALISE', label: 'Coût finalisé', color: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200' },
];

export function statutInfo(statut: string | null | undefined): StatutInfo {
  const s = STATUTS.find((x) => x.value === statut);
  return s ? { label: s.label, color: s.color } : { label: statut || '—', color: 'bg-slate-100 text-slate-700' };
}

export function statutIndex(statut: string | null | undefined): number {
  return STATUTS.findIndex((x) => x.value === statut);
}

export const STATUTS_EN_COURS: Statut[] = ['COMMANDE', 'ACOMPTE_PAYE', 'PREPARATION', 'PAYE', 'EXPEDIE', 'EN_TRANSIT', 'ARRIVE'];

/** Statuts depuis lesquels chaque action est possible (miroir de suppliers/services.py). */
export const TRANSITIONS: Record<'commander' | 'preparer' | 'expedier' | 'transit' | 'arriver' | 'finaliser', Statut[]> = {
  commander: ['BROUILLON'],
  preparer: ['COMMANDE', 'ACOMPTE_PAYE', 'PAYE'],
  expedier: ['COMMANDE', 'ACOMPTE_PAYE', 'PREPARATION', 'PAYE'],
  transit: ['EXPEDIE'],
  arriver: ['EXPEDIE', 'EN_TRANSIT'],
  finaliser: ['ARRIVE'],
};

export function actionPossible(action: keyof typeof TRANSITIONS, statut: string | null | undefined): boolean {
  return TRANSITIONS[action].includes(statut as Statut);
}

/** Un paiement ou une modification reste possible tant que le coût n'est pas finalisé. */
export function modifiable(statut: string | null | undefined): boolean {
  return statut !== 'COUT_FINALISE';
}

export const DEVISES: { value: Devise; label: string; symbole: string }[] = [
  { value: 'USD', label: 'Dollar US (USD)', symbole: '$' },
  { value: 'EUR', label: 'Euro (EUR)', symbole: '€' },
  { value: 'CNY', label: 'Yuan (CNY)', symbole: '¥' },
  { value: 'MGA', label: 'Ariary (MGA)', symbole: 'Ar' },
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

export function labelOf(list: { value: string; label: string }[], value: string | null | undefined): string {
  if (!value) return '—';
  return list.find((x) => x.value === value)?.label ?? value;
}

const fmtAriary = new Intl.NumberFormat('fr-MG', { maximumFractionDigits: 0 });
const fmtDeux = new Intl.NumberFormat('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtTauxNombre = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 4 });

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

/** Taux de change (Ar pour 1 unité de devise), jusqu'à 4 décimales : « 4 512,5 Ar ». */
export function fmtTaux(n: number | string | null | undefined): string {
  const v = Number(n);
  if (n === null || n === undefined || n === '' || Number.isNaN(v)) return '—';
  return fmtTauxNombre.format(v) + ' Ar';
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
