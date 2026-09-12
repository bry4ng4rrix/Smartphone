'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { djangoClient } from '@/lib/django-client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { Loader2, Settings2, TrendingDown, TrendingUp } from 'lucide-react';
import { fmtAr, fmtDate, fmtNb, fmtPct } from '@/lib/reports';
import { ReportTable } from '@/components/reports/report-table';

export interface StatsGain {
  nb_ventes: number;
  nb_articles: number;
  nb_pertes: number;
  ca_produits: number;
  livraison_client: number;
  total_encaisse: number;
  cout_achat: number;
  frais_agence: number;
  part_boost: number;
  gain_reel: number;
  etat: 'benefice' | 'perte' | 'equilibre';
  repartition: { reappro: number; epargne: number; depenses: number };
}

export interface RepartitionPct {
  reappro: number;
  epargne: number;
  depenses: number;
}

const Ligne = ({ label, valeur, signe, bold, cls }: { label: string; valeur: number; signe?: '+' | '−'; bold?: boolean; cls?: string }) => (
  <div className={`flex items-center justify-between gap-2 text-sm ${bold ? 'font-semibold border-t pt-2 mt-1' : ''}`}>
    <span className={bold ? '' : 'text-muted-foreground'}>{signe && <span className="inline-block w-4 text-center">{signe}</span>}{label}</span>
    <span className={`tabular-nums ${cls || ''}`}>{fmtAr(valeur)}</span>
  </div>
);

