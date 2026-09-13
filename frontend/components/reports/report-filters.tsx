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
  /** Date de référence (AAAA-MM-JJ) ; vide = aujourd'hui. */
  date: string;
  granularity: Granularity | 'auto';
}

/**
 * Filtres communs à tous les rapports : période (liste déroulante, à la
 * place de l'ancien choix de granularité — les séries suivent la granularité
 * automatique) et date de référence unique. Empilés proprement sur mobile.
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
  const dateRef = filtres.date || period.to;
  return (
    <div className="space-y-3 print:hidden">
      <div className="flex flex-col sm:flex-row sm:flex-wrap sm:items-end gap-2">
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Période</Label>
          <Select value={filtres.preset} onValueChange={(v) => onChange({ ...filtres, preset: v as PeriodPreset })}>
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
          <Label className="text-xs text-muted-foreground">Date</Label>
          <Input
            type="date"
            value={dateRef}
            onChange={(e) => onChange({ ...filtres, date: e.target.value })}
            className="h-9 w-full sm:w-auto"
            aria-label="Date de référence"
          />
        </div>
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
