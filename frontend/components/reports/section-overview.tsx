'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { BadgeDollarSign, Package, ShoppingCart, TrendingUp, Truck, Wallet } from 'lucide-react';
import { fmtAr, fmtDate, fmtNb, STATUT_COULEURS, type OverviewData } from '@/lib/reports';
import { KpiCard, KpiGrid, VariationBadge } from './kpi-card';
import { CamembertChart, ChartCard, SerieChart } from './report-chart';
import { useReport, type ReportParams } from './use-report';

export function SectionOverview({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const { data, loading, error } = useReport<OverviewData>('overview', params, enabled);
  const k = data?.kpis;
  const serie = (cle: string) => data?.series.map((p) => Number(p[cle]) || 0);

  return (
    <div className="space-y-4">
      <KpiGrid cols={4}>
        <KpiCard loading={loading} titre="Chiffre d'affaires" icon={BadgeDollarSign} valeur={k && fmtAr(k.ca_total.actuel)} variation={k?.ca_total} format={fmtAr} serie={serie('ventes')} />
        <KpiCard
          loading={loading}
          titre="Bénéfice net"
          icon={TrendingUp}
          valeur={k && fmtAr(k.benefice_net.actuel)}
          couleur={k && k.benefice_net.actuel < 0 ? 'text-red-600 dark:text-red-400' : 'text-emerald-600 dark:text-emerald-400'}
          variation={k?.benefice_net}
          format={fmtAr}
          serie={serie('benefices')}
          detail="CA − coût d'achat − dépenses (hors achats de stock)"
        />
        <KpiCard loading={loading} titre="Commandes" icon={ShoppingCart} valeur={k && fmtNb(k.nb_commandes.actuel)} variation={k?.nb_commandes} format={fmtNb} detail={k && `${fmtNb(k.nb_livrees.actuel)} livrées`} />
        <KpiCard loading={loading} titre="Panier moyen" icon={Package} valeur={k && fmtAr(k.panier_moyen.actuel)} variation={k?.panier_moyen} format={fmtAr} detail="CA / commandes livrées" />
      </KpiGrid>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ChartCard
            titre="Ventes, dépenses et bénéfices"
            description={data && `Par ${{ day: 'jour', week: 'semaine', month: 'mois', year: 'année' }[data.periode.granularity]} — ${fmtDate(data.periode.from)} → ${fmtDate(data.periode.to)}`}
            loading={loading}
            error={error}
            vide={!data?.series.length}
            hauteur={320}
          >
            {data && (
              <SerieChart
                data={data.series}
                hauteur={320}
                series={[
                  { key: 'ventes', label: 'Ventes (CA)', type: 'bar', color: '#2563eb' },
                  { key: 'depenses', label: 'Dépenses', type: 'bar', color: '#ef4444' },
                  { key: 'benefices', label: 'Bénéfices', type: 'line', color: '#16a34a' },
                ]}
              />
            )}
          </ChartCard>
        </div>
        <ChartCard titre="Commandes par statut" loading={loading} error={error} vide={!data?.repartition_statuts.some((r) => r.nb > 0)} hauteur={320}>
          {data && (
            <CamembertChart
              data={data.repartition_statuts}
              labelKey="label"
              valueKey="nb"
              hauteur={320}
              colors={data.repartition_statuts.filter((r) => r.nb > 0).map((r) => STATUT_COULEURS[r.statut] || '#64748b')}
            />
          )}
        </ChartCard>
      </div>

      <Card className="print:break-inside-avoid">
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Comparaison avec la période précédente</CardTitle>
          {data && (
            <p className="text-xs text-muted-foreground">
              {fmtDate(data.periode.from)} → {fmtDate(data.periode.to)} comparé à {fmtDate(data.periode.prev_from)} → {fmtDate(data.periode.prev_to)}
            </p>
          )}
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <div className="p-4 space-y-2">
              {[0, 1, 2, 3].map((i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          ) : (
            data && (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-xs text-muted-foreground">
                    <tr className="border-b">
                      <th className="text-left px-4 py-2 font-medium">Indicateur</th>
                      <th className="text-right px-4 py-2 font-medium">Période actuelle</th>
                      <th className="text-right px-4 py-2 font-medium">Période précédente</th>
                      <th className="text-right px-4 py-2 font-medium">Écart</th>
                      <th className="text-right px-4 py-2 font-medium">Évolution</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(
                      [
                        ['Chiffre d’affaires', data.kpis.ca_total, fmtAr, false, BadgeDollarSign],
                        ['Marge brute (produits)', data.kpis.marge_brute, fmtAr, false, TrendingUp],
                        ['Dépenses', data.kpis.depenses, fmtAr, true, Wallet],
                        ['Bénéfice net', data.kpis.benefice_net, fmtAr, false, TrendingUp],
                        ['Commandes', data.kpis.nb_commandes, fmtNb, false, ShoppingCart],
                        ['Commandes livrées', data.kpis.nb_livrees, fmtNb, false, Truck],
                        ['Panier moyen', data.kpis.panier_moyen, fmtAr, false, Package],
                      ] as const
                    ).map(([label, v, f, inverse, Icon]) => (
                      <tr key={label} className="border-b last:border-0">
                        <td className="px-4 py-2 flex items-center gap-2">
                          <Icon className="h-3.5 w-3.5 text-muted-foreground" />
                          {label}
                        </td>
                        <td className="px-4 py-2 text-right tabular-nums font-medium">{f(v.actuel)}</td>
                        <td className="px-4 py-2 text-right tabular-nums text-muted-foreground">{f(v.precedent)}</td>
                        <td className="px-4 py-2 text-right tabular-nums">{v.variation > 0 ? '+' : ''}{f(v.variation)}</td>
                        <td className="px-4 py-2 text-right">
                          <VariationBadge pct={v.variation_pct} inverse={inverse} />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )
          )}
        </CardContent>
      </Card>
    </div>
  );
}
