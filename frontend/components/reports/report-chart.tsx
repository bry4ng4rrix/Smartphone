'use client';

import type { ReactNode } from 'react';
import {
  Bar,
  CartesianGrid,
  Cell,
  ComposedChart,
  Legend,
  Line,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { fmtAr, fmtArCourt, fmtNb, PALETTE, type SeriePoint } from '@/lib/reports';

export interface SerieDef {
  key: string;
  label: string;
  type?: 'bar' | 'line' | 'area';
  color?: string;
  /** Montants en Ar (défaut) ou simple nombre. */
  unite?: 'ar' | 'nb';
  stackId?: string;
}

export function ChartCard({
  titre,
  description,
  loading,
  error,
  vide,
  hauteur = 280,
  children,
  actions,
}: {
  titre: string;
  description?: ReactNode;
  loading?: boolean;
  error?: string | null;
  vide?: boolean;
  hauteur?: number;
  children: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <Card className="print:break-inside-avoid">
      <CardHeader className="flex flex-row items-start justify-between gap-2 space-y-0 pb-2">
        <div>
          <CardTitle className="text-base">{titre}</CardTitle>
          {description && <CardDescription className="text-xs mt-0.5">{description}</CardDescription>}
        </div>
        {actions && <div className="shrink-0 print:hidden">{actions}</div>}
      </CardHeader>
      <CardContent>
        {loading ? (
          <Skeleton style={{ height: hauteur }} className="w-full" />
        ) : error ? (
          <p className="text-sm text-destructive py-8 text-center">{error}</p>
        ) : vide ? (
          <p className="text-sm text-muted-foreground py-8 text-center">Aucune donnée sur la période.</p>
        ) : (
          <div style={{ height: hauteur }} className="w-full">
            {children}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

/** Courbes / barres dans le temps (séries renvoyées par le serveur). */
export function SerieChart({
  data,
  series,
  hauteur = 280,
}: {
  data: SeriePoint[];
  series: SerieDef[];
  hauteur?: number;
}) {
  const ar = series.some((s) => (s.unite ?? 'ar') === 'ar');
  const nb = series.some((s) => s.unite === 'nb');
  return (
    <ResponsiveContainer width="100%" height={hauteur}>
      <ComposedChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="currentColor" opacity={0.12} />
        <XAxis dataKey="label" tick={{ fontSize: 11 }} interval="preserveStartEnd" minTickGap={16} />
        {ar && <YAxis yAxisId="ar" tick={{ fontSize: 11 }} tickFormatter={fmtArCourt} width={48} />}
        {nb && <YAxis yAxisId="nb" orientation={ar ? 'right' : 'left'} tick={{ fontSize: 11 }} allowDecimals={false} width={36} />}
        <Tooltip
          formatter={(v: number, name: string) => {
            const s = series.find((x) => x.label === name);
            return [(s?.unite ?? 'ar') === 'ar' ? fmtAr(v) : fmtNb(v), name];
          }}
          contentStyle={{ fontSize: 12 }}
        />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        {series.map((s, i) => {
          const color = s.color || PALETTE[i % PALETTE.length];
          const yAxisId = (s.unite ?? 'ar') === 'ar' ? 'ar' : 'nb';
          if (s.type === 'line') {
            return <Line key={s.key} yAxisId={yAxisId} type="monotone" dataKey={s.key} name={s.label} stroke={color} strokeWidth={2} dot={data.length <= 31} />;
          }
          return <Bar key={s.key} yAxisId={yAxisId} dataKey={s.key} name={s.label} fill={color} radius={[3, 3, 0, 0]} stackId={s.stackId} maxBarSize={40} />;
        })}
      </ComposedChart>
    </ResponsiveContainer>
  );
}

/** Barres horizontales pour un classement (catégories, zones, livreurs…). */
export function BarresChart({
  data,
  labelKey,
  valueKey,
  unite = 'ar',
  hauteur = 280,
  color = PALETTE[0],
  colors,
}: {
  data: object[];
  labelKey: string;
  valueKey: string;
  unite?: 'ar' | 'nb';
  hauteur?: number;
  color?: string;
  colors?: string[];
}) {
  return (
    <ResponsiveContainer width="100%" height={hauteur}>
      <ComposedChart data={data} layout="vertical" margin={{ top: 4, right: 16, left: 8, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="currentColor" opacity={0.12} horizontal={false} />
        <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={unite === 'ar' ? fmtArCourt : undefined} allowDecimals={false} />
        <YAxis type="category" dataKey={labelKey} tick={{ fontSize: 11 }} width={120} interval={0} />
        <Tooltip formatter={(v: number) => (unite === 'ar' ? fmtAr(v) : fmtNb(v))} contentStyle={{ fontSize: 12 }} />
        <Bar dataKey={valueKey} fill={color} radius={[0, 3, 3, 0]} maxBarSize={22}>
          {colors && data.map((_, i) => <Cell key={i} fill={colors[i % colors.length]} />)}
        </Bar>
      </ComposedChart>
    </ResponsiveContainer>
  );
}

/** Répartition (statuts, plateformes, catégories de dépenses). */
export function CamembertChart({
  data,
  labelKey,
  valueKey,
  unite = 'nb',
  hauteur = 280,
  colors,
}: {
  data: object[];
  labelKey: string;
  valueKey: string;
  unite?: 'ar' | 'nb';
  hauteur?: number;
  colors?: string[];
}) {
  const filtres = (data as Record<string, unknown>[]).filter((d) => Number(d[valueKey]) > 0);
  return (
    <ResponsiveContainer width="100%" height={hauteur}>
      <PieChart>
        <Pie data={filtres} dataKey={valueKey} nameKey={labelKey} innerRadius="45%" outerRadius="75%" paddingAngle={2} isAnimationActive={false}>
          {filtres.map((_, i) => (
            <Cell key={i} fill={(colors || PALETTE)[i % (colors || PALETTE).length]} />
          ))}
        </Pie>
        <Tooltip formatter={(v: number) => (unite === 'ar' ? fmtAr(v) : fmtNb(v))} contentStyle={{ fontSize: 12 }} />
        <Legend wrapperStyle={{ fontSize: 12 }} />
      </PieChart>
    </ResponsiveContainer>
  );
}
