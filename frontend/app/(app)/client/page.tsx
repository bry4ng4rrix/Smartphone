'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useDeliveryZones } from '@/lib/hooks/useDeliveryZones';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { appDatetimeLocalToIso, appDatetimeLocalValue, appDayKey, fmtAppDateTime } from '@/lib/timezone';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { DateTimeInput } from '@/components/ui/datetime-input';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Check, ChevronLeft, ChevronRight, Phone, RefreshCw, ShieldAlert, ShoppingBag, Truck, X,
} from 'lucide-react';
import { toast } from 'sonner';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';

const MODE_PAIEMENT: Record<string, string> = {
  LIVRAISON: 'Paiement à la livraison',
  AVANT: 'Paiement avant la livraison',
};

const TAILLES_PAGE = [10, 25, 50];

type Staff = { id: number; full_name: string; available: boolean };

/**
 * Demandes venues de la boutique en ligne (clients_frontend) : commandes
 * « En attente d'approbation ». Le gérant complète ce que le client ne
 * choisit pas — date et heure de livraison, préparateur, livreur, zone (donc
 * les frais), notes et paiement — puis confirme. La commande rejoint alors le
 * circuit habituel (« Nouvelle ») et apparaît dans la page Commandes ; le
 * client, lui, voit la zone et le total définitifs dans son espace.
 */
