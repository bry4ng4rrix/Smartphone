'use client';

import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Truck } from 'lucide-react';
import { fmtAr, fmtDate, fmtNb } from '@/lib/reports';

export interface StatsLivraison {
  from: string;
  to: string;
  nb: number;
  facturee: number;
  agence: number;
  resultat: number;
  etat: 'benefice' | 'perte' | 'equilibre';
}

const ETAT = {
  benefice: { label: 'Bénéfice livraison', cls: 'text-emerald-600 dark:text-emerald-400', bord: 'border-l-emerald-500' },
  perte: { label: 'Perte livraison', cls: 'text-red-600 dark:text-red-400', bord: 'border-l-red-500' },
  equilibre: { label: 'Équilibre', cls: 'text-muted-foreground', bord: 'border-l-border' },
};

function Bloc({ titre, s }: { titre: string; s: StatsLivraison }) {
  const etat = ETAT[s.etat];
  return (
    <div className={`rounded-lg border border-l-4 ${etat.bord} p-3 space-y-1.5`}>
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold">{titre}</p>
        <span className="text-xs text-muted-foreground">{fmtNb(s.nb)} livraison(s)</span>
      </div>
      <div className="flex justify-between gap-2 text-sm"><span className="text-muted-foreground">Livraison facturée</span><span className="tabular-nums whitespace-nowrap">{fmtAr(s.facturee)}</span></div>
      <div className="flex justify-between gap-2 text-sm"><span className="text-muted-foreground">Frais de livraison acceptés</span><span className="tabular-nums whitespace-nowrap">{fmtAr(s.agence)}</span></div>
      <div className="flex justify-between gap-2 text-sm font-semibold border-t pt-1.5">
        <span>{etat.label}</span>
        <span className={`tabular-nums whitespace-nowrap ${etat.cls}`}>{Number(s.resultat) > 0 ? '+' : ''}{fmtAr(s.resultat)}</span>
      </div>
    </div>
  );
}

/** Résultat livraison : facturé au client vs payé aux agences (jour / semaine / mois / période). */
export function SectionLivraison({ data, loading }: { data: { periode: StatsLivraison; jour: StatsLivraison; semaine: StatsLivraison; mois: StatsLivraison } | null; loading: boolean }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base"><Truck className="h-4 w-4" aria-hidden /> Résultats livraison</CardTitle>
        <CardDescription className="text-xs">
          Livraison facturée au client − frais de livraison acceptés (dépenses des livreurs de type LIVRAISON 3K / 4K / 5K… validées par le gérant, même chiffre que le rapport Dépenses).
          Les frais facturés ne sont jamais un bénéfice tant que le coût réel n&apos;est pas déduit.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {loading || !data ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-28" />)}</div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">
            <Bloc titre="Aujourd'hui" s={data.jour} />
            <Bloc titre="Cette semaine" s={data.semaine} />
            <Bloc titre="Ce mois" s={data.mois} />
            <div className="relative">
              <Badge variant="secondary" className="absolute -top-2 right-2 text-[10px]">filtre</Badge>
              <Bloc titre={`${fmtDate(data.periode.from)} → ${fmtDate(data.periode.to)}`} s={data.periode} />
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
