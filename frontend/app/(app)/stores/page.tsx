'use client';

import { useEffect, useState, useCallback } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';

import { Store, Users, RefreshCw, Loader2, Edit, ArrowLeftRight } from 'lucide-react';
import { toast } from 'sonner';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { TransferProductsDialog } from '@/components/transfer-products-dialog';

export default function StoresPage() {
  const { user, isAdmin } = useCurrentUser();

  const [stores, setStores] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const [isRegisterDialogOpen, setIsRegisterDialogOpen] = useState(false);

  const [storeName, setStoreName] = useState('');
  const [managerName, setManagerName] = useState('');
  const [managerEmail, setManagerEmail] = useState('');
  const [managerPassword, setManagerPassword] = useState('');

  const [submittingStore, setSubmittingStore] = useState(false);

  const [editingStore, setEditingStore] = useState<any>(null);
  const [isEditStoreDialogOpen, setIsEditStoreDialogOpen] = useState(false);
  const [editStoreName, setEditStoreName] = useState('');
  const [editStoreLogoFile, setEditStoreLogoFile] = useState<File | null>(null);
  const [editStoreLogoPreview, setEditStoreLogoPreview] = useState<string | null>(null);
  const [submittingEditStore, setSubmittingEditStore] = useState(false);

  const [isTransferDialogOpen, setIsTransferDialogOpen] = useState(false);
  const [transferSourceStore, setTransferSourceStore] = useState<any>(null);

  const fetchData = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);

    try {
      const data = await djangoClient.get<any[]>(
        '/users/magasins/users/'
      );

      let stats: any[] = [];
      let profitByMagasins: any[] = [];

      try {
        stats = await djangoClient.get<any[]>(
          '/users/magasins/stats/'
        );
      } catch (statsErr) {
        console.error(statsErr);
      }

      if (isAdmin) {
        try {
          const profitRes =
            await djangoClient.transfers.getProfitByMagasins();

          profitByMagasins =
            profitRes?.profit_by_magasins || [];
        } catch (profitErr) {
          console.error(profitErr);
        }
      }

      const merged = data.map((store) => {
        const storeStats =
          stats.find(
            (item) =>
              item.magasin_id === store.magasin_id
          ) || {
            total_products: 0,
            total_stock_value: 0,
            total_sold_value: 0,
            profit: 0,
          };

        const profitStats =
          profitByMagasins.find(
            (item) =>
              item.magasin_id === store.magasin_id
          );

        return {
          ...store,
          stats: {
            ...storeStats,
            profit:
              profitStats?.total_profit ??
              storeStats.profit ??
              0,
          },
        };
      });

      setStores(merged);
    } catch (err) {
      console.error(err);
      if (!silent) toast.error('Erreur lors du chargement.');
    } finally {
      if (!silent) setLoading(false);
    }
  }, [isAdmin]);

  useRealtimeRefresh(['product_variant', 'order'], () => fetchData(true));

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const handleStartEditStore = (store: any) => {
    setEditingStore(store);
    setEditStoreName(store.shop_name);
    setEditStoreLogoFile(null);
    setEditStoreLogoPreview(store.shop_logo || null);
    setIsEditStoreDialogOpen(true);
  };

  const handleEditStoreLogoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setEditStoreLogoFile(file);
      setEditStoreLogoPreview(URL.createObjectURL(file));
    }
  };

  const handleUpdateStore = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingStore) return;
    setSubmittingEditStore(true);
    try {
      const formData = new FormData();
      formData.append('shop_name', editStoreName);
      if (editStoreLogoFile) {
        formData.append('shop_logo', editStoreLogoFile);
      }
      
      await djangoClient.patchFormData(`/users/magasins/${editingStore.magasin_id}/`, formData);
      toast.success('Magasin mis à jour avec succès');
      setIsEditStoreDialogOpen(false);
      fetchData();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la mise à jour');
    } finally {
      setSubmittingEditStore(false);
    }
  };

  const handleRegisterStore = async (
    e: React.FormEvent
  ) => {
    e.preventDefault();

    setSubmittingStore(true);

    try {
      const response =
        await djangoClient.auth.register(
          managerEmail,
          managerEmail,
          managerPassword,
          'magasin',
          {
            full_name: managerName,
            shop_name: storeName,
            admin_email: user?.email,
          }
        );

      if (response?.id) {
        await djangoClient.auth.approveUser(
          response.id
        );
      }

      toast.success('Magasin créé.');

      setStoreName('');
      setManagerName('');
      setManagerEmail('');
      setManagerPassword('');

      setIsRegisterDialogOpen(false);

      fetchData();
    } catch (err: any) {
      toast.error(
        err?.message ||
          'Erreur lors de la création.'
      );
    } finally {
      setSubmittingStore(false);
    }
  };

  const formatNumber = (
    value: number | string | null | undefined
  ) =>
    new Intl.NumberFormat('fr-FR').format(
      Number(value ?? 0)
    );

  const formatCurrency = (
    value: number | string | null | undefined
  ) =>
    `${new Intl.NumberFormat('fr-MG').format(
      Number(value ?? 0)
    )} Ar`;
  const handleStartTransfer = (store: any) => {
    setTransferSourceStore(store);
    setIsTransferDialogOpen(true);
  };

  const handleTransferDialogChange = (open: boolean) => {
    setIsTransferDialogOpen(open);
    if (!open) setTransferSourceStore(null);
  };

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 sm:px-6 py-6 sm:py-8 space-y-6">

        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl sm:text-3xl font-bold">
              Magasins
            </h1>

            <p className="text-muted-foreground text-sm sm:text-base">
              {stores.length} magasin(s)
            </p>
          </div>

          <div className="flex flex-wrap gap-2">

            {isAdmin && (
              <Dialog
                open={isRegisterDialogOpen}
                onOpenChange={setIsRegisterDialogOpen}
              >
                <DialogTrigger asChild>
                  <Button>
                    Créer un magasin
                  </Button>
                </DialogTrigger>

                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>
                      Nouveau magasin
                    </DialogTitle>

                    <DialogDescription>
                      Ajouter un magasin
                    </DialogDescription>
                  </DialogHeader>

                  <form
                    onSubmit={handleRegisterStore}
                    className="space-y-4"
                  >
                    <div>
                      <Label>
                        Nom du magasin
                      </Label>

                      <Input
                        value={storeName}
                        onChange={(e) =>
                          setStoreName(
                            e.target.value
                          )
                        }
                      />
                    </div>

                    <div>
                      <Label>
                        Nom du gérant
                      </Label>

                      <Input
                        value={managerName}
                        onChange={(e) =>
                          setManagerName(
                            e.target.value
                          )
                        }
                      />
                    </div>

                    <div>
                      <Label>Email</Label>

                      <Input
                        type="email"
                        value={managerEmail}
                        onChange={(e) =>
                          setManagerEmail(
                            e.target.value
                          )
                        }
                      />
                    </div>

                    <div>
                      <Label>
                        Mot de passe
                      </Label>

                      <Input
                        type="password"
                        value={managerPassword}
                        onChange={(e) =>
                          setManagerPassword(
                            e.target.value
                          )
                        }
                      />
                    </div>

                    <Button
                      type="submit"
                      disabled={submittingStore}
                      className="w-full"
                    >
                      {submittingStore ? (
                        <>
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                          Création...
                        </>
                      ) : (
                        'Créer'
                      )}
                    </Button>
                  </form>
                </DialogContent>
              </Dialog>
            )}

            <Button
              variant="outline"
              onClick={() => fetchData()}
            >
              <RefreshCw
                className={`h-4 w-4 mr-2 ${
                  loading
                    ? 'animate-spin'
                    : ''
                }`}
              />

              Actualiser
            </Button>
          </div>
        </div>

        {loading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
            {Array.from({ length: 3 }).map(
              (_, i) => (
                <Skeleton
                  key={i}
                  className="h-48 rounded-xl"
                />
              )
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
                 
            {stores.map((store) => (
              <Card
                key={store.magasin_id}
              >
                <CardHeader className="flex flex-row items-start justify-between space-y-0 pb-2 gap-2">
                  <CardTitle className="flex items-center gap-2 min-w-0 text-base sm:text-lg">
                    {store.shop_logo ? (
                      <img src={store.shop_logo} alt="logo" className="h-5 w-5 shrink-0 rounded-full object-cover" />
                    ) : (
                      <Store className="h-5 w-5 shrink-0" />
                    )}
                    <span className="truncate">{store.shop_name}</span>
                  </CardTitle>
                  {isAdmin && (
                   <div className="flex shrink-0 gap-1 sm:gap-2">
                                        {/*transfert products between stores  */}    
                    <Button 
                      size="icon"
                      variant='outline'
                      onClick={() => handleStartTransfer(store)}
                    >
                      <ArrowLeftRight className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => handleStartEditStore(store)}
                    >
                     <Edit className="h-4 w-4" />
                    </Button>
                   </div>
                  )}
                </CardHeader>

                <CardContent className="space-y-4">

                  {store.manager && (
                    <div className="border-b pb-3">
                      <p className="font-medium">
                        {store.manager.full_name}
                      </p>

                      <p className="text-sm text-muted-foreground">
                        {store.manager.email}
                      </p>
                    </div>
                  )}

                  <div className="grid grid-cols-2 gap-2 sm:gap-3">

                    <div className="border rounded-lg p-2 sm:p-3">
                      <p className="text-xs text-muted-foreground">
                        Produits
                      </p>

                    <div>
                    <p className="font-bold text-sm sm:text-base leading-tight">
                    {formatNumber(store.stats?.total_stock_quantity)} unité(s) sur {formatNumber(store.stats?.total_products)} produits
                      </p>

                    </div>
                    </div>

                    <div className="border rounded-lg p-2 sm:p-3">
                      <p className="text-xs text-muted-foreground">
                        Stock
                      </p>

                      <p className="font-bold text-sm sm:text-base">
                        {formatCurrency(
                          store.stats?.total_stock_value
                        )}
                      </p>
                    </div>

                    <div className="border rounded-lg p-2 sm:p-3">
                      <p className="text-xs text-muted-foreground">
                        Ventes
                      </p>

                      <p className="font-bold text-sm sm:text-base">
                        {formatCurrency(
                          store.stats?.total_sold_value
                        )}
                      </p>
                    </div>

                    <div className="border rounded-lg p-2 sm:p-3 bg-green-50 dark:bg-green-950/30">
                      <p className="text-xs text-muted-foreground">
                        Profit
                      </p>

                      <p className="font-bold text-sm sm:text-base text-green-700 dark:text-green-400">
                        {formatCurrency(
                          store.stats?.profit
                        )}
                      </p>
                    </div>
                  </div>

                  <div className="border-t pt-3">
                    <p className="flex items-center gap-2 text-sm font-medium">
                      <Users className="h-4 w-4" />
                      Employés (
                      {store.employers?.length || 0})
                    </p>

                    <div className="space-y-2 mt-2">
                      {store.employers
                        ?.slice(0, 3)
                        .map((emp: any) => (
                          <div
                            key={emp.id}
                            className="flex justify-between items-center"
                          >
                            <span className="text-sm">
                              {emp.full_name}
                            </span>

                            <Badge variant="outline">
                              {emp.is_confirmed
                                ? 'Actif'
                                : 'Attente'}
                            </Badge>
                          </div>
                        ))}
                    </div>
                  </div>

                </CardContent>
              </Card>
            ))}

          </div>
        )}
      </div>

      <TransferProductsDialog
        open={isTransferDialogOpen}
        onOpenChange={handleTransferDialogChange}
        sourceStore={transferSourceStore}
        stores={stores}
        onSuccess={() => fetchData()}
      />

      <Dialog open={isEditStoreDialogOpen} onOpenChange={setIsEditStoreDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Modifier le magasin</DialogTitle>
            <DialogDescription>
              Modifier le nom et le logo du magasin.
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleUpdateStore} className="space-y-4">
            <div>
              <Label>Nom du magasin</Label>
              <Input
                value={editStoreName}
                onChange={(e) => setEditStoreName(e.target.value)}
                required
              />
            </div>
            
            <div>
              <Label>Logo du magasin</Label>
              <Input
                type="file"
                accept="image/*"
                onChange={handleEditStoreLogoChange}
              />
              {editStoreLogoPreview && (
                <div className="mt-2 flex justify-center">
                  <img
                    src={editStoreLogoPreview}
                    alt="Logo magasin"
                    className="h-20 w-20 object-contain rounded-md border"
                  />
                </div>
              )}
            </div>

            <Button
              type="submit"
              disabled={submittingEditStore}
              className="w-full"
            >
              {submittingEditStore ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Enregistrement...
                </>
              ) : (
                'Enregistrer'
              )}
            </Button>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}