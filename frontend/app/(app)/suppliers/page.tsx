'use client';

/**
 * Gérant → Fournisseurs.
 *
 * Deux vues : les fiches fournisseur (avec résumé financier) et les
 * approvisionnements (commandes fournisseur, du brouillon jusqu'au coût
 * finalisé). Le détail d'un approvisionnement vit sur `/suppliers/[id]`.
 */

import { Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { useDebouncedValue } from '@/lib/hooks/useDebouncedValue';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Progress } from '@/components/ui/progress';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle,
} from '@/components/ui/sheet';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { KpiCard, KpiGrid } from '@/components/reports/kpi-card';
import {
  Building2, ChevronLeft, ChevronRight, ClipboardList, Coins, ExternalLink, Eye, History,
  MoreHorizontal, PackageCheck, Pencil, Plus, Receipt, RefreshCw, Search, Ship, ShieldAlert,
  Trash2, Truck, Wallet, X,
} from 'lucide-react';
import { toast } from 'sonner';
import { SupplierFormDialog } from '@/components/suppliers/supplier-form-dialog';
import { SupplierOrderCreateDialog } from '@/components/suppliers/supplier-order-create-dialog';
import {
  STATUTS, fmtAr, fmtDate, fmtDevise, fmtNombre, fmtPourcent, fmtTaux, messageErreur, statutInfo,
} from '@/components/suppliers/supplier-status';

const PAR_PAGE = 15;
const TOUS = '__tous__';

type Onglet = 'fournisseurs' | 'approvisionnements';

/** `?fournisseur={id}` (lien depuis la page de détail) → identifiant valide ou `null`. */
function fournisseurDepuisUrl(params: URLSearchParams): string | null {
  const v = params.get('fournisseur');
  return v && /^\d+$/.test(v) ? v : null;
}

export default function SuppliersPage() {
  // `useSearchParams` impose une frontière Suspense au build (même convention que /dashboard).
  return (
    <Suspense fallback={<div className="p-4 sm:p-6"><Skeleton className="h-64 w-full" /></div>}>
      <SuppliersContent />
    </Suspense>
  );
}

