// Centre de rapports — types, périodes et formats partagés par la page
// Rapports et ses sections (components/reports/*).

import { appToday } from '@/lib/timezone';

export type Section =
  | 'overview'
  | 'sales'
  | 'financial'
  | 'expenses'
  | 'stock'
  | 'orders'
  | 'deliveries'
  | 'marketing';

export const SECTIONS: { key: Section; label: string; description: string }[] = [
  { key: 'overview', label: 'Vue générale', description: 'KPI, tendances et comparaison avec la période précédente' },
  { key: 'sales', label: 'Ventes', description: 'Chiffre d’affaires, produits, livreurs' },
  { key: 'financial', label: 'Financier', description: 'Marge brute, dépenses, bénéfice net' },
  { key: 'expenses', label: 'Dépenses', description: 'Caisse, tournées, marge sur livraison' },
  { key: 'stock', label: 'Stock', description: 'État, ruptures, mouvements, stock dormant' },
  { key: 'orders', label: 'Commandes', description: 'Statuts, annulations, zones' },
  { key: 'deliveries', label: 'Livraisons', description: 'Performance des livreurs et des zones' },
  { key: 'marketing', label: 'Marketing', description: 'Campagnes, dépenses publicitaires, ROI' },
];

export type Granularity = 'day' | 'week' | 'month' | 'year';

export const GRANULARITES: { key: Granularity; label: string }[] = [
  { key: 'day', label: 'Jour' },
  { key: 'week', label: 'Semaine' },
  { key: 'month', label: 'Mois' },
  { key: 'year', label: 'Année' },
];

export type PeriodPreset =
  | 'today'
  | 'last7'
  | 'week'
  | 'month'
  | 'prev_month'
  | 'year'
  | 'prev_year'
  | 'custom';

export const PRESETS: { key: PeriodPreset; label: string }[] = [
  { key: 'today', label: "Aujourd'hui" },
  { key: 'last7', label: '7 derniers jours' },
  { key: 'week', label: 'Cette semaine' },
  { key: 'month', label: 'Ce mois' },
  { key: 'prev_month', label: 'Mois précédent' },
  { key: 'year', label: 'Cette année' },
  { key: 'prev_year', label: 'Année précédente' },
  { key: 'custom', label: 'Personnalisée' },
];

export interface Period {
  from: string;
  to: string;
  /** Période de comparaison : mois/année/semaine calendaires précédents pour
   *  les préréglages, sinon la fenêtre de même longueur juste avant. */
  prevFrom: string;
  prevTo: string;
}

const iso = (d: Date) => d.toISOString().slice(0, 10);
const midi = (day: string) => new Date(`${day}T12:00:00+03:00`);
const addDays = (day: string, n: number) => {
  const d = midi(day);
  d.setDate(d.getDate() + n);
  return iso(d);
};

function fenetrePrecedente(from: string, to: string): { prevFrom: string; prevTo: string } {
  const longueur = Math.round((midi(to).getTime() - midi(from).getTime()) / 86_400_000) + 1;
  const prevTo = addDays(from, -1);
  return { prevFrom: addDays(prevTo, -(longueur - 1)), prevTo };
}

export function periodeDepuisPreset(preset: PeriodPreset, custom?: { from: string; to: string }): Period {
  const today = appToday();
  const t = midi(today);
  const y = t.getFullYear();
  const m = t.getMonth();
  const pad = (n: number) => String(n).padStart(2, '0');
  const jourMois = (yy: number, mm: number, dd: number) => `${yy}-${pad(mm + 1)}-${pad(dd)}`;
  const finMois = (yy: number, mm: number) => new Date(yy, mm + 1, 0).getDate();

  switch (preset) {
    case 'today':
      return { from: today, to: today, prevFrom: addDays(today, -1), prevTo: addDays(today, -1) };
    case 'last7': {
      const from = addDays(today, -6);
      return { from, to: today, ...fenetrePrecedente(from, today) };
    }
    case 'week': {
      const lundi = addDays(today, -((t.getDay() + 6) % 7));
      return { from: lundi, to: today, prevFrom: addDays(lundi, -7), prevTo: addDays(lundi, -1) };
    }
    case 'month': {
      const from = jourMois(y, m, 1);
      const pm = m === 0 ? 11 : m - 1;
      const py = m === 0 ? y - 1 : y;
      return { from, to: today, prevFrom: jourMois(py, pm, 1), prevTo: jourMois(py, pm, finMois(py, pm)) };
    }
    case 'prev_month': {
      const pm = m === 0 ? 11 : m - 1;
      const py = m === 0 ? y - 1 : y;
      const ppm = pm === 0 ? 11 : pm - 1;
      const ppy = pm === 0 ? py - 1 : py;
      return {
        from: jourMois(py, pm, 1),
        to: jourMois(py, pm, finMois(py, pm)),
        prevFrom: jourMois(ppy, ppm, 1),
        prevTo: jourMois(ppy, ppm, finMois(ppy, ppm)),
      };
    }
    case 'year':
      return { from: `${y}-01-01`, to: today, prevFrom: `${y - 1}-01-01`, prevTo: `${y - 1}-12-31` };
    case 'prev_year':
      return { from: `${y - 1}-01-01`, to: `${y - 1}-12-31`, prevFrom: `${y - 2}-01-01`, prevTo: `${y - 2}-12-31` };
    case 'custom':
    default: {
      const from = custom?.from || addDays(today, -29);
      const to = custom?.to || today;
      const [a, b] = from <= to ? [from, to] : [to, from];
      return { from: a, to: b, ...fenetrePrecedente(a, b) };
    }
  }
}

