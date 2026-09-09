'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { ShieldAlert, RefreshCw, Receipt, Undo2, PackageCheck } from 'lucide-react';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';

// Bornes du jour en heure locale — l'historique du livreur (voir orders/views.py
// ::get_queryset, branche `historique`) est déjà scopé à ce livreur, il ne
// reste qu'à borner la période à aujourd'hui.
function todayBounds() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
  const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
  return { start: start.toISOString(), end: end.toISOString() };
}

// Prix produit seul = total à payer moins les frais de livraison — dérivé
// sans avoir besoin du prix par article (jamais exposé au livreur, voir
// orders/serializers.py::OrderItemPublicSerializer).
const prixProduit = (order: any) =>
  Number(order.total_a_payer || 0) - Number(order.frais_livraison || 0);

function sumTotals(orders: any[]) {
  return {
    count: orders.length,
    prix: orders.reduce((s, o) => s + prixProduit(o), 0),
    frais: orders.reduce((s, o) => s + Number(o.frais_livraison || 0), 0),
    argent: orders.reduce((s, o) => s + Number(o.total_a_payer || 0), 0),
  };
}

export default function BilanPage() {
  const { isLivreur, loading: userLoading } = useCurrentUser();
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchOrders = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const { start, end } = todayBounds();
      const data = await djangoClient.orders.list({
        historique: true,
        date_from: start,
        date_to: end,
      });
      setOrders(data);
    } catch {
      setOrders([]);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(['order', 'order_status_history'], () => fetchOrders(true));
  useEffect(() => {
    if (!userLoading && isLivreur) fetchOrders();
  }, [userLoading, isLivreur, fetchOrders]);

  // Les retours ne sont volontairement pas additionnés aux livrées (§ demande)
  // — un colis retourné n'a rien fait encaisser au livreur.
  const livrees = useMemo(
    () => orders.filter((o) => o.statut_courant === 'LIVRE'),
    [orders],
  );
  const retours = useMemo(
    () => orders.filter((o) => o.statut_courant === 'RETOUR'),
    [orders],
  );
  const totalLivrees = useMemo(() => sumTotals(livrees), [livrees]);
  const totalRetours = useMemo(() => sumTotals(retours), [retours]);

  if (!userLoading && !isLivreur) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-20 text-center">
            <ShieldAlert className="h-12 w-12 text-red-500 mb-4" />
            <h2 className="text-xl font-bold">Accès refusé</h2>
            <p className="text-muted-foreground mt-2">Cette page est réservée au livreur.</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  const OrdersTable = ({ rows }: { rows: any[] }) => (
    <div className="overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>N° commande</TableHead>
            <TableHead>Type</TableHead>
            <TableHead>Sous-type</TableHead>
            <TableHead>Produit</TableHead>
            <TableHead>Date</TableHead>
            <TableHead>Client</TableHead>
            <TableHead>Adresse</TableHead>
            <TableHead className="text-right">Prix</TableHead>
            <TableHead className="text-right">Frais</TableHead>
            <TableHead className="text-right">Argent</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((order) => {
            const firstItem = (order.items || [])[0];
            return (
              <TableRow key={order.id}>
                <TableCell className="align-top font-medium">{order.numero}</TableCell>
                <TableCell className="align-top">{firstItem?.category_name || '-'}</TableCell>
                <TableCell className="align-top">{firstItem?.type_name || '-'}</TableCell>
                <TableCell className="align-top max-w-[220px]">
                  {(order.items || [])
                    .map((it: any) => `${it.reference_name}${it.couleur ? ` (${it.couleur})` : ''} x${it.quantite}`)
                    .join(', ')}
                </TableCell>
                <TableCell className="align-top whitespace-nowrap text-xs text-muted-foreground">
                  {order.date_commande
                    ? new Date(order.date_commande).toLocaleString('fr-FR', {
                        day: '2-digit',
                        month: '2-digit',
                        hour: '2-digit',
                        minute: '2-digit',
                      })
                    : '-'}
                </TableCell>
                <TableCell className="align-top">{order.client_nom}</TableCell>
                <TableCell className="align-top max-w-[180px] truncate">
                  {order.adresse_livraison || '-'}
                </TableCell>
                <TableCell className="align-top text-right">{fmt(prixProduit(order))}</TableCell>
                <TableCell className="align-top text-right">{fmt(order.frais_livraison)}</TableCell>
                <TableCell className="align-top text-right font-medium">
                  {fmt(order.total_a_payer)}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Bilan du jour</h1>
          <p className="text-sm text-muted-foreground">
            Livraisons effectuées et retours d'aujourd'hui — voir le ticket récapitulatif.
          </p>
        </div>
        <Button variant="outline" size="icon" onClick={() => fetchOrders()}>
          <RefreshCw className="h-4 w-4" />
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_300px] gap-6">
        {/* Tableaux — livraisons effectuées puis retours, jamais mélangés dans les totaux */}
        <div className="space-y-6 min-w-0">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <PackageCheck className="h-4 w-4" /> Livraisons effectuées ({livrees.length})
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6">
                  <Skeleton className="h-32 w-full" />
                </div>
              ) : livrees.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-10">
                  Aucune livraison effectuée aujourd'hui.
                </p>
              ) : (
                <OrdersTable rows={livrees} />
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Undo2 className="h-4 w-4 text-red-600" /> Retours ({retours.length})
              </CardTitle>
              <CardDescription>
                Colis rapportés — rien n'a été encaissé, ces montants ne sont pas comptés dans le
                total du ticket.
              </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6">
                  <Skeleton className="h-24 w-full" />
                </div>
              ) : retours.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-10">
                  Aucun retour aujourd'hui.
                </p>
              ) : (
                <OrdersTable rows={retours} />
              )}
            </CardContent>
          </Card>
        </div>

        {/* Ticket récapitulatif */}
        <div className="lg:sticky lg:top-6 self-start">
          <Card className="font-mono">
            <CardHeader className="text-center border-b border-dashed">
              <Receipt className="h-5 w-5 mx-auto mb-1 text-muted-foreground" />
              <CardTitle className="text-base tracking-wide">BILAN DU JOUR</CardTitle>
              <CardDescription>
                {new Date().toLocaleDateString('fr-FR', {
                  day: '2-digit',
                  month: '2-digit',
                  year: 'numeric',
                })}
              </CardDescription>
            </CardHeader>
            <CardContent className="text-sm space-y-4 pt-4">
              <div className="space-y-1.5">
                <p className="text-xs font-semibold text-muted-foreground">LIVRAISONS EFFECTUÉES</p>
                <div className="flex justify-between">
                  <span>Nombre</span>
                  <span>{totalLivrees.count}</span>
                </div>
                <div className="flex justify-between">
                  <span>Total produits</span>
                  <span>{fmt(totalLivrees.prix)}</span>
                </div>
                <div className="flex justify-between">
                  <span>Total frais livraison</span>
                  <span>{fmt(totalLivrees.frais)}</span>
                </div>
                <div className="border-t border-dashed pt-1.5 flex justify-between font-bold">
                  <span>TOTAL ARGENT</span>
                  <span>{fmt(totalLivrees.argent)}</span>
                </div>
              </div>

              <div className="space-y-1.5 border-t border-dashed pt-3">
                <p className="text-xs font-semibold text-muted-foreground">
                  RETOURS (hors total ci-dessus)
                </p>
                <div className="flex justify-between">
                  <span>Nombre</span>
                  <span>{totalRetours.count}</span>
                </div>
                <div className="flex justify-between">
                  <span>Total produits</span>
                  <span>{fmt(totalRetours.prix)}</span>
                </div>
                <div className="flex justify-between">
                  <span>Total frais livraison</span>
                  <span>{fmt(totalRetours.frais)}</span>
                </div>
                <div className="border-t border-dashed pt-1.5 flex justify-between font-bold text-red-600">
                  <span>TOTAL NON ENCAISSÉ</span>
                  <span>{fmt(totalRetours.argent)}</span>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
