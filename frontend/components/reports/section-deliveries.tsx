'use client';

import { Badge } from '@/components/ui/badge';
import { CheckCircle2, Clock, Truck, Wallet, XCircle } from 'lucide-react';
import { fmtAr, fmtDuree, fmtNb, fmtPct, type DeliveriesData, type LigneLivreur } from '@/lib/reports';
import { KpiCard, KpiGrid } from './kpi-card';
import { BarresChart, ChartCard, SerieChart } from './report-chart';
import { ReportTable, type Colonne } from './report-table';
import { useReport, type ReportParams } from './use-report';

const COLONNES: Colonne<LigneLivreur>[] = [
  { key: 'nom', label: 'Livreur' },
  { key: 'livraisons', label: 'Livraisons', align: 'right' },
  { key: 'reussies', label: 'Réussies', align: 'right', render: (r) => <span className="text-emerald-600">{fmtNb(r.reussies)}</span> },
  { key: 'echouees', label: 'Échouées', align: 'right', render: (r) => <span className={r.echouees ? 'text-red-600' : ''}>{fmtNb(r.echouees)}</span> },
  { key: 'en_cours', label: 'En cours', align: 'right' },
  { key: 'cout_total', label: 'Coût total payé', align: 'right', render: (r) => fmtAr(r.cout_total) },
  { key: 'cout_moyen', label: 'Coût moyen', align: 'right', render: (r) => fmtAr(r.cout_moyen) },
  { key: 'frais_factures', label: 'Frais facturés', align: 'right', render: (r) => fmtAr(r.frais_factures) },
  { key: 'marge_livraison', label: 'Marge livraison', align: 'right', render: (r) => <span className={r.marge_livraison < 0 ? 'text-red-600' : ''}>{fmtAr(r.marge_livraison)}</span> },
  { key: 'taux_reussite', label: 'Taux réussite', align: 'right', render: (r) => fmtPct(r.taux_reussite) },
  { key: 'taux_echec', label: 'Taux échec', align: 'right', render: (r) => fmtPct(r.taux_echec) },
  { key: 'delai_moyen_minutes', label: 'Délai moyen', align: 'right', render: (r) => fmtDuree(r.delai_moyen_minutes), export: (r) => r.delai_moyen_minutes },
];

export function SectionDeliveries({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const { data, loading, error } = useReport<DeliveriesData>('deliveries', params, enabled);
  const t = data?.totaux;

  return (
    <div className="space-y-4">
      <p className="text-xs text-muted-foreground">
        La livraison est assurée par les livreurs de l&apos;équipe (pas d&apos;agence externe) : chaque livreur est traité comme une agence. Livraison
        réussie = commande livrée, échouée = retour. Coût payé = frais de tournée acceptés. Délai = passage « En livraison » → « Livré ».
      </p>
      <KpiGrid cols={5}>
        <KpiCard loading={loading} titre="Livraisons terminées" icon={Truck} valeur={t && fmtNb(t.livraisons)} detail={t && `${fmtNb(t.en_cours)} en cours`} />
        <KpiCard loading={loading} titre="Taux de réussite" icon={CheckCircle2} valeur={t && fmtPct(t.taux_reussite)} couleur="text-emerald-600 dark:text-emerald-400" detail={t && `${fmtNb(t.reussies)} réussies`} />
        <KpiCard loading={loading} titre="Taux d'échec" icon={XCircle} valeur={t && fmtPct(t.taux_echec)} couleur={t && Number(t.echouees) > 0 ? 'text-red-600 dark:text-red-400' : undefined} detail={t && `${fmtNb(t.echouees)} retours`} />
        <KpiCard loading={loading} titre="Coût moyen / livraison" icon={Wallet} valeur={t && fmtAr(t.cout_moyen)} detail={t && `total ${fmtAr(t.cout_total)} · marge ${fmtAr(t.marge_livraison)}`} />
        <KpiCard loading={loading} titre="Délai moyen" icon={Clock} valeur={t && fmtDuree(t.delai_moyen_minutes)} detail={t && `sur ${fmtNb(t.nb_delais_mesures)} livraisons mesurées`} />
      </KpiGrid>

      <ReportTable
        titre="Comparatif des livreurs"
        colonnes={COLONNES}
        lignes={data?.par_livreur}
        loading={loading}
        error={error}
        exportNom="livraisons_par_livreur"
        rowKey={(r) => r.id}
        vide="Aucune livraison assignée sur la période."
      />

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ChartCard titre="Livraisons réussies et échouées" loading={loading} error={error} vide={!data?.serie.length}>
            {data && (
              <SerieChart
                data={data.serie}
                series={[
                  { key: 'reussies', label: 'Réussies', type: 'bar', unite: 'nb', color: '#16a34a', stackId: 'l' },
                  { key: 'echouees', label: 'Échouées', type: 'bar', unite: 'nb', color: '#ef4444', stackId: 'l' },
                ]}
              />
            )}
          </ChartCard>
        </div>
        <ChartCard titre="Taux de réussite par livreur" loading={loading} error={error} vide={!data?.par_livreur.length}>
          {data && <BarresChart data={data.par_livreur} labelKey="nom" valueKey="taux_reussite" unite="nb" color="#16a34a" />}
        </ChartCard>
      </div>

      <ReportTable
        titre="Par zone de livraison"
        colonnes={[
          { key: 'zone', label: 'Zone', render: (r) => (r.zone === 'RECUPERATION' ? <Badge variant="outline">Récupération</Badge> : r.zone) },
          { key: 'livraisons', label: 'Livraisons', align: 'right' },
          { key: 'reussies', label: 'Réussies', align: 'right' },
          { key: 'echouees', label: 'Échouées', align: 'right' },
          { key: 'frais', label: 'Frais encaissés', align: 'right', render: (r) => fmtAr(r.frais) },
          { key: 'taux_reussite', label: 'Taux réussite', align: 'right', render: (r) => fmtPct(r.taux_reussite) },
        ]}
        lignes={data?.par_zone}
        loading={loading}
        error={error}
        pageSize={10}
        exportNom="livraisons_par_zone"
        rowKey={(r) => r.zone}
      />
    </div>
  );
}