/** Granularité par défaut lisible pour une plage donnée. */
export function granulariteAuto(period: Period): Granularity {
  const jours = Math.round((midi(period.to).getTime() - midi(period.from).getTime()) / 86_400_000) + 1;
  if (jours <= 31) return 'day';
  if (jours <= 120) return 'week';
  if (jours <= 800) return 'month';
  return 'year';
}

// ---------------------------------------------------------------------------
// Formats
// ---------------------------------------------------------------------------

const nf = new Intl.NumberFormat('fr-MG', { maximumFractionDigits: 0 });

export const fmtAr = (v: number | string | null | undefined) => `${nf.format(Math.round(Number(v) || 0))} Ar`;
export const fmtNb = (v: number | string | null | undefined) => nf.format(Number(v) || 0);
export const fmtPct = (v: number | null | undefined, signe = false) =>
  v === null || v === undefined || Number.isNaN(v) ? '—' : `${signe && v > 0 ? '+' : ''}${Number(v).toFixed(1)} %`;
export const fmtArCourt = (v: number) => {
  const n = Math.abs(v);
  if (n >= 1_000_000) return `${(v / 1_000_000).toFixed(1)} M`;
  if (n >= 1_000) return `${Math.round(v / 1_000)} k`;
  return String(Math.round(v));
};
export const fmtDate = (isoDate: string | null | undefined) =>
  isoDate
    ? new Date(isoDate.length === 10 ? `${isoDate}T12:00:00+03:00` : isoDate).toLocaleDateString('fr-FR', {
        timeZone: 'Indian/Antananarivo',
      })
    : '—';
