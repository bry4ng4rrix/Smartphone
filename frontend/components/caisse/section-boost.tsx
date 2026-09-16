'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { djangoClient } from '@/lib/django-client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Loader2, Megaphone, Plus } from 'lucide-react';
import { appToday } from '@/lib/timezone';
import { fmtAr, fmtDate, fmtNb } from '@/lib/reports';
import { ReportTable } from '@/components/reports/report-table';

export interface Boost {
  id: number; nom: string; plateforme: string; plateforme_label: string; type_periode: string; date_debut: string; date_fin: string | null;
  montant: number; articles_vendus: number; cout_par_article: number; actif: boolean; en_caisse: boolean;
  /** Affectation automatique par période (serveur) : commandes concernées, livrées, CA généré, coût par commande. */
  nb_commandes: number; nb_livrees: number; ca: number; cout_par_commande: number | null;
  periode_effective?: { from: string; to: string; en_cours: boolean };
}

const PLATEFORMES = [['FACEBOOK', 'Facebook'], ['INSTAGRAM', 'Instagram'], ['TIKTOK', 'TikTok'], ['GOOGLE', 'Google'], ['AUTRE', 'Autre']] as const;
const TYPES = [['JOUR', 'Jour'], ['SEMAINE', 'Semaine'], ['MOIS', 'Mois'], ['PERSONNALISE', 'Personnalisée']] as const;

const addDays = (day: string, n: number) => {
  const d = new Date(`${day}T12:00:00+03:00`);
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
};

