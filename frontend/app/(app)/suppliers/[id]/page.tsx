'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { fmtAppDateTime } from '@/lib/timezone';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Progress } from '@/components/ui/progress';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  ArrowLeft, RefreshCw, Pencil, ShoppingCart, PackageCheck, Ship, Anchor, Boxes, Lock,
  Plus, Trash2, Wallet, Receipt, Truck, Info, Check, Save, Search,
} from 'lucide-react';
import { toast } from 'sonner';
import { CostSummary } from '@/components/suppliers/cost-summary';
import {
  METHODES_ALLOCATION, MODES_TRANSPORT, STATUTS_RECEPTION, actionPossible, fmtAr, fmtDate, fmtDevise, fmtTaux,
  labelOf, messageErreur, statutInfo,
} from '@/components/suppliers/supplier-status';
import {
  ArriverDialog,
  EditOrderDialog,
  FeeDialog,
  FinaliserDialog,
  PaymentDialog,
  ReceptionDialog,
  TransportDialog,
} from '@/components/suppliers/order-dialogs';

/* -------------------------------------------------------------------------- */
/* Frise du workflow                                                           */
/* -------------------------------------------------------------------------- */

const ETAPES: { key: string; label: string; statuts: string[] }[] = [
  { key: 'BROUILLON', label: 'Brouillon', statuts: ['BROUILLON'] },
  { key: 'COMMANDE', label: 'Commandé', statuts: ['COMMANDE'] },
  { key: 'PAYE', label: 'Payé', statuts: ['PARTIELLEMENT_PAYE', 'PAYE'] },
  { key: 'PREPARE', label: 'Préparé', statuts: ['PREPARE'] },
  { key: 'EN_TRANSIT', label: 'En transit', statuts: ['EN_TRANSIT'] },
  { key: 'ARRIVE', label: 'Arrivé', statuts: ['ARRIVE'] },
  { key: 'RECU', label: 'Réceptionné', statuts: ['PARTIELLEMENT_RECU', 'RECU'] },
  { key: 'COUT_FINALISE', label: 'Coût finalisé', statuts: ['COUT_FINALISE'] },
];

function etapeIndex(statut: string) {
  const i = ETAPES.findIndex((e) => e.statuts.includes(statut));
  return i < 0 ? 0 : i;
}

