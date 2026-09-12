'use client';

import type { ReactNode } from 'react';
import { Line, LineChart, ResponsiveContainer } from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { ArrowDownRight, ArrowUpRight, Minus } from 'lucide-react';
import { fmtPct, type Variation } from '@/lib/reports';

/**
 * Indicateur d'évolution : flèche + pourcentage. `inverse` pour les
 * indicateurs où une hausse est mauvaise (dépenses, annulations).
 */
export function VariationBadge({
  pct,
  inverse = false,
  className = '',
}: {
  pct: number | null | undefined;
  inverse?: boolean;
  className?: string;
}) {
  if (pct === null || pct === undefined) {
    return <span className={`text-xs text-muted-foreground ${className}`}>n/a (période préc. = 0)</span>;
  }
  const positif = pct > 0;
  const nul = pct === 0;
  const bon = nul ? null : inverse ? !positif : positif;
  const couleur = nul ? 'text-muted-foreground' : bon ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400';
  const Icon = nul ? Minus : positif ? ArrowUpRight : ArrowDownRight;
  return (
    <span className={`inline-flex items-center gap-0.5 text-xs font-medium ${couleur} ${className}`}>
      <Icon className="h-3.5 w-3.5" />
      {fmtPct(pct, true)}
    </span>
  );
}

export function KpiCard({
  titre,
  valeur,
  detail,
  variation,
  inverse,
  icon: Icon,
  couleur = 'text-foreground',
  serie,
  loading,
  format,
}: {
  titre: string;
  valeur?: string | null;
  detail?: ReactNode;
  /** Comparaison avec la période précédente. */
  variation?: Variation;
  /** Une hausse est une mauvaise nouvelle (dépenses, annulations…). */
  inverse?: boolean;
  icon?: React.ComponentType<{ className?: string }>;
  couleur?: string;
  /** Petite tendance (valeurs brutes). */
  serie?: number[];
  loading?: boolean;
  /** Pour afficher la valeur précédente. */
  format?: (v: number) => string;
}) {
  if (loading) {
    return (
      <Card>
        <CardHeader className="pb-2">
          <Skeleton className="h-3.5 w-24" />
          <Skeleton className="h-7 w-32 mt-1" />
        </CardHeader>
        <CardContent className="pt-0">
          <Skeleton className="h-3 w-20" />
        </CardContent>
      </Card>
    );
  }
  const hausse = variation && variation.variation_pct !== null && variation.variation_pct !== 0
    ? (inverse ? variation.variation_pct < 0 : variation.variation_pct > 0)
    : null;
  return (
    <Card className="relative overflow-hidden">
      <CardHeader className="pb-2">
        <CardDescription className="flex items-center gap-1.5 text-xs">
          {Icon && <Icon className="h-3.5 w-3.5" />}
          {titre}
        </CardDescription>
        <CardTitle className={`text-xl sm:text-2xl tabular-nums ${couleur}`}>{valeur ?? '—'}</CardTitle>
      </CardHeader>
      <CardContent className="pt-0 space-y-1">
        {variation && (
          <div className="flex items-center gap-2 flex-wrap">
            <VariationBadge pct={variation.variation_pct} inverse={inverse} />
            {format && (
              <span className="text-xs text-muted-foreground">préc. {format(variation.precedent)}</span>
            )}
          </div>
        )}
        {detail && <p className="text-xs text-muted-foreground">{detail}</p>}
        {serie && serie.length > 1 && (
          <div className="h-8 -mx-1">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={serie.map((v, i) => ({ i, v }))}>
                <Line
                  type="monotone"
                  dataKey="v"
                  stroke={hausse === null ? '#64748b' : hausse ? '#16a34a' : '#dc2626'}
                  strokeWidth={1.5}
                  dot={false}
                  isAnimationActive={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export function KpiGrid({ children, cols = 4 }: { children: ReactNode; cols?: 2 | 3 | 4 | 5 }) {
  const map = { 2: 'lg:grid-cols-2', 3: 'lg:grid-cols-3', 4: 'lg:grid-cols-4', 5: 'lg:grid-cols-5' };
  return <div className={`grid grid-cols-1 sm:grid-cols-2 ${map[cols]} gap-3 sm:gap-4`}>{children}</div>;
}
