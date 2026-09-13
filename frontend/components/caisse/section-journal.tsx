'use client';

import { Badge } from '@/components/ui/badge';
import { ArrowDownCircle, ArrowUpCircle } from 'lucide-react';
import { fmtAr, fmtDateHeure } from '@/lib/reports';
import { ReportTable } from '@/components/reports/report-table';
import { POS, NEG } from './ui';

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
      description="Entrées et sorties de la période avec le solde après chaque mouvement (le solde repart du fond d'ouverture à chaque session). Les mouvements automatiques portent une référence et ne peuvent pas être supprimés."
      colonnes={[
        { key: 'date', label: 'Date', render: (r) => <span className="whitespace-nowrap">{fmtDateHeure(r.date)}</span> },
        { key: 'origine_label', label: 'Type', render: (r) => <Badge variant={r.automatique ? 'default' : 'outline'}>{r.origine_label}</Badge> },
        { key: 'libelle', label: 'Description', render: (r) => <span>{r.libelle}{r.categorie && <span className="text-muted-foreground"> · {r.categorie}</span>}</span> },
        { key: 'entree', label: 'Entrée', align: 'right', render: (r) => (Number(r.entree) ? <span className={POS}>+{fmtAr(r.entree)}</span> : ''), export: (r) => Number(r.entree) || null },
        { key: 'sortie', label: 'Sortie', align: 'right', render: (r) => (Number(r.sortie) ? <span className={NEG}>−{fmtAr(r.sortie)}</span> : ''), export: (r) => Number(r.sortie) || null },
        { key: 'solde_apres', label: 'Solde', align: 'right', render: (r) => <span className="font-medium tabular-nums whitespace-nowrap">{fmtAr(r.solde_apres)}</span> },
        { key: 'reference', label: 'Référence', render: (r) => <span className="text-xs text-muted-foreground">{r.reference}</span> },
        { key: 'auteur', label: 'Par' },
      ]}
      carteMobile={(r) => (
        <div className="flex items-start gap-3">
          {r.type === 'in' ? <ArrowUpCircle className={`h-5 w-5 mt-0.5 shrink-0 ${POS}`} aria-hidden /> : <ArrowDownCircle className={`h-5 w-5 mt-0.5 shrink-0 ${NEG}`} aria-hidden />}
          <div className="min-w-0 flex-1 space-y-1">
            <div className="flex items-start justify-between gap-2">
              <p className="text-sm font-medium leading-snug break-words">{r.libelle}</p>
              <span className={`text-sm font-semibold tabular-nums whitespace-nowrap ${r.type === 'in' ? POS : NEG}`}>
                {r.type === 'in' ? '+' : '−'}{fmtAr(r.montant)}
              </span>
            </div>
            <p className="text-xs text-muted-foreground">
              {fmtDateHeure(r.date)}{r.auteur ? ` · ${r.auteur}` : ''}
            </p>
            <div className="flex flex-wrap items-center gap-1.5 text-xs">
              <Badge variant={r.automatique ? 'default' : 'outline'} className="text-[10px]">{r.origine_label}</Badge>
              {r.categorie && <Badge variant="secondary" className="text-[10px]">{r.categorie}</Badge>}
              <span className="ml-auto text-muted-foreground">Solde : <span className="font-medium text-foreground tabular-nums">{fmtAr(r.solde_apres)}</span></span>
            </div>
          </div>
        </div>
      )}
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