export const fmtDateHeure = (isoDate: string | null | undefined) =>
  isoDate
    ? new Date(isoDate).toLocaleString('fr-FR', {
        timeZone: 'Indian/Antananarivo',
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';
export const fmtDuree = (minutes: number | null | undefined) => {
  if (minutes === null || minutes === undefined) return '—';
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  return h ? `${h} h ${String(m).padStart(2, '0')}` : `${m} min`;
};

// ---------------------------------------------------------------------------
// Types de réponse (voir orders/reporting.py)
// ---------------------------------------------------------------------------

export interface Variation {
  actuel: number;
  precedent: number;
  variation: number;
  variation_pct: number | null;
}

export interface PeriodeInfo {
  from: string;
  to: string;
  prev_from: string;
  prev_to: string;
  granularity: Granularity;
}

export interface SeriePoint {
  periode: string;
  label: string;
  [k: string]: number | string;
}

export interface LigneVente {
  label: string;
  quantite: number;
  nb_commandes: number;
  ca: number;
  cout: number;
  marge: number;
  marge_pct: number;
}

export interface OverviewData {
  periode: PeriodeInfo;
  kpis: Record<'ca_total' | 'benefice_net' | 'nb_commandes' | 'panier_moyen' | 'nb_livrees' | 'depenses' | 'marge_brute', Variation>;
  /** Bénéfice obtenu (marge brute des articles livrés de la période) et
   *  bénéfice estimé (potentiel du stock actuel : valeur de vente − valeur d'achat). */
  benefices: {
    obtenu: Variation;
    estime: { benefice: number; valeur_vente: number; valeur_achat: number; quantite: number };
  };
  series: SeriePoint[];
  repartition_statuts: { statut: string; label: string; nb: number }[];
}

export interface SalesData {
  periode: PeriodeInfo;
  kpis: Record<'ca_total' | 'ca_produits' | 'nb_livrees' | 'quantite_vendue' | 'panier_moyen', Variation>;
  dimensions: { cle: string; label: string }[];
  par: Record<string, LigneVente[]>;
  top_produits: LigneVente[];
  moins_vendus: LigneVente[];
  par_livreur: { id: number; nom: string; commandes: number; livrees: number; retours: number; en_cours: number; ca: number; taux_reussite: number }[];
  serie: SeriePoint[];
}

export interface FinancialData {
  periode: PeriodeInfo;
  totaux: Record<string, number>;
  comparaison: Record<string, Variation>;
  par_produit: LigneVente[];
  par_categorie: LigneVente[];
  par_sous_type: LigneVente[];
  series: SeriePoint[];
}

export interface ExpensesData {
  periode: PeriodeInfo;
  totaux: { total: Variation; caisse: Variation; livreur: Variation; achats_stock: Variation; charges: Variation; nb_mouvements: number };
  par_categorie: { label: string; source: 'caisse' | 'livreur'; total: number; nb: number; hors_resultat: boolean }[];
  serie: SeriePoint[];
  livraison: Record<string, number>;
  mouvements: { date: string; source: string; categorie: string; libelle: string; montant: number; auteur: string }[];
}

export interface LigneStock {
  variant_id: number;
  produit: string;
  variante: string;
  stock: number;
  seuil: number;
  prix_achat: number;
  prix_vente: number;
}

export interface StockData {
  periode: PeriodeInfo;
  etat: Record<string, number>;
  ruptures: LigneStock[];
  reappro: LigneStock[];
  par_categorie: { label: string; quantite: number; valeur_achat: number; nb_variantes: number }[];
  mouvements_resume: { origine: string; label: string; nb: number; entrees: number; sorties: number }[];
  mouvements: {
    id: number; date: string; produit: string; variante: string; quantite: number; type: string;
    origine: string; origine_label: string; reference: string; note: string; utilisateur: string;
  }[];
  nb_mouvements: number;
  serie: SeriePoint[];
  dormant: {
    jours: number;
    nb: number;
    valeur_immobilisee: number;
    lignes: { variant_id: number; produit: string; variante: string; stock: number; derniere_vente: string | null; jours_sans_vente: number; valeur_immobilisee: number }[];
  };
}

export interface OrdersData {
  periode: PeriodeInfo;
  kpis: Record<string, number>;
  comparaison: Record<string, Variation>;
  repartition: { statut: string; label: string; nb: number; part: number }[];
  par_zone: { zone: string; nb: number; livrees: number; ca: number; frais: number }[];
  par_paiement: { mode: string; label: string; nb: number; ca: number }[];
  serie: SeriePoint[];
  montant_annule: number;
  montant_retourne: number;
}

export interface LigneLivreur {
  id: number; nom: string; assignees: number; livraisons: number; reussies: number; echouees: number; en_cours: number;
  cout_total: number; cout_moyen: number; frais_factures: number; marge_livraison: number; ca: number;
  taux_reussite: number; taux_echec: number; delai_moyen_minutes: number | null;
}

export interface DeliveriesData {
  periode: PeriodeInfo;
  totaux: Record<string, number | null>;
  par_livreur: LigneLivreur[];
  par_zone: { zone: string; livraisons: number; reussies: number; echouees: number; frais: number; taux_reussite: number }[];
  serie: SeriePoint[];
}

export interface Campagne {
  id: number; nom: string; plateforme: string; plateforme_label: string; date_debut: string; date_fin: string | null; actif: boolean;
  depenses: number; commandes: number; commandes_livrees: number; ca: number; marge_produits: number; benefice: number;
  roi_pct: number | null; cout_par_commande: number | null;
}

export interface MarketingData {
  periode: PeriodeInfo;
  totaux: Record<string, number | null>;
  campagnes: Campagne[];
  par_plateforme: { plateforme: string; label: string; depenses: number; commandes: number; commandes_livrees: number; ca: number; nb_campagnes: number; roi_pct: number | null }[];
  plus_rentables: Campagne[];
  moins_rentables: Campagne[];
  plateformes: { code: string; label: string }[];
}

export const STATUT_COULEURS: Record<string, string> = {
  NOUVELLE: '#3b82f6',
  EN_PREPARATION: '#f59e0b',
  PRETE: '#8b5cf6',
  EN_LIVRAISON: '#06b6d4',
  LIVRE: '#22c55e',
  RETOUR: '#f97316',
  ANNULEE: '#ef4444',
};

export const PALETTE = ['#2563eb', '#16a34a', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#f97316', '#64748b'];
