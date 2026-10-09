'use client';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { RefreshCw } from 'lucide-react';
import {
  PRESETS,
  fmtDate,
  type Granularity,
  type Period,
  type PeriodPreset,
} from '@/lib/reports';

export interface Filtres {
  preset: PeriodPreset;
  /** Date de référence (AAAA-MM-JJ) ; vide = aujourd'hui. En période
   *  personnalisée, c'est la borne de DÉBUT. */
  date: string;
  /** Borne de FIN — n'a de sens qu'en période personnalisée ; vide = la
   *  période vaut le seul jour de `date`. */
  dateFin: string;
  granularity: Granularity | 'auto';
}

/**
 * Filtres communs à tous les rapports : période (liste déroulante, à la
 * place de l'ancien choix de granularité — les séries suivent la granularité
 * automatique) et date(s).
 *
 * Les préréglages déduisent leur plage d'UNE SEULE date de référence : « Ce
 * mois » au 15/08 va du 1er au 15 août. « Personnalisée » est le seul cas où
 * l'utilisateur borne les deux extrémités — on y affiche donc deux champs,
 * « Du » et « Au », et un seul partout ailleurs (§ demande). Empilés
 * proprement sur mobile.
 */
export function ReportFilters({
  filtres,
  period,
  onChange,
  onReload,
  loading,
}: {
  filtres: Filtres;
  period: Period;
  onChange: (f: Filtres) => void;
  onReload: () => void;
  loading?: boolean;
}) {
  const personnalisee = filtres.preset === 'custom';
  // Repli quand rien n'est saisi — et il ne désigne pas la même chose selon
  // le mode : en personnalisé le champ EST la borne de début, ailleurs c'est
  // la date de référence dont le préréglage déduit sa plage (qui se termine
  // donc sur elle).
  const dateRef = filtres.date || (personnalisee ? period.from : period.to);
  return (
    <div className="space-y-3 print:hidden">
      <div className="flex flex-col sm:flex-row sm:flex-wrap sm:items-end gap-2">
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Période</Label>
          <Select
            value={filtres.preset}
            onValueChange={(v) => {
              const preset = v as PeriodPreset;
              // En passant sur « Personnalisée », on amorce la borne de fin
              // sur la date de référence : la plage est valide d'emblée,
              // l'utilisateur n'a qu'à l'élargir.
              onChange({
                ...filtres,
                preset,
                dateFin: preset === 'custom' ? filtres.dateFin || dateRef : '',
              });
            }}
          >
            <SelectTrigger className="h-9 w-full sm:w-44">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {PRESETS.map((p) => (
                <SelectItem key={p.key} value={p.key}>
                  {p.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">{personnalisee ? 'Du' : 'Date'}</Label>
          <Input
            type="date"
            value={dateRef}
            max={personnalisee && filtres.dateFin ? filtres.dateFin : undefined}
            onChange={(e) => onChange({ ...filtres, date: e.target.value })}
            className="h-9 w-full sm:w-auto"
            aria-label={personnalisee ? 'Début de la période' : 'Date de référence'}
          />
        </div>
        {personnalisee && (
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Au</Label>
            <Input
              type="date"
              value={filtres.dateFin || dateRef}
              min={dateRef || undefined}
              onChange={(e) => onChange({ ...filtres, dateFin: e.target.value })}
              className="h-9 w-full sm:w-auto"
              aria-label="Fin de la période"
            />
          </div>
        )}
        <div className="flex items-end gap-2 sm:ml-auto">
          <p className="text-xs text-muted-foreground leading-9">
            {fmtDate(period.from)} → {fmtDate(period.to)}
            <span className="hidden md:inline"> · comparé à {fmtDate(period.prevFrom)} → {fmtDate(period.prevTo)}</span>
          </p>
          <Button variant="outline" size="icon" className="h-9 w-9 shrink-0" onClick={onReload} disabled={loading} aria-label="Actualiser">
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </Button>
        </div>
      </div>
    </div>
  );
}
