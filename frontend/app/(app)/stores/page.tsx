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

import { Store, Users, RefreshCw, Loader2, Edit, ArrowLeftRight, Trash2, UserCog, MapPin, Phone, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { TransferProductsDialog } from '@/components/transfer-products-dialog';
import { ConfirmDeleteDialog } from '@/components/confirm-delete-dialog';
import { Textarea } from '@/components/ui/textarea';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

export default function StoresPage() {
  const { user, isAdmin } = useCurrentUser();

  const [stores, setStores] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const [isRegisterDialogOpen, setIsRegisterDialogOpen] = useState(false);

  const [storeName, setStoreName] = useState('');
  // Coordonnées du point de vente : l'adresse et le premier numéro sont
  // exigés (c'est ce qu'on donne au client qui vient retirer sa commande),
  // le second numéro est un secours facultatif.
  const [storeAdresse, setStoreAdresse] = useState('');
  const [storeTelephone, setStoreTelephone] = useState('');
  const [storeTelephone2, setStoreTelephone2] = useState('');
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

  const [editStoreDescription, setEditStoreDescription] = useState('');
  const [editStoreAdresse, setEditStoreAdresse] = useState('');
  const [editStoreTelephone, setEditStoreTelephone] = useState('');
  const [editStoreTelephone2, setEditStoreTelephone2] = useState('');
  // '' = inchangé, 'aucun' = détacher, sinon l'id du compte gérant.
  const [editManagerId, setEditManagerId] = useState<string>('');

  // Création : un magasin peut naître sans gérant, on l'affecte plus tard.
  const [avecGerant, setAvecGerant] = useState(true);

  const [isTransferDialogOpen, setIsTransferDialogOpen] = useState(false);
  const [transferSourceStore, setTransferSourceStore] = useState<any>(null);

  // Suppression : on demande d'abord au serveur ce qu'elle détruirait.
  const [deleteTarget, setDeleteTarget] = useState<any>(null);
  const [deleteContenu, setDeleteContenu] = useState<any>(null);
  const [confirmationNom, setConfirmationNom] = useState('');

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
    setEditStoreDescription(store.description || '');
    setEditStoreAdresse(store.adresse || '');
    setEditStoreTelephone(store.telephone || '');
    setEditStoreTelephone2(store.telephone_2 || '');
    setEditManagerId(store.gerant ? String(store.gerant.id) : 'aucun');
    setEditStoreLogoFile(null);
    setEditStoreLogoPreview(store.shop_logo || null);
    setIsEditStoreDialogOpen(true);
  };

  /**
   * Comptes pouvant devenir gérant de `store` : ceux de rôle « magasin » qui
   * ne tiennent aucune autre boutique. `MagasinProfile.user` est un OneToOne,
   * un compte ne peut donc gérer qu'un magasin à la fois — proposer un gérant
   * déjà pris ne ferait qu'amener un refus du serveur.
   */
  const gerantsDisponibles = (store: any) => {
    const pris = new Set(
      stores.filter((s) => s.gerant && s.magasin_id !== store?.magasin_id).map((s) => s.gerant.id),
    );
    const comptes = stores.flatMap((s) => s.company_users || []);
    const vus = new Set<number>();
    return comptes.filter((u: any) => {
      if (u.role !== 'magasin' || pris.has(u.id) || vus.has(u.id)) return false;
      vus.add(u.id);
      return true;
    });
  };

  /**
   * Ouvre la confirmation de suppression — après avoir demandé au serveur ce
   * qu'elle détruirait. On ne propose jamais une suppression impossible : un
   * magasin qui a vendu garde son historique (OrderItem.product_variant est
   * en PROTECT côté base).
   */
  const handleStartDeleteStore = async (store: any) => {
    setDeleteTarget(store);
    setDeleteContenu(null);
    setConfirmationNom('');
    try {
      setDeleteContenu(await djangoClient.magasins.contenu(store.magasin_id));
    } catch (err: any) {
      toast.error(err.message || 'Impossible de lire le contenu du magasin');
      setDeleteTarget(null);
    }
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
      // Le logo passe en multipart ; le reste en JSON, parce qu'un FormData
      // ne sait pas transporter un `null` (nécessaire pour détacher le gérant).
      if (editStoreLogoFile) {
        const formData = new FormData();
        formData.append('shop_name', editStoreName);
        formData.append('shop_logo', editStoreLogoFile);
        await djangoClient.patchFormData(`/users/magasins/${editingStore.magasin_id}/`, formData);
      }

      const infos: {
        shop_name: string;
        description: string;
        adresse: string;
        telephone: string;
        telephone_2: string;
        manager_id?: number | null;
      } = {
        shop_name: editStoreName,
        description: editStoreDescription,
        adresse: editStoreAdresse.trim(),
        telephone: editStoreTelephone.trim(),
        telephone_2: editStoreTelephone2.trim(),
      };
      const gerantActuel = editingStore.gerant ? String(editingStore.gerant.id) : 'aucun';
      if (editManagerId !== gerantActuel) {
        infos.manager_id = editManagerId === 'aucun' ? null : Number(editManagerId);
      }
      await djangoClient.magasins.update(editingStore.magasin_id, infos);

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
      if (avecGerant) {
        // Voie historique : le compte gérant et le magasin naissent ensemble.
        const response = await djangoClient.auth.register(
          managerEmail,
          managerEmail,
          managerPassword,
          'magasin',
          {
            full_name: managerName,
            shop_name: storeName,
            shop_adresse: storeAdresse.trim(),
            shop_telephone: storeTelephone.trim(),
            shop_telephone_2: storeTelephone2.trim(),
            admin_email: user?.email,
          }
        );

        if (response?.id) {
          await djangoClient.auth.approveUser(response.id);
        }
      } else {
        // Magasin seul : on lui affectera un gérant plus tard, depuis le
        // bouton « Modifier » de sa carte.
        await djangoClient.magasins.create({
          shop_name: storeName,
          adresse: storeAdresse.trim(),
          telephone: storeTelephone.trim(),
          telephone_2: storeTelephone2.trim(),
        });
      }

      toast.success(avecGerant ? 'Magasin et gérant créés.' : 'Magasin créé, sans gérant.');

      setStoreName('');
      setStoreAdresse('');
      setStoreTelephone('');
      setStoreTelephone2('');
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

                    {/* Coordonnées du point de vente : c'est ce qu'on
                        communique au client venant retirer sa commande. */}
                    <div>
                      <Label>Adresse du magasin</Label>
                      <Input
                        value={storeAdresse}
                        onChange={(e) => setStoreAdresse(e.target.value)}
                        placeholder="Lot II M 12 bis, Antananarivo"
                        required
                      />
                    </div>

                    <div className="grid gap-3 sm:grid-cols-2">
                      <div>
                        <Label>Numéro du magasin</Label>
                        <Input
                          value={storeTelephone}
                          onChange={(e) => setStoreTelephone(e.target.value)}
                          placeholder="+261 34 00 000 00"
                          required
                        />
                      </div>
                      <div>
                        <Label>
                          Numéro 2{' '}
                          <span className="font-normal text-muted-foreground">
                            (facultatif)
                          </span>
                        </Label>
                        <Input
                          value={storeTelephone2}
                          onChange={(e) => setStoreTelephone2(e.target.value)}
                          placeholder="+261 32 00 000 00"
                        />
                      </div>
                    </div>

                    {/* Un magasin peut naître sans gérant : on l'affecte
                        ensuite depuis « Modifier » sur sa carte. */}
                    <label className="flex cursor-pointer items-start gap-2 rounded-md border p-3 text-sm">
                      <input
                        type="checkbox"
                        checked={!avecGerant}
                        onChange={(e) => setAvecGerant(!e.target.checked)}
                        className="mt-0.5"
                      />
                      <span>
                        Créer le magasin sans gérant
                        <span className="block text-xs text-muted-foreground">
                          Vous lui affecterez un gérant plus tard.
                        </span>
                      </span>
                    </label>

                    {avecGerant && (
                      <>
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
                            required
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
                            required
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
                            required
                            minLength={6}
                          />
                        </div>
                      </>
                    )}

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
                      title="Modifier le magasin et son gérant"
                    >
                     <Edit className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => handleStartDeleteStore(store)}
                      title="Supprimer ce magasin"
                    >
                      <Trash2 className="h-4 w-4 text-red-500" />
                    </Button>
                   </div>
                  )}
                </CardHeader>

                <CardContent className="space-y-4">

                  {/* Le gérant du magasin — distinct de `manager`, qui est
                      l'admin de la société. Un magasin peut ne pas en avoir. */}
                  <div className="border-b pb-3">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">
                      Gérant
                    </p>
                    {store.gerant ? (
                      <>
                        <p className="font-medium">{store.gerant.full_name}</p>
                        <p className="text-sm text-muted-foreground">{store.gerant.email}</p>
                      </>
                    ) : (
                      <div className="flex items-center gap-2 pt-1">
                        <Badge variant="outline" className="gap-1 font-normal">
                          <UserCog className="h-3 w-3" /> Aucun gérant
                        </Badge>
                        {isAdmin && (
                          <button
                            type="button"
                            onClick={() => handleStartEditStore(store)}
                            className="text-xs text-blue-600 hover:underline dark:text-blue-400"
                          >
                            Affecter
                          </button>
                        )}
                      </div>
                    )}
                  </div>

                  {/* Coordonnées du point de vente. Un magasin sans adresse
                      ni numéro ne peut rien dire au client qui vient retirer
                      sa commande : on le signale plutôt que de laisser un
                      blanc silencieux. */}
                  <div className="border-b pb-3">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">
                      Coordonnées
                    </p>
                    {store.adresse || store.telephone ? (
                      <div className="space-y-1 pt-1 text-sm">
                        {store.adresse && (
                          <p className="flex items-start gap-1.5">
                            <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                            <span>{store.adresse}</span>
                          </p>
                        )}
                        {store.telephone && (
                          <p className="flex items-center gap-1.5">
                            <Phone className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                            <span>
                              {store.telephone}
                              {store.telephone_2 && ` / ${store.telephone_2}`}
                            </span>
                          </p>
                        )}
                      </div>
                    ) : (
                      <div className="flex items-center gap-2 pt-1">
                        <Badge variant="outline" className="gap-1 font-normal text-amber-600 dark:text-amber-400">
                          <AlertTriangle className="h-3 w-3" /> Non renseignées
                        </Badge>
                        {isAdmin && (
                          <button
                            type="button"
                            onClick={() => handleStartEditStore(store)}
                            className="text-xs text-blue-600 hover:underline dark:text-blue-400"
                          >
                            Renseigner
                          </button>
                        )}
                      </div>
                    )}
                  </div>

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
              Nom, coordonnées, description, logo et gérant.
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

            {/* Adresse et premier numéro : exigés aussi par le serveur
                (MagasinViewSet.partial_update), qui refuse un envoi vide. */}
            <div>
              <Label>Adresse du magasin</Label>
              <Input
                value={editStoreAdresse}
                onChange={(e) => setEditStoreAdresse(e.target.value)}
                placeholder="Lot II M 12 bis, Antananarivo"
                required
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Affichée au client qui vient retirer sa commande sur place.
              </p>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <Label>Numéro du magasin</Label>
                <Input
                  value={editStoreTelephone}
                  onChange={(e) => setEditStoreTelephone(e.target.value)}
                  placeholder="+261 34 00 000 00"
                  required
                />
              </div>
              <div>
                <Label>
                  Numéro 2{' '}
                  <span className="font-normal text-muted-foreground">
                    (facultatif)
                  </span>
                </Label>
                <Input
                  value={editStoreTelephone2}
                  onChange={(e) => setEditStoreTelephone2(e.target.value)}
                  placeholder="+261 32 00 000 00"
                />
              </div>
            </div>

            <div>
              <Label>Description</Label>
              <Textarea
                value={editStoreDescription}
                onChange={(e) => setEditStoreDescription(e.target.value)}
                placeholder="Quartier, spécialité, horaires…"
                rows={2}
              />
            </div>

            <div>
              <Label>Gérant</Label>
              <Select value={editManagerId} onValueChange={setEditManagerId}>
                <SelectTrigger>
                  <SelectValue placeholder="Choisir un gérant" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="aucun">Aucun gérant</SelectItem>
                  {gerantsDisponibles(editingStore).map((u: any) => (
                    <SelectItem key={u.id} value={String(u.id)}>
                      {u.full_name} — {u.email}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="mt-1 text-xs text-muted-foreground">
                Seuls les comptes « gérant de magasin » libres sont proposés :
                un compte ne peut tenir qu&apos;une boutique à la fois.
              </p>
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

      {/* Suppression d'un magasin — trois barrières : l'inventaire de ce qui
          sera détruit, le nom exact à retaper, puis le mot de passe de
          l'administrateur (demandé par ConfirmDeleteDialog). */}
      <ConfirmDeleteDialog
        open={!!deleteTarget && !!deleteContenu}
        onOpenChange={(ouvert) => {
          if (!ouvert) {
            setDeleteTarget(null);
            setDeleteContenu(null);
            setConfirmationNom('');
          }
        }}
        title={`Supprimer « ${deleteTarget?.shop_name ?? ''} » ?`}
        description={
          deleteContenu ? (
            <div className="space-y-3">
              {deleteContenu.suppression_possible ? (
                <>
                  <p>Cette action est irréversible. Seront définitivement supprimés :</p>
                  <ul className="list-inside list-disc text-sm">
                    {Object.entries(deleteContenu.contenu)
                      .filter(([, n]) => Number(n) > 0)
                      .map(([cle, n]) => (
                        <li key={cle}>
                          <span className="font-medium tabular-nums">{String(n)}</span>{' '}
                          {cle.replace(/_/g, ' ')}
                        </li>
                      ))}
                    {Object.values(deleteContenu.contenu).every((n) => Number(n) === 0) && (
                      <li className="list-none text-muted-foreground">
                        Ce magasin est vide.
                      </li>
                    )}
                  </ul>
                  <div>
                    <Label className="text-xs">
                      Retapez le nom exact du magasin pour confirmer
                    </Label>
                    <Input
                      value={confirmationNom}
                      onChange={(e) => setConfirmationNom(e.target.value)}
                      placeholder={deleteTarget?.shop_name}
                      autoComplete="off"
                    />
                  </div>
                </>
              ) : (
                <p className="text-amber-600 dark:text-amber-500">
                  {deleteContenu.raison_blocage} Vous pouvez en revanche retirer
                  son gérant depuis « Modifier ».
                </p>
              )}
            </div>
          ) : null
        }
        onConfirm={async (password) => {
          if (!deleteContenu?.suppression_possible) {
            throw new Error('Ce magasin ne peut pas être supprimé.');
          }
          if (confirmationNom.trim() !== deleteTarget.shop_name) {
            throw new Error(`Retapez exactement : « ${deleteTarget.shop_name} »`);
          }
          await djangoClient.magasins.remove(
            deleteTarget.magasin_id,
            confirmationNom.trim(),
            password,
          );
          toast.success(`« ${deleteTarget.shop_name} » supprimé.`);
          setDeleteTarget(null);
          setDeleteContenu(null);
          setConfirmationNom('');
          fetchData();
        }}
      />
    </div>
  );
}