'use client';

import { useState } from 'react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { BadgeDollarSign, Boxes, Package, ShoppingBag } from 'lucide-react';
import { fmtAr, fmtNb, fmtPct, type LigneVente, type SalesData } from '@/lib/reports';
import { KpiCard, KpiGrid } from './kpi-card';
import { BarresChart, ChartCard, SerieChart } from './report-chart';
import { ReportTable, type Colonne } from './report-table';
import { useReport, type ReportParams } from './use-report';

export const COLONNES_VENTE: Colonne<LigneVente>[] = [
  { key: 'label', label: 'Libellé' },
  { key: 'quantite', label: 'Qté vendue', align: 'right', render: (r) => fmtNb(r.quantite) },
  { key: 'nb_commandes', label: 'Commandes', align: 'right', render: (r) => fmtNb(r.nb_commandes) },
  { key: 'ca', label: 'CA', align: 'right', render: (r) => fmtAr(r.ca) },
  { key: 'marge', label: 'Marge', align: 'right', render: (r) => fmtAr(r.marge) },
  { key: 'marge_pct', label: 'Marge %', align: 'right', render: (r) => fmtPct(r.marge_pct) },
];

export function SectionSales({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const { data, loading, error } = useReport<SalesData>('sales', params, enabled);
  const [dimension, setDimension] = useState('produit');
  const k = data?.kpis;
  const lignes = data?.par[dimension] ?? [];
  const dimLabel = data?.dimensions.find((d) => d.cle === dimension)?.label ?? 'Produit';

  return (
    <div className="space-y-4">
      <KpiGrid cols={4}>
        <KpiCard loading={loading} titre="Chiffre d'affaires" icon={BadgeDollarSign} valeur={k && fmtAr(k.ca_total.actuel)} variation={k?.ca_total} format={fmtAr} detail={k && `dont produits ${fmtAr(k.ca_produits.actuel)}`} />
        <KpiCard loading={loading} titre="Ventes (commandes livrées)" icon={ShoppingBag} valeur={k && fmtNb(k.nb_livrees.actuel)} variation={k?.nb_livrees} format={fmtNb} />
        <KpiCard loading={loading} titre="Quantité vendue" icon={Boxes} valeur={k && fmtNb(k.quantite_vendue.actuel)} variation={k?.quantite_vendue} format={fmtNb} detail="articles livrés, hors retours" />
        <KpiCard loading={loading} titre="Panier moyen" icon={Package} valeur={k && fmtAr(k.panier_moyen.actuel)} variation={k?.panier_moyen} format={fmtAr} />
      </KpiGrid>

      <ChartCard titre="Évolution des ventes" loading={loading} error={error} vide={!data?.serie.length}>
        {data && (
          <SerieChart
            data={data.serie}
            series={[
              { key: 'ca', label: 'CA produits', type: 'bar', color: '#2563eb' },
              { key: 'ventes', label: 'Commandes livrées', type: 'line', unite: 'nb', color: '#16a34a' },
            ]}
          />
        )}
      </ChartCard>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ReportTable
            titre={`Ventes par ${dimLabel.toLowerCase()}`}
            description="Commandes livrées de la période, articles rapportés exclus. Marge = CA − coût d'achat actuel du catalogue."
            colonnes={COLONNES_VENTE}
            lignes={lignes}
            loading={loading}
            error={error}
            exportNom={`ventes_par_${dimension}`}
            rowKey={(r) => r.label}
            actions={
              <Select value={dimension} onValueChange={setDimension}>
                <SelectTrigger className="h-8 w-40 text-xs">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(data?.dimensions ?? [{ cle: 'produit', label: 'Produit' }]).map((d) => (
                    <SelectItem key={d.cle} value={d.cle}>
                      {d.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            }
          />
        </div>
        <ChartCard titre={`Top 10 par ${dimLabel.toLowerCase()} (CA)`} loading={loading} error={error} vide={!lignes.length} hauteur={360}>
          <BarresChart data={[...lignes].sort((a, b) => b.ca - a.ca).slice(0, 10)} labelKey="label" valueKey="ca" hauteur={360} />
        </ChartCard>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <ReportTable titre="Produits les plus vendus" colonnes={COLONNES_VENTE} lignes={data?.top_produits} loading={loading} error={error} pageSize={10} exportNom="top_produits" rowKey={(r) => r.label} />
        <ReportTable titre="Produits les moins vendus" description="Parmi les produits vendus au moins une fois sur la période." colonnes={COLONNES_VENTE} lignes={data?.moins_vendus} loading={loading} error={error} pageSize={10} exportNom="produits_moins_vendus" rowKey={(r) => r.label} />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ReportTable
            titre="Ventes par livreur"
            description="CA = total encaissé des commandes livrées (articles + frais)."
            colonnes={[
              { key: 'nom', label: 'Livreur' },
              { key: 'commandes', label: 'Commandes', align: 'right' },
              { key: 'livrees', label: 'Livrées', align: 'right' },
              { key: 'retours', label: 'Retours', align: 'right' },
              { key: 'en_cours', label: 'En cours', align: 'right' },
              { key: 'ca', label: 'CA', align: 'right', render: (r) => fmtAr(r.ca) },
              { key: 'taux_reussite', label: 'Taux réussite', align: 'right', render: (r) => fmtPct(r.taux_reussite) },
            ]}
            lignes={data?.par_livreur}
            loading={loading}
            error={error}
            exportNom="ventes_par_livreur"
            rowKey={(r) => r.id}
            vide="Aucune commande assignée à un livreur sur la période."
          />
        </div>
        <ChartCard titre="CA par livreur" loading={loading} error={error} vide={!data?.par_livreur.length} hauteur={300}>
          {data && <BarresChart data={data.par_livreur.slice(0, 10)} labelKey="nom" valueKey="ca" hauteur={300} color="#16a34a" />}
        </ChartCard>
      </div>
    </div>
  );
}
