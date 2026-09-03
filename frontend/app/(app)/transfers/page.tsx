'use client';

import { useCallback, useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import {
  TransferProductsPanel,
  type TransferStore,
} from '@/components/transfer-products-panel';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Store, ShieldAlert, ArrowLeftRight } from 'lucide-react';
import { toast } from 'sonner';

export default function TransfersPage() {
  const { isAdmin, loading: userLoading } = useCurrentUser();
  const [stores, setStores] = useState<TransferStore[]>([]);
  const [loading, setLoading] = useState(true);
  const [sourceStoreId, setSourceStoreId] = useState<number | null>(null);

  const fetchStores = useCallback(async () => {
    setLoading(true);
    try {
      const data = await djangoClient.get<any[]>('/users/magasins/users/');
      setStores(data);
    } catch (err: any) {
      toast.error('Erreur de chargement des magasins: ' + (err.message || err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isAdmin) fetchStores();
  }, [isAdmin, fetchStores]);

  const sourceStore = stores.find((s) => s.magasin_id === sourceStoreId) ?? null;

  if (userLoading || loading) {
    return (
      <div className="p-6 space-y-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-16 w-full" />
        ))}
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-20 text-center">
            <ShieldAlert className="h-12 w-12 text-red-500 mb-4" />
            <h2 className="text-xl font-bold">Accès refusé</h2>
            <p className="text-muted-foreground mt-2">
              Cette page est réservée aux administrateurs.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col gap-4 p-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
          <ArrowLeftRight className="h-8 w-8 text-blue-600" />
          Transfert de produits
        </h1>
        <p className="text-muted-foreground mt-1">
          Choisissez un magasin source, puis sélectionnez les produits (et
          leurs variantes) à transférer vers un autre magasin.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium text-muted-foreground shrink-0">
          Magasin source :
        </span>
        {stores.length === 0 ? (
          <span className="text-sm text-muted-foreground">Aucun magasin</span>
        ) : (
          stores.map((store) => (
            <button
              key={store.magasin_id}
              type="button"
              onClick={() => setSourceStoreId(store.magasin_id)}
              className={`flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm transition-colors hover:bg-muted/50 ${
                sourceStoreId === store.magasin_id
                  ? 'bg-primary/10 border-primary/30 font-medium'
                  : 'border-border'
              }`}
            >
              {store.shop_logo ? (
                <img
                  src={store.shop_logo}
                  alt=""
                  className="h-4 w-4 rounded-full object-cover"
                />
              ) : (
                <Store className="h-4 w-4 text-muted-foreground" />
              )}
              {store.shop_name}
            </button>
          ))
        )}
      </div>

      {sourceStore ? (
        <TransferProductsPanel
          key={sourceStore.magasin_id}
          sourceStore={sourceStore}
          stores={stores}
          onSuccess={() => {
            setSourceStoreId(null);
            fetchStores();
          }}
        />
      ) : (
        <div className="flex-1 min-h-[300px] flex items-center justify-center text-muted-foreground border rounded-lg border-dashed">
          Sélectionnez un magasin source pour commencer.
        </div>
      )}
    </div>
  );
}
