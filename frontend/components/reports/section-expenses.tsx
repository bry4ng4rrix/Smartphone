'use client';

import { useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { FilterX, Landmark, Receipt, Truck, Wallet } from 'lucide-react';
import { appDayKey } from '@/lib/timezone';
import { fmtAr, fmtDateHeure, fmtNb, type ExpensesData } from '@/lib/reports';
import { KpiCard, KpiGrid } from './kpi-card';
import { CamembertChart, ChartCard, SerieChart } from './report-chart';
import { ReportTable } from './report-table';
import { useReport, type ReportParams } from './use-report';

const TOUS = 'TOUS';
const filtresVides = () => ({ date: '', source: TOUS, categorie: TOUS, auteur: TOUS, libelle: '' });

export function SectionExpenses({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const { data, loading, error } = useReport<ExpensesData>('expenses', params, enabled);
  const t = data?.totaux;
  const l = data?.livraison;

  // Filtres LOCAUX du « Détail des dépenses » (§ demande) : date (un jour,
  // heure de Madagascar), source, catégorie, utilisateur, libellé.
  const [f, setF] = useState(filtresVides);
  const actif = JSON.stringify(f) !== JSON.stringify(filtresVides());
  const mouvements = data?.mouvements ?? [];
  const categories = useMemo(() => [...new Set(mouvements.map((m) => m.categorie || 'Sans catégorie'))].sort((a, b) => a.localeCompare(b, 'fr')), [mouvements]);
  const auteurs = useMemo(() => [...new Set(mouvements.map((m) => m.auteur || '—'))].sort((a, b) => a.localeCompare(b, 'fr')), [mouvements]);
  const jourDe = (m: ExpensesData['mouvements'][number]) => (m.source === 'caisse' ? appDayKey(m.date) : m.date.slice(0, 10));
  const filtres = useMemo(() => {
    const q = f.libelle.trim().toLowerCase();
    return mouvements.filter((m) => {
      if (f.date && jourDe(m) !== f.date) return false;
      if (f.source !== TOUS && m.source !== f.source) return false;
      if (f.categorie !== TOUS && (m.categorie || 'Sans catégorie') !== f.categorie) return false;
      if (f.auteur !== TOUS && (m.auteur || '—') !== f.auteur) return false;
      if (q && !`${m.libelle} ${m.categorie}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [mouvements, f]);
  const totalFiltre = useMemo(() => filtres.reduce((a, m) => a + Number(m.montant || 0), 0), [filtres]);

  const barreFiltres = (
    <div className="print:hidden flex flex-wrap items-end gap-2 mt-3">
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Date</Label>
        <Input type="date" value={f.date} onChange={(e) => setF({ ...f, date: e.target.value })} className="h-9 w-[150px]" />
      </div>
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Source</Label>
        <Select value={f.source} onValueChange={(v) => setF({ ...f, source: v })}>
          <SelectTrigger className="h-9 w-[130px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={TOUS}>Toutes</SelectItem>
            <SelectItem value="caisse">Caisse</SelectItem>
            <SelectItem value="livreur">Livreur</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Catégorie</Label>
        <Select value={f.categorie} onValueChange={(v) => setF({ ...f, categorie: v })}>
          <SelectTrigger className="h-9 w-[180px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={TOUS}>Toutes les catégories</SelectItem>
            {categories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label className="text-xs text-muted-foreground">Utilisateur</Label>
        <Select value={f.auteur} onValueChange={(v) => setF({ ...f, auteur: v })}>
          <SelectTrigger className="h-9 w-[180px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={TOUS}>Tous les utilisateurs</SelectItem>
            {auteurs.map((a) => <SelectItem key={a} value={a}>{a}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1 min-w-[200px] flex-1">
        <Label className="text-xs text-muted-foreground">Libellé</Label>
        <Input value={f.libelle} onChange={(e) => setF({ ...f, libelle: e.target.value })} className="h-9" placeholder="Rechercher dans le libellé…" />
      </div>
      {actif && (
        <Button variant="ghost" size="sm" className="h-9" onClick={() => setF(filtresVides())}>
          <FilterX className="h-4 w-4 mr-1" aria-hidden /> Réinitialiser
        </Button>
      )}
      {data && (
        <p className="basis-full text-xs text-muted-foreground">
          {fmtNb(filtres.length)} opération(s){actif ? ` sur ${fmtNb(mouvements.length)}` : ''} · total <span className="font-medium text-foreground">{fmtAr(totalFiltre)}</span>
        </p>
      )}
    </div>
  );

  return (
    <div className="space-y-4">
      <KpiGrid cols={4}>
        <KpiCard loading={loading} titre="Total des sorties" icon={Wallet} valeur={t && fmtAr(t.total.actuel)} variation={t?.total} inverse format={fmtAr} detail={t && `${fmtNb(t.nb_mouvements)} opérations · charges ${fmtAr(t.charges.actuel)}`} />
        <KpiCard loading={loading} titre="Sorties de caisse" icon={Landmark} valeur={t && fmtAr(t.caisse.actuel)} variation={t?.caisse} inverse format={fmtAr} detail={t && (t.achats_stock.actuel ? `dont achats de stock ${fmtAr(t.achats_stock.actuel)} (hors bénéfice)` : 'salaires, pub, autres')} />
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
          description="Catégories de caisse (Paramètres › Dépenses) et types de dépense des livreurs. Les achats de stock sont listés mais n'entrent pas dans le bénéfice : la marchandise est comptée à la vente, dans le coût d'achat."
          colonnes={[
            { key: 'label', label: 'Catégorie', render: (r) => <span>{r.label}{r.hors_resultat && <Badge variant="secondary" className="ml-2 text-[10px]">Achat de stock · hors bénéfice</Badge>}</span> },
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
              Frais facturés = frais de livraison des commandes livrées. Coût réel = dépenses déclarées par les livreurs, acceptées par le gérant,
              des seuls types marqués « frais de livraison » dans Paramètres (LIVRAISON 3K / 4K / 5K…) — repas, enveloppes, NAP n&apos;y entrent pas.
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
                      ['Frais de livraison acceptés (LIVRAISON 3K / 4K / 5K…)', fmtAr(l.cout_reel_livreurs)],
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
        description={<>Les 300 opérations les plus récentes de la période.{barreFiltres}</>}
        colonnes={[
          { key: 'date', label: 'Date', render: (r) => (r.source === 'caisse' ? fmtDateHeure(r.date) : fmtDateHeure(`${r.date}T12:00:00+03:00`).slice(0, 10)), export: (r) => r.date },
          { key: 'source', label: 'Source', render: (r) => <Badge variant="outline">{r.source === 'caisse' ? 'Caisse' : 'Livreur'}</Badge>, export: (r) => (r.source === 'caisse' ? 'Caisse' : 'Livreur') },
          { key: 'categorie', label: 'Catégorie' },
          { key: 'libelle', label: 'Libellé' },
          { key: 'auteur', label: 'Par' },
          { key: 'montant', label: 'Montant', align: 'right', render: (r) => fmtAr(r.montant) },
        ]}
        lignes={data ? filtres : null}
        loading={loading}
        error={error}
        pageSize={20}
        exportNom="detail_depenses"
        compact
        vide={actif ? 'Aucune opération ne correspond à ces filtres.' : 'Aucune dépense sur la période.'}
      />
    </div>
  );
}
