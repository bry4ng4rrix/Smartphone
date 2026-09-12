'use client';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { RefreshCw } from 'lucide-react';
import {
  GRANULARITES,
  PRESETS,
  fmtDate,
  type Granularity,
  type Period,
  type PeriodPreset,
} from '@/lib/reports';

export interface Filtres {
  preset: PeriodPreset;
  custom: { from: string; to: string };
  granularity: Granularity | 'auto';
}

/**
 * Filtres communs à tous les rapports : période rapide ou personnalisée,
 * granularité des séries. Empilés proprement sur mobile.
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
  return (
    <div className="space-y-3 print:hidden">
      <div className="flex flex-wrap gap-1.5">
        {PRESETS.map((p) => (
          <Button
            key={p.key}
            size="sm"
            variant={filtres.preset === p.key ? 'default' : 'outline'}
            className="h-8 text-xs"
            onClick={() => onChange({ ...filtres, preset: p.key })}
          >
            {p.label}
          </Button>
        ))}
      </div>
      <div className="flex flex-col sm:flex-row sm:flex-wrap sm:items-end gap-2">
        <div className="grid grid-cols-2 gap-2 sm:flex sm:items-end">
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Du</Label>
            <Input
              type="date"
              value={filtres.preset === 'custom' ? filtres.custom.from : period.from}
              max={filtres.preset === 'custom' ? filtres.custom.to : undefined}
              onChange={(e) =>
                onChange({ ...filtres, preset: 'custom', custom: { from: e.target.value, to: filtres.preset === 'custom' ? filtres.custom.to : period.to } })
              }
              className="h-9 w-full sm:w-auto"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Au</Label>
            <Input
              type="date"
              value={filtres.preset === 'custom' ? filtres.custom.to : period.to}
              min={filtres.preset === 'custom' ? filtres.custom.from : undefined}
              onChange={(e) =>
                onChange({ ...filtres, preset: 'custom', custom: { from: filtres.preset === 'custom' ? filtres.custom.from : period.from, to: e.target.value } })
              }
              className="h-9 w-full sm:w-auto"
            />
          </div>
        </div>
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Granularité</Label>
          <Select value={filtres.granularity} onValueChange={(v) => onChange({ ...filtres, granularity: v as Filtres['granularity'] })}>
            <SelectTrigger className="h-9 w-full sm:w-36">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="auto">Automatique</SelectItem>
              {GRANULARITES.map((g) => (
                <SelectItem key={g.key} value={g.key}>
                  {g.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
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