function SuppliersContent() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const fournisseurUrl = fournisseurDepuisUrl(searchParams);

  const [onglet, setOnglet] = useState<Onglet>(fournisseurUrl ? 'approvisionnements' : 'fournisseurs');

  // --- Indicateurs -------------------------------------------------------- //
  const [kpis, setKpis] = useState<any | null>(null);
  const [kpisLoading, setKpisLoading] = useState(true);

  // --- Fournisseurs ------------------------------------------------------- //
  const [rechercheFournisseur, setRechercheFournisseur] = useState('');
  const rechercheFournisseurDeb = useDebouncedValue(rechercheFournisseur, 250);
  const [fournisseurs, setFournisseurs] = useState<any[]>([]);
  const [fournisseursLoading, setFournisseursLoading] = useState(true);
  /** Liste complète (non filtrée) pour le Select de l'onglet Approvisionnements. */
  const [tousFournisseurs, setTousFournisseurs] = useState<any[]>([]);

  // --- Approvisionnements ------------------------------------------------- //
  const [filtreStatut, setFiltreStatut] = useState<string>(TOUS);
  const [filtreFournisseur, setFiltreFournisseur] = useState<string>(fournisseurUrl ?? TOUS);
  const [rechercheAppro, setRechercheAppro] = useState('');
  const rechercheApproDeb = useDebouncedValue(rechercheAppro, 250);
  const [appros, setAppros] = useState<any[]>([]);
  const [approsLoading, setApprosLoading] = useState(true);
  const [page, setPage] = useState(1);

  // --- Dialogs / drawers -------------------------------------------------- //
  const [formOpen, setFormOpen] = useState(false);
  const [formSupplier, setFormSupplier] = useState<any | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [createSupplier, setCreateSupplier] = useState<any | null>(null);
  const [ficheId, setFicheId] = useState<number | null>(null);

  // ------------------------------------------------------------------------ //
  // Chargement
  // ------------------------------------------------------------------------ //

  const chargerKpis = useCallback(async (silent = false) => {
    if (!silent) setKpisLoading(true);
    try {
      setKpis(await djangoClient.suppliers.kpis());
    } catch (err) {
      if (!silent) toast.error(messageErreur(err, 'Impossible de charger les indicateurs'));
    } finally {
      if (!silent) setKpisLoading(false);
    }
  }, []);

  const chargerFournisseurs = useCallback(async (silent = false) => {
    if (!silent) setFournisseursLoading(true);
    try {
      const search = rechercheFournisseurDeb.trim();
      const list = await djangoClient.suppliers.suppliersList(search ? { search } : undefined);
      setFournisseurs(list);
      if (!search) setTousFournisseurs(list);
    } catch (err) {
      if (!silent) toast.error(messageErreur(err, 'Impossible de charger les fournisseurs'));
    } finally {
      if (!silent) setFournisseursLoading(false);
    }
  }, [rechercheFournisseurDeb]);

  const chargerTousFournisseurs = useCallback(async () => {
    try {
      setTousFournisseurs(await djangoClient.suppliers.suppliersList());
    } catch {
      /* silencieux : la liste filtrée reste disponible */
    }
  }, []);

  const chargerAppros = useCallback(async (silent = false) => {
    if (!silent) setApprosLoading(true);
    try {
      const list = await djangoClient.suppliers.list({
        supplier: filtreFournisseur !== TOUS ? Number(filtreFournisseur) : undefined,
        statut: filtreStatut !== TOUS ? filtreStatut : undefined,
        search: rechercheApproDeb.trim() || undefined,
      });
      setAppros(list);
    } catch (err) {
      if (!silent) toast.error(messageErreur(err, 'Impossible de charger les approvisionnements'));
    } finally {
      if (!silent) setApprosLoading(false);
    }
  }, [filtreFournisseur, filtreStatut, rechercheApproDeb]);

  useEffect(() => { if (isGerant) chargerKpis(); }, [isGerant, chargerKpis]);
  useEffect(() => { if (isGerant) chargerFournisseurs(); }, [isGerant, chargerFournisseurs]);
  useEffect(() => { if (isGerant) chargerAppros(); }, [isGerant, chargerAppros]);
  useEffect(() => { setPage(1); }, [filtreFournisseur, filtreStatut, rechercheApproDeb]);

  // Navigation vers /suppliers?fournisseur={id} alors que la page est déjà montée
  // (autre fournisseur depuis une page de détail) : on applique le filtre.
  useEffect(() => {
    if (!fournisseurUrl) return;
    setFiltreFournisseur(fournisseurUrl);
    setOnglet('approvisionnements');
  }, [fournisseurUrl]);

  /** Reflète le filtre fournisseur dans l'URL (lien partageable, retour arrière). */
  const ecrireFiltreUrl = useCallback((id: string | null) => {
    const q = new URLSearchParams(searchParams.toString());
    if (id && id !== TOUS) q.set('fournisseur', id); else q.delete('fournisseur');
    const qs = q.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
  }, [router, pathname, searchParams]);

  const changerFiltreFournisseur = (v: string) => { setFiltreFournisseur(v); ecrireFiltreUrl(v); };

  const toutRecharger = useCallback((silent = false) => {
    chargerKpis(silent);
    chargerFournisseurs(silent);
    chargerAppros(silent);
    if (rechercheFournisseurDeb.trim()) chargerTousFournisseurs();
  }, [chargerKpis, chargerFournisseurs, chargerAppros, chargerTousFournisseurs, rechercheFournisseurDeb]);

  useRealtimeRefresh(['supplier_order'], () => toutRecharger(true));

  // ------------------------------------------------------------------------ //
  // Actions
  // ------------------------------------------------------------------------ //

  const ouvrirCreationFournisseur = () => { setFormSupplier(null); setFormOpen(true); };
  const ouvrirModificationFournisseur = (s: any) => { setFormSupplier(s); setFormOpen(true); };
  const ouvrirNouvelAppro = (s: any | null = null) => { setCreateSupplier(s); setCreateOpen(true); };
  const voirHistorique = (s: any) => {
    changerFiltreFournisseur(String(s.id));
    setFiltreStatut(TOUS);
    setRechercheAppro('');
    setOnglet('approvisionnements');
  };
  const ouvrirAppro = (id: number) => router.push(`/suppliers/${id}`);

  /**
   * DELETE /suppliers/suppliers/{id}/ : le backend supprime la fiche si elle
   * n'a aucun approvisionnement, sinon il la désactive (historique conservé).
   */
  const supprimerFournisseur = async (s: any) => {
    const utilise = Number(s.nb_approvisionnements || 0) > 0;
    const question = utilise
      ? `« ${s.nom} » a ${fmtNombre(s.nb_approvisionnements)} approvisionnement(s) : il sera désactivé (l'historique est conservé). Continuer ?`
      : `Supprimer définitivement le fournisseur « ${s.nom} » ?`;
    if (!window.confirm(question)) return;
    try {
      await djangoClient.suppliers.supplierDelete(s.id);
      toast.success(utilise ? 'Fournisseur désactivé' : 'Fournisseur supprimé');
      if (ficheId === s.id) setFicheId(null);
      chargerFournisseurs(true);
      chargerTousFournisseurs();
      chargerKpis(true);
    } catch (err) {
      toast.error(messageErreur(err, 'Suppression impossible'));
    }
  };

  const totalPages = Math.max(1, Math.ceil(appros.length / PAR_PAGE));
  const pageCourante = Math.min(page, totalPages);
  const approsPage = useMemo(
    () => appros.slice((pageCourante - 1) * PAR_PAGE, pageCourante * PAR_PAGE),
    [appros, pageCourante],
  );

  const optionsFournisseurs = useMemo(() => {
    const base = tousFournisseurs.length ? tousFournisseurs : fournisseurs;
    // Un fournisseur filtré doit rester visible dans le Select même s'il est absent de la liste.
    if (filtreFournisseur !== TOUS && !base.some((s) => String(s.id) === filtreFournisseur)) {
      const trouve = fournisseurs.find((s) => String(s.id) === filtreFournisseur);
      if (trouve) return [...base, trouve];
    }
    return base;
  }, [tousFournisseurs, fournisseurs, filtreFournisseur]);

  // ------------------------------------------------------------------------ //
  // Accès
  // ------------------------------------------------------------------------ //

  if (userLoading) {
    return (
      <div className="p-4 sm:p-6 space-y-4">
        <Skeleton className="h-10 w-64" />
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
          {Array.from({ length: 8 }).map((_, i) => <Skeleton key={i} className="h-24 w-full" />)}
        </div>
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (!isGerant) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-20 text-center">
            <ShieldAlert className="h-12 w-12 text-red-500 mb-4" />
            <h2 className="text-xl font-bold">Accès refusé</h2>
            <p className="text-muted-foreground mt-2">Cette page est réservée au gérant.</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  // ------------------------------------------------------------------------ //
  // Rendu
  // ------------------------------------------------------------------------ //

  return (
    <div className="p-4 sm:p-6 space-y-6">
      {/* En-tête */}
      <div className="flex flex-col lg:flex-row lg:items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Truck className="h-6 w-6" /> Fournisseurs
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Coût réel des approvisionnements jusqu'à Madagascar : fournisseur + transport + douane + frais → coût de revient par pièce.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" size="icon" aria-label="Actualiser" title="Actualiser" onClick={() => toutRecharger()}>
            <RefreshCw className="h-4 w-4" />
          </Button>
          <Button variant="outline" onClick={ouvrirCreationFournisseur}>
            <Building2 className="h-4 w-4 mr-2" /> Nouveau fournisseur
          </Button>
          <Button onClick={() => ouvrirNouvelAppro(null)}>
            <Plus className="h-4 w-4 mr-2" /> Nouvel approvisionnement
          </Button>
        </div>
      </div>

      {/* Indicateurs */}
      <KpiGrid cols={4}>
        <KpiCard loading={kpisLoading} titre="Nombre de fournisseurs" icon={Building2} valeur={fmtNombre(kpis?.nb_fournisseurs)} detail="fournisseurs actifs" />
        <KpiCard loading={kpisLoading} titre="Approvisionnements en cours" icon={ClipboardList} valeur={fmtNombre(kpis?.en_cours)} detail={`${fmtNombre(kpis?.nb_approvisionnements)} au total · ${fmtNombre(kpis?.finalises)} finalisé${Number(kpis?.finalises) > 1 ? 's' : ''}`} />
        <KpiCard loading={kpisLoading} titre="Marchandises en transit" icon={Ship} valeur={fmtNombre(kpis?.en_transit)} detail="approvisionnements expédiés" />
        <KpiCard loading={kpisLoading} titre="Approvisionnements arrivés" icon={PackageCheck} valeur={fmtNombre(kpis?.arrives)} detail="à réceptionner en stock" />
        <KpiCard loading={kpisLoading} titre="Montant dû aux fournisseurs" icon={Wallet} valeur={fmtAr(kpis?.reste_a_payer_mga)} couleur={Number(kpis?.reste_a_payer_mga) > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-foreground'} detail={`sur ${fmtAr(kpis?.total_achats_mga)} d'achats`} />
        <KpiCard loading={kpisLoading} titre="Montant total payé" icon={Coins} valeur={fmtAr(kpis?.total_paye_mga)} detail="paiements fournisseurs" />
        <KpiCard loading={kpisLoading} titre="Frais d'importation" icon={Receipt} valeur={fmtAr(kpis?.total_frais_mga)} detail="transport, douane, taxes…" />
        <KpiCard loading={kpisLoading} titre="Valeur totale des marchandises reçues" icon={Truck} valeur={fmtAr(kpis?.valeur_recue_mga)} couleur="text-emerald-600 dark:text-emerald-400" detail="au coût de revient" />
      </KpiGrid>

      {/* Onglets */}
      <Tabs value={onglet} onValueChange={(v) => setOnglet(v as Onglet)}>
        <TabsList>
          <TabsTrigger value="fournisseurs">
            Fournisseurs
            {!fournisseursLoading && <Badge variant="secondary" className="ml-1">{fournisseurs.length}</Badge>}
          </TabsTrigger>
          <TabsTrigger value="approvisionnements">
            Approvisionnements
            {!approsLoading && <Badge variant="secondary" className="ml-1">{appros.length}</Badge>}
          </TabsTrigger>
        </TabsList>

        {/* ---------------------- Fournisseurs ---------------------- */}
        <TabsContent value="fournisseurs" className="space-y-3">
          <div className="relative max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              className="pl-9"
              placeholder="Rechercher un fournisseur (nom, pays, contact, e-mail)…"
              value={rechercheFournisseur}
              onChange={(e) => setRechercheFournisseur(e.target.value)}
            />
            {rechercheFournisseur && (
              <button
                type="button"
                aria-label="Effacer la recherche"
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                onClick={() => setRechercheFournisseur('')}
              >
                <X className="h-4 w-4" />
              </button>
            )}
          </div>

          <Card>
            <CardContent className="p-0">
              {fournisseursLoading ? (
                <TableSkeleton />
              ) : fournisseurs.length === 0 ? (
                <EtatVide
                  icon={Building2}
                  titre={rechercheFournisseur ? 'Aucun fournisseur ne correspond à cette recherche.' : 'Aucun fournisseur enregistré.'}
                  action={!rechercheFournisseur && (
                    <Button variant="outline" onClick={ouvrirCreationFournisseur}>
                      <Plus className="h-4 w-4 mr-2" /> Créer le premier fournisseur
                    </Button>
                  )}
                />
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Nom</TableHead>
                        <TableHead>Pays</TableHead>
                        <TableHead>Contact</TableHead>
                        <TableHead>Téléphone</TableHead>
                        <TableHead>E-mail</TableHead>
                        <TableHead className="text-right">Nb appro.</TableHead>
                        <TableHead className="text-right">Total acheté</TableHead>
                        <TableHead className="text-right">Payé</TableHead>
                        <TableHead className="text-right">Reste à payer</TableHead>
                        <TableHead>Dernier appro.</TableHead>
                        <TableHead>Statut</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {fournisseurs.map((s) => {
                        const dernier = s.dernier_approvisionnement;
                        const reste = Number(s.reste_a_payer_mga || 0);
                        return (
                          <TableRow key={s.id} className="cursor-pointer" onClick={() => setFicheId(s.id)}>
                            <TableCell className="font-medium whitespace-nowrap">
                              {s.nom}
                              <span className="block text-xs text-muted-foreground font-normal">Devise : {s.devise}</span>
                            </TableCell>
                            <TableCell>{s.pays || '—'}</TableCell>
                            <TableCell>{s.contact || '—'}</TableCell>
                            <TableCell className="whitespace-nowrap">{s.telephone || '—'}</TableCell>
                            <TableCell>{s.email || '—'}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmtNombre(s.nb_approvisionnements)}</TableCell>
                            <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtAr(s.total_achats_mga)}</TableCell>
                            <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtAr(s.total_paye_mga)}</TableCell>
                            <TableCell className={`text-right tabular-nums whitespace-nowrap ${reste > 0 ? 'text-amber-600 dark:text-amber-400 font-medium' : ''}`}>
                              {fmtAr(s.reste_a_payer_mga)}
                            </TableCell>
                            <TableCell>
                              {dernier ? (
                                <div className="flex flex-col gap-1">
                                  <button
                                    type="button"
                                    className="text-left font-medium hover:underline"
                                    onClick={(e) => { e.stopPropagation(); ouvrirAppro(dernier.id); }}
                                  >
                                    {dernier.numero}
                                  </button>
                                  <BadgeStatut statut={dernier.statut} label={dernier.statut_label} />
                                </div>
                              ) : (
                                <span className="text-muted-foreground">—</span>
                              )}
                            </TableCell>
                            <TableCell>
                              {s.actif ? (
                                <Badge className="bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-200">Actif</Badge>
                              ) : (
                                <Badge variant="secondary">Inactif</Badge>
                              )}
                            </TableCell>
                            <TableCell className="text-right" onClick={(e) => e.stopPropagation()}>
                              <div className="flex items-center justify-end gap-1">
                                <Button size="sm" variant="ghost" onClick={() => setFicheId(s.id)}>
                                  <Eye className="h-4 w-4 mr-1" /> Voir
                                </Button>
                                <DropdownMenu>
                                  <DropdownMenuTrigger asChild>
                                    <Button size="icon" variant="ghost" aria-label="Plus d'actions">
                                      <MoreHorizontal className="h-4 w-4" />
                                    </Button>
                                  </DropdownMenuTrigger>
                                  <DropdownMenuContent align="end">
                                    <DropdownMenuItem onClick={() => ouvrirModificationFournisseur(s)}>
                                      <Pencil className="h-4 w-4 mr-2" /> Modifier
                                    </DropdownMenuItem>
                                    <DropdownMenuItem onClick={() => ouvrirNouvelAppro(s)}>
                                      <Plus className="h-4 w-4 mr-2" /> Nouvel approvisionnement
                                    </DropdownMenuItem>
                                    <DropdownMenuSeparator />
                                    <DropdownMenuItem onClick={() => voirHistorique(s)}>
                                      <History className="h-4 w-4 mr-2" /> Historique des approvisionnements
                                    </DropdownMenuItem>
                                    {s.actif && (
                                      <>
                                        <DropdownMenuSeparator />
                                        <DropdownMenuItem
                                          className="text-red-600 focus:text-red-600 dark:text-red-400"
                                          onClick={() => supprimerFournisseur(s)}
                                        >
                                          <Trash2 className="h-4 w-4 mr-2" />
                                          {Number(s.nb_approvisionnements || 0) > 0 ? 'Désactiver' : 'Supprimer'}
                                        </DropdownMenuItem>
                                      </>
                                    )}
                                  </DropdownMenuContent>
                                </DropdownMenu>
                              </div>
                            </TableCell>
                          </TableRow>
                        );
                      })}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* ---------------------- Approvisionnements ---------------------- */}
        <TabsContent value="approvisionnements" className="space-y-3">
          <div className="flex flex-col sm:flex-row sm:flex-wrap gap-2">
            <Select value={filtreStatut} onValueChange={setFiltreStatut}>
              <SelectTrigger className="w-full sm:w-56"><SelectValue placeholder="Statut" /></SelectTrigger>
              <SelectContent>
                <SelectItem value={TOUS}>Tous les statuts</SelectItem>
                {STATUTS.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={filtreFournisseur} onValueChange={changerFiltreFournisseur}>
              <SelectTrigger className="w-full sm:w-56"><SelectValue placeholder="Fournisseur" /></SelectTrigger>
              <SelectContent>
                <SelectItem value={TOUS}>Tous les fournisseurs</SelectItem>
                {optionsFournisseurs.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.nom}</SelectItem>)}
              </SelectContent>
            </Select>
            <div className="relative flex-1 min-w-50 sm:max-w-md">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                className="pl-9"
                placeholder="Numéro, description, suivi (tracking)…"
                value={rechercheAppro}
                onChange={(e) => setRechercheAppro(e.target.value)}
              />
            </div>
            {(filtreStatut !== TOUS || filtreFournisseur !== TOUS || rechercheAppro) && (
              <Button
                variant="ghost"
                onClick={() => { setFiltreStatut(TOUS); changerFiltreFournisseur(TOUS); setRechercheAppro(''); }}
              >
                <X className="h-4 w-4 mr-1" /> Réinitialiser
              </Button>
            )}
          </div>

          <Card>
            <CardContent className="p-0">
              {approsLoading ? (
                <TableSkeleton />
              ) : appros.length === 0 ? (
                <EtatVide
                  icon={ClipboardList}
                  titre={
                    filtreStatut !== TOUS || filtreFournisseur !== TOUS || rechercheAppro
                      ? 'Aucun approvisionnement ne correspond à ces filtres.'
                      : 'Aucun approvisionnement pour le moment.'
                  }
                  action={filtreStatut === TOUS && filtreFournisseur === TOUS && !rechercheAppro && (
                    <Button onClick={() => ouvrirNouvelAppro(null)}>
                      <Plus className="h-4 w-4 mr-2" /> Créer un approvisionnement
                    </Button>
                  )}
                />
              ) : (
                <>
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Numéro</TableHead>
                          <TableHead>Fournisseur</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead>Statut</TableHead>
                          <TableHead>Devise</TableHead>
                          <TableHead className="text-right">Valeur d'achat</TableHead>
                          <TableHead className="text-right">Frais</TableHead>
                          <TableHead className="text-right">Valeur réelle</TableHead>
                          <TableHead className="min-w-35">Payé</TableHead>
                          <TableHead className="text-right">Reçu</TableHead>
                          <TableHead className="text-right">Action</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {approsPage.map((o) => {
                          const pct = Math.max(0, Math.min(100, Number(o.pourcentage_paye || 0)));
                          const totalQty = Number(o.total_qty || 0);
                          const totalRecu = Number(o.total_recu || 0);
                          return (
                            <TableRow key={o.id} className="cursor-pointer" onClick={() => ouvrirAppro(o.id)}>
                              <TableCell className="font-medium whitespace-nowrap">
                                {o.numero}
                                {o.description && (
                                  <span className="block text-xs text-muted-foreground font-normal max-w-55 truncate" title={o.description}>
                                    {o.description}
                                  </span>
                                )}
                              </TableCell>
                              <TableCell className="whitespace-nowrap">{o.supplier_nom || <span className="text-muted-foreground">—</span>}</TableCell>
                              <TableCell className="whitespace-nowrap">{fmtDate(o.date)}</TableCell>
                              <TableCell><BadgeStatut statut={o.statut} label={o.statut_label} /></TableCell>
                              <TableCell className="whitespace-nowrap">
                                {o.devise}
                                {o.devise !== 'MGA' && o.taux_change && (
                                  <span className="block text-xs text-muted-foreground">1 {o.devise} = {fmtTaux(o.taux_change)}</span>
                                )}
                              </TableCell>
                              <TableCell className="text-right tabular-nums whitespace-nowrap">
                                {fmtAr(o.valeur_achat_mga)}
                                {o.devise !== 'MGA' && (
                                  <span className="block text-xs text-muted-foreground">
                                    {fmtDevise(o.lines?.reduce((s: number, l: any) => s + Number(l.total_fournisseur_devise || 0), 0), o.devise)}
                                  </span>
                                )}
                              </TableCell>
                              <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtAr(o.total_frais_mga)}</TableCell>
                              <TableCell className="text-right tabular-nums whitespace-nowrap font-medium">
                                {fmtAr(o.cout_total)}
                                {totalQty > 0 && (
                                  <span className="block text-xs text-muted-foreground font-normal">{fmtAr(o.cout_unitaire)} / pièce</span>
                                )}
                              </TableCell>
                              <TableCell>
                                <div className="space-y-1">
                                  <div className="flex justify-between text-xs">
                                    <span className={pct >= 100 ? 'text-emerald-600 dark:text-emerald-400 font-medium' : ''}>{fmtPourcent(pct)}</span>
                                    <span className="text-muted-foreground tabular-nums">{fmtAr(o.total_paye_mga)}</span>
                                  </div>
                                  <Progress value={pct} className="h-1.5" />
                                </div>
                              </TableCell>
                              <TableCell className="text-right tabular-nums whitespace-nowrap">
                                <span className={totalQty > 0 && totalRecu >= totalQty ? 'text-emerald-600 dark:text-emerald-400 font-medium' : ''}>
                                  {fmtNombre(totalRecu)} / {fmtNombre(totalQty)}
                                </span>
                              </TableCell>
                              <TableCell className="text-right" onClick={(e) => e.stopPropagation()}>
                                <Button size="sm" variant="outline" onClick={() => ouvrirAppro(o.id)}>
                                  Ouvrir <ExternalLink className="h-3.5 w-3.5 ml-1" />
                                </Button>
                              </TableCell>
                            </TableRow>
                          );
                        })}
                      </TableBody>
                    </Table>
                  </div>
                  {totalPages > 1 && (
                    <div className="flex items-center justify-between gap-2 px-4 py-3 border-t text-sm">
                      <span className="text-muted-foreground">
                        {((pageCourante - 1) * PAR_PAGE) + 1}–{Math.min(pageCourante * PAR_PAGE, appros.length)} sur {appros.length}
                      </span>
                      <div className="flex items-center gap-1">
                        <Button size="icon" variant="outline" aria-label="Page précédente" disabled={pageCourante <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>
                          <ChevronLeft className="h-4 w-4" />
                        </Button>
                        <span className="px-2 tabular-nums">{pageCourante} / {totalPages}</span>
                        <Button size="icon" variant="outline" aria-label="Page suivante" disabled={pageCourante >= totalPages} onClick={() => setPage((p) => Math.min(totalPages, p + 1))}>
                          <ChevronRight className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                  )}
                </>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Fiche fournisseur */}
      <FicheFournisseurSheet
        supplierId={ficheId}
        onClose={() => setFicheId(null)}
        onModifier={(s) => { setFicheId(null); ouvrirModificationFournisseur(s); }}
        onNouvelAppro={(s) => { setFicheId(null); ouvrirNouvelAppro(s); }}
        onHistorique={(s) => { setFicheId(null); voirHistorique(s); }}
        onOuvrirAppro={ouvrirAppro}
      />

      {/* Dialogs */}
      <SupplierFormDialog
        open={formOpen}
        onOpenChange={setFormOpen}
        supplier={formSupplier}
        onSaved={() => { chargerFournisseurs(true); chargerTousFournisseurs(); chargerKpis(true); }}
      />
      <SupplierOrderCreateDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        supplierInitial={createSupplier}
        onCreated={(order) => {
          toutRecharger(true);
          if (order?.id) router.push(`/suppliers/${order.id}`);
        }}
      />
    </div>
  );
}

// -------------------------------------------------------------------------- //
// Sous-composants
// -------------------------------------------------------------------------- //

function BadgeStatut({ statut, label }: { statut: string; label?: string }) {
  const info = statutInfo(statut);
  return <Badge className={`${info.color} whitespace-nowrap`}>{label || info.label}</Badge>;
}

function TableSkeleton() {
  return (
    <div className="p-4 space-y-2">
      <Skeleton className="h-8 w-full" />
      {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}
    </div>
  );
}

function EtatVide({
  icon: Icon,
  titre,
  action,
}: {
  icon: React.ComponentType<{ className?: string }>;
  titre: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-14 text-center gap-3">
      <Icon className="h-10 w-10 text-muted-foreground/60" />
      <p className="text-sm text-muted-foreground">{titre}</p>
      {action}
    </div>
  );
}

/**
 * Fiche fournisseur (Sheet) : informations, résumé financier et historique
 * des approvisionnements — chargée via GET /suppliers/suppliers/{id}/.
 */
function FicheFournisseurSheet({
  supplierId,
  onClose,
  onModifier,
  onNouvelAppro,
  onHistorique,
  onOuvrirAppro,
}: {
  supplierId: number | null;
  onClose: () => void;
  onModifier: (s: any) => void;
  onNouvelAppro: (s: any) => void;
  onHistorique: (s: any) => void;
  onOuvrirAppro: (id: number) => void;
}) {
  const [fiche, setFiche] = useState<any | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!supplierId) { setFiche(null); return; }
    let annule = false;
    setLoading(true);
    djangoClient.suppliers.supplierGet(supplierId)
      .then((d) => { if (!annule) setFiche(d); })
      .catch((err) => { if (!annule) { toast.error(messageErreur(err, 'Fiche fournisseur introuvable')); onClose(); } })
      .finally(() => { if (!annule) setLoading(false); });
    return () => { annule = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supplierId]);

  const appros: any[] = fiche?.approvisionnements || [];

  return (
    <Sheet open={!!supplierId} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full sm:max-w-xl overflow-y-auto p-0">
        <div className="p-6 space-y-5">
          <SheetHeader className="p-0 space-y-1">
            <SheetTitle className="flex items-center gap-2">
              <Building2 className="h-5 w-5" />
              {loading || !fiche ? 'Fiche fournisseur' : fiche.nom}
            </SheetTitle>
            <SheetDescription>
              {loading || !fiche
                ? 'Chargement de la fiche…'
                : [fiche.pays, fiche.contact].filter(Boolean).join(' · ') || 'Fiche fournisseur'}
            </SheetDescription>
          </SheetHeader>

          {loading || !fiche ? (
            <div className="space-y-3">
              <Skeleton className="h-24 w-full" />
              <Skeleton className="h-32 w-full" />
              <Skeleton className="h-48 w-full" />
            </div>
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-2">
                {fiche.actif ? (
                  <Badge className="bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-200">Actif</Badge>
                ) : (
                  <Badge variant="secondary">Inactif</Badge>
                )}
                <Badge variant="outline">Devise habituelle : {fiche.devise}</Badge>
                <div className="ml-auto flex flex-wrap gap-1.5">
                  <Button size="sm" variant="outline" onClick={() => onModifier(fiche)}>
                    <Pencil className="h-3.5 w-3.5 mr-1" /> Modifier
                  </Button>
                  <Button size="sm" onClick={() => onNouvelAppro(fiche)}>
                    <Plus className="h-3.5 w-3.5 mr-1" /> Nouvel approvisionnement
                  </Button>
                </div>
              </div>

              {/* Informations */}
              <section className="space-y-2">
                <h3 className="text-sm font-semibold">Informations</h3>
                <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 text-sm">
                  <InfoLigne label="Pays" valeur={fiche.pays} />
                  <InfoLigne label="Contact" valeur={fiche.contact} />
                  <InfoLigne label="Téléphone" valeur={fiche.telephone} />
                  <InfoLigne label="E-mail" valeur={fiche.email} />
                  <div className="sm:col-span-2"><InfoLigne label="Adresse" valeur={fiche.adresse} /></div>
                  {fiche.notes && (
                    <div className="sm:col-span-2"><InfoLigne label="Notes" valeur={fiche.notes} /></div>
                  )}
                </dl>
              </section>

              {/* Résumé financier */}
              <section className="space-y-2">
                <h3 className="text-sm font-semibold">Résumé financier</h3>
                <div className="grid grid-cols-2 gap-2">
                  <Montant label="Total des achats" valeur={fiche.total_achats_mga} />
                  <Montant label="Total payé" valeur={fiche.total_paye_mga} />
                  <Montant
                    label="Reste à payer"
                    valeur={fiche.reste_a_payer_mga}
                    couleur={Number(fiche.reste_a_payer_mga) > 0 ? 'text-amber-600 dark:text-amber-400' : undefined}
                  />
                  <Montant label="Total frais d'importation" valeur={fiche.total_frais_mga} />
                  <div className="col-span-2">
                    <Montant label="Valeur totale reçue (au coût de revient)" valeur={fiche.valeur_recue_mga} couleur="text-emerald-600 dark:text-emerald-400" />
                  </div>
                </div>
              </section>

              {/* Historique */}
              <section className="space-y-2">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-semibold">
                    Approvisionnements <span className="text-muted-foreground font-normal">({appros.length})</span>
                  </h3>
                  {appros.length > 0 && (
                    <Button size="sm" variant="ghost" onClick={() => onHistorique(fiche)}>
                      <History className="h-3.5 w-3.5 mr-1" /> Voir dans la liste
                    </Button>
                  )}
                </div>
                {appros.length === 0 ? (
                  <p className="text-sm text-muted-foreground border rounded-lg border-dashed py-6 text-center">
                    Aucun approvisionnement pour ce fournisseur.
                  </p>
                ) : (
                  <div className="rounded-lg border overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Numéro</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead className="text-right">Achat</TableHead>
                          <TableHead>Statut</TableHead>
                          <TableHead className="text-right" />
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {appros.map((o) => (
                          <TableRow key={o.id} className="cursor-pointer" onClick={() => onOuvrirAppro(o.id)}>
                            <TableCell className="font-medium whitespace-nowrap">{o.numero}</TableCell>
                            <TableCell className="whitespace-nowrap">{fmtDate(o.date)}</TableCell>
                            <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtAr(o.valeur_achat_mga)}</TableCell>
                            <TableCell><BadgeStatut statut={o.statut} label={o.statut_label} /></TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); onOuvrirAppro(o.id); }}>
                                Ouvrir <ExternalLink className="h-3.5 w-3.5 ml-1" />
                              </Button>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </section>
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}

function InfoLigne({ label, valeur }: { label: string; valeur?: string | null }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="wrap-break-word">{valeur || '—'}</dd>
    </div>
  );
}

function Montant({ label, valeur, couleur }: { label: string; valeur: number | string | null | undefined; couleur?: string }) {
  return (
    <div className="rounded-lg border p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className={`text-base font-semibold tabular-nums ${couleur ?? ''}`}>{fmtAr(valeur)}</p>
    </div>
  );
}
