'use client';

import { Badge } from '@/components/ui/badge';
import { Ban, CheckCircle2, ClipboardList, RotateCcw, Truck } from 'lucide-react';
import { fmtAr, fmtNb, fmtPct, STATUT_COULEURS, type OrdersData } from '@/lib/reports';
import { KpiCard, KpiGrid } from './kpi-card';
import { CamembertChart, ChartCard, SerieChart } from './report-chart';
import { ReportTable } from './report-table';
import { useReport, type ReportParams } from './use-report';

export function SectionOrders({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const { data, loading, error } = useReport<OrdersData>('orders', params, enabled);
  const k = data?.kpis;
  const c = data?.comparaison;

  return (
    <div className="space-y-4">
      <KpiGrid cols={5}>
        <KpiCard loading={loading} titre="Commandes" icon={ClipboardList} valeur={k && fmtNb(k.total)} variation={c?.total} format={fmtNb} detail={k && `${fmtNb(k.nouvelles)} nouvelles · ${fmtNb(k.en_cours)} en préparation/prêtes`} />
        <KpiCard loading={loading} titre="En livraison" icon={Truck} valeur={k && fmtNb(k.en_livraison)} />
        <KpiCard loading={loading} titre="Livrées" icon={CheckCircle2} valeur={k && fmtNb(k.livrees)} variation={c?.livrees} format={fmtNb} detail={k && `taux de livraison ${fmtPct(k.taux_livraison)}`} />
        <KpiCard loading={loading} titre="Annulées" icon={Ban} valeur={k && fmtNb(k.annulees)} variation={c?.annulees} inverse format={fmtNb} couleur={k && k.annulees > 0 ? 'text-red-600 dark:text-red-400' : undefined} detail={k && `taux d'annulation ${fmtPct(k.taux_annulation)} · ${fmtAr(data!.montant_annule)}`} />
        <KpiCard loading={loading} titre="Retournées" icon={RotateCcw} valeur={k && fmtNb(k.retournees)} variation={c?.retournees} inverse format={fmtNb} detail={k && `taux de retour ${fmtPct(k.taux_retour)} · ${fmtAr(data!.montant_retourne)}`} />
      </KpiGrid>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ChartCard titre="Commandes dans le temps" loading={loading} error={error} vide={!data?.serie.length}>
            {data && (
              <SerieChart
                data={data.serie}
                series={[
                  { key: 'total', label: 'Toutes', type: 'bar', unite: 'nb', color: '#94a3b8' },
                  { key: 'livrees', label: 'Livrées', type: 'line', unite: 'nb', color: '#16a34a' },
                  { key: 'annulees', label: 'Annulées', type: 'line', unite: 'nb', color: '#ef4444' },
                  { key: 'retours', label: 'Retours', type: 'line', unite: 'nb', color: '#f97316' },
                ]}
              />
            )}
          </ChartCard>
        </div>
        <ChartCard titre="Répartition par statut" loading={loading} error={error} vide={!data?.repartition.some((r) => r.nb > 0)}>
          {data && <CamembertChart data={data.repartition} labelKey="label" valueKey="nb" colors={data.repartition.filter((r) => r.nb > 0).map((r) => STATUT_COULEURS[r.statut] || '#64748b')} />}
        </ChartCard>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <ReportTable
          titre="Détail par statut"
          colonnes={[
            { key: 'label', label: 'Statut', render: (r) => <span className="flex items-center gap-2"><span className="h-2.5 w-2.5 rounded-full" style={{ background: STATUT_COULEURS[r.statut] }} />{r.label}</span> },
            { key: 'nb', label: 'Nb', align: 'right' },
            { key: 'part', label: 'Part', align: 'right', render: (r) => fmtPct(r.part) },
          ]}
          lignes={data?.repartition}
          loading={loading}
          error={error}
          pageSize={10}
          rowKey={(r) => r.statut}
          exportNom="commandes_par_statut"
        />
        <ReportTable
          titre="Par zone de livraison"
          colonnes={[
            { key: 'zone', label: 'Zone', render: (r) => (r.zone === 'RECUPERATION' ? <Badge variant="outline">Récupération</Badge> : r.zone) },
            { key: 'nb', label: 'Commandes', align: 'right' },
            { key: 'livrees', label: 'Livrées', align: 'right' },
            { key: 'ca', label: 'CA livré', align: 'right', render: (r) => fmtAr(r.ca) },
          ]}
          lignes={data?.par_zone}
          loading={loading}
          error={error}
          pageSize={10}
          rowKey={(r) => r.zone}
          exportNom="commandes_par_zone"
        />
        <ReportTable
          titre="Par mode de paiement"
          colonnes={[
            { key: 'label', label: 'Mode' },
            { key: 'nb', label: 'Commandes', align: 'right' },
            { key: 'ca', label: 'CA livré', align: 'right', render: (r) => fmtAr(r.ca) },
          ]}
          lignes={data?.par_paiement}
          loading={loading}
          error={error}
          pageSize={10}
          rowKey={(r) => r.mode}
          exportNom="commandes_par_paiement"
        />
      </div>
    </div>
  );
}