function WorkflowTimeline({ statut, statutLabel }: { statut: string; statutLabel: string }) {
  const courant = etapeIndex(statut);
  const partiel = statut === 'PARTIELLEMENT_PAYE' || statut === 'PARTIELLEMENT_RECU';
  return (
    <div className="overflow-x-auto pb-1">
      <ol className="flex items-start min-w-[640px]">
        {ETAPES.map((e, i) => {
          const fait = i < courant;
          const actif = i === courant;
          return (
            <li key={e.key} className="flex-1 relative">
              {i > 0 && (
                <div className={`absolute top-3.5 left-0 right-1/2 h-0.5 ${i <= courant ? 'bg-primary' : 'bg-border'}`} />
              )}
              {i < ETAPES.length - 1 && (
                <div className={`absolute top-3.5 left-1/2 right-0 h-0.5 ${i < courant ? 'bg-primary' : 'bg-border'}`} />
              )}
              <div className="relative flex flex-col items-center text-center px-1">
                <div
                  className={`h-7 w-7 rounded-full border-2 flex items-center justify-center text-xs font-semibold z-10 transition-colors ${
                    fait
                      ? 'bg-primary border-primary text-primary-foreground'
                      : actif
                        ? `border-primary text-primary bg-background ring-4 ring-primary/20 ${partiel ? 'border-dashed' : ''}`
                        : 'border-border bg-background text-muted-foreground'
                  }`}
                >
                  {fait ? <Check className="h-3.5 w-3.5" /> : i + 1}
                </div>
                <span className={`mt-1.5 text-[11px] leading-tight ${actif ? 'font-semibold text-primary' : fait ? 'text-foreground' : 'text-muted-foreground'}`}>
                  {actif && partiel ? statutLabel : e.label}
                </span>
              </div>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Petits composants                                                           */
/* -------------------------------------------------------------------------- */

function InfoItem({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="text-sm font-medium break-words">{children ?? '—'}</div>
    </div>
  );
}

function SectionTitle({ icon: Icon, children, action }: { icon: React.ComponentType<{ className?: string }>; children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <CardHeader className="pb-3 flex flex-row items-center justify-between gap-2 space-y-0">
      <CardTitle className="text-base flex items-center gap-2"><Icon className="h-4 w-4" /> {children}</CardTitle>
      {action}
    </CardHeader>
  );
}

/* -------------------------------------------------------------------------- */
/* Page                                                                        */
/* -------------------------------------------------------------------------- */

export default function SupplierOrderDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = Number(params?.id);
  const { isGerant, loading: userLoading } = useCurrentUser();

  const [order, setOrder] = useState<any | null>(null);
  const [loading, setLoading] = useState(true);
  const [introuvable, setIntrouvable] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);
  const [acting, setActing] = useState<string | null>(null);

  const [dlg, setDlg] = useState<null | 'paiement' | 'frais' | 'expedier' | 'transport' | 'arriver' | 'reception' | 'finaliser' | 'modifier'>(null);

  const load = useCallback(async (silent = false) => {
    if (!Number.isFinite(id) || id <= 0) { setIntrouvable(true); setLoading(false); return; }
    if (!silent) setLoading(true);
    try {
      const data = await djangoClient.suppliers.getById(id);
      setOrder(data);
      setIntrouvable(false);
      setErreur(null);
    } catch (err) {
      const msg = messageErreur(err, 'Erreur de chargement');
      // DRF get_object → 404 {"detail": "No SupplierOrder matches the given query."} (ou traduit).
      if (/404|introuvable|not found|matches the given query|ne correspond|pas trouvé/i.test(msg)) {
        setIntrouvable(true);
      } else {
        setErreur(msg);
        if (!silent) toast.error(msg);
      }
    } finally {
      if (!silent) setLoading(false);
    }
  }, [id]);

  // Chargement réservé au gérant (l'API renvoie 403 sinon).
  useEffect(() => { if (isGerant) load(); }, [load, isGerant]);
  useRealtimeRefresh(['supplier_order'], () => { if (isGerant) load(true); });

  const action = async (nom: string, fn: () => Promise<any>, succes: string) => {
    setActing(nom);
    try {
      await fn();
      toast.success(succes);
      await load(true);
    } catch (err) {
      toast.error(messageErreur(err, 'Action impossible'));
    } finally {
      setActing(null);
    }
  };

  const supprimerPaiement = (p: any) => {
    if (!window.confirm(`Supprimer le paiement de ${fmtDevise(p.montant, p.devise)} du ${fmtDate(p.date)} ?`)) return;
    action(`paiement-${p.id}`, () => djangoClient.suppliers.deletePayment(order.id, p.id), 'Paiement supprimé');
  };
  const supprimerFrais = (f: any) => {
    if (!window.confirm(`Supprimer le frais « ${f.type_label} » de ${fmtDevise(f.montant, f.devise)} ?`)) return;
    action(`frais-${f.id}`, () => djangoClient.suppliers.deleteFee(order.id, f.id), 'Frais supprimé — coût recalculé');
  };

  /* ---- Allocation manuelle (colonne éditable) ---- */
  const [allocEdit, setAllocEdit] = useState<Record<number, string>>({});
  const [allocDirty, setAllocDirty] = useState(false);
  useEffect(() => {
    if (!order) return;
    const init: Record<number, string> = {};
    for (const l of order.lines || []) init[l.id] = l.allocation_manuelle_mga !== null && l.allocation_manuelle_mga !== undefined ? String(Number(l.allocation_manuelle_mga)) : '';
    setAllocEdit(init);
    setAllocDirty(false);
  }, [order]);

  const enregistrerAllocation = () =>
    action(
      'allocation',
      () => djangoClient.suppliers.update(order.id, {
        lines: (order.lines || []).map((l: any) => ({
          id: l.id,
          product_variant: l.product_variant,
          quantite: l.quantite,
          prix_unitaire: l.prix_unitaire,
          allocation_manuelle_mga: allocEdit[l.id] === '' || allocEdit[l.id] === undefined ? null : Number(allocEdit[l.id]),
        })),
      }),
      'Allocation des frais enregistrée',
    );

  const totalAllocSaisi = useMemo(
    () => Object.values(allocEdit).reduce((s, v) => s + (Number(v) || 0), 0),
    [allocEdit],
  );

  /* ---- Rendu ---- */

  if (!userLoading && !isGerant) {
    return (
      <div className="p-6 text-center text-sm text-muted-foreground">Cette page est réservée au gérant.</div>
    );
  }

  if (loading) {
    return (
      <div className="p-4 sm:p-6 space-y-4">
        <Skeleton className="h-9 w-64" />
        <Skeleton className="h-16 w-full" />
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <Skeleton className="h-48 w-full" />
          <Skeleton className="h-48 w-full" />
        </div>
        <Skeleton className="h-72 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (introuvable || !order) {
    return (
      <div className="p-4 sm:p-6 space-y-4">
        <Button variant="ghost" size="sm" onClick={() => router.push('/suppliers')}><ArrowLeft className="h-4 w-4 mr-1" /> Retour</Button>
        <Card>
          <CardContent className="py-16 text-center space-y-2">
            <Search className="h-8 w-8 mx-auto text-muted-foreground" />
            <p className="font-medium">Approvisionnement introuvable</p>
            <p className="text-sm text-muted-foreground">{erreur || 'Il a peut-être été supprimé ou n\'appartient pas à votre magasin.'}</p>
            <Button variant="outline" size="sm" onClick={() => load()}><RefreshCw className="h-4 w-4 mr-1" /> Réessayer</Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  const statut: string = order.statut;
  const si = statutInfo(statut);
  const finalise = statut === 'COUT_FINALISE';
  const modifiable = !finalise;
  const enReception = (STATUTS_RECEPTION as string[]).includes(statut);
  const devise: string = order.devise || 'MGA';
  const taux = Number(order.taux_change) || 1;
  const lines: any[] = order.lines || [];
  const payments: any[] = order.payments || [];
  const fees: any[] = order.fees || [];
  const manuel = order.methode_allocation === 'MANUEL';
  const totalDevise = lines.reduce((s, l) => s + (Number(l.total_fournisseur_devise) || 0), 0);
  const totalFournisseurAr = Number(order.valeur_achat_mga) || 0;
  const pctPaye = Math.min(100, Math.max(0, Number(order.pourcentage_paye) || 0));
  const aTransport = !!(order.date_expedition || order.transporteur || order.mode_transport || order.tracking || order.lieu_depart || order.date_arrivee);
  const fraisHistoriques = [
    { key: 'fret', label: 'Transport / expédition', montant: Number(order.fret_import) || 0 },
    { key: 'douane', label: 'Douane', montant: Number(order.douane) || 0 },
  ].filter((f) => f.montant > 0);
  const totalFrais = Number(order.total_frais_mga) || 0;
  const totalAlloue = lines.reduce((s, l) => s + (Number(l.frais_alloues_mga) || 0), 0);

  const busy = acting !== null;

  return (
    <div className="p-4 sm:p-6 space-y-5">
      {/* En-tête */}
      <div className="space-y-4">
        <div className="flex flex-col lg:flex-row lg:items-start justify-between gap-3">
          <div className="flex items-start gap-2 min-w-0">
            <Button variant="ghost" size="icon" className="shrink-0" onClick={() => router.push('/suppliers')} title="Retour">
              <ArrowLeft className="h-4 w-4" />
            </Button>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="text-2xl font-bold tracking-tight">{order.numero}</h1>
                <Badge className={si.color}>{si.label}</Badge>
                {finalise && <Badge variant="outline" className="gap-1"><Lock className="h-3 w-3" /> Figé</Badge>}
              </div>
              <p className="text-sm text-muted-foreground mt-0.5">
                {order.supplier ? (
                  <Link href={`/suppliers?fournisseur=${order.supplier}`} className="font-medium text-foreground hover:underline">
                    {order.supplier_nom}
                  </Link>
                ) : (
                  <span>Fournisseur non renseigné</span>
                )}
                {' · '}du {fmtDate(order.date)}
                {order.magasin_name ? ` · ${order.magasin_name}` : ''}
              </p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="outline" size="icon" onClick={() => load()} title="Actualiser" disabled={busy}>
              <RefreshCw className={`h-4 w-4 ${busy ? 'animate-spin' : ''}`} />
            </Button>
            {modifiable && (
              <Button variant="outline" onClick={() => setDlg('modifier')} disabled={busy}>
                <Pencil className="h-4 w-4 mr-1.5" /> Modifier
              </Button>
            )}
            {actionPossible('commander', statut) && (
              <Button onClick={() => action('commander', () => djangoClient.suppliers.commander(order.id), 'Commande passée au fournisseur')} disabled={busy}>
                <ShoppingCart className="h-4 w-4 mr-1.5" /> Commander
              </Button>
            )}
            {actionPossible('preparer', statut) && (
              <Button variant="outline" onClick={() => action('preparer', () => djangoClient.suppliers.preparer(order.id), 'Marchandise préparée par le fournisseur')} disabled={busy}>
                <PackageCheck className="h-4 w-4 mr-1.5" /> Marquer préparé
              </Button>
            )}
            {actionPossible('expedier', statut) && (
              <Button variant={statut === 'PREPARE' ? 'default' : 'outline'} onClick={() => setDlg('expedier')} disabled={busy}>
                <Ship className="h-4 w-4 mr-1.5" /> Expédier
              </Button>
            )}
            {actionPossible('arriver', statut) && (
              <Button variant={statut === 'EN_TRANSIT' ? 'default' : 'outline'} onClick={() => setDlg('arriver')} disabled={busy}>
                <Anchor className="h-4 w-4 mr-1.5" /> Marquer arrivé
              </Button>
            )}
            {actionPossible('receptionner', statut) && (
              <Button variant={statut === 'ARRIVE' || statut === 'PARTIELLEMENT_RECU' ? 'default' : 'outline'} onClick={() => setDlg('reception')} disabled={busy}>
                <Boxes className="h-4 w-4 mr-1.5" /> {statut === 'PARTIELLEMENT_RECU' ? 'Réceptionner le reste' : 'Réceptionner'}
              </Button>
            )}
            {actionPossible('finaliser', statut) && (
              <Button onClick={() => setDlg('finaliser')} disabled={busy}>
                <Lock className="h-4 w-4 mr-1.5" /> Finaliser le coût
              </Button>
            )}
          </div>
        </div>

        <Card>
          <CardContent className="pt-5 pb-3">
            <WorkflowTimeline statut={statut} statutLabel={si.label} />
          </CardContent>
        </Card>
      </div>

      {/* Indicateurs clés */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Card><CardContent className="p-4">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Achat fournisseur</p>
          <p className="text-lg font-bold tabular-nums">{fmtAr(totalFournisseurAr)}</p>
          {devise !== 'MGA' && <p className="text-xs text-muted-foreground">{fmtDevise(totalDevise, devise)}</p>}
        </CardContent></Card>
        <Card><CardContent className="p-4">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Frais d'importation</p>
          <p className="text-lg font-bold tabular-nums">{fmtAr(totalFrais)}</p>
          <p className="text-xs text-muted-foreground">{fees.length + fraisHistoriques.length} ligne(s)</p>
        </CardContent></Card>
        <Card><CardContent className="p-4">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Valeur réelle</p>
          <p className="text-lg font-bold tabular-nums">{fmtAr(order.cout_total)}</p>
          <p className="text-xs text-muted-foreground">{fmtAr(order.cout_unitaire)} / pièce</p>
        </CardContent></Card>
        <Card><CardContent className="p-4">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Reste à payer</p>
          <p className={`text-lg font-bold tabular-nums ${Number(order.reste_a_payer_mga) > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-emerald-600 dark:text-emerald-400'}`}>
            {fmtAr(order.reste_a_payer_mga)}
          </p>
          <p className="text-xs text-muted-foreground">{pctPaye.toFixed(0)} % payé</p>
        </CardContent></Card>
      </div>

      {/* Synthèse du coût réel */}
      <CostSummary order={order} />

      {/* Informations générales + Transport */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Card>
          <SectionTitle icon={Info}>Informations générales</SectionTitle>
          <CardContent className="grid grid-cols-2 gap-x-4 gap-y-3">
            <InfoItem label="Référence">{order.numero}</InfoItem>
            <InfoItem label="Fournisseur">
              {order.supplier ? <Link href={`/suppliers?fournisseur=${order.supplier}`} className="hover:underline">{order.supplier_nom}</Link> : '—'}
            </InfoItem>
            <InfoItem label="Date de commande">{fmtDate(order.date)}</InfoItem>
            <InfoItem label="Statut"><Badge className={si.color}>{si.label}</Badge></InfoItem>
            <InfoItem label="Devise / taux">
              {devise}{devise !== 'MGA' ? ` · 1 ${devise} = ${fmtTaux(taux)}` : ''}
            </InfoItem>
            <InfoItem label="Destination">{order.destination || '—'}</InfoItem>
            <InfoItem label="Méthode d'allocation des frais">{labelOf(METHODES_ALLOCATION, order.methode_allocation)}</InfoItem>
            <InfoItem label="Magasin">{order.magasin_name || '—'}</InfoItem>
            <div className="col-span-2">
              <InfoItem label="Description">{order.description || '—'}</InfoItem>
            </div>
            {(order.received_at || order.finalise_at) && (
              <>
                {order.received_at && <InfoItem label="Réceptionné le">{fmtAppDateTime(order.received_at)}</InfoItem>}
                {order.finalise_at && <InfoItem label="Coût finalisé le">{fmtAppDateTime(order.finalise_at)}</InfoItem>}
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <SectionTitle
            icon={Truck}
            action={modifiable && (
              <Button variant="outline" size="sm" onClick={() => setDlg('transport')} disabled={busy}>
                <Pencil className="h-3.5 w-3.5 mr-1" /> Modifier
              </Button>
            )}
          >
            Transport
          </SectionTitle>
          <CardContent>
            {!aTransport ? (
              <p className="text-sm text-muted-foreground py-6 text-center">Aucune information de transport.</p>
            ) : (
              <div className="grid grid-cols-2 gap-x-4 gap-y-3">
                <InfoItem label="Lieu de départ">{order.lieu_depart || '—'}</InfoItem>
                <InfoItem label="Date d'expédition">{fmtDate(order.date_expedition)}</InfoItem>
                <InfoItem label="Transporteur">{order.transporteur || '—'}</InfoItem>
                <InfoItem label="Mode">{order.mode_transport ? labelOf(MODES_TRANSPORT, order.mode_transport) : '—'}</InfoItem>
                <InfoItem label="Numéro de suivi">{order.tracking ? <span className="font-mono">{order.tracking}</span> : '—'}</InfoItem>
                <InfoItem label="Destination">{order.destination || '—'}</InfoItem>
                <InfoItem label="Date d'arrivée">{fmtDate(order.date_arrivee)}</InfoItem>
                <InfoItem label="Statut"><Badge className={si.color}>{si.label}</Badge></InfoItem>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Produits */}
      <Card>
        <SectionTitle
          icon={Boxes}
          action={manuel && modifiable && allocDirty && (
            <Button size="sm" onClick={enregistrerAllocation} disabled={busy}>
              <Save className="h-3.5 w-3.5 mr-1" /> Enregistrer l'allocation
            </Button>
          )}
        >
          Produits <span className="text-sm font-normal text-muted-foreground">({lines.length} ligne(s) · {order.total_recu ?? 0} / {lines.reduce((s, l) => s + Number(l.quantite || 0), 0)} pièces reçues)</span>
        </SectionTitle>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Produit</TableHead>
                  <TableHead>Variante</TableHead>
                  <TableHead className="text-right">Qté commandée</TableHead>
                  <TableHead className="text-right">Qté reçue</TableHead>
                  <TableHead className="text-right">Prix unitaire ({devise})</TableHead>
                  <TableHead className="text-right">Total fournisseur ({devise})</TableHead>
                  <TableHead className="text-right">Valeur d'achat (Ar)</TableHead>
                  <TableHead className="text-right">Frais alloués (Ar)</TableHead>
                  <TableHead className="text-right">Coût de revient unit. (Ar)</TableHead>
                  <TableHead className="text-right">Prix de vente (Ar)</TableHead>
                  <TableHead className="text-right">Marge unit. (Ar)</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {lines.length === 0 ? (
                  <TableRow><TableCell colSpan={11} className="text-center text-muted-foreground py-8">Aucune ligne.</TableCell></TableRow>
                ) : lines.map((l) => {
                  const marge = Number(l.marge_unitaire) || 0;
                  const reste = Number(l.reste_a_recevoir ?? Math.max(Number(l.quantite) - Number(l.quantite_recue || 0), 0));
                  return (
                    <TableRow key={l.id}>
                      <TableCell className="font-medium whitespace-nowrap">{l.brand_name ? `${l.brand_name} ` : ''}{l.reference_name}</TableCell>
                      <TableCell>{l.couleur || '—'}</TableCell>
                      <TableCell className="text-right tabular-nums">{l.quantite}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {l.quantite_recue || 0}
                        {reste > 0 && <span className="block text-[11px] text-amber-600 dark:text-amber-400">reste {reste}</span>}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{fmtDevise(l.prix_unitaire, devise)}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmtDevise(l.total_fournisseur_devise, devise)}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmtAr(l.valeur_achat_mga)}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {manuel && modifiable ? (
                          <Input
                            type="number"
                            min={0}
                            step="0.01"
                            className="h-8 w-32 ml-auto text-right"
                            value={allocEdit[l.id] ?? ''}
                            placeholder="0"
                            onChange={(e) => { setAllocEdit((prev) => ({ ...prev, [l.id]: e.target.value })); setAllocDirty(true); }}
                          />
                        ) : fmtAr(l.frais_alloues_mga)}
                      </TableCell>
                      <TableCell className="text-right tabular-nums font-semibold">{fmtAr(l.cout_unitaire_calcule)}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmtAr(l.prix_vente)}</TableCell>
                      <TableCell className={`text-right tabular-nums font-medium ${marge < 0 ? 'text-red-600 dark:text-red-400' : 'text-emerald-700 dark:text-emerald-400'}`}>
                        {fmtAr(marge)}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
          {manuel && modifiable && (
            <div className={`px-4 py-2 border-t text-xs flex flex-wrap justify-between gap-2 ${Math.abs(totalAllocSaisi - totalFrais) > 0.5 ? 'text-amber-700 dark:text-amber-300' : 'text-muted-foreground'}`}>
              <span>Allocation manuelle : {fmtAr(totalAllocSaisi)} répartis sur {fmtAr(totalFrais)} de frais.</span>
              {Math.abs(totalAllocSaisi - totalFrais) > 0.5 && <span>Écart : {fmtAr(totalFrais - totalAllocSaisi)}</span>}
            </div>
          )}
          {!manuel && lines.length > 0 && (
            <div className="px-4 py-2 border-t text-xs text-muted-foreground">
              Frais répartis automatiquement ({labelOf(METHODES_ALLOCATION, order.methode_allocation).toLowerCase()}) : {fmtAr(totalAlloue)}.
              {enReception ? ' Calcul sur les quantités reçues.' : ' Calcul sur les quantités commandées.'}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Paiements + Frais */}
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        {/* Paiements */}
        <Card>
          <SectionTitle
            icon={Wallet}
            action={modifiable && (
              <Button size="sm" onClick={() => setDlg('paiement')} disabled={busy}>
                <Plus className="h-3.5 w-3.5 mr-1" /> Ajouter un paiement
              </Button>
            )}
          >
            Paiements fournisseur
          </SectionTitle>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
              <div>
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Total fournisseur</p>
                <p className="font-semibold tabular-nums">{fmtAr(totalFournisseurAr)}</p>
                {devise !== 'MGA' && <p className="text-xs text-muted-foreground tabular-nums">{fmtDevise(totalDevise, devise)}</p>}
              </div>
              <div>
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Total payé</p>
                <p className="font-semibold tabular-nums text-emerald-700 dark:text-emerald-400">{fmtAr(order.total_paye_mga)}</p>
                {devise !== 'MGA' && <p className="text-xs text-muted-foreground tabular-nums">{fmtDevise(order.total_paye_devise, devise)}</p>}
              </div>
              <div>
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Reste à payer</p>
                <p className={`font-semibold tabular-nums ${Number(order.reste_a_payer_mga) > 0 ? 'text-amber-600 dark:text-amber-400' : ''}`}>{fmtAr(order.reste_a_payer_mga)}</p>
              </div>
              <div>
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Payé</p>
                <p className="font-semibold tabular-nums">{pctPaye.toFixed(0)} %</p>
                <Progress value={pctPaye} className="h-1.5 mt-1.5" />
              </div>
            </div>

            {payments.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-6">Aucun paiement enregistré.</p>
            ) : (
              <ol className="relative border-l ml-2 space-y-4">
                {payments.map((p) => (
                  <li key={p.id} className="ml-4">
                    <span className="absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full bg-primary ring-4 ring-background" />
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div className="text-sm">
                        <p className="text-xs text-muted-foreground">{fmtDate(p.date)} · {p.type_label}</p>
                        <p className="font-semibold tabular-nums">
                          {fmtDevise(p.montant, p.devise)}
                          {p.devise !== 'MGA' && <span className="font-normal text-muted-foreground"> ≈ {fmtAr(p.montant_mga)}</span>}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {p.methode_label}
                          {p.reference ? ` · réf. ${p.reference}` : ''}
                          {p.created_by_name ? ` · par ${p.created_by_name}` : ''}
                        </p>
                        {p.commentaire && <p className="text-xs italic mt-0.5">{p.commentaire}</p>}
                      </div>
                      {modifiable && (
                        <Button size="icon" variant="ghost" onClick={() => supprimerPaiement(p)} disabled={busy} title="Supprimer">
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      )}
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </CardContent>
        </Card>

        {/* Frais */}
        <Card>
          <SectionTitle
            icon={Receipt}
            action={modifiable && (
              <Button size="sm" onClick={() => setDlg('frais')} disabled={busy}>
                <Plus className="h-3.5 w-3.5 mr-1" /> Ajouter un frais
              </Button>
            )}
          >
            Frais d'importation
          </SectionTitle>
          <CardContent className="space-y-4">
            {(order.frais_par_type || []).length > 0 && (
              <div className="flex flex-wrap gap-2">
                {(order.frais_par_type || []).map((f: any) => (
                  <Badge key={f.type} variant="secondary" className="tabular-nums font-normal">
                    {f.label} : <span className="font-semibold ml-1">{fmtAr(f.montant_mga)}</span>
                  </Badge>
                ))}
                <Badge className="tabular-nums">Total : {fmtAr(totalFrais)}</Badge>
              </div>
            )}
            {fees.length === 0 && fraisHistoriques.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-6">Aucun frais enregistré.</p>
            ) : (
              <div className="overflow-x-auto rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Type</TableHead>
                      <TableHead>Date</TableHead>
                      <TableHead className="text-right">Montant</TableHead>
                      <TableHead className="text-right">≈ Ar</TableHead>
                      <TableHead>Prestataire</TableHead>
                      <TableHead>Description</TableHead>
                      <TableHead>Auteur</TableHead>
                      <TableHead className="w-10" />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {fraisHistoriques.map((f) => (
                      <TableRow key={f.key} className="text-muted-foreground">
                        <TableCell>{f.label} <Badge variant="outline" className="ml-1 text-[10px]">historique</Badge></TableCell>
                        <TableCell>{fmtDate(order.date)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmtAr(f.montant)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmtAr(f.montant)}</TableCell>
                        <TableCell>—</TableCell>
                        <TableCell>Montant global saisi à la création</TableCell>
                        <TableCell>—</TableCell>
                        <TableCell />
                      </TableRow>
                    ))}
                    {fees.map((f) => (
                      <TableRow key={f.id}>
                        <TableCell className="font-medium whitespace-nowrap">{f.type_label}</TableCell>
                        <TableCell className="whitespace-nowrap">{fmtDate(f.date)}</TableCell>
                        <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtDevise(f.montant, f.devise)}</TableCell>
                        <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtAr(f.montant_mga)}</TableCell>
                        <TableCell>{f.prestataire || '—'}</TableCell>
                        <TableCell className="max-w-[200px] truncate" title={f.description}>{f.description || '—'}</TableCell>
                        <TableCell className="whitespace-nowrap">{f.created_by_name || '—'}</TableCell>
                        <TableCell>
                          {modifiable && (
                            <Button size="icon" variant="ghost" onClick={() => supprimerFrais(f)} disabled={busy} title="Supprimer">
                              <Trash2 className="h-4 w-4 text-red-500" />
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Dialogs */}
      <PaymentDialog open={dlg === 'paiement'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
      <FeeDialog open={dlg === 'frais'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
      <TransportDialog mode="expedier" open={dlg === 'expedier'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
      <TransportDialog mode="modifier" open={dlg === 'transport'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
      <ArriverDialog open={dlg === 'arriver'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
      <ReceptionDialog open={dlg === 'reception'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
      <FinaliserDialog open={dlg === 'finaliser'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
      <EditOrderDialog open={dlg === 'modifier'} onOpenChange={(o) => !o && setDlg(null)} order={order} onSaved={() => load(true)} />
    </div>
  );
}
