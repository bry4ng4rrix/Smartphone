'use client';

/**
 * Module Fournisseur — approvisionnements (§ demande « remplacement »).
 *
 * Un approvisionnement = 1 fournisseur + 1 produit + 1 quantité + N
 * paiements + 1 expédition + 1 Frais + Douane + 1 coût total + 1 coût par
 * pièce. Onglet « Approvisionnements » (cartes § 16) et onglet
 * « Fournisseurs » (fiches). Tous les montants viennent de l'API.
 */
import { Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { useDebouncedValue } from '@/lib/hooks/useDebouncedValue';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { KpiCard, KpiGrid } from '@/components/reports/kpi-card';
import { Building2, ClipboardList, Coins, ExternalLink, Package, Pencil, Plus, Receipt, RefreshCw, Search, Ship, Trash2, Wallet } from 'lucide-react';
import { toast } from 'sonner';
import { SupplierFormDialog } from '@/components/suppliers/supplier-form-dialog';
import { SupplierOrderCreateDialog } from '@/components/suppliers/supplier-order-create-dialog';
import { CostSummary } from '@/components/suppliers/cost-summary';
import { STATUTS, fmtAr, fmtDate, fmtDevise, fmtNombre, messageErreur, statutInfo } from '@/components/suppliers/supplier-status';

const TOUS = 'TOUS';
const PAR_PAGE = 12;
type Onglet = 'approvisionnements' | 'fournisseurs';

export default function SuppliersPage() {
  return (
    <Suspense fallback={<div className="p-4 sm:p-6"><Skeleton className="h-64 w-full" /></div>}>
      <SuppliersContent />
    </Suspense>
  );
}

function SuppliersContent() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const router = useRouter();
  const fournisseurUrl = useSearchParams().get('fournisseur');

  const [onglet, setOnglet] = useState<Onglet>('approvisionnements');
  const [kpis, setKpis] = useState<any | null>(null);
  const [kpisLoading, setKpisLoading] = useState(true);

  const [fournisseurs, setFournisseurs] = useState<any[]>([]);
  const [fournisseursLoading, setFournisseursLoading] = useState(true);
  const [rechercheFournisseur, setRechercheFournisseur] = useState('');
  const rechercheFournisseurD = useDebouncedValue(rechercheFournisseur, 300);

  const [appros, setAppros] = useState<any[]>([]);
  const [approsLoading, setApprosLoading] = useState(true);
  const [filtreStatut, setFiltreStatut] = useState(TOUS);
  const [filtreFournisseur, setFiltreFournisseur] = useState(fournisseurUrl && /^\d+$/.test(fournisseurUrl) ? fournisseurUrl : TOUS);
  const [rechercheAppro, setRechercheAppro] = useState('');
  const rechercheApproD = useDebouncedValue(rechercheAppro, 300);
  const [page, setPage] = useState(1);

  const [formOpen, setFormOpen] = useState(false);
  const [formSupplier, setFormSupplier] = useState<any | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [createSupplier, setCreateSupplier] = useState<any | null>(null);
  const [ficheId, setFicheId] = useState<number | null>(null);

  const chargerKpis = useCallback(async (silent = false) => {
    if (!silent) setKpisLoading(true);
    try { setKpis(await djangoClient.suppliers.kpis()); } catch { /* KPI facultatifs */ } finally { setKpisLoading(false); }
  }, []);
  const chargerFournisseurs = useCallback(async (silent = false) => {
    if (!silent) setFournisseursLoading(true);
    try { setFournisseurs(await djangoClient.suppliers.suppliersList(rechercheFournisseurD ? { search: rechercheFournisseurD } : undefined)); }
    catch (e) { toast.error(messageErreur(e, 'Erreur de chargement des fournisseurs')); }
    finally { setFournisseursLoading(false); }
  }, [rechercheFournisseurD]);
  const chargerAppros = useCallback(async (silent = false) => {
    if (!silent) setApprosLoading(true);
    try {
      setAppros(await djangoClient.suppliers.list({
        statut: filtreStatut === TOUS ? undefined : filtreStatut,
        supplier: filtreFournisseur === TOUS ? undefined : Number(filtreFournisseur),
        search: rechercheApproD || undefined,
      }));
    } catch (e) { toast.error(messageErreur(e, 'Erreur de chargement des approvisionnements')); }
    finally { setApprosLoading(false); }
  }, [filtreStatut, filtreFournisseur, rechercheApproD]);

  useEffect(() => { if (isGerant) { chargerKpis(); } }, [isGerant, chargerKpis]);
  useEffect(() => { if (isGerant) chargerFournisseurs(); }, [isGerant, chargerFournisseurs]);
  useEffect(() => { if (isGerant) { setPage(1); chargerAppros(); } }, [isGerant, chargerAppros]);
  const toutRecharger = useCallback((silent = false) => { chargerKpis(silent); chargerFournisseurs(silent); chargerAppros(silent); }, [chargerKpis, chargerFournisseurs, chargerAppros]);
  useRealtimeRefresh(['supplier_order', 'stock_movement'], () => { if (isGerant) toutRecharger(true); });

  const ouvrirAppro = (id: number) => router.push(`/suppliers/${id}`);

  const supprimerFournisseur = async (s: any) => {
    const utilise = Number(s.nb_approvisionnements || 0) > 0;
    if (!window.confirm(utilise ? `« ${s.nom} » a ${fmtNombre(s.nb_approvisionnements)} approvisionnement(s) : il sera désactivé (historique conservé). Continuer ?` : `Supprimer définitivement le fournisseur « ${s.nom} » ?`)) return;
    try {
      await djangoClient.suppliers.supplierDelete(s.id);
      toast.success(utilise ? 'Fournisseur désactivé' : 'Fournisseur supprimé');
      if (ficheId === s.id) setFicheId(null);
      toutRecharger(true);
    } catch (e) { toast.error(messageErreur(e, 'Suppression impossible')); }
  };

  const totalPages = Math.max(1, Math.ceil(appros.length / PAR_PAGE));
  const pageCourante = Math.min(page, totalPages);
  const approsPage = useMemo(() => appros.slice((pageCourante - 1) * PAR_PAGE, pageCourante * PAR_PAGE), [appros, pageCourante]);

  if (userLoading) return <div className="p-4 sm:p-6 space-y-4"><Skeleton className="h-10 w-64" /><Skeleton className="h-64 w-full" /></div>;
  if (!isGerant) return <div className="p-6"><h1 className="text-2xl font-bold">Fournisseurs</h1><p className="text-sm text-muted-foreground mt-2">Accès réservé au gérant.</p></div>;

  return (
    <div className="p-4 sm:p-6 space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Fournisseurs</h1>
          <p className="text-sm text-muted-foreground">Approvisionnements : un produit par envoi, paiements au taux du jour, Frais + Douane, coût de revient par pièce.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={() => toutRecharger()}><RefreshCw className="h-4 w-4 mr-1" /> Actualiser</Button>
          <Button variant="outline" size="sm" onClick={() => { setFormSupplier(null); setFormOpen(true); }}><Building2 className="h-4 w-4 mr-1" /> Nouveau fournisseur</Button>
          <Button size="sm" onClick={() => { setCreateSupplier(null); setCreateOpen(true); }}><Plus className="h-4 w-4 mr-1" /> Nouvel approvisionnement</Button>
        </div>
      </div>

      <KpiGrid cols={4}>
        <KpiCard loading={kpisLoading} titre="Approvisionnements en cours" icon={ClipboardList} valeur={fmtNombre(kpis?.nb_en_cours)} detail={`${fmtNombre(kpis?.nb_approvisionnements)} au total · ${fmtNombre(kpis?.nb_finalises)} finalisé(s)`} />
        <KpiCard loading={kpisLoading} titre="En transit" icon={Ship} valeur={fmtNombre(kpis?.en_transit?.nb)} detail={`${fmtAr(kpis?.en_transit?.valeur_mga)} · ${fmtNombre(kpis?.a_finaliser)} arrivé(s) à finaliser`} />
        <KpiCard loading={kpisLoading} titre="Total payé aux fournisseurs" icon={Coins} valeur={fmtAr(kpis?.total_paye_mga)} detail={`Frais + Douane : ${fmtAr(kpis?.total_frais_douane_mga)}`} />
        <KpiCard loading={kpisLoading} titre="Coût moyen par pièce" icon={Wallet} valeur={kpis?.cout_moyen_par_piece_mga != null ? fmtAr(kpis.cout_moyen_par_piece_mga) : '—'} detail={`${fmtNombre(kpis?.nb_fournisseurs_actifs)} fournisseur(s) actif(s)`} />
      </KpiGrid>

      <Tabs value={onglet} onValueChange={(v) => setOnglet(v as Onglet)}>
        <TabsList>
          <TabsTrigger value="approvisionnements"><Package className="h-4 w-4 mr-1" /> Approvisionnements</TabsTrigger>
          <TabsTrigger value="fournisseurs"><Building2 className="h-4 w-4 mr-1" /> Fournisseurs</TabsTrigger>
        </TabsList>

        <TabsContent value="approvisionnements" className="space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative flex-1 min-w-[220px]">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input className="pl-8" placeholder="N°, produit, fournisseur, tracking, colis…" value={rechercheAppro} onChange={(e) => setRechercheAppro(e.target.value)} />
            </div>
            <Select value={filtreStatut} onValueChange={setFiltreStatut}>
              <SelectTrigger className="w-[190px]"><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value={TOUS}>Tous les statuts</SelectItem>{STATUTS.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
            </Select>
            <Select value={filtreFournisseur} onValueChange={setFiltreFournisseur}>
              <SelectTrigger className="w-[200px]"><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value={TOUS}>Tous les fournisseurs</SelectItem>{fournisseurs.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.nom}</SelectItem>)}</SelectContent>
            </Select>
            {(filtreStatut !== TOUS || filtreFournisseur !== TOUS || rechercheAppro) && <Button variant="ghost" size="sm" onClick={() => { setFiltreStatut(TOUS); setFiltreFournisseur(TOUS); setRechercheAppro(''); }}>Réinitialiser</Button>}
            <span className="text-xs text-muted-foreground ml-auto">{fmtNombre(appros.length)} approvisionnement(s)</span>
          </div>

          {approsLoading ? (
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-80 w-full" />)}</div>
          ) : appros.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-sm text-muted-foreground">Aucun approvisionnement. Créez-en un : un fournisseur, un produit, une quantité.</CardContent></Card>
          ) : (
            <>
              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                {approsPage.map((o) => (
                  <div key={o.id} className="group cursor-pointer" onClick={() => ouvrirAppro(o.id)} role="link" tabIndex={0} onKeyDown={(e) => { if (e.key === 'Enter') ouvrirAppro(o.id); }}>
                    <CostSummary order={o} compact />
                    <div className="flex justify-end -mt-9 mr-3 relative"><Button variant="ghost" size="sm" className="h-7 text-xs opacity-70 group-hover:opacity-100" onClick={(e) => { e.stopPropagation(); ouvrirAppro(o.id); }}>Ouvrir <ExternalLink className="h-3 w-3 ml-1" /></Button></div>
                  </div>
                ))}
              </div>
              {totalPages > 1 && (
                <div className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">Page {pageCourante} / {totalPages}</span>
                  <div className="flex gap-2">
                    <Button variant="outline" size="sm" disabled={pageCourante <= 1} onClick={() => setPage(pageCourante - 1)}>Précédent</Button>
                    <Button variant="outline" size="sm" disabled={pageCourante >= totalPages} onClick={() => setPage(pageCourante + 1)}>Suivant</Button>
                  </div>
                </div>
              )}
            </>
          )}
        </TabsContent>

        <TabsContent value="fournisseurs" className="space-y-3">
          <div className="relative max-w-md">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input className="pl-8" placeholder="Nom, pays, contact, e-mail…" value={rechercheFournisseur} onChange={(e) => setRechercheFournisseur(e.target.value)} />
          </div>
          {fournisseursLoading ? (
            <Skeleton className="h-48 w-full" />
          ) : fournisseurs.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-sm text-muted-foreground">Aucun fournisseur. Créez une fiche pour y rattacher vos approvisionnements.</CardContent></Card>
          ) : (
            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              {fournisseurs.map((s) => (
                <Card key={s.id} className={!s.actif ? 'opacity-60' : ''}>
                  <CardContent className="p-4 space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <button type="button" className="text-left min-w-0" onClick={() => setFicheId(s.id)}>
                        <p className="font-semibold truncate">{s.nom}{!s.actif && <Badge variant="outline" className="ml-2 text-[10px]">Inactif</Badge>}</p>
                        <p className="text-xs text-muted-foreground truncate">{[s.pays, s.contact, s.telephone].filter(Boolean).join(' · ') || '—'}</p>
                      </button>
                      <div className="flex shrink-0">
                        <Button variant="ghost" size="icon" className="h-8 w-8" title="Modifier" onClick={() => { setFormSupplier(s); setFormOpen(true); }}><Pencil className="h-4 w-4" /></Button>
                        <Button variant="ghost" size="icon" className="h-8 w-8 text-red-600" title="Supprimer" onClick={() => supprimerFournisseur(s)}><Trash2 className="h-4 w-4" /></Button>
                      </div>
                    </div>
                    <div className="grid grid-cols-2 gap-x-3 gap-y-0.5 text-xs">
                      <span className="text-muted-foreground">Approvisionnements</span><span className="text-right tabular-nums">{fmtNombre(s.nb_approvisionnements)} ({fmtNombre(s.nb_en_cours)} en cours)</span>
                      <span className="text-muted-foreground">Total payé</span><span className="text-right tabular-nums">{fmtAr(s.total_paye_mga)}</span>
                      <span className="text-muted-foreground">Reste à payer</span><span className="text-right tabular-nums">{fmtDevise(s.reste_a_payer_devise, s.devise)}</span>
                      <span className="text-muted-foreground">Dernier envoi</span><span className="text-right">{s.dernier_approvisionnement ? `${s.dernier_approvisionnement.numero} · ${statutInfo(s.dernier_approvisionnement.statut).label}` : '—'}</span>
                    </div>
                    <div className="flex gap-2 pt-1">
                      <Button size="sm" variant="outline" className="h-8" onClick={() => { setCreateSupplier(s); setCreateOpen(true); }}><Plus className="h-3.5 w-3.5 mr-1" /> Approvisionnement</Button>
                      <Button size="sm" variant="ghost" className="h-8" onClick={() => { setFiltreFournisseur(String(s.id)); setOnglet('approvisionnements'); }}><Receipt className="h-3.5 w-3.5 mr-1" /> Historique</Button>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>

      <SupplierFormDialog open={formOpen} onOpenChange={setFormOpen} supplier={formSupplier} onSaved={() => toutRecharger(true)} />
      <SupplierOrderCreateDialog open={createOpen} onOpenChange={setCreateOpen} supplierInitial={createSupplier} onCreated={(o) => { toutRecharger(true); if (o?.id) router.push(`/suppliers/${o.id}`); }} />

      <Sheet open={!!ficheId} onOpenChange={(o) => !o && setFicheId(null)}>
        <SheetContent side="right" className="w-full sm:max-w-xl overflow-y-auto">
          <FicheFournisseur supplierId={ficheId} onOuvrirAppro={ouvrirAppro} onNouvelAppro={(s) => { setFicheId(null); setCreateSupplier(s); setCreateOpen(true); }} />
        </SheetContent>
      </Sheet>
    </div>
  );
}

function FicheFournisseur({ supplierId, onOuvrirAppro, onNouvelAppro }: { supplierId: number | null; onOuvrirAppro: (id: number) => void; onNouvelAppro: (s: any) => void }) {
  const [fiche, setFiche] = useState<any | null>(null);
  useEffect(() => {
    if (!supplierId) { setFiche(null); return; }
    let annule = false;
    djangoClient.suppliers.supplierGet(supplierId).then((d) => { if (!annule) setFiche(d); }).catch((e) => toast.error(messageErreur(e, 'Fiche introuvable')));
    return () => { annule = true; };
  }, [supplierId]);
  if (!fiche) return <div className="p-4"><Skeleton className="h-48 w-full" /></div>;
  const appros: any[] = fiche.approvisionnements || [];
  return (
    <>
      <SheetHeader>
        <SheetTitle>{fiche.nom}</SheetTitle>
        <SheetDescription>{[fiche.pays, fiche.contact, fiche.telephone, fiche.email].filter(Boolean).join(' · ') || 'Fiche fournisseur'}</SheetDescription>
      </SheetHeader>
      <div className="space-y-4 mt-4">
        <div className="grid grid-cols-2 gap-2 text-sm">
          <div className="rounded-md border p-2"><p className="text-xs text-muted-foreground">Approvisionnements</p><p className="font-semibold">{fmtNombre(fiche.nb_approvisionnements)}</p></div>
          <div className="rounded-md border p-2"><p className="text-xs text-muted-foreground">Total payé</p><p className="font-semibold tabular-nums">{fmtAr(fiche.total_paye_mga)}</p></div>
          <div className="rounded-md border p-2"><p className="text-xs text-muted-foreground">Frais + Douane</p><p className="font-semibold tabular-nums">{fmtAr(fiche.total_frais_douane_mga)}</p></div>
          <div className="rounded-md border p-2"><p className="text-xs text-muted-foreground">Coût total rendu</p><p className="font-semibold tabular-nums">{fmtAr(fiche.cout_total_mga)}</p></div>
        </div>
        {fiche.adresse && <p className="text-sm">{fiche.adresse}</p>}
        {fiche.notes && <p className="text-sm text-muted-foreground whitespace-pre-line">{fiche.notes}</p>}
        <Button size="sm" onClick={() => onNouvelAppro(fiche)}><Plus className="h-4 w-4 mr-1" /> Nouvel approvisionnement</Button>
        <div>
          <p className="text-sm font-medium mb-2">Historique des envois ({appros.length})</p>
          {appros.length === 0 ? <p className="text-sm text-muted-foreground">Aucun approvisionnement.</p> : (
            <ul className="space-y-1.5">
              {appros.map((o) => {
                const s = statutInfo(o.statut);
                return (
                  <li key={o.id}>
                    <button type="button" className="w-full text-left rounded-md border p-2 hover:bg-muted/50" onClick={() => onOuvrirAppro(o.id)}>
                      <div className="flex items-center justify-between gap-2 text-sm">
                        <span className="font-medium truncate">{o.numero} · {o.produit?.libelle}</span>
                        <Badge className={`${s.color} border-0 text-[10px] whitespace-nowrap`}>{s.label}</Badge>
                      </div>
                      <p className="text-xs text-muted-foreground">{fmtDate(o.date)} · {fmtNombre(o.quantite)} pièces · payé {fmtAr(o.total_paiements_mga)}{o.statut === 'COUT_FINALISE' ? ` · ${fmtAr(o.cout_unitaire_mga)} / pièce` : ''}</p>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </div>
    </>
  );
}