/** Boosts / publicité par période : montant réparti sur les articles vendus de la même période. */
export function SectionBoost({ boosts, loading, error, magasinId, sessionOuverte, onChanged }: { boosts: Boost[] | null; loading: boolean; error?: string | null; magasinId: number | null; sessionOuverte: boolean; onChanged: () => void }) {
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({ nom: '', plateforme: 'FACEBOOK', type_periode: 'SEMAINE', montant: '', date_debut: appToday(), date_fin: appToday(), en_caisse: false });
  const [enCours, setEnCours] = useState(false);

  const changerType = (t: string) => {
    const debut = f.date_debut || appToday();
    const fin = t === 'JOUR' ? debut : t === 'SEMAINE' ? addDays(debut, 6) : t === 'MOIS' ? addDays(debut, 29) : f.date_fin;
    setF({ ...f, type_periode: t, date_fin: fin });
  };

  const enregistrer = async () => {
    if (!f.nom.trim() || !f.date_debut || !(Number(f.montant) > 0)) {
      toast.error('Nom, montant et date de début sont requis');
      return;
    }
    setEnCours(true);
    try {
      await djangoClient.campaigns.create({
        nom: f.nom.trim(), plateforme: f.plateforme, montant: Number(f.montant), date_debut: f.date_debut, date_fin: f.date_fin || null,
        type_periode: f.type_periode as 'JOUR' | 'SEMAINE' | 'MOIS' | 'PERSONNALISE', en_caisse: f.en_caisse, magasin_id: magasinId ?? undefined,
      });
      toast.success('Boost enregistré — les gains de la période sont recalculés');
      setOuvert(false);
      setF({ nom: '', plateforme: 'FACEBOOK', type_periode: 'SEMAINE', montant: '', date_debut: appToday(), date_fin: appToday(), en_caisse: false });
      onChanged();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur');
    } finally {
      setEnCours(false);
    }
  };

  return (
    <>
      <ReportTable
        titre="Boost / publicité"
        description="Une dépense globale par période. Les commandes de la période sont rattachées automatiquement au boost (rien à sélectionner) ; son montant est réparti dans le gain réel sur le nombre réel d'articles vendus pendant la période (coût par article = montant / articles vendus ; 0 article = coût 0). Le coût par commande est un indicateur."
        actions={
          <Button size="sm" className="h-9 sm:h-8" onClick={() => setOuvert(true)}>
            <Plus className="h-4 w-4 mr-1" aria-hidden /> Nouveau boost
          </Button>
        }
        colonnes={[
          { key: 'nom', label: 'Boost', render: (r) => <span className="font-medium">{r.nom}</span> },
          { key: 'plateforme_label', label: 'Plateforme' },
          { key: 'periode', label: 'Période', render: (r) => `${fmtDate(r.date_debut)} → ${r.date_fin ? fmtDate(r.date_fin) : 'en cours'}`, export: (r) => `${r.date_debut} → ${r.date_fin || ''}` },
          { key: 'montant', label: 'Montant', align: 'right', render: (r) => fmtAr(r.montant) },
          { key: 'nb_commandes', label: 'Commandes concernées', align: 'right', render: (r) => `${fmtNb(r.nb_commandes)} (${fmtNb(r.nb_livrees)} livrées)`, export: (r) => r.nb_commandes },
          { key: 'ca', label: 'CA généré', align: 'right', render: (r) => fmtAr(r.ca) },
          { key: 'cout_par_commande', label: 'Coût boost / commande', align: 'right', render: (r) => (r.cout_par_commande === null ? <Badge variant="outline">aucune commande</Badge> : fmtAr(r.cout_par_commande)), export: (r) => r.cout_par_commande },
          { key: 'articles_vendus', label: 'Articles vendus', align: 'right', render: (r) => fmtNb(r.articles_vendus) },
          { key: 'cout_par_article', label: 'Coût boost / article', align: 'right', render: (r) => (r.articles_vendus ? <span className="font-medium">{fmtAr(r.cout_par_article)}</span> : <Badge variant="outline">aucun article vendu</Badge>), export: (r) => r.cout_par_article },
          { key: 'en_caisse', label: 'Caisse', render: (r) => (r.en_caisse ? <Badge>Sortie enregistrée</Badge> : <span className="text-xs text-muted-foreground">hors caisse</span>), export: (r) => (r.en_caisse ? 'oui' : 'non') },
        ]}
        carteMobile={(r) => (
          <div className="space-y-1">
            <div className="flex items-start justify-between gap-2">
              <p className="text-sm font-medium break-words">{r.nom}</p>
              <span className="text-sm font-semibold tabular-nums whitespace-nowrap">{fmtAr(r.montant)}</span>
            </div>
            <p className="text-xs text-muted-foreground">{r.plateforme_label} · {fmtDate(r.date_debut)} → {r.date_fin ? fmtDate(r.date_fin) : 'en cours'}</p>
            <p className="text-xs">
              {fmtNb(r.nb_commandes)} commande(s) concernée(s) ({fmtNb(r.nb_livrees)} livrées) · CA {fmtAr(r.ca)}
              {r.cout_par_commande !== null && <> · {fmtAr(r.cout_par_commande)} / commande</>}
            </p>
            <p className="text-xs">
              {fmtNb(r.articles_vendus)} article(s) vendu(s) · coût/article : {r.articles_vendus ? <span className="font-medium">{fmtAr(r.cout_par_article)}</span> : <Badge variant="outline" className="text-[10px]">aucun article vendu</Badge>}
            </p>
            {r.en_caisse ? <Badge className="text-[10px]">Sortie enregistrée en caisse</Badge> : <span className="text-[11px] text-muted-foreground">hors caisse</span>}
          </div>
        )}
        lignes={boosts}
        loading={loading}
        error={error}
        pageSize={8}
        exportNom="boosts"
        rowKey={(r) => r.id}
        compact
        vide="Aucun boost sur la période. Enregistrez-en un pour répartir son coût sur les articles vendus."
      />

      <Dialog open={ouvert} onOpenChange={setOuvert}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Megaphone className="h-4 w-4" /> Nouveau boost</DialogTitle>
            <DialogDescription>Les commandes entre les deux dates seront rattachées automatiquement au boost ; le coût par article et par commande se calculent seuls, et se recalculent à chaque modification du montant ou des dates.</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1"><Label>Nom</Label><Input value={f.nom} onChange={(e) => setF({ ...f, nom: e.target.value })} placeholder="Ex : Boost Facebook semaine 37" autoFocus /></div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>Plateforme</Label>
                <Select value={f.plateforme} onValueChange={(v) => setF({ ...f, plateforme: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PLATEFORMES.map(([c, l]) => <SelectItem key={c} value={c}>{l}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label>Type de période</Label>
                <Select value={f.type_periode} onValueChange={changerType}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{TYPES.map(([c, l]) => <SelectItem key={c} value={c}>{l}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1"><Label>Début</Label><Input type="date" value={f.date_debut} onChange={(e) => setF({ ...f, date_debut: e.target.value })} /></div>
              <div className="space-y-1"><Label>Fin</Label><Input type="date" value={f.date_fin} min={f.date_debut} onChange={(e) => setF({ ...f, date_fin: e.target.value })} /></div>
            </div>
            <div className="space-y-1"><Label>Montant total du boost (Ar)</Label><Input type="number" min={0} value={f.montant} onChange={(e) => setF({ ...f, montant: e.target.value })} /></div>
            <div className="flex items-center justify-between rounded-lg border p-3">
              <div>
                <Label htmlFor="boost-caisse">Enregistrer la sortie en caisse</Label>
                <p className="text-xs text-muted-foreground">{sessionOuverte ? 'Une sortie « Boost » sera ajoutée à la session ouverte.' : 'Caisse fermée : la sortie ne peut pas être enregistrée maintenant.'}</p>
              </div>
              <Switch id="boost-caisse" checked={f.en_caisse} onCheckedChange={(v) => setF({ ...f, en_caisse: v })} disabled={!sessionOuverte} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOuvert(false)} disabled={enCours}>Annuler</Button>
            <Button onClick={enregistrer} disabled={enCours}>{enCours ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Enregistrer'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
