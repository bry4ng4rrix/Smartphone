'use client';

import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Landmark, Receipt, Truck, Wallet } from 'lucide-react';
import { fmtAr, fmtDateHeure, fmtNb, type ExpensesData } from '@/lib/reports';
import { KpiCard, KpiGrid } from './kpi-card';
import { CamembertChart, ChartCard, SerieChart } from './report-chart';
import { ReportTable } from './report-table';
import { useReport, type ReportParams } from './use-report';

export function SectionExpenses({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const { data, loading, error } = useReport<ExpensesData>('expenses', params, enabled);
  const t = data?.totaux;
  const l = data?.livraison;

  return (
    <div className="space-y-4">
      <KpiGrid cols={4}>
        <KpiCard loading={loading} titre="Total des dépenses" icon={Wallet} valeur={t && fmtAr(t.total.actuel)} variation={t?.total} inverse format={fmtAr} detail={t && `${fmtNb(t.nb_mouvements)} opérations`} />
        <KpiCard loading={loading} titre="Sorties de caisse" icon={Landmark} valeur={t && fmtAr(t.caisse.actuel)} variation={t?.caisse} inverse format={fmtAr} detail="salaires, pub, achats de stock, autres" />
        <KpiCard loading={loading} titre="Frais de tournée (livreurs)" icon={Truck} valeur={t && fmtAr(t.livreur.actuel)} variation={t?.livreur} inverse format={fmtAr} detail="dépenses acceptées par le gérant" />
        <KpiCard
          loading={loading}
          titre="Marge sur livraison"
          icon={Receipt}
          valeur={l && fmtAr(l.marge_livraison)}
          couleur={l && l.marge_livraison < 0 ? 'text-red-600 dark:text-red-400' : 'text-emerald-600 dark:text-emerald-400'}
          detail={l && `facturé ${fmtAr(l.frais_factures_client)} − coût réel ${fmtAr(l.cout_reel_livreurs)}`}
        />
      </KpiGrid>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ChartCard titre="Évolution des dépenses" loading={loading} error={error} vide={!data?.serie.length}>
            {data && (
              <SerieChart
                data={data.serie}
                series={[
                  { key: 'caisse', label: 'Caisse', type: 'bar', color: '#ef4444', stackId: 'd' },
                  { key: 'livreur', label: 'Tournées livreurs', type: 'bar', color: '#f59e0b', stackId: 'd' },
                ]}
              />
            )}
          </ChartCard>
        </div>
        <ChartCard titre="Dépenses par catégorie" loading={loading} error={error} vide={!data?.par_categorie.length}>
          {data && <CamembertChart data={data.par_categorie} labelKey="label" valueKey="total" unite="ar" />}
        </ChartCard>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <ReportTable
          titre="Dépenses par catégorie"
          description="Catégories de caisse (Paramètres › Dépenses) et types de dépense des livreurs."
          colonnes={[
            { key: 'label', label: 'Catégorie' },
            { key: 'source', label: 'Source', render: (r) => <Badge variant="outline">{r.source === 'caisse' ? 'Caisse' : 'Livreur'}</Badge>, export: (r) => (r.source === 'caisse' ? 'Caisse' : 'Livreur') },
            { key: 'nb', label: 'Opérations', align: 'right' },
            { key: 'total', label: 'Total', align: 'right', render: (r) => fmtAr(r.total) },
            { key: 'part', label: 'Part', align: 'right', render: (r) => (t && t.total.actuel ? `${((100 * r.total) / t.total.actuel).toFixed(1)} %` : '—'), export: (r) => (t && t.total.actuel ? Number(((100 * r.total) / t.total.actuel).toFixed(1)) : null) },
          ]}
          lignes={data?.par_categorie}
          loading={loading}
          error={error}
          exportNom="depenses_par_categorie"
          rowKey={(r) => `${r.source}-${r.label}`}
        />

        <Card className="print:break-inside-avoid">
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Livraison : facturé au client vs coût réel</CardTitle>
            <CardDescription className="text-xs">
              Frais facturés = frais de livraison des commandes livrées. Coût réel = frais de tournée déclarés par les livreurs et acceptés
              (carburant, repas…). L&apos;application n&apos;a pas d&apos;agence externe : la livraison est assurée par les livreurs de l&apos;équipe.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {loading || !l ? (
              <div className="space-y-2">
                {[0, 1, 2, 3].map((i) => (
                  <Skeleton key={i} className="h-7 w-full" />
                ))}
              </div>
            ) : (
              <table className="w-full text-sm">
                <tbody>
                  {(
                    [
                      ['Commandes livrées', fmtNb(l.nb_livrees)],
                      ['Frais de livraison facturés au client', fmtAr(l.frais_factures_client)],
                      ['Frais réellement payés (tournées acceptées)', fmtAr(l.cout_reel_livreurs)],
                      ['Marge livraison', fmtAr(l.marge_livraison)],
                      ['Frais moyen facturé par livraison', fmtAr(l.frais_moyen_client)],
                      ['Coût moyen réel par livraison', fmtAr(l.cout_moyen_livraison)],
                    ] as const
                  ).map(([label, val], i) => (
                    <tr key={label} className={`border-b last:border-0 ${i === 3 ? 'font-semibold' : ''}`}>
                      <td className="py-2 pr-2">{label}</td>
                      <td className={`py-2 text-right tabular-nums ${i === 3 ? (l.marge_livraison < 0 ? 'text-red-600' : 'text-emerald-600') : ''}`}>{val}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>
      </div>

      <ReportTable
        titre="Détail des dépenses"
        description="Les 300 opérations les plus récentes de la période."
        colonnes={[
          { key: 'date', label: 'Date', render: (r) => (r.source === 'caisse' ? fmtDateHeure(r.date) : fmtDateHeure(`${r.date}T12:00:00+03:00`).slice(0, 10)), export: (r) => r.date },
          { key: 'source', label: 'Source', render: (r) => <Badge variant="outline">{r.source === 'caisse' ? 'Caisse' : 'Livreur'}</Badge>, export: (r) => (r.source === 'caisse' ? 'Caisse' : 'Livreur') },
          { key: 'categorie', label: 'Catégorie' },
          { key: 'libelle', label: 'Libellé' },
          { key: 'auteur', label: 'Par' },
          { key: 'montant', label: 'Montant', align: 'right', render: (r) => fmtAr(r.montant) },
        ]}
        lignes={data?.mouvements}
        loading={loading}
        error={error}
        pageSize={20}
        exportNom="detail_depenses"
        compact
      />
    </div>
  );
}
