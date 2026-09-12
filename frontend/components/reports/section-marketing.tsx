'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { djangoClient } from '@/lib/django-client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { BadgeDollarSign, Megaphone, Pencil, Percent, Plus, ShoppingCart, Trash2, Wallet } from 'lucide-react';
import { appToday } from '@/lib/timezone';
import { fmtAr, fmtDate, fmtNb, fmtPct, type Campagne, type MarketingData } from '@/lib/reports';
import { KpiCard, KpiGrid } from './kpi-card';
import { BarresChart, CamembertChart, ChartCard } from './report-chart';
import { ReportTable, type Colonne } from './report-table';
import { invalidateReports, useReport, type ReportParams } from './use-report';

const PLATEFORMES = [
  { code: 'FACEBOOK', label: 'Facebook' },
  { code: 'INSTAGRAM', label: 'Instagram' },
  { code: 'TIKTOK', label: 'TikTok' },
  { code: 'GOOGLE', label: 'Google' },
  { code: 'AUTRE', label: 'Autre' },
];

const roiCouleur = (roi: number | null) => (roi === null ? '' : roi >= 0 ? 'text-emerald-600' : 'text-red-600');

type Formulaire = { nom: string; plateforme: string; montant: string; date_debut: string; date_fin: string; note: string };
const vide = (): Formulaire => ({ nom: '', plateforme: 'FACEBOOK', montant: '', date_debut: appToday(), date_fin: '', note: '' });

