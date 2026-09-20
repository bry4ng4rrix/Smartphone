'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useDeliveryZones } from '@/lib/hooks/useDeliveryZones';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
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
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  CalendarClock, Check, MapPin, Package, Phone, RefreshCw, ShieldAlert, ShoppingBag, Truck, UserRound, X,
} from 'lucide-react';
import { toast } from 'sonner';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';

/** `Date` -> valeur `datetime-local` (`YYYY-MM-DDTHH:mm`), heure locale. */
function toDatetimeLocal(value: string | null | undefined): string {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

const fmtDateTime = (value: string | null | undefined) => {
  if (!value) return '—';
  const d = new Date(value);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
};

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
  const [cible, setCible] = useState<any | null>(null);
  const [refusCible, setRefusCible] = useState<any | null>(null);

  // Champs complétés par le gérant avant confirmation.
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

  /** Ouvre la fiche de validation, pré-remplie avec ce que le client a demandé. */
  const examiner = async (order: any) => {
    setCible(order);
    setDateCommande(toDatetimeLocal(order.date_commande));
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

  /** Applique les modifications du gérant, puis approuve la commande. */
  const confirmer = async () => {
    if (!cible) return;
    setEnvoi(true);
    try {
      await djangoClient.orders.update(cible.id, {
        livraison_zone: zone || undefined,
        mode_paiement: modePaiement,
        note_preparateur: notePreparateur,
        note_livreur: noteLivreur,
        // `datetime-local` est une heure locale : envoyée telle quelle, Django
        // l'interprète dans le fuseau du projet (Antananarivo).
        date_commande: dateCommande ? `${dateCommande}:00` : undefined,
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

      {loading ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-32 w-full" />)}
        </div>
      ) : demandes.length === 0 ? (
        <Card>
          <CardContent className="py-16 text-center text-sm text-muted-foreground">
            Aucune demande en attente. Les commandes validées se suivent dans{' '}
            <Link href="/orders" className="underline">Commandes</Link>.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-3 lg:grid-cols-2">
          {demandes.map((order) => (
            <Card key={order.id}>
              <CardContent className="p-4 space-y-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="font-semibold">{order.numero}</p>
                    <p className="text-sm text-muted-foreground flex items-center gap-1.5">
                      <UserRound className="h-3.5 w-3.5" /> {order.client_nom}
                      {order.client_email ? <span className="truncate">· {order.client_email}</span> : null}
                    </p>
                  </div>
                  <Badge className="bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-300">
                    En attente
                  </Badge>
                </div>

                <div className="grid gap-1.5 text-sm text-muted-foreground">
                  <span className="flex items-center gap-1.5">
                    <CalendarClock className="h-3.5 w-3.5 shrink-0" />
                    Souhaitée le {fmtDateTime(order.date_commande)}
                  </span>
                  <a href={`tel:${order.telephone}`} className="flex items-center gap-1.5 text-blue-600 hover:underline w-fit">
                    <Phone className="h-3.5 w-3.5" /> {order.telephone}
                  </a>
                  <span className="flex items-start gap-1.5">
                    {order.livraison_zone === 'RECUPERATION' ? (
                      <Package className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                    ) : (
                      <MapPin className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                    )}
                    {order.livraison_zone === 'RECUPERATION'
                      ? 'Retrait sur place'
                      : order.adresse_livraison || 'Adresse non précisée'}
                  </span>
                </div>

                <p className="text-sm">
                  {(order.items || []).map((it: any) => `${it.reference_name} (${it.couleur}) ×${it.quantite}`).join(', ')}
                </p>

                <div className="flex items-center justify-between border-t pt-3">
                  <span className="text-sm font-semibold">{fmt(order.total_a_payer)}</span>
                  <Button size="sm" onClick={() => examiner(order)}>
                    Examiner et confirmer
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* ------------------------------------------------ Fiche de validation */}
      <Dialog open={!!cible} onOpenChange={(o) => !o && fermer()}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Demande {cible?.numero}</DialogTitle>
            <DialogDescription>
              Complétez ce que le client ne choisit pas, puis confirmez : la commande passera en « Nouvelle ».
            </DialogDescription>
          </DialogHeader>

          {cible && (
            <div className="space-y-5">
              {/* Ce que le client a demandé — lecture seule */}
              <div className="rounded-lg border bg-muted/30 p-4 space-y-2 text-sm">
                <p className="font-medium flex items-center gap-1.5">
                  <UserRound className="h-4 w-4" /> {cible.client_nom}
                  {cible.client_email ? <span className="text-muted-foreground">· {cible.client_email}</span> : null}
                </p>
                <p className="text-muted-foreground">
                  {cible.telephone}
                  {cible.telephone_2 ? ` / ${cible.telephone_2}` : ''}
                </p>
                {cible.livraison_zone !== 'RECUPERATION' && (
                  <p className="text-muted-foreground flex items-start gap-1.5">
                    <MapPin className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                    {cible.adresse_livraison || 'Adresse non précisée'}
                  </p>
                )}
                <ul className="pt-2 border-t space-y-1">
                  {(cible.items || []).map((it: any) => (
                    <li key={it.id} className="flex items-center justify-between gap-3">
                      <span>{it.reference_name} ({it.couleur}) ×{it.quantite}</span>
                      <span className="tabular-nums">{fmt(Number(it.prix_unitaire) * Number(it.quantite))}</span>
                    </li>
                  ))}
                </ul>
              </div>

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
              <div className="rounded-lg border p-4 space-y-1.5 text-sm">
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
