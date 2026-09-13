'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { djangoClient } from '@/lib/django-client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { HandCoins, Loader2 } from 'lucide-react';
import { fmtAr, fmtDate, fmtNb } from '@/lib/reports';
import { WARN } from './ui';

export interface Encaissements {
  lignes: { id: number; numero: string; client: string; montant: number; source: string; source_label: string; livreur_id: number | null; livreur: string; date_commande: string }[];
  par_livreur: { livreur_id: number | null; nom: string; nb: number; brut: number; depenses: number; net: number }[];
  total: number;
  chez_livreurs: number;
  a_enregistrer: number;
}

/** Argent des ventes livrées pas encore en caisse, et remise par livreur. */
export function SectionEncaissements({
  data, loading, magasinId, sessionOuverte, onChanged,
}: { data: Encaissements | null; loading: boolean; magasinId: number | null; sessionOuverte: boolean; onChanged: () => void }) {
  const [cible, setCible] = useState<Encaissements['par_livreur'][number] | null>(null);
  const [enCours, setEnCours] = useState(false);

  const remettre = async () => {
    if (!cible) return;
    setEnCours(true);
    try {
      const res = await djangoClient.finance.remise(
        magasinId,
        cible.livreur_id
          ? { livreur_id: cible.livreur_id, inclure_depenses: true }
          : { encaissement_ids: data!.lignes.filter((l) => !l.livreur_id).map((l) => l.id) },
      );
      toast.success(`${res.nb} vente(s) remise(s) en caisse — net ${fmtAr(res.net)}`);
      setCible(null);
      onChanged();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur');
    } finally {
      setEnCours(false);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base"><HandCoins className="h-4 w-4" /> Argent en attente de remise</CardTitle>
        <CardDescription className="text-xs">
          Ventes livrées dont l&apos;argent n&apos;est pas encore en caisse : encaissé par un livreur en tournée, ou payé au comptoir / d&apos;avance quand
          la caisse était fermée. La remise crée une entrée par vente (jamais deux fois) et déduit les frais de tournée acceptés du livreur.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {loading || !data ? (
          <Skeleton className="h-24" />
        ) : data.par_livreur.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-4">Tout l&apos;argent des ventes livrées est en caisse.</p>
        ) : (
          <div className="space-y-2">
            {!sessionOuverte && <p className={`text-xs ${WARN}`} role="status">Ouvrez la caisse pour enregistrer une remise.</p>}
            {data.par_livreur.map((p) => (
              <div key={p.livreur_id ?? 'comptoir'} className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 rounded-lg border p-3">
                <div className="min-w-0">
                  <p className="text-sm font-medium">{p.nom} <Badge variant="secondary" className="ml-1">{fmtNb(p.nb)} vente(s)</Badge></p>
                  <p className="text-xs text-muted-foreground">
                    encaissé {fmtAr(p.brut)}{Number(p.depenses) > 0 && ` − frais de tournée acceptés ${fmtAr(p.depenses)}`} → net à remettre <span className="font-medium text-foreground">{fmtAr(p.net)}</span>
                  </p>
                </div>
                <Button size="sm" className="h-9 sm:h-8 w-full sm:w-auto" onClick={() => setCible(p)} disabled={!sessionOuverte}>
                  Enregistrer la remise
                </Button>
              </div>
            ))}
            <details className="text-xs">
              <summary className="cursor-pointer text-muted-foreground">Détail des {fmtNb(data.lignes.length)} vente(s) en attente</summary>
              <ul className="mt-2 space-y-1">
                {data.lignes.map((l) => (
                  <li key={l.id} className="flex justify-between gap-2 border-b py-1.5 last:border-0">
                    <span className="min-w-0 break-words">{fmtDate(l.date_commande)} · {l.numero} · {l.client} <span className="text-muted-foreground">({l.livreur || l.source_label})</span></span>
                    <span className="tabular-nums shrink-0">{fmtAr(l.montant)}</span>
                  </li>
                ))}
              </ul>
            </details>
          </div>
        )}
      </CardContent>

      <Dialog open={!!cible} onOpenChange={(o) => !o && setCible(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Confirmer la remise en caisse</DialogTitle>
            <DialogDescription>
              {cible && (
                <>
                  {cible.nom} : {fmtNb(cible.nb)} vente(s), {fmtAr(cible.brut)} encaissés
                  {Number(cible.depenses) > 0 && <>, {fmtAr(cible.depenses)} de frais de tournée déduits</>}. Entrée nette en caisse : <span className="font-semibold text-foreground">{fmtAr(cible.net)}</span>.
                </>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCible(null)} disabled={enCours}>Annuler</Button>
            <Button onClick={remettre} disabled={enCours}>{enCours ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Confirmer la remise'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
