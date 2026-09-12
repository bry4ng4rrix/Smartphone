'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { BadgeDollarSign, Percent, TrendingDown, TrendingUp, Wallet } from 'lucide-react';
import { fmtAr, fmtDate, fmtPct, type FinancialData, type LigneVente } from '@/lib/reports';
import { KpiCard, KpiGrid, VariationBadge } from './kpi-card';
import { ChartCard, SerieChart } from './report-chart';
import { ReportTable, type Colonne } from './report-table';
import { useReport, type ReportParams } from './use-report';

const COLONNES: Colonne<LigneVente>[] = [
  { key: 'label', label: 'Libellé' },
  { key: 'quantite', label: 'Qté', align: 'right' },
  { key: 'ca', label: 'CA', align: 'right', render: (r) => fmtAr(r.ca) },
  { key: 'cout', label: "Coût d'achat", align: 'right', render: (r) => fmtAr(r.cout) },
  { key: 'marge', label: 'Marge', align: 'right', render: (r) => <span className={r.marge < 0 ? 'text-red-600' : ''}>{fmtAr(r.marge)}</span> },
  { key: 'marge_pct', label: 'Marge %', align: 'right', render: (r) => fmtPct(r.marge_pct) },
];

export function SectionFinancial({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const { data, loading, error } = useReport<FinancialData>('financial', params, enabled);
  const t = data?.totaux;
  const c = data?.comparaison;

  return (
    <div className="space-y-4">
      <KpiGrid cols={5}>
        <KpiCard loading={loading} titre="CA brut" icon={BadgeDollarSign} valeur={t && fmtAr(t.ca_total)} variation={c?.ca_total} format={fmtAr} detail={t && `produits ${fmtAr(t.ca_produits)} + livraison ${fmtAr(t.frais_livraison)}`} />
        <KpiCard loading={loading} titre="Coût d'achat des ventes" icon={TrendingDown} valeur={t && fmtAr(t.cout_achat)} variation={c?.cout_achat} inverse format={fmtAr} detail="prix d'achat actuel × quantités" />
        <KpiCard loading={loading} titre="Marge brute" icon={Percent} valeur={t && fmtAr(t.marge_brute)} variation={c?.marge_brute} format={fmtAr} detail={t && `${fmtPct(t.taux_marge_brute)} du CA produits`} />
        <KpiCard loading={loading} titre="Dépenses (charges)" icon={Wallet} valeur={t && fmtAr(t.depenses)} variation={c?.depenses} inverse format={fmtAr} detail={t && `caisse ${fmtAr(t.depenses_caisse)} · tournées ${fmtAr(t.depenses_livreur)}${t.achats_stock ? ` · achats de stock exclus : ${fmtAr(t.achats_stock)}` : ''}`} />
        <KpiCard
          loading={loading}
          titre="Bénéfice net"
          icon={TrendingUp}
          valeur={t && fmtAr(t.benefice_net)}
          couleur={t && t.benefice_net < 0 ? 'text-red-600 dark:text-red-400' : 'text-emerald-600 dark:text-emerald-400'}
          variation={c?.benefice_net}
          format={fmtAr}
          detail={t && `${fmtPct(t.taux_benefice)} du CA`}
        />
      </KpiGrid>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ChartCard titre="Rentabilité dans le temps" description="CA, coût d'achat, dépenses et bénéfice net par période" loading={loading} error={error} vide={!data?.series.length} hauteur={320}>
            {data && (
              <SerieChart
                data={data.series}
                hauteur={320}
                series={[
                  { key: 'ventes', label: 'CA', type: 'bar', color: '#2563eb' },
                  { key: 'cout_achat', label: "Coût d'achat", type: 'bar', color: '#f59e0b' },
                  { key: 'depenses', label: 'Dépenses', type: 'bar', color: '#ef4444' },
                  { key: 'benefices', label: 'Bénéfice net', type: 'line', color: '#16a34a' },
                ]}
              />
            )}
          </ChartCard>
        </div>
        <Card className="print:break-inside-avoid">
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Période actuelle vs précédente</CardTitle>
            {data && (
              <p className="text-xs text-muted-foreground">
                {fmtDate(data.periode.from)} → {fmtDate(data.periode.to)} vs {fmtDate(data.periode.prev_from)} → {fmtDate(data.periode.prev_to)}
              </p>
            )}
          </CardHeader>
          <CardContent className="p-0">
            {loading ? (
              <div className="p-4 space-y-2">
                {[0, 1, 2, 3, 4].map((i) => (
                  <Skeleton key={i} className="h-7 w-full" />
                ))}
              </div>
            ) : (
              c && (
                <table className="w-full text-sm">
                  <tbody>
                    {(
                      [
                        ['CA brut', c.ca_total, false],
                        ["Coût d'achat", c.cout_achat, true],
                        ['Marge brute', c.marge_brute, false],
                        ['Dépenses', c.depenses, true],
                        ['Bénéfice net', c.benefice_net, false],
                      ] as const
                    ).map(([label, v, inverse]) => (
                      <tr key={label} className="border-b last:border-0 align-top">
                        <td className="px-4 py-2">
                          <span className="font-medium">{label}</span>
                          <span className="block text-xs text-muted-foreground">préc. {fmtAr(v.precedent)}</span>
                        </td>
                        <td className="px-4 py-2 text-right tabular-nums">
                          <span className="font-medium">{fmtAr(v.actuel)}</span>
                          <span className="block text-xs text-muted-foreground">
                            {v.variation > 0 ? '+' : ''}
                            {fmtAr(v.variation)}
                          </span>
                        </td>
                        <td className="px-4 py-2 text-right">
                          <VariationBadge pct={v.variation_pct} inverse={inverse} />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )
            )}
          </CardContent>
        </Card>
      </div>

      <p className="text-xs text-muted-foreground">
        Bénéfice net = CA (produits + frais de livraison encaissés) − coût d&apos;achat des articles vendus − sorties de caisse − frais de tournée
        des livreurs acceptés. Les sorties de caisse « Commande stock » ne sont pas des charges : la marchandise achetée est comptée au moment de
        la vente, dans le coût d&apos;achat — les compter deux fois ferait de chaque réassort une perte. Le coût d&apos;achat utilise le prix
        d&apos;achat actuel de chaque référence (non historisé par commande).
      </p>

      <ReportTable titre="Rentabilité par produit" colonnes={COLONNES} lignes={data?.par_produit} loading={loading} error={error} exportNom="rentabilite_produits" rowKey={(r) => r.label} />
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <ReportTable titre="Rentabilité par catégorie" colonnes={COLONNES} lignes={data?.par_categorie} loading={loading} error={error} exportNom="rentabilite_categories" rowKey={(r) => r.label} pageSize={10} />
        <ReportTable titre="Rentabilité par sous-type" colonnes={COLONNES} lignes={data?.par_sous_type} loading={loading} error={error} exportNom="rentabilite_sous_types" rowKey={(r) => r.label} pageSize={10} />
      </div>
    </div>
  );
}
