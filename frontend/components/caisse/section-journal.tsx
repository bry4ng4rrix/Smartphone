'use client';

import { Badge } from '@/components/ui/badge';
import { fmtAr, fmtDateHeure } from '@/lib/reports';
import { ReportTable } from '@/components/reports/report-table';

export interface LigneJournal {
  id: number; date: string; session_id: number; type: 'in' | 'out'; origine: string; origine_label: string;
  entree: number; sortie: number; montant: number; libelle: string; categorie: string; reference: string;
  solde_apres: number; auteur: string; automatique: boolean;
}

/** Journal des mouvements de caisse avec solde après chaque mouvement. */
export function SectionJournal({ lignes, loading, error }: { lignes: LigneJournal[] | null; loading: boolean; error?: string | null }) {
  return (
    <ReportTable
      titre="Journal des mouvements de caisse"
      description="Toutes les entrées et sorties de la période, avec le solde de caisse après chaque mouvement (le solde repart du fond d'ouverture à chaque session). Les mouvements automatiques portent une référence et ne peuvent pas être supprimés."
      colonnes={[
        { key: 'date', label: 'Date', render: (r) => fmtDateHeure(r.date) },
        { key: 'origine_label', label: 'Type', render: (r) => <Badge variant={r.automatique ? 'default' : 'outline'}>{r.origine_label}</Badge> },
        { key: 'libelle', label: 'Description', render: (r) => <span>{r.libelle}{r.categorie && <span className="text-muted-foreground"> · {r.categorie}</span>}</span> },
        { key: 'entree', label: 'Entrée', align: 'right', render: (r) => (Number(r.entree) ? <span className="text-emerald-600">+{fmtAr(r.entree)}</span> : ''), export: (r) => Number(r.entree) || null },
        { key: 'sortie', label: 'Sortie', align: 'right', render: (r) => (Number(r.sortie) ? <span className="text-red-600">−{fmtAr(r.sortie)}</span> : ''), export: (r) => Number(r.sortie) || null },
        { key: 'solde_apres', label: 'Solde', align: 'right', render: (r) => <span className="font-medium tabular-nums">{fmtAr(r.solde_apres)}</span> },
        { key: 'reference', label: 'Référence', render: (r) => <span className="text-xs text-muted-foreground">{r.reference}</span> },
        { key: 'auteur', label: 'Par' },
      ]}
      lignes={lignes}
      loading={loading}
      error={error}
      pageSize={15}
      exportNom="journal_caisse"
      rowKey={(r) => r.id}
      compact
      vide="Aucun mouvement de caisse sur la période."
    />
  );
}