export function SectionMarketing({ params, enabled }: { params: ReportParams; enabled: boolean }) {
  const [plateforme, setPlateforme] = useState('ALL');
  const { data, loading, error, reload } = useReport<MarketingData>('marketing', { ...params, platform: plateforme === 'ALL' ? undefined : plateforme }, enabled);
  const t = data?.totaux;

  const [edition, setEdition] = useState<{ id?: number; form: Formulaire } | null>(null);
  const [suppression, setSuppression] = useState<Campagne | null>(null);
  const [enCours, setEnCours] = useState(false);

  const enregistrer = async () => {
    if (!edition) return;
    const f = edition.form;
    if (!f.nom.trim() || !f.date_debut) {
      toast.error('Nom et date de début sont requis');
      return;
    }
    setEnCours(true);
    try {
      const payload = { nom: f.nom.trim(), plateforme: f.plateforme, montant: Number(f.montant) || 0, date_debut: f.date_debut, date_fin: f.date_fin || null, note: f.note };
      if (edition.id) await djangoClient.campaigns.update(edition.id, payload);
      else await djangoClient.campaigns.create(payload);
      toast.success(edition.id ? 'Campagne modifiée' : 'Campagne créée');
      setEdition(null);
      invalidateReports();
      reload();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur');
    } finally {
      setEnCours(false);
    }
  };

  const supprimer = async () => {
    if (!suppression) return;
    setEnCours(true);
    try {
      await djangoClient.campaigns.delete(suppression.id);
      toast.success('Campagne supprimée');
      setSuppression(null);
      invalidateReports();
      reload();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur');
    } finally {
      setEnCours(false);
    }
  };

  const colonnes: Colonne<Campagne>[] = [
    { key: 'nom', label: 'Campagne', render: (r) => <span className="font-medium">{r.nom}{!r.actif && <Badge variant="outline" className="ml-2">Inactive</Badge>}</span> },
    { key: 'plateforme_label', label: 'Plateforme' },
    { key: 'periode', label: 'Période', render: (r) => `${fmtDate(r.date_debut)}${r.date_fin ? ` → ${fmtDate(r.date_fin)}` : ' → en cours'}`, export: (r) => `${r.date_debut} → ${r.date_fin || ''}` },
    { key: 'depenses', label: 'Dépenses', align: 'right', render: (r) => fmtAr(r.depenses) },
    { key: 'commandes', label: 'Commandes', align: 'right', render: (r) => `${fmtNb(r.commandes)} (${fmtNb(r.commandes_livrees)} livrées)`, export: (r) => r.commandes },
    { key: 'ca', label: 'CA généré', align: 'right', render: (r) => fmtAr(r.ca) },
    { key: 'marge_produits', label: 'Marge produits', align: 'right', render: (r) => fmtAr(r.marge_produits) },
    { key: 'benefice', label: 'Bénéfice attribué', align: 'right', render: (r) => <span className={r.benefice < 0 ? 'text-red-600' : ''}>{fmtAr(r.benefice)}</span> },
    { key: 'roi_pct', label: 'ROI', align: 'right', render: (r) => <span className={`font-medium ${roiCouleur(r.roi_pct)}`}>{r.roi_pct === null ? 'n/a (coût 0)' : fmtPct(r.roi_pct, true)}</span>, export: (r) => r.roi_pct },
    {
      key: 'actions',
      label: '',
      align: 'right',
      className: 'print:hidden',
      render: (r) => (
        <span className="inline-flex gap-1">
          <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setEdition({ id: r.id, form: { nom: r.nom, plateforme: r.plateforme, montant: String(r.depenses), date_debut: r.date_debut, date_fin: r.date_fin || '', note: '' } })} aria-label="Modifier">
            <Pencil className="h-3.5 w-3.5" />
          </Button>
          <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive" onClick={() => setSuppression(r)} aria-label="Supprimer">
            <Trash2 className="h-3.5 w-3.5" />
          </Button>
        </span>
      ),
      export: () => null,
    },
  ];

  const f = edition?.form;

  return (
    <div className="space-y-4">
      <p className="text-xs text-muted-foreground">
        ROI = (CA généré − coût de la campagne) / coût × 100. Le CA généré vient des commandes rattachées à la campagne (champ « Campagne » à la
        création d&apos;une commande) et livrées sur la période. Bénéfice attribué = marge produits de ces commandes − coût de la campagne.
        {t && Number(t.commandes_sans_campagne) > 0 && ` ${fmtNb(t.commandes_sans_campagne)} commandes de la période ne sont rattachées à aucune campagne.`}
      </p>

      <KpiGrid cols={4}>
        <KpiCard loading={loading} titre="Dépenses de campagnes" icon={Wallet} valeur={t && fmtAr(t.depenses_campagnes)} detail={t && `${fmtNb(t.nb_campagnes)} campagnes · Pub en caisse : ${fmtAr(t.depenses_pub_caisse)}`} />
        <KpiCard loading={loading} titre="Commandes générées" icon={ShoppingCart} valeur={t && fmtNb(t.commandes)} detail={t && `${fmtNb(t.commandes_livrees)} livrées`} />
        <KpiCard loading={loading} titre="CA généré" icon={BadgeDollarSign} valeur={t && fmtAr(t.ca)} detail={t && `marge produits ${fmtAr(t.marge_produits)}`} />
        <KpiCard loading={loading} titre="ROI global" icon={Percent} valeur={t && (t.roi_pct === null ? 'n/a' : fmtPct(t.roi_pct as number, true))} couleur={t ? roiCouleur(t.roi_pct as number | null) : undefined} detail={t && t.roi_pct === null ? 'aucune dépense de campagne' : undefined} />
      </KpiGrid>

      <ReportTable
        titre="Campagnes"
        description="Campagnes actives sur la période. Créez-les ici, puis rattachez les commandes concernées."
        actions={
          <div className="flex items-center gap-1">
            <Select value={plateforme} onValueChange={setPlateforme}>
              <SelectTrigger className="h-8 w-36 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">Toutes plateformes</SelectItem>
                {PLATEFORMES.map((p) => (
                  <SelectItem key={p.code} value={p.code}>
                    {p.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button size="sm" className="h-8" onClick={() => setEdition({ form: vide() })}>
              <Plus className="h-4 w-4 mr-1" /> Campagne
            </Button>
          </div>
        }
        colonnes={colonnes}
        lignes={data?.campagnes}
        loading={loading}
        error={error}
        exportNom="campagnes_marketing"
        rowKey={(r) => r.id}
        vide="Aucune campagne sur la période. Cliquez sur « Campagne » pour en enregistrer une."
      />

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <ChartCard titre="Dépenses par plateforme" loading={loading} error={error} vide={!data?.par_plateforme.length}>
          {data && <CamembertChart data={data.par_plateforme} labelKey="label" valueKey="depenses" unite="ar" />}
        </ChartCard>
        <ChartCard titre="CA généré par plateforme" loading={loading} error={error} vide={!data?.par_plateforme.length}>
          {data && <BarresChart data={data.par_plateforme} labelKey="label" valueKey="ca" color="#16a34a" />}
        </ChartCard>
        <ReportTable
          titre="Par plateforme"
          colonnes={[
            { key: 'label', label: 'Plateforme' },
            { key: 'nb_campagnes', label: 'Camp.', align: 'right' },
            { key: 'depenses', label: 'Dépenses', align: 'right', render: (r) => fmtAr(r.depenses) },
            { key: 'commandes', label: 'Cmd', align: 'right' },
            { key: 'ca', label: 'CA', align: 'right', render: (r) => fmtAr(r.ca) },
            { key: 'roi_pct', label: 'ROI', align: 'right', render: (r) => <span className={roiCouleur(r.roi_pct)}>{r.roi_pct === null ? 'n/a' : fmtPct(r.roi_pct, true)}</span>, export: (r) => r.roi_pct },
          ]}
          lignes={data?.par_plateforme}
          loading={loading}
          error={error}
          pageSize={10}
          rowKey={(r) => r.plateforme}
          compact
        />
      </div>

      {data && (data.plus_rentables.length > 0 || data.moins_rentables.length > 0) && (
        <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
          <ReportTable
            titre="Campagnes les plus rentables"
            colonnes={[
              { key: 'nom', label: 'Campagne' },
              { key: 'plateforme_label', label: 'Plateforme' },
              { key: 'depenses', label: 'Dépenses', align: 'right', render: (r) => fmtAr(r.depenses) },
              { key: 'ca', label: 'CA', align: 'right', render: (r) => fmtAr(r.ca) },
              { key: 'roi_pct', label: 'ROI', align: 'right', render: (r) => <span className={roiCouleur(r.roi_pct)}>{fmtPct(r.roi_pct, true)}</span> },
            ]}
            lignes={data.plus_rentables}
            rowKey={(r) => r.id}
            pageSize={5}
          />
          <ReportTable
            titre="Campagnes les moins rentables"
            colonnes={[
              { key: 'nom', label: 'Campagne' },
              { key: 'plateforme_label', label: 'Plateforme' },
              { key: 'depenses', label: 'Dépenses', align: 'right', render: (r) => fmtAr(r.depenses) },
              { key: 'ca', label: 'CA', align: 'right', render: (r) => fmtAr(r.ca) },
              { key: 'roi_pct', label: 'ROI', align: 'right', render: (r) => <span className={roiCouleur(r.roi_pct)}>{fmtPct(r.roi_pct, true)}</span> },
            ]}
            lignes={data.moins_rentables}
            rowKey={(r) => r.id}
            pageSize={5}
            vide="Il faut au moins deux campagnes avec un coût pour comparer."
          />
        </div>
      )}

      <Dialog open={!!edition} onOpenChange={(o) => !o && setEdition(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Megaphone className="h-4 w-4" /> {edition?.id ? 'Modifier la campagne' : 'Nouvelle campagne'}
            </DialogTitle>
          </DialogHeader>
          {f && (
            <div className="space-y-3">
              <div className="space-y-1">
                <Label>Nom</Label>
                <Input value={f.nom} onChange={(e) => setEdition({ ...edition!, form: { ...f, nom: e.target.value } })} placeholder="Ex: Boost coques iPhone – septembre" autoFocus />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label>Plateforme</Label>
                  <Select value={f.plateforme} onValueChange={(v) => setEdition({ ...edition!, form: { ...f, plateforme: v } })}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {PLATEFORMES.map((p) => (
                        <SelectItem key={p.code} value={p.code}>
                          {p.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label>Dépense (Ar)</Label>
                  <Input type="number" min={0} value={f.montant} onChange={(e) => setEdition({ ...edition!, form: { ...f, montant: e.target.value } })} placeholder="0" />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label>Début</Label>
                  <Input type="date" value={f.date_debut} onChange={(e) => setEdition({ ...edition!, form: { ...f, date_debut: e.target.value } })} />
                </div>
                <div className="space-y-1">
                  <Label>Fin (facultatif)</Label>
                  <Input type="date" value={f.date_fin} min={f.date_debut} onChange={(e) => setEdition({ ...edition!, form: { ...f, date_fin: e.target.value } })} />
                </div>
              </div>
              <div className="space-y-1">
                <Label>Note</Label>
                <Textarea rows={2} value={f.note} onChange={(e) => setEdition({ ...edition!, form: { ...f, note: e.target.value } })} />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setEdition(null)} disabled={enCours}>
              Annuler
            </Button>
            <Button onClick={enregistrer} disabled={enCours}>
              {enCours ? 'Enregistrement…' : 'Enregistrer'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!suppression} onOpenChange={(o) => !o && setSuppression(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Supprimer la campagne « {suppression?.nom} » ?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">Les commandes rattachées ne seront pas supprimées, elles perdront seulement leur campagne.</p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSuppression(null)} disabled={enCours}>
              Annuler
            </Button>
            <Button variant="destructive" onClick={supprimer} disabled={enCours}>
              Supprimer
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
