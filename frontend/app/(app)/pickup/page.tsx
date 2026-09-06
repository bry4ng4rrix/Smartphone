'use client';

import { useCallback, useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { ShieldAlert, RefreshCw, PackageCheck, Phone } from 'lucide-react';
import { toast } from 'sonner';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';

export default function PickupPage() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [confirming, setConfirming] = useState<number | null>(null);

  const fetchOrders = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const data = await djangoClient.orders.list({ statut: 'PRETE', livraison_zone: 'RECUPERATION' });
      setOrders(data);
    } catch (err: any) {
      toast.error(err.message || 'Erreur de chargement des commandes');
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(['order', 'order_status_history'], () => fetchOrders(true));
  useEffect(() => { if (!userLoading && isGerant) fetchOrders(); }, [userLoading, isGerant, fetchOrders]);

  const confirmPickup = async (order: any) => {
    setConfirming(order.id);
    try {
      await djangoClient.orders.changeStatus(order.id, 'LIVRE');
      toast.success(`Commande ${order.numero} récupérée`);
      fetchOrders(true);
    } catch (err: any) {
      toast.error(err.message || 'Action impossible');
    } finally {
      setConfirming(null);
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
            <PackageCheck className="h-6 w-6" /> Récupération sur place
          </h1>
          <p className="text-sm text-muted-foreground">
            Commandes prêtes à retirer au comptoir (zone "Récupération") — pas de livreur assigné.
          </p>
        </div>
        <Button variant="outline" size="icon" onClick={() => fetchOrders()}>
          <RefreshCw className="h-4 w-4" />
        </Button>
      </div>

      {loading ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-24 w-full" />)}
        </div>
      ) : orders.length === 0 ? (
        <Card>
          <CardContent className="py-16 text-center text-sm text-muted-foreground">
            Aucune commande prête à récupérer pour le moment.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {orders.map((order) => (
            <Card key={order.id}>
              <CardContent className="p-4 space-y-3">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-semibold">{order.numero}</p>
                    <p className="text-sm text-muted-foreground">{order.client_nom}</p>
                  </div>
                  <Badge className="bg-blue-100 text-blue-800">Prête</Badge>
                </div>
                <a
                  href={`tel:${order.telephone}`}
                  className="flex items-center gap-1.5 text-sm text-blue-600 hover:underline w-fit"
                >
                  <Phone className="h-3.5 w-3.5" /> {order.telephone}
                </a>
                <div className="text-sm text-muted-foreground">
                  {(order.items || []).map((it: any) => `${it.reference_name} (${it.couleur}) x${it.quantite}`).join(', ')}
                </div>
                <div className="flex items-center justify-between border-t pt-3">
                  <span className="text-sm font-semibold">{fmt(order.total_a_payer)}</span>
                  <Button size="sm" onClick={() => confirmPickup(order)} disabled={confirming === order.id}>
                    <PackageCheck className="h-4 w-4 mr-1" />
                    {confirming === order.id ? 'Confirmation...' : 'Marquer comme récupérée'}
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
