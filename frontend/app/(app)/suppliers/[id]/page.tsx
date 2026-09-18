'use client';

/**
 * Fiche d'un approvisionnement (§ 16) : FOURNISSEUR / PRODUIT / PAIEMENTS /
 * TRANSPORT / COÛT, avec les actions du cycle :
 * Commande → Acompte payé → Préparation → Entièrement payé → Expédié →
 * En transit → Arrivé à Madagascar → Frais + Douane → Coût finalisé (+ stock).
 */
import { useCallback, useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { ArrowLeft, Calculator, CheckCircle2, CreditCard, Loader2, Package, Pencil, Plane, Ship, Trash2, Truck } from 'lucide-react';
import { toast } from 'sonner';
import { CostSummary } from '@/components/suppliers/cost-summary';
import { STATUTS, actionPossible, fmtAr, fmtDate, fmtDevise, fmtNombre, fmtTaux, labelOf, messageErreur, METHODES_PAIEMENT, modifiable, statutIndex, statutInfo, TYPES_PAIEMENT } from '@/components/suppliers/supplier-status';
import { ArriverDialog, EditOrderDialog, FinaliserDialog, FraisDouaneDialog, PaymentDialog, TransportDialog } from '@/components/suppliers/order-dialogs';

export default function SupplierOrderPage() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const router = useRouter();
  const params = useParams<{ id: string }>();
  const id = Number(params.id);

  const [order, setOrder] = useState<any | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [dialog, setDialog] = useState<null | 'paiement' | 'expedier' | 'transit' | 'arriver' | 'frais' | 'finaliser' | 'modifier'>(null);
  const [suppressionPaiement, setSuppressionPaiement] = useState<any | null>(null);

  const load = useCallback(async (silent = false) => {
    if (!Number.isFinite(id)) return;
    if (!silent) setLoading(true);
    try {
      setOrder(await djangoClient.suppliers.getById(id));
    } catch (e) {
      toast.error(messageErreur(e, 'Approvisionnement introuvable'));
      router.push('/suppliers');
    } finally {
      if (!silent) setLoading(false);
    }
  }, [id, router]);

  useEffect(() => { if (isGerant) load(); }, [isGerant, load]);
  useRealtimeRefresh(['supplier_order', 'stock_movement'], () => { if (isGerant) load(true); });

  const action = async (cle: string, fn: () => Promise<any>, succes: string) => {
    setBusy(cle);
    try {
      const o = await fn();
      if (o && typeof o === 'object' && 'id' in o) setOrder(o); else await load(true);
      toast.success(succes);
    } catch (e) {
      toast.error(messageErreur(e));
    } finally {
      setBusy(null);
    }
  };

  if (userLoading || (loading && !order)) {
    return <div className="p-4 sm:p-6 space-y-4"><Skeleton className="h-8 w-64" /><Skeleton className="h-96 w-full" /></div>;
  }
  if (!isGerant) {
    return <div className="p-6"><p className="text-sm text-muted-foreground">Accès réservé au gérant.</p></div>;
  }
  if (!order) return null;

  const s = statutInfo(order.statut);
  const idx = statutIndex(order.statut);
  const ouvert = modifiable(order.statut);
  const paiements: any[] = order.payments ?? [];

  return (
    <div className="p-4 sm:p-6 space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div className="flex items-center gap-2 min-w-0">
          <Button variant="ghost" size="icon" className="shrink-0" onClick={() => router.push('/suppliers')} title="Retour"><ArrowLeft className="h-4 w-4" /></Button>
          <div className="min-w-0">
            <h1 className="text-xl sm:text-2xl font-bold truncate">{order.numero}</h1>
            <p className="text-sm text-muted-foreground truncate">{order.produit_libelle} · {fmtNombre(order.quantite)} pièces{order.supplier_nom ? ` · ${order.supplier_nom}` : ''}</p>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Badge className={`${s.color} border-0`}>{s.label}</Badge>
          {ouvert && <Button variant="outline" size="sm" onClick={() => setDialog('modifier')}><Pencil className="h-4 w-4 mr-1" /> Modifier</Button>}
        </div>
      </div>

      {/* Progression du cycle (§ 15) */}
      <ol className="flex flex-wrap gap-1 text-[11px]">
        {STATUTS.map((st, i) => (
          <li key={st.value} className={`rounded-full px-2 py-0.5 border ${i < idx ? 'bg-muted text-muted-foreground' : i === idx ? `${st.color} border-transparent font-semibold` : 'text-muted-foreground/60'}`}>
            {i < idx ? '✓ ' : ''}{st.label}
          </li>
        ))}
      </ol>

      {/* Actions du moment */}
      {ouvert && (
        <Card>
          <CardContent className="p-3 flex flex-wrap gap-2">
            {actionPossible('commander', order.statut) && <Button onClick={() => action('commander', () => djangoClient.suppliers.commander(order.id), 'Commande passée au fournisseur')} disabled={!!busy}>{busy === 'commander' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Package className="h-4 w-4 mr-1" />} Commander</Button>}
            <Button variant={order.statut === 'BROUILLON' ? 'outline' : 'default'} onClick={() => setDialog('paiement')} disabled={!!busy}><CreditCard className="h-4 w-4 mr-1" /> {paiements.length ? 'Nouveau paiement' : 'Premier paiement (acompte)'}</Button>
            {actionPossible('preparer', order.statut) && <Button variant="outline" onClick={() => action('preparer', () => djangoClient.suppliers.preparer(order.id), 'Marchandise en préparation chez le fournisseur')} disabled={!!busy}>Préparation</Button>}
            {actionPossible('expedier', order.statut) && <Button variant="outline" onClick={() => setDialog('expedier')} disabled={!!busy}><Plane className="h-4 w-4 mr-1" /> Départ Chine</Button>}
            {actionPossible('transit', order.statut) && <Button variant="outline" onClick={() => setDialog('transit')} disabled={!!busy}><Ship className="h-4 w-4 mr-1" /> En transit</Button>}
            {actionPossible('arriver', order.statut) && <Button variant="outline" onClick={() => setDialog('arriver')} disabled={!!busy}><Truck className="h-4 w-4 mr-1" /> Arrivée Madagascar</Button>}
            {order.statut === 'ARRIVE' && <Button variant="outline" onClick={() => setDialog('frais')} disabled={!!busy}><Calculator className="h-4 w-4 mr-1" /> Frais + Douane</Button>}
            {actionPossible('finaliser', order.statut) && <Button onClick={() => setDialog('finaliser')} disabled={!!busy}><CheckCircle2 className="h-4 w-4 mr-1" /> Finaliser le coût</Button>}
          </CardContent>
        </Card>
      )}
      {!ouvert && (
        <p className="text-sm text-muted-foreground">Coût finalisé le {fmtDate(order.finalise_at)} — {fmtNombre(order.quantite_recue)} pièce(s) reçue(s). Ce coût est historique : il ne change plus.</p>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <CostSummary order={order} />

        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Paiements ({paiements.length})</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            {paiements.length === 0 && <p className="text-sm text-muted-foreground">Aucun paiement. Le premier paiement (acompte) fait passer l&apos;approvisionnement à « Acompte payé ».</p>}
            {paiements.map((p, i) => (
              <div key={p.id} className="rounded-md border p-3 text-sm">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-medium">Paiement {i + 1} · {labelOf(TYPES_PAIEMENT, p.type_paiement)} · {fmtDate(p.date)}</p>
                    <p className="text-muted-foreground text-xs">{labelOf(METHODES_PAIEMENT, p.methode)}{p.reference ? ` · ${p.reference}` : ''}{p.created_by_name ? ` · ${p.created_by_name}` : ''}{order.caisse?.paiements?.includes(p.id) ? ' · en caisse' : ''}</p>
                    {p.commentaire && <p className="text-xs mt-1">{p.commentaire}</p>}
                  </div>
                  <div className="text-right tabular-nums">
                    <p className="font-semibold">{fmtDevise(p.montant, p.devise)}</p>
                    {p.devise !== 'MGA' && <p className="text-xs text-muted-foreground">taux {fmtTaux(p.taux_change)}</p>}
                    <p className="text-xs">= {fmtAr(p.montant_mga)}</p>
                  </div>
                </div>
                {ouvert && (
                  <div className="mt-2 flex justify-end">
                    <Button variant="ghost" size="sm" className="h-7 text-red-600" onClick={() => setSuppressionPaiement(p)} disabled={!!busy}><Trash2 className="h-3.5 w-3.5 mr-1" /> Supprimer</Button>
                  </div>
                )}
              </div>
            ))}
            <div className="flex justify-between text-sm border-t pt-2">
              <span className="text-muted-foreground">Total fournisseur (MGA)</span>
              <span className="font-semibold tabular-nums">{fmtAr(order.total_paiements_mga)}</span>
            </div>
          </CardContent>
        </Card>
      </div>

      <PaymentDialog open={dialog === 'paiement'} onOpenChange={(o) => !o && setDialog(null)} order={order} onSaved={setOrder} />
      <TransportDialog mode="expedier" open={dialog === 'expedier'} onOpenChange={(o) => !o && setDialog(null)} order={order} onSaved={setOrder} />
      <TransportDialog mode="transit" open={dialog === 'transit'} onOpenChange={(o) => !o && setDialog(null)} order={order} onSaved={setOrder} />
      <ArriverDialog open={dialog === 'arriver'} onOpenChange={(o) => !o && setDialog(null)} order={order} onSaved={setOrder} />
      <FraisDouaneDialog open={dialog === 'frais'} onOpenChange={(o) => !o && setDialog(null)} order={order} onSaved={setOrder} />
      <FinaliserDialog open={dialog === 'finaliser'} onOpenChange={(o) => !o && setDialog(null)} order={order} onSaved={setOrder} />
      <EditOrderDialog open={dialog === 'modifier'} onOpenChange={(o) => !o && setDialog(null)} order={order} onSaved={setOrder} />

      <AlertDialog open={!!suppressionPaiement} onOpenChange={(o) => !o && setSuppressionPaiement(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Supprimer ce paiement ?</AlertDialogTitle>
            <AlertDialogDescription>{suppressionPaiement && `${fmtDevise(suppressionPaiement.montant, suppressionPaiement.devise)} du ${fmtDate(suppressionPaiement.date)} — le coût total sera recalculé. Une éventuelle sortie de caisse déjà enregistrée n'est pas annulée.`}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Annuler</AlertDialogCancel>
            <AlertDialogAction className="bg-red-600 hover:bg-red-700" onClick={() => { const p = suppressionPaiement; setSuppressionPaiement(null); if (p) action(`paiement-${p.id}`, () => djangoClient.suppliers.deletePayment(order.id, p.id), 'Paiement supprimé'); }}>Supprimer</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