/** Gain réel de la période + répartition (calculés par le backend). */
export function SectionGain({
  gain, pct, periode, loading, magasinId, onSettingsChanged,
}: { gain: StatsGain | null; pct: RepartitionPct | null; periode?: { from: string; to: string }; loading: boolean; magasinId: number | null; onSettingsChanged: () => void }) {
  const [edit, setEdit] = useState(false);
  const [form, setForm] = useState({ reappro: '60', epargne: '25', depenses: '15' });
  const [saving, setSaving] = useState(false);
  const total = Number(form.reappro || 0) + Number(form.epargne || 0) + Number(form.depenses || 0);

  const ouvrir = () => {
    if (pct) setForm({ reappro: String(Number(pct.reappro)), epargne: String(Number(pct.epargne)), depenses: String(Number(pct.depenses)) });
    setEdit(true);
  };

  const enregistrer = async () => {
    if (total !== 100) {
      toast.error(`La répartition doit totaliser 100 % (actuellement ${total} %).`);
      return;
    }
    setSaving(true);
    try {
      await djangoClient.finance.settings.update(magasinId, { pct_reappro: Number(form.reappro), pct_epargne: Number(form.epargne), pct_depenses: Number(form.depenses) });
      toast.success('Répartition enregistrée');
      setEdit(false);
      onSettingsChanged();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur');
    } finally {
      setSaving(false);
    }
  };

  const perte = gain && Number(gain.gain_reel) < 0;

  return (
    <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base">
            {perte ? <TrendingDown className="h-4 w-4 text-red-600" /> : <TrendingUp className="h-4 w-4 text-emerald-600" />} Gain réel
          </CardTitle>
          <CardDescription className="text-xs">
            {periode && `${fmtDate(periode.from)} → ${fmtDate(periode.to)} · `}
            (prix de vente + livraison client) − prix d&apos;achat − frais agence − part de boost.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {loading || !gain ? (
            <Skeleton className="h-52" />
          ) : (
            <div className="space-y-1.5">
              <p className="text-xs text-muted-foreground mb-2">
                {fmtNb(gain.nb_ventes)} vente(s) livrée(s) · {fmtNb(gain.nb_articles)} article(s)
                {gain.nb_pertes > 0 && <Badge variant="destructive" className="ml-2 text-[10px]">{gain.nb_pertes} vente(s) à perte</Badge>}
              </p>
              <Ligne label="Chiffre d'affaires (produits)" valeur={gain.ca_produits} />
              <Ligne label="Livraison facturée au client" valeur={gain.livraison_client} signe="+" />
              <Ligne label="Coût d'achat" valeur={gain.cout_achat} signe="−" />
              <Ligne label="Frais agences de livraison" valeur={gain.frais_agence} signe="−" />
              <Ligne label="Boost / publicité (part des articles vendus)" valeur={gain.part_boost} signe="−" />
              <Ligne
                label={perte ? 'PERTE RÉELLE' : 'GAIN RÉEL'}
                valeur={gain.gain_reel}
                bold
                cls={perte ? 'text-red-600 dark:text-red-400' : 'text-emerald-600 dark:text-emerald-400'}
              />
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-2 space-y-0 pb-3">
          <div>
            <CardTitle className="text-base">Répartition du gain</CardTitle>
            <CardDescription className="text-xs">
              Appliquée automatiquement à chaque vente rentable ; la part épargne est versée au compte d&apos;épargne. Un gain nul ou négatif n&apos;est pas réparti.
            </CardDescription>
          </div>
          <Button variant="outline" size="sm" className="h-8 shrink-0" onClick={ouvrir} disabled={!pct}>
            <Settings2 className="h-4 w-4 mr-1" /> Paramètres
          </Button>
        </CardHeader>
        <CardContent>
          {loading || !gain || !pct ? (
            <Skeleton className="h-40" />
          ) : (
            <div className="space-y-2">
              {(
                [
                  ['Réapprovisionnement', pct.reappro, gain.repartition.reappro, 'bg-blue-500'],
                  ['Épargne', pct.epargne, gain.repartition.epargne, 'bg-emerald-500'],
                  ['Dépenses courantes', pct.depenses, gain.repartition.depenses, 'bg-amber-500'],
                ] as const
              ).map(([label, p, montant, couleur]) => (
                <div key={label} className="space-y-1">
                  <div className="flex items-center justify-between text-sm">
                    <span>{label} <span className="text-muted-foreground">· {fmtPct(Number(p))}</span></span>
                    <span className="font-medium tabular-nums">{fmtAr(montant)}</span>
                  </div>
                  <div className="h-1.5 rounded bg-muted overflow-hidden">
                    <div className={`h-full ${couleur}`} style={{ width: `${Number(p)}%` }} />
                  </div>
                </div>
              ))}
              <p className="text-xs text-muted-foreground pt-1">
                Total réparti : {fmtAr(Number(gain.repartition.reappro) + Number(gain.repartition.epargne) + Number(gain.repartition.depenses))}
                {perte && ' — aucune répartition sur une perte.'}
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={edit} onOpenChange={setEdit}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Paramètres de répartition</DialogTitle>
            <DialogDescription>Les trois pourcentages doivent totaliser exactement 100 %. Les ventes déjà calculées gardent leur répartition.</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            {(['reappro', 'epargne', 'depenses'] as const).map((k) => (
              <div key={k} className="space-y-1">
                <Label>{{ reappro: 'Réapprovisionnement (%)', epargne: 'Épargne (%)', depenses: 'Dépenses courantes (%)' }[k]}</Label>
                <Input type="number" min={0} max={100} step="0.01" value={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.value })} />
              </div>
            ))}
            <p className={`text-sm font-medium ${total === 100 ? 'text-emerald-600' : 'text-red-600'}`}>Total : {total} %{total !== 100 && ' — doit faire 100 %'}</p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEdit(false)} disabled={saving}>Annuler</Button>
            <Button onClick={enregistrer} disabled={saving || total !== 100}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Enregistrer'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

export interface LigneVenteResultat {
  id: number; numero: string; client: string; date_vente: string; livreur: string; zone: string; nb_articles: number;
  ca_produits: number; livraison_client: number; total_client: number; cout_achat: number; frais_agence: number;
  resultat_livraison: number; part_boost: number; gain_reel: number; etat: string;
  part_reappro: number; part_epargne: number; part_depenses: number; annule: boolean; encaissement: string; encaissement_statut: string;
}

/** Détail par vente : le cas « cache-écran » ligne par ligne. */
export function TableVentes({ ventes, loading, error }: { ventes: LigneVenteResultat[] | null; loading: boolean; error?: string | null }) {
  return (
    <ReportTable
      titre="Gain réel par vente"
      description="Chaque commande livrée : ce que le client a payé, ce qu'elle a coûté, ce qu'elle a rapporté et sa répartition."
      colonnes={[
        { key: 'date_vente', label: 'Date', render: (r) => fmtDate(r.date_vente) },
        { key: 'numero', label: 'Commande', render: (r) => <span className={r.annule ? 'line-through text-muted-foreground' : 'font-medium'}>{r.numero}</span> },
        { key: 'client', label: 'Client' },
        { key: 'nb_articles', label: 'Art.', align: 'right' },
        { key: 'total_client', label: 'Total client', align: 'right', render: (r) => fmtAr(r.total_client), export: (r) => r.total_client },
        { key: 'cout_achat', label: "Coût d'achat", align: 'right', render: (r) => fmtAr(r.cout_achat) },
        { key: 'resultat_livraison', label: 'Livraison (client − agence)', align: 'right', render: (r) => <span className={Number(r.resultat_livraison) < 0 ? 'text-red-600' : ''}>{fmtAr(r.resultat_livraison)}</span> },
        { key: 'part_boost', label: 'Boost', align: 'right', render: (r) => fmtAr(r.part_boost) },
        { key: 'gain_reel', label: 'Gain réel', align: 'right', render: (r) => <span className={`font-semibold ${Number(r.gain_reel) < 0 ? 'text-red-600' : 'text-emerald-600'}`}>{fmtAr(r.gain_reel)}</span> },
        { key: 'part_epargne', label: 'Épargne', align: 'right', render: (r) => fmtAr(r.part_epargne) },
        { key: 'encaissement', label: 'Argent', render: (r) => (r.annule ? <Badge variant="outline">Annulée</Badge> : r.encaissement ? <Badge variant={r.encaissement_statut === 'REMIS' ? 'default' : 'secondary'}>{r.encaissement}</Badge> : <span className="text-muted-foreground text-xs">historique</span>) },
      ]}
      lignes={ventes}
      loading={loading}
      error={error}
      pageSize={10}
      exportNom="gain_reel_par_vente"
      rowKey={(r) => r.id}
      compact
      vide="Aucune vente livrée sur la période."
    />
  );
}
