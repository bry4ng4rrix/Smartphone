'use client';

import { useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowDownCircle, ArrowUpCircle, FilterX } from 'lucide-react';
import { appDayKey } from '@/lib/timezone';
import { fmtAr, fmtDateHeure } from '@/lib/reports';
import { ReportTable } from '@/components/reports/report-table';
import { POS, NEG } from './ui';

export interface LigneJournal {
  id: number; date: string; session_id: number; type: 'in' | 'out'; origine: string; origine_label: string;
  entree: number; sortie: number; montant: number; libelle: string; categorie: string; reference: string;
  solde_apres: number; auteur: string; automatique: boolean;
}

type Sens = 'TOUS' | 'in' | 'out';

const filtresVides = () => ({ date: '', sens: 'TOUS' as Sens, origine: 'TOUTES', recherche: '', min: '', max: '' });

/**
 * Journal des mouvements de caisse avec solde après chaque mouvement.
 * Filtres LOCAUX (§ demande) sur les lignes déjà chargées pour la période
 * de la page : date (un seul jour, heure de Madagascar), sens (entrées / sorties),
 * type (origine), montant min / max et recherche libre (description,
 * numéro de commande / référence, catégorie, auteur).
 */
export function SectionJournal({ lignes, loading, error }: { lignes: LigneJournal[] | null; loading: boolean; error?: string | null }) {
  const [f, setF] = useState(filtresVides);
  const actif = JSON.stringify(f) !== JSON.stringify(filtresVides());

  // Types réellement présents dans la période, pour ne proposer que l'utile.
  const origines = useMemo(() => {
    const m = new Map<string, string>();
    for (const l of lignes ?? []) m.set(l.origine, l.origine_label);
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1], 'fr'));
  }, [lignes]);

  const filtrees = useMemo(() => {
    if (!lignes) return lignes;
    const q = f.recherche.trim().toLowerCase();
    const min = f.min === '' ? null : Number(f.min);
    const max = f.max === '' ? null : Number(f.max);
    return lignes.filter((l) => {
      if (f.date && appDayKey(l.date) !== f.date) return false;
      if (f.sens !== 'TOUS' && l.type !== f.sens) return false;
      if (f.origine !== 'TOUTES' && l.origine !== f.origine) return false;
      const montant = Number(l.montant);
      if (min !== null && montant < min) return false;
      if (max !== null && montant > max) return false;
      if (q) {
        const texte = [l.libelle, l.reference, l.categorie, l.auteur, l.origine_label, String(l.montant)].join(' ').toLowerCase();
        if (!texte.includes(q)) return false;
      }
      return true;
    });
  }, [lignes, f]);

  const totalEntrees = useMemo(() => (filtrees ?? []).reduce((a, l) => a + Number(l.entree || 0), 0), [filtrees]);
  const totalSorties = useMemo(() => (filtrees ?? []).reduce((a, l) => a + Number(l.sortie || 0), 0), [filtrees]);

  const filtres = (
    <div className="print:hidden flex flex-wrap items-end gap-2 mt-3">
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Date</Label>
        <Input type="date" value={f.date} onChange={(e) => setF({ ...f, date: e.target.value })} className="h-9 w-[150px]" />
      </div>
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Sens</Label>
        <Select value={f.sens} onValueChange={(v) => setF({ ...f, sens: v as Sens })}>
          <SelectTrigger className="h-9 w-[130px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="TOUS">Entrées + sorties</SelectItem>
            <SelectItem value="in">Entrées</SelectItem>
            <SelectItem value="out">Sorties</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Type</Label>
        <Select value={f.origine} onValueChange={(v) => setF({ ...f, origine: v })}>
          <SelectTrigger className="h-9 w-[190px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="TOUTES">Tous les types</SelectItem>
            {origines.map(([code, label]) => <SelectItem key={code} value={code}>{label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Montant min (Ar)</Label>
        <Input type="number" min={0} value={f.min} onChange={(e) => setF({ ...f, min: e.target.value })} className="h-9 w-[130px]" placeholder="0" />
      </div>
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Montant max (Ar)</Label>
        <Input type="number" min={0} value={f.max} onChange={(e) => setF({ ...f, max: e.target.value })} className="h-9 w-[130px]" placeholder="∞" />
      </div>
      <div className="space-y-1 min-w-[220px] flex-1">
        <Label className="text-xs text-muted-foreground">Recherche</Label>
        <Input value={f.recherche} onChange={(e) => setF({ ...f, recherche: e.target.value })} className="h-9" placeholder="Nom, n° de commande, référence, catégorie, auteur…" />
      </div>
      {actif && (
        <Button variant="ghost" size="sm" className="h-9" onClick={() => setF(filtresVides())}>
          <FilterX className="h-4 w-4 mr-1" aria-hidden /> Réinitialiser
        </Button>
      )}
      {lignes && (
        <p className="basis-full text-xs text-muted-foreground">
          {filtrees?.length ?? 0} mouvement(s){actif ? ` sur ${lignes.length}` : ''} · entrées <span className={POS}>+{fmtAr(totalEntrees)}</span> · sorties <span className={NEG}>−{fmtAr(totalSorties)}</span>
        </p>
      )}
    </div>
  );

  return (
    <ReportTable
      titre="Journal des mouvements de caisse"
      description={
        <>
          Entrées et sorties de la période avec le solde après chaque mouvement (le solde repart du fond d&apos;ouverture à chaque session). Les mouvements automatiques portent une référence et ne peuvent pas être supprimés.
          {filtres}
        </>
      }
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
      lignes={filtrees}
      loading={loading}
      error={error}
      pageSize={15}
      exportNom="journal_caisse"
      rowKey={(r) => r.id}
      compact
      vide={actif ? 'Aucun mouvement ne correspond à ces filtres.' : 'Aucun mouvement de caisse sur la période.'}
    />
  );
}
