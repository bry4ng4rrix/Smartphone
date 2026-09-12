'use client';

import { useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { AlertTriangle, Boxes, Clock, Layers, PackageX, Wallet } from 'lucide-react';
import { fmtAr, fmtDate, fmtDateHeure, fmtNb, type LigneStock, type StockData } from '@/lib/reports';
import { KpiCard, KpiGrid } from './kpi-card';
import { BarresChart, ChartCard, SerieChart } from './report-chart';
import { ReportTable, type Colonne } from './report-table';
import { useReport, type ReportParams } from './use-report';

const DORMANT_CHOIX = [30, 60, 90];

const COLONNES_ETAT: Colonne<LigneStock>[] = [
  { key: 'produit', label: 'Produit' },
  { key: 'variante', label: 'Variante', render: (r) => r.variante || <span className="text-muted-foreground">—</span> },
  { key: 'stock', label: 'Stock', align: 'right', render: (r) => <span className={r.stock <= 0 ? 'text-red-600 font-medium' : ''}>{fmtNb(r.stock)}</span> },
  { key: 'seuil', label: "Seuil d'alerte", align: 'right' },
  { key: 'prix_achat', label: "Prix d'achat", align: 'right', render: (r) => fmtAr(r.prix_achat) },
];

export function SectionStock({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const [dormantJours, setDormantJours] = useState(30);
  const [dormantCustom, setDormantCustom] = useState('');
  const jours = dormantCustom ? Math.max(1, Number(dormantCustom) || 30) : dormantJours;
  const { data, loading, error } = useReport<StockData>('stock', { ...params, dormant_days: jours }, enabled);
  const e = data?.etat;

  return (
    <div className="space-y-4">
      <p className="text-xs text-muted-foreground">
        L&apos;état du stock est celui d&apos;aujourd&apos;hui ; l&apos;historique des mouvements suit la période sélectionnée.
      </p>
      <KpiGrid cols={5}>
        <KpiCard loading={loading} titre="Quantité en stock" icon={Boxes} valeur={e && fmtNb(e.quantite_totale)} detail={e && `${fmtNb(e.nb_variantes)} variantes · ${fmtNb(e.nb_references)} références`} />
        <KpiCard loading={loading} titre="Valeur du stock (achat)" icon={Wallet} valeur={e && fmtAr(e.valeur_achat)} detail={e && `valeur de vente ${fmtAr(e.valeur_vente)}`} />
        <KpiCard loading={loading} titre="Produits en rupture" icon={PackageX} valeur={e && fmtNb(e.nb_ruptures)} couleur={e && e.nb_ruptures > 0 ? 'text-red-600 dark:text-red-400' : undefined} detail="stock à 0" />
        <KpiCard loading={loading} titre="À réapprovisionner" icon={AlertTriangle} valeur={e && fmtNb(e.nb_reappro)} couleur={e && e.nb_reappro > 0 ? 'text-amber-600 dark:text-amber-400' : undefined} detail={e && `stock ≤ seuil (dont ${fmtNb(e.nb_stock_bas)} en stock bas)`} />
        <KpiCard loading={loading} titre={`Stock dormant (${jours} j)`} icon={Clock} valeur={data && fmtNb(data.dormant.nb)} detail={data && `${fmtAr(data.dormant.valeur_immobilisee)} immobilisés`} />
      </KpiGrid>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2">
          <ChartCard titre="Entrées et sorties de stock" description="Quantités par période" loading={loading} error={error} vide={!data?.serie.length}>
            {data && (
              <SerieChart
                data={data.serie}
                series={[
                  { key: 'entrees', label: 'Entrées', type: 'bar', unite: 'nb', color: '#16a34a' },
                  { key: 'sorties', label: 'Sorties', type: 'bar', unite: 'nb', color: '#ef4444' },
                ]}
              />
            )}
          </ChartCard>
        </div>
        <ChartCard titre="Valeur du stock par catégorie" loading={loading} error={error} vide={!data?.par_categorie.length}>
          {data && <BarresChart data={data.par_categorie.slice(0, 10)} labelKey="label" valueKey="valeur_achat" />}
        </ChartCard>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <ReportTable titre="Ruptures de stock" description="Variantes à 0." colonnes={COLONNES_ETAT} lignes={data?.ruptures} loading={loading} error={error} pageSize={10} exportNom="ruptures" rowKey={(r) => r.variant_id} vide="Aucune rupture." />
        <ReportTable titre="À réapprovisionner" description="Stock ≤ seuil d'alerte (ruptures comprises)." colonnes={COLONNES_ETAT} lignes={data?.reappro} loading={loading} error={error} pageSize={10} exportNom="reapprovisionnement" rowKey={(r) => r.variant_id} vide="Rien à réapprovisionner." />
      </div>

      <ReportTable
        titre={`Stock dormant — sans vente depuis ${jours} jours`}
        description="Variantes en stock sans sortie pour une commande depuis la durée choisie. Valeur immobilisée = stock × prix d'achat."
        actions={
          <div className="flex items-center gap-1">
            <Select value={dormantCustom ? 'custom' : String(dormantJours)} onValueChange={(v) => { if (v === 'custom') setDormantCustom('45'); else { setDormantCustom(''); setDormantJours(Number(v)); } }}>
              <SelectTrigger className="h-8 w-32 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {DORMANT_CHOIX.map((j) => (
                  <SelectItem key={j} value={String(j)}>
                    {j} jours
                  </SelectItem>
                ))}
                <SelectItem value="custom">Personnalisé</SelectItem>
              </SelectContent>
            </Select>
            {dormantCustom !== '' && (
              <Input type="number" min={1} value={dormantCustom} onChange={(ev) => setDormantCustom(ev.target.value)} className="h-8 w-20 text-xs" aria-label="Nombre de jours" />
            )}
          </div>
        }
        colonnes={[
          { key: 'produit', label: 'Produit' },
          { key: 'variante', label: 'Variante', render: (r) => r.variante || '—' },
          { key: 'stock', label: 'Stock restant', align: 'right' },
          { key: 'derniere_vente', label: 'Dernière vente', render: (r) => (r.derniere_vente ? fmtDate(r.derniere_vente) : <Badge variant="outline">Jamais</Badge>), export: (r) => r.derniere_vente || 'Jamais' },
          { key: 'jours_sans_vente', label: 'Jours sans vente', align: 'right' },
          { key: 'valeur_immobilisee', label: 'Valeur immobilisée', align: 'right', render: (r) => fmtAr(r.valeur_immobilisee) },
        ]}
        lignes={data?.dormant.lignes}
        loading={loading}
        error={error}
        pageSize={15}
        exportNom="stock_dormant"
        rowKey={(r) => r.variant_id}
        vide="Aucun produit dormant sur cette durée."
      />

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <ReportTable
          titre="Mouvements par origine"
          colonnes={[
            { key: 'label', label: 'Origine' },
            { key: 'nb', label: 'Nb', align: 'right' },
            { key: 'entrees', label: 'Entrées', align: 'right' },
            { key: 'sorties', label: 'Sorties', align: 'right' },
          ]}
          lignes={data?.mouvements_resume}
          loading={loading}
          error={error}
          pageSize={10}
          rowKey={(r) => r.origine}
        />
        <div className="xl:col-span-2">
          <ReportTable
            titre="Historique des mouvements"
            description={data && `${fmtNb(data.nb_mouvements)} mouvements sur la période (300 plus récents affichés).`}
            colonnes={[
              { key: 'date', label: 'Date', render: (r) => fmtDateHeure(r.date) },
              { key: 'produit', label: 'Produit', render: (r) => `${r.produit}${r.variante ? ` (${r.variante})` : ''}` },
              { key: 'type', label: 'Type', render: (r) => <Badge variant={r.type === 'ENTREE' ? 'default' : 'destructive'}>{r.type === 'ENTREE' ? 'Entrée' : 'Sortie'}</Badge> },
              { key: 'quantite', label: 'Qté', align: 'right' },
              { key: 'origine_label', label: 'Origine' },
              { key: 'reference', label: 'Réf.', render: (r) => r.reference || r.note || '' },
              { key: 'utilisateur', label: 'Par' },
            ]}
            lignes={data?.mouvements}
            loading={loading}
            error={error}
            pageSize={15}
            exportNom="mouvements_stock"
            rowKey={(r) => r.id}
            compact
            vide="Aucun mouvement sur la période."
          />
        </div>
      </div>
      <Button variant="link" size="sm" className="px-0 text-xs" asChild>
        <a href="/movements">Voir tous les mouvements →</a>
      </Button>
    </div>
  );
}
