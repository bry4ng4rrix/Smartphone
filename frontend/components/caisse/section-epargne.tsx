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
import { AlertTriangle, Loader2, PiggyBank } from 'lucide-react';
import { fmtAr, fmtDateHeure } from '@/lib/reports';
import { ReportTable } from '@/components/reports/report-table';

export interface MouvementEpargne {
  id: number; type: 'VERSEMENT' | 'RETRAIT' | 'CORRECTION'; type_label: string; montant: number; solde_apres: number;
  motif: string; order_numero: string; reference: string; created_by_name: string; created_at: string;
}

const TYPE_VARIANT: Record<string, 'default' | 'destructive' | 'secondary'> = { VERSEMENT: 'default', RETRAIT: 'destructive', CORRECTION: 'secondary' };

/** Compte d'épargne : solde, versements automatiques, retraits confirmés, historique. */
export function SectionEpargne({
  solde, historique, loading, error, magasinId, onChanged, versePeriode, retirePeriode,
}: { solde: number | null; historique: MouvementEpargne[] | null; loading: boolean; error?: string | null; magasinId: number | null; onChanged: () => void; versePeriode?: number; retirePeriode?: number }) {
  const [ouvert, setOuvert] = useState(false);
  const [montant, setMontant] = useState('');
  const [motif, setMotif] = useState('');
  const [etape, setEtape] = useState<1 | 2>(1);
  const [enCours, setEnCours] = useState(false);
  const m = Number(montant) || 0;

  const fermer = () => { setOuvert(false); setEtape(1); setMontant(''); setMotif(''); };

  const retirer = async () => {
    setEnCours(true);
    try {
      const res = await djangoClient.finance.retraitEpargne(magasinId, { montant: m, motif });
      toast.success(`Retrait de ${fmtAr(m)} enregistré — épargne restante ${fmtAr(res.solde_apres)}`);
      fermer();
      onChanged();
    } catch (e: unknown) {
      toast.error((e as Error)?.message || 'Erreur');
    } finally {
      setEnCours(false);
    }
  };

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-2 space-y-0 pb-3">
          <div>
            <CardTitle className="flex items-center gap-2 text-base"><PiggyBank className="h-4 w-4" /> Épargne</CardTitle>
            <CardDescription className="text-xs">
              Alimentée automatiquement à chaque vente rentable (part épargne du gain réel). Intouchable par défaut : un retrait est une opération exceptionnelle, confirmée et tracée.
            </CardDescription>
          </div>
          <Button variant="outline" size="sm" className="h-8 shrink-0" onClick={() => setOuvert(true)} disabled={loading || !solde || Number(solde) <= 0}>
            Retirer
          </Button>
        </CardHeader>
        <CardContent>
          {loading ? (
            <Skeleton className="h-16" />
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div><p className="text-xs text-muted-foreground">Total accumulé</p><p className="text-2xl font-bold tabular-nums text-blue-600 dark:text-blue-400">{fmtAr(solde ?? 0)}</p></div>
              <div><p className="text-xs text-muted-foreground">Versé sur la période</p><p className="text-lg font-semibold tabular-nums text-emerald-600">+{fmtAr(versePeriode ?? 0)}</p></div>
              <div><p className="text-xs text-muted-foreground">Retiré sur la période</p><p className="text-lg font-semibold tabular-nums text-red-600">−{fmtAr(retirePeriode ?? 0)}</p></div>
            </div>
          )}
        </CardContent>
      </Card>

      <ReportTable
        titre="Historique de l'épargne"
        colonnes={[
          { key: 'created_at', label: 'Date', render: (r) => fmtDateHeure(r.created_at) },
          { key: 'type_label', label: 'Type', render: (r) => <Badge variant={TYPE_VARIANT[r.type] || 'outline'}>{r.type_label}</Badge> },
          { key: 'montant', label: 'Montant', align: 'right', render: (r) => <span className={Number(r.montant) < 0 ? 'text-red-600' : 'text-emerald-600'}>{Number(r.montant) > 0 ? '+' : ''}{fmtAr(r.montant)}</span> },
          { key: 'solde_apres', label: 'Solde après', align: 'right', render: (r) => <span className="font-medium tabular-nums">{fmtAr(r.solde_apres)}</span> },
          { key: 'motif', label: 'Motif', render: (r) => <span>{r.motif}{r.order_numero && <span className="text-muted-foreground"> · {r.order_numero}</span>}</span> },
          { key: 'created_by_name', label: 'Par', render: (r) => r.created_by_name || 'Automatique' },
        ]}
        lignes={historique}
        loading={loading}
        error={error}
        pageSize={10}
        exportNom="historique_epargne"
        rowKey={(r) => r.id}
        compact
        vide="Aucun mouvement d'épargne pour l'instant : la première vente rentable alimentera le compte."
      />

      <Dialog open={ouvert} onOpenChange={(o) => !o && fermer()}>
        <DialogContent className="max-w-sm">
          {etape === 1 ? (
            <>
              <DialogHeader>
                <DialogTitle>Retrait d&apos;épargne</DialogTitle>
                <DialogDescription>Épargne disponible : <span className="font-semibold text-foreground">{fmtAr(solde ?? 0)}</span></DialogDescription>
              </DialogHeader>
              <div className="space-y-3">
                <div className="space-y-1">
                  <Label>Montant (Ar)</Label>
                  <Input type="number" min={1} max={Number(solde ?? 0)} value={montant} onChange={(e) => setMontant(e.target.value)} autoFocus />
                  {m > Number(solde ?? 0) && <p className="text-xs text-red-600">Supérieur à l&apos;épargne disponible.</p>}
                </div>
                <div className="space-y-1">
                  <Label>Motif</Label>
                  <Input value={motif} onChange={(e) => setMotif(e.target.value)} placeholder="Ex : réparation urgente" />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={fermer}>Annuler</Button>
                <Button onClick={() => setEtape(2)} disabled={m <= 0 || m > Number(solde ?? 0)}>Continuer</Button>
              </DialogFooter>
            </>
          ) : (
            <>
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2 text-red-600"><AlertTriangle className="h-5 w-5" /> Attention</DialogTitle>
                <DialogDescription asChild>
                  <div className="text-sm text-foreground space-y-2 pt-1">
                    <p>Vous êtes sur le point de retirer <span className="font-semibold">{fmtAr(m)}</span> de l&apos;épargne.</p>
                    <p>Cette somme sera retirée de l&apos;épargne accumulée ({fmtAr(solde ?? 0)} → {fmtAr(Number(solde ?? 0) - m)}). L&apos;opération sera enregistrée dans l&apos;historique.</p>
                    <p>Voulez-vous vraiment continuer ?</p>
                  </div>
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" onClick={() => setEtape(1)} disabled={enCours}>Annuler</Button>
                <Button variant="destructive" onClick={retirer} disabled={enCours}>{enCours ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Confirmer le retrait'}</Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