export default function DemandesClientsPage() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const { zones } = useDeliveryZones();

  const [demandes, setDemandes] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  // Filtres — même barre que la page Commandes (date, zone, paiement, recherche).
  const [filtreDate, setFiltreDate] = useState('');
  const [filtreReception, setFiltreReception] = useState('ALL');
  const [filtrePaiement, setFiltrePaiement] = useState('ALL');
  const [recherche, setRecherche] = useState('');
  const [page, setPage] = useState(1);
  const [taillePage, setTaillePage] = useState(10);

  // Fiche de validation.
  const [cible, setCible] = useState<any | null>(null);
  const [refusCible, setRefusCible] = useState<any | null>(null);
  const [dateCommande, setDateCommande] = useState('');
  const [preparateurId, setPreparateurId] = useState('');
  const [livreurId, setLivreurId] = useState('');
  const [zone, setZone] = useState('');
  const [notePreparateur, setNotePreparateur] = useState('');
  const [noteLivreur, setNoteLivreur] = useState('');
  const [modePaiement, setModePaiement] = useState<'AVANT' | 'LIVRAISON'>('LIVRAISON');
  const [preparateurs, setPreparateurs] = useState<Staff[]>([]);
  const [livreurs, setLivreurs] = useState<Staff[]>([]);
  const [envoi, setEnvoi] = useState(false);
  const [motifRefus, setMotifRefus] = useState('');

  const charger = useCallback(async (silencieux = false) => {
    if (!silencieux) setLoading(true);
    try {
      const data = await djangoClient.orders.list({ statut: 'EN_ATTENTE_APPROBATION' });
      setDemandes(data);
    } catch (err: any) {
      toast.error(err.message || 'Erreur de chargement des demandes');
    } finally {
      if (!silencieux) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(['order', 'order_status_history'], () => charger(true));
  useEffect(() => {
    if (!userLoading && isGerant) charger();
  }, [userLoading, isGerant, charger]);

  const nomZone = useCallback(
    (code: string) => (code === 'RECUPERATION' ? 'Retrait sur place' : zones.find((z) => z.code === code)?.nom || code),
    [zones],
  );

  // ------------------------------------------------------------ filtrage
  const filtrees = useMemo(() => {
    const q = recherche.trim().toLowerCase();
    return demandes.filter((o) => {
      if (filtreDate && appDayKey(o.date_commande) !== filtreDate) return false;
      if (filtreReception === 'RETRAIT' && o.livraison_zone !== 'RECUPERATION') return false;
      if (filtreReception === 'LIVRAISON' && o.livraison_zone === 'RECUPERATION') return false;
      if (filtrePaiement !== 'ALL' && o.mode_paiement !== filtrePaiement) return false;
      if (q) {
        const texte = [
          o.numero, o.client_nom, o.client_email, o.telephone, o.telephone_2, o.adresse_livraison,
          nomZone(o.livraison_zone), fmtAppDateTime(o.date_commande),
          ...(o.items || []).map((it: any) => `${it.reference_name} ${it.brand_name} ${it.type_name} ${it.couleur}`),
        ].join(' ').toLowerCase();
        if (!texte.includes(q)) return false;
      }
      return true;
    });
  }, [demandes, filtreDate, filtreReception, filtrePaiement, recherche, nomZone]);

  const nbPages = Math.max(1, Math.ceil(filtrees.length / taillePage));
  const pageCourante = Math.min(page, nbPages);
  const affichees = filtrees.slice((pageCourante - 1) * taillePage, pageCourante * taillePage);
  const filtresActifs = !!filtreDate || filtreReception !== 'ALL' || filtrePaiement !== 'ALL' || !!recherche;

  const reinitialiser = () => {
    setFiltreDate('');
    setFiltreReception('ALL');
    setFiltrePaiement('ALL');
    setRecherche('');
    setPage(1);
  };

  // ------------------------------------------------------------ fiche
  /** Ouvre la fiche de validation, pré-remplie avec ce que le client a demandé. */
  const examiner = async (order: any) => {
    setCible(order);
    setDateCommande(order.date_commande ? appDatetimeLocalValue(new Date(order.date_commande)) : '');
    setZone(order.livraison_zone || '');
    setNotePreparateur(order.note_preparateur || '');
    setNoteLivreur(order.note_livreur || '');
    setModePaiement(order.mode_paiement === 'AVANT' ? 'AVANT' : 'LIVRAISON');
    setPreparateurId(order.preparateur ? String(order.preparateur) : '');
    setLivreurId(order.livreur ? String(order.livreur) : '');
    try {
      const [prep, liv] = await Promise.all([
        djangoClient.orders.availableStaff('PREPARATEUR', order.magasin),
        djangoClient.orders.availableStaff('LIVREUR', order.magasin, order.date_commande),
      ]);
      setPreparateurs(prep);
      setLivreurs(liv);
    } catch {
      setPreparateurs([]);
      setLivreurs([]);
    }
  };

  const fermer = () => {
    setCible(null);
    setEnvoi(false);
  };

  const zoneChoisie = useMemo(() => zones.find((z) => z.code === zone) || null, [zones, zone]);
  const totalArticles = useMemo(
    () => (cible?.items || []).reduce((n: number, it: any) => n + Number(it.prix_unitaire || 0) * Number(it.quantite || 0), 0),
    [cible],
  );
  const fraisPrevus = zone === 'RECUPERATION' ? 0 : Number(zoneChoisie?.prix ?? 0);

  /** Applique les modifications du gérant, approuve, puis assigne. */
  const confirmer = async () => {
    if (!cible) return;
    setEnvoi(true);
    try {
      await djangoClient.orders.update(cible.id, {
        livraison_zone: zone || undefined,
        adresse_livraison: zone === 'RECUPERATION' ? '' : undefined,
        mode_paiement: modePaiement,
        note_preparateur: notePreparateur,
        note_livreur: noteLivreur,
        // Saisie à l'heure d'Antananarivo, quel que soit le fuseau de l'appareil.
        date_commande: dateCommande ? appDatetimeLocalToIso(dateCommande) : undefined,
      });

      // L'approbation d'abord : la pré-assignation d'un préparateur exige une
      // commande déjà entrée dans le circuit (voir assign_preparateur_early).
      await djangoClient.orders.approuver(cible.id);

      if (preparateurId) await djangoClient.orders.assignPreparateur(cible.id, Number(preparateurId));
      if (livreurId) await djangoClient.orders.assignLivreur(cible.id, Number(livreurId));

      toast.success(`Commande ${cible.numero} confirmée`, {
        description: 'Elle est maintenant dans la page Commandes.',
      });
      fermer();
      charger(true);
    } catch (err: any) {
      toast.error(err.message || 'Confirmation impossible');
      setEnvoi(false);
    }
  };

  const refuser = async () => {
    if (!refusCible) return;
    setEnvoi(true);
    try {
      await djangoClient.orders.refuser(refusCible.id, motifRefus.trim() || undefined);
      toast.success(`Commande ${refusCible.numero} refusée`);
      setRefusCible(null);
      setMotifRefus('');
      setCible(null);
      charger(true);
    } catch (err: any) {
      toast.error(err.message || 'Refus impossible');
    } finally {
      setEnvoi(false);
    }
  };

  if (!userLoading && !isGerant) {
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

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <ShoppingBag className="h-6 w-6" /> Demandes des clients
          </h1>
          <p className="text-sm text-muted-foreground">
            Commandes passées depuis la boutique en ligne, en attente de votre validation.
          </p>
        </div>
        <div className="flex items-center gap-2">
          {demandes.length > 0 && (
            <Badge className="bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-300">
              {demandes.length} en attente
            </Badge>
          )}
          <Button variant="outline" size="icon" onClick={() => charger()}>
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* ------------------------------------------------------- Filtres */}
      <div className="flex flex-wrap items-end gap-2">
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Date de livraison</Label>
          <Input
            type="date"
            value={filtreDate}
            onChange={(e) => { setFiltreDate(e.target.value); setPage(1); }}
            className="w-auto"
          />
        </div>
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Réception</Label>
          <Select value={filtreReception} onValueChange={(v) => { setFiltreReception(v); setPage(1); }}>
            <SelectTrigger className="w-45">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="ALL">Toutes</SelectItem>
              <SelectItem value="LIVRAISON">Livraison à domicile</SelectItem>
              <SelectItem value="RETRAIT">Retrait sur place</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Paiement</Label>
          <Select value={filtrePaiement} onValueChange={(v) => { setFiltrePaiement(v); setPage(1); }}>
            <SelectTrigger className="w-45">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="ALL">Tous</SelectItem>
              <SelectItem value="LIVRAISON">À la livraison</SelectItem>
              <SelectItem value="AVANT">Avant la livraison</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1 min-w-[220px] flex-1 max-w-[360px]">
          <Label className="text-xs text-muted-foreground">Recherche</Label>
          <Input
            value={recherche}
            onChange={(e) => { setRecherche(e.target.value); setPage(1); }}
            placeholder="Code, client, e-mail, produit, adresse, téléphone…"
            className="w-full"
          />
        </div>
        {filtresActifs && (
          <Button variant="ghost" size="sm" onClick={reinitialiser}>
            Réinitialiser
          </Button>
        )}
      </div>

      {/* ------------------------------------------------------- Tableau */}
      <Card>
        <CardContent className="p-0">
          {loading ? (
            <div className="space-y-3 p-4">
              {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}
            </div>
          ) : filtrees.length === 0 ? (
            <p className="py-16 text-center text-sm text-muted-foreground">
              {demandes.length === 0 ? (
                <>
                  Aucune demande en attente. Les commandes validées se suivent dans{' '}
                  <Link href="/orders" className="underline">Commandes</Link>.
                </>
              ) : (
                'Aucune demande ne correspond à ces filtres.'
              )}
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="text-center">Statut</TableHead>
                    <TableHead className="text-center">Produit</TableHead>
                    <TableHead className="text-center">Adresse</TableHead>
                    <TableHead className="text-center">Numéro</TableHead>
                    <TableHead className="text-center">Paiement</TableHead>
                    <TableHead className="text-center">Total</TableHead>
                    <TableHead className="text-center">Date et heure</TableHead>
                    <TableHead className="text-center">Action</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {/* Tout est centré, verticalement (align-middle) comme
                      horizontalement (text-center / justify-center). */}
                  {affichees.map((order) => (
                    <TableRow key={order.id} className="cursor-pointer" onClick={() => examiner(order)}>
                      <TableCell className="align-middle text-center">
                        <Badge className="bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-300">
                          En attente
                        </Badge>
                      </TableCell>

                      {/* Produit : nom, sous-type, catégorie, couleur, nombre. */}
                      <TableCell className="align-middle text-center max-w-[300px]">
                        <div className="flex flex-col items-center gap-2">
                          {(order.items || []).map((it: any) => (
                            <div key={it.id} className="flex flex-col items-center leading-tight">
                              <div className="flex items-center justify-center gap-2">
                                <span className="font-medium text-foreground text-sm leading-tight">
                                  {it.reference_name || 'Article'}
                                </span>
                                {it.quantite ? (
                                  <span className="text-[11px] font-semibold text-sky-700 dark:text-sky-400 whitespace-nowrap">
                                    ×{it.quantite}
                                  </span>
                                ) : null}
                              </div>
                              <div className="flex flex-wrap items-center justify-center gap-1.5 text-[11px] text-muted-foreground">
                                {[it.type_name, it.category_name].filter(Boolean).map((label: string) => (
                                  <span key={label}>{label}</span>
                                ))}
                                {it.couleur && (
                                  <span className="inline-flex items-center rounded-full border border-border bg-background px-1.5 py-0.5 text-[10px] text-foreground">
                                    {it.couleur}
                                  </span>
                                )}
                              </div>
                            </div>
                          ))}
                        </div>
                      </TableCell>

                      {/* Adresse : retrait sur place, ou adresse du client. */}
                      <TableCell className="align-middle text-center max-w-[200px]">
                        <span className="text-sm break-words">
                          {order.livraison_zone === 'RECUPERATION' ? 'Retrait sur place' : order.adresse_livraison || '—'}
                        </span>
                      </TableCell>

                      {/* Numéro(s) cliquables, comme pour le livreur. */}
                      <TableCell className="align-middle text-center">
                        <div className="flex flex-col items-center gap-0.5">
                          <a
                            href={`tel:${order.telephone}`}
                            onClick={(e) => e.stopPropagation()}
                            className="inline-flex items-center justify-center gap-1 text-sm text-blue-600 hover:underline whitespace-nowrap"
                          >
                            <Phone className="h-3 w-3" /> {order.telephone}
                          </a>
                          {order.telephone_2 && (
                            <a
                              href={`tel:${order.telephone_2}`}
                              onClick={(e) => e.stopPropagation()}
                              className="inline-flex items-center justify-center gap-1 text-sm text-blue-600 hover:underline whitespace-nowrap"
                            >
                              <Phone className="h-3 w-3" /> {order.telephone_2}
                            </a>
                          )}
                        </div>
                      </TableCell>

                      <TableCell className="align-middle text-center text-sm whitespace-nowrap">
                        {order.mode_paiement === 'AVANT' ? 'Avant la livraison' : 'À la livraison'}
                      </TableCell>

                      <TableCell className="align-middle text-center font-semibold whitespace-nowrap">{fmt(order.total_a_payer)}</TableCell>

                      {/* Créneau demandé par le client (à confirmer). */}
                      <TableCell className="align-middle text-center text-sm whitespace-nowrap">
                        {fmtAppDateTime(order.date_commande)}
                      </TableCell>

                      <TableCell className="align-middle text-center">
                        <div className="flex items-center justify-center">
                          <Button size="sm" onClick={(e) => { e.stopPropagation(); examiner(order); }}>
                            Examiner
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ---------------------------------------------------- Pagination */}
      {!loading && filtrees.length > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-3 text-sm">
          <div className="flex items-center gap-2 text-muted-foreground">
            <span>
              {filtrees.length} demande{filtrees.length > 1 ? 's' : ''}
              {filtresActifs ? ` sur ${demandes.length}` : ''}
            </span>
            <Select value={String(taillePage)} onValueChange={(v) => { setTaillePage(Number(v)); setPage(1); }}>
              <SelectTrigger className="h-8 w-28">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TAILLES_PAGE.map((n) => (
                  <SelectItem key={n} value={String(n)}>{n} / page</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="icon" className="h-8 w-8" disabled={pageCourante <= 1} onClick={() => setPage(pageCourante - 1)}>
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <span className="tabular-nums">Page {pageCourante} / {nbPages}</span>
            <Button variant="outline" size="icon" className="h-8 w-8" disabled={pageCourante >= nbPages} onClick={() => setPage(pageCourante + 1)}>
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      )}

      {/* ------------------------------------------------ Fiche de validation */}
      <Dialog open={!!cible} onOpenChange={(o) => !o && fermer()}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Demande {cible?.numero}</DialogTitle>
            <DialogDescription>
              Ce que le client a commandé, puis ce que vous complétez avant de confirmer.
            </DialogDescription>
          </DialogHeader>

          {cible && (
            <div className="space-y-5 text-sm">
              {/* ---- Détail de la commande du client (même présentation que Commandes) */}
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground mb-2">Information</p>

                <div className="space-y-2 rounded-md border bg-muted/10 p-3">
                  <p className="text-muted-foreground text-xs uppercase tracking-[0.2em]">Articles</p>
                  {(cible.items || []).map((it: any) => (
                    <div key={it.id} className="space-y-1">
                      <div className="font-medium text-foreground">
                        {it.reference_name || 'Article'}
                        {it.couleur ? ` (${it.couleur})` : ''}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {[it.category_name, it.type_name, it.brand_name].filter(Boolean).join(' • ') || 'Sans métadonnées'}
                      </div>
                      <div className="flex items-end justify-between gap-3">
                        <div className="text-2xl font-bold text-sky-700 dark:text-sky-400">
                          {it.quantite ? `Quantité : ${it.quantite}` : ''}
                        </div>
                        <div className="text-right text-xs">
                          <div className="font-medium">{fmt(it.prix_unitaire)} / unité</div>
                          <div className="text-muted-foreground">{fmt(Number(it.prix_unitaire) * Number(it.quantite))}</div>
                        </div>
                      </div>
                    </div>
                  ))}
                  <div className="flex justify-between gap-4 border-t pt-2 font-medium">
                    <span>Total articles</span>
                    <span>{fmt(totalArticles)}</span>
                  </div>
                </div>

                <div className="grid gap-2 mt-3">
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Livraison souhaitée le</span>
                    <span className="text-right">{fmtAppDateTime(cible.date_commande)}</span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Nom client</span>
                    <span className="text-right">{cible.client_nom || '-'}</span>
                  </div>
                  {cible.client_email && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">E-mail</span>
                      <span className="text-right break-all">{cible.client_email}</span>
                    </div>
                  )}
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Numéro client</span>
                    <span className="text-right">{cible.telephone || '-'}</span>
                  </div>
                  {cible.telephone_2 && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Autre numéro</span>
                      <span className="text-right">{cible.telephone_2}</span>
                    </div>
                  )}
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Réception demandée</span>
                    <span className="text-right">
                      {cible.livraison_zone === 'RECUPERATION' ? 'Retrait sur place' : 'Livraison à domicile'}
                    </span>
                  </div>
                  {cible.livraison_zone !== 'RECUPERATION' && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Adresse client</span>
                      <span className="text-right max-w-[55%] break-words">{cible.adresse_livraison || '-'}</span>
                    </div>
                  )}
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Paiement demandé</span>
                    <span className="text-right">{MODE_PAIEMENT[cible.mode_paiement] || cible.mode_paiement || '-'}</span>
                  </div>
                  {cible.note_livreur && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Remarque du client</span>
                      <span className="text-right max-w-[55%] whitespace-pre-line break-words">{cible.note_livreur}</span>
                    </div>
                  )}
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Passée le</span>
                    <span className="text-right">{fmtAppDateTime(cible.created_at)}</span>
                  </div>
                </div>
              </div>

              {/* ---- Ce que le gérant complète */}
              <div className="space-y-4 border-t pt-4">
                <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">À compléter avant confirmation</p>

                <div className="space-y-2">
                  <Label>Date et heure de livraison</Label>
                  <DateTimeInput value={dateCommande} onChange={setDateCommande} />
                  <p className="text-xs text-muted-foreground">
                    Créneau demandé par le client — ajustez-le si besoin. C&apos;est cette date qui pilote la tournée du livreur.
                  </p>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Préparateur</Label>
                    <Select value={preparateurId} onValueChange={setPreparateurId}>
                      <SelectTrigger className="w-full">
                        <SelectValue placeholder="Assigner plus tard" />
                      </SelectTrigger>
                      <SelectContent>
                        {preparateurs.map((p) => (
                          <SelectItem key={p.id} value={String(p.id)}>
                            {p.full_name}{p.available ? '' : ' (occupé)'}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label>Livreur</Label>
                    <Select value={livreurId} onValueChange={setLivreurId}>
                      <SelectTrigger className="w-full">
                        <SelectValue placeholder="Assigner plus tard" />
                      </SelectTrigger>
                      <SelectContent>
                        {livreurs.map((p) => (
                          <SelectItem key={p.id} value={String(p.id)}>
                            {p.full_name}{p.available ? '' : ' (occupé)'}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Zone de livraison</Label>
                    <Select value={zone} onValueChange={setZone}>
                      <SelectTrigger className="w-full">
                        <SelectValue placeholder="Choisir une zone" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="RECUPERATION">Récupération sur place (0 Ar)</SelectItem>
                        {zones.map((z) => (
                          <SelectItem key={z.code} value={z.code}>
                            {z.nom} ({fmt(z.prix)})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-muted-foreground">
                      Le client ne choisit pas sa zone : c&apos;est vous qui fixez les frais d&apos;après son adresse.
                    </p>
                  </div>

                  <div className="space-y-2">
                    <Label>Paiement</Label>
                    <Select value={modePaiement} onValueChange={(v) => setModePaiement(v as 'AVANT' | 'LIVRAISON')}>
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="LIVRAISON">Paiement à la livraison</SelectItem>
                        <SelectItem value="AVANT">Paiement avant la livraison</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                <div className="space-y-2">
                  <Label>Note pour le préparateur</Label>
                  <Textarea value={notePreparateur} onChange={(e) => setNotePreparateur(e.target.value)} rows={2} />
                </div>

                <div className="space-y-2">
                  <Label>Note pour le livreur</Label>
                  <Textarea value={noteLivreur} onChange={(e) => setNoteLivreur(e.target.value)} rows={2} />
                  <p className="text-xs text-muted-foreground">Pré-remplie avec la remarque laissée par le client.</p>
                </div>

                {/* Impact chiffré du choix de zone */}
                <div className="rounded-lg border p-4 space-y-1.5">
                  <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Articles</span>
                    <span className="tabular-nums">{fmt(totalArticles)}</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-muted-foreground flex items-center gap-1.5">
                      <Truck className="h-3.5 w-3.5" /> Livraison {zoneChoisie ? `· ${zoneChoisie.nom}` : ''}
                    </span>
                    <span className="tabular-nums">{fraisPrevus > 0 ? fmt(fraisPrevus) : 'Sans frais'}</span>
                  </div>
                  <div className="flex items-center justify-between border-t pt-2 font-semibold">
                    <span>Total à payer</span>
                    <span className="tabular-nums">{fmt(totalArticles + fraisPrevus)}</span>
                  </div>
                </div>
              </div>
            </div>
          )}

          <DialogFooter className="gap-2 sm:gap-2">
            <Button
              variant="outline"
              className="text-red-600 hover:text-red-700"
              onClick={() => setRefusCible(cible)}
              disabled={envoi}
            >
              <X className="h-4 w-4 mr-1" /> Refuser
            </Button>
            <Button onClick={confirmer} disabled={envoi || !zone}>
              <Check className="h-4 w-4 mr-1" />
              {envoi ? 'Confirmation…' : 'Confirmer la commande'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ------------------------------------------------------------ Refus */}
      <Dialog open={!!refusCible} onOpenChange={(o) => !o && setRefusCible(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Refuser la demande {refusCible?.numero} ?</DialogTitle>
            <DialogDescription>
              La commande sera annulée. Aucun stock n&apos;a été réservé, rien n&apos;est déduit.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label>Motif (facultatif)</Label>
            <Input
              value={motifRefus}
              onChange={(e) => setMotifRefus(e.target.value)}
              placeholder="Ex : article plus disponible"
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRefusCible(null)} disabled={envoi}>Annuler</Button>
            <Button variant="destructive" onClick={refuser} disabled={envoi}>
              {envoi ? 'Refus…' : 'Refuser la demande'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
