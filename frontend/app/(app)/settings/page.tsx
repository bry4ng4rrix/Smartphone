'use client';

import { useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { toast } from 'sonner';
import { User, Lock, Building2, Loader2, Plus, Pencil, Trash2, Wallet, MapPin } from 'lucide-react';

const roleLabel: Record<string, string> = {
  admin: 'Administrateur',
  magasin: 'Gérant de magasin',
  employer: 'Commercial',
};

export default function SettingsPage() {
  const { user, isGerant, loading: userLoading } = useCurrentUser();
  const [expenseCategories, setExpenseCategories] = useState<any[]>([]);

  const loadExpenseCategories = () => {
    if (!isGerant) return;
    djangoClient.caisse.categories.list().then(setExpenseCategories).catch(() => {});
  };

  useEffect(loadExpenseCategories, [isGerant]);

  const [deliveryZones, setDeliveryZones] = useState<any[]>([]);

  const loadDeliveryZones = () => {
    if (!isGerant) return;
    djangoClient.zones.list().then(setDeliveryZones).catch(() => {});
  };

  useEffect(loadDeliveryZones, [isGerant]);

  // Types de dépense proposés aux livreurs (§ demande).
  const [expenseTypes, setExpenseTypes] = useState<any[]>([]);

  const loadExpenseTypes = () => {
    if (!isGerant) return;
    djangoClient.expenseTypes.list().then(setExpenseTypes).catch(() => {});
  };

  useEffect(loadExpenseTypes, [isGerant]);

  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [adresse, setAdresse] = useState('');
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const [oldPassword, setOldPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [changingPw, setChangingPw] = useState(false);

  const [modalOpen, setModalOpen] = useState(false);
  const [companyName, setCompanyName] = useState('');
  const [shopName, setShopName] = useState('');
  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [logoPreview, setLogoPreview] = useState<string | null>(null);
  const [updatingDetails, setUpdatingDetails] = useState(false);

  useEffect(() => {
    if (user) {
      setFullName(user.full_name || '');
      setPhone(user.phone || '');
      setAdresse(user.adresse || '');
      setAvatarPreview(user.photo || null);
      setCompanyName(user.company_name || '');
      setShopName(user.shop_name || '');
    }
  }, [user]);

  const handleAvatarChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setAvatarFile(file);
      setAvatarPreview(URL.createObjectURL(file));
    }
  };

  const handleLogoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setLogoFile(file);
      setLogoPreview(URL.createObjectURL(file));
    }
  };

  const handleUpdateDetails = async (e: React.FormEvent) => {
    e.preventDefault();
    setUpdatingDetails(true);
    try {
      const formData = new FormData();
      if (user?.role === 'admin') {
        formData.append('company_name', companyName);
        if (logoFile) {
          formData.append('logo', logoFile);
        }
      } else if (user?.role === 'magasin') {
        formData.append('shop_name', shopName);
        if (logoFile) {
          formData.append('shop_logo', logoFile);
        }
      }

      await djangoClient.patchFormData('/users/me/', formData);
      toast.success('Informations mises à jour avec succès');
      setModalOpen(false);
      window.location.reload();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la mise à jour');
    } finally {
      setUpdatingDetails(false);
    }
  };

  const handleUpdateProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      await djangoClient.users.updateProfile({ full_name: fullName, phone, adresse });
      if (avatarFile) {
        const fd = new FormData();
        fd.append('photo', avatarFile);
        await djangoClient.patchFormData('/users/me/', fd);
        setAvatarFile(null);
      }
      toast.success('Profil mis à jour');
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la mise à jour');
    } finally {
      setSaving(false);
    }
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword !== confirmPassword) {
      toast.error('Les mots de passe ne correspondent pas');
      return;
    }
    if (newPassword.length < 6) {
      toast.error('Le mot de passe doit contenir au moins 6 caractères');
      return;
    }
    setChangingPw(true);
    try {
      await djangoClient.post('/users/change-password/', {
        old_password: oldPassword,
        new_password: newPassword,
      });
      toast.success('Mot de passe changé avec succès');
      setOldPassword('');
      setNewPassword('');
      setConfirmPassword('');
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors du changement de mot de passe');
    } finally {
      setChangingPw(false);
    }
  };

  if (userLoading) {
    return (
      <div className="p-6 space-y-4">
        {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-24 w-full" />)}
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Paramètres</h1>
        <p className="text-muted-foreground mt-1">Gérez votre profil et vos préférences</p>
      </div>

      <Tabs defaultValue="profile" className="space-y-6">
        <TabsList>
          <TabsTrigger value="profile">
            <User className="h-4 w-4 mr-2" />Mon profil
          </TabsTrigger>
          <TabsTrigger value="security">
            <Lock className="h-4 w-4 mr-2" />Sécurité
          </TabsTrigger>
          {isGerant && (
            <TabsTrigger value="depenses">
              <Wallet className="h-4 w-4 mr-2" />Dépenses
            </TabsTrigger>
          )}
          {isGerant && (
            <TabsTrigger value="zones">
              <MapPin className="h-4 w-4 mr-2" />Zones de livraison
            </TabsTrigger>
          )}
        </TabsList>

        {/* Profile tab */}
        <TabsContent value="profile">
          <Card>
            <CardHeader>
              <CardTitle>Informations personnelles</CardTitle>
              <CardDescription>
                {isGerant
                  ? 'Mettez à jour vos informations'
                  : 'Seul le gérant peut modifier ces informations. Contactez votre gérant pour toute correction.'}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleUpdateProfile} className="space-y-4 max-w-md">
                <div className="space-y-2">
                  <Label>Photo de profil</Label>
                  <div className="flex items-center gap-4">
                    {avatarPreview ? (
                      <img
                        src={avatarPreview}
                        alt="Photo de profil"
                        className="h-16 w-16 rounded-full object-cover border"
                      />
                    ) : (
                      <div className="h-16 w-16 rounded-full border bg-muted flex items-center justify-center">
                        <User className="h-6 w-6 text-muted-foreground" />
                      </div>
                    )}
                    <Input type="file" accept="image/*" onChange={handleAvatarChange} className="max-w-xs" disabled={!isGerant} />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Email</Label>
                  <Input value={user?.email || ''} disabled className="bg-muted" />
                  <p className="text-xs text-muted-foreground">L'email ne peut pas être modifié</p>
                </div>
                <div className="space-y-2">
                  <Label>Rôle</Label>
                  <div>
                    <Badge variant="outline">{roleLabel[user?.role || ''] || user?.role}</Badge>
                  </div>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="fullName">Nom complet</Label>
                  <Input
                    id="fullName"
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    placeholder="Votre nom"
                    disabled={!isGerant}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="phone">Téléphone</Label>
                  <Input
                    id="phone"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="+261 XX XXX XX XX"
                    disabled={!isGerant}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="adresse">Adresse</Label>
                  <Input
                    id="adresse"
                    value={adresse}
                    onChange={(e) => setAdresse(e.target.value)}
                    placeholder="Ex: Lot II A 45, Antanimena, Antananarivo"
                    disabled={!isGerant}
                  />
                </div>
                {user?.role === 'magasin' && user.shop_name && (
                  <div className="space-y-2 border-t pt-4">
                    <Label>Magasin</Label>
                    <div className="flex items-center justify-between gap-2 p-3 border rounded-lg bg-slate-50/50">
                      <div className="flex items-center gap-2 text-sm">
                        <Building2 className="h-4 w-4 text-muted-foreground" />
                        <span className="font-semibold">{user.shop_name}</span>
                      </div>
                      <Button type="button" variant="outline" size="sm" onClick={() => setModalOpen(true)}>
                        Modifier
                      </Button>
                    </div>
                  </div>
                )}
                {user?.role === 'admin' && user.company_name && (
                  <div className="space-y-2 border-t pt-4">
                    <Label>Entreprise</Label>
                    <div className="flex items-center justify-between gap-2 p-3 border rounded-lg bg-slate-50/50">
                      <div className="flex items-center gap-2 text-sm">
                        <Building2 className="h-4 w-4 text-muted-foreground" />
                        <span className="font-semibold">{user.company_name}</span>
                      </div>
                      <Button type="button" variant="outline" size="sm" onClick={() => setModalOpen(true)}>
                        Modifier
                      </Button>
                    </div>
                  </div>
                )}
                {isGerant && (
                  <Button type="submit" disabled={saving}>
                    {saving ? 'Enregistrement...' : 'Enregistrer'}
                  </Button>
                )}
              </form>
            </CardContent>
          </Card>
        </TabsContent>

        {/* Security tab */}
        <TabsContent value="security">
          <Card>
            <CardHeader>
              <CardTitle>Changer le mot de passe</CardTitle>
              <CardDescription>
                {isGerant
                  ? 'Sécurisez votre compte'
                  : 'Seul le gérant peut modifier le mot de passe. Contactez votre gérant.'}
              </CardDescription>
            </CardHeader>
            {isGerant && (
              <CardContent>
                <form onSubmit={handleChangePassword} className="space-y-4 max-w-md">
                  <div className="space-y-2">
                    <Label htmlFor="oldPw">Mot de passe actuel</Label>
                    <Input
                      id="oldPw"
                      type="password"
                      value={oldPassword}
                      onChange={(e) => setOldPassword(e.target.value)}
                      placeholder="••••••••"
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="newPw">Nouveau mot de passe</Label>
                    <Input
                      id="newPw"
                      type="password"
                      value={newPassword}
                      onChange={(e) => setNewPassword(e.target.value)}
                      placeholder="••••••••"
                      minLength={6}
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="confirmPw">Confirmer le mot de passe</Label>
                    <Input
                      id="confirmPw"
                      type="password"
                      value={confirmPassword}
                      onChange={(e) => setConfirmPassword(e.target.value)}
                      placeholder="••••••••"
                      required
                    />
                  </div>
                  <Button type="submit" disabled={changingPw}>
                    {changingPw ? 'Changement...' : 'Changer le mot de passe'}
                  </Button>
                </form>
              </CardContent>
            )}
          </Card>
        </TabsContent>

        {/* Dépenses tab — bien séparé du Catalogue : classification comptable des sorties de caisse, pas un réglage produit */}
        {isGerant && (
          <TabsContent value="depenses" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Catégories de dépenses</CardTitle>
                <CardDescription>
                  Catégories proposées lors d'une saisie de sortie de caisse (Salaire, Pub, Commande
                  stock...). Ajoutez-en, renommez ou supprimez-les selon vos besoins.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ExpenseCategoriesCrudList categories={expenseCategories} onChanged={loadExpenseCategories} />
              </CardContent>
            </Card>

            {/* Dépenses que les livreurs déclarent depuis leur bilan du jour
                (§ demande) — repas, carburant, enveloppes… Distinctes des
                catégories de caisse ci-dessus : celles-ci sont des frais de
                tournée, soumis à la validation du gérant. */}
            <Card>
              <CardHeader>
                <CardTitle>Dépenses des livreurs</CardTitle>
                <CardDescription>
                  Types proposés au livreur quand il déclare une dépense depuis
                  son bilan du jour. Le prix sert de valeur par défaut ; cochez
                  « à l&apos;unité » pour une dépense qui se compte (enveloppes,
                  sacs…), le livreur saisira alors une quantité.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <LivreurExpenseTypesCrudList
                  types={expenseTypes}
                  onChanged={loadExpenseTypes}
                />
              </CardContent>
            </Card>
          </TabsContent>
        )}

        {/* Zones de livraison — nom + prix, utilisées par le formulaire Nouvelle
            commande (§ demande). Le "code" interne (jamais montré ici) reste
            stable même si le nom/prix change, pour ne pas affecter les
            commandes déjà passées avec cette zone. */}
        {isGerant && (
          <TabsContent value="zones" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Zones de livraison</CardTitle>
                <CardDescription>
                  Zones proposées à la création d'une commande (nom + frais de livraison). Le
                  retrait sur place ("Récupération") reste toujours disponible séparément et n'est
                  pas géré ici. Ajoutez-en, renommez ou changez le prix selon vos besoins — pensez
                  à garder au moins une zone gratuite (0 Ar).
                </CardDescription>
              </CardHeader>
              <CardContent>
                <DeliveryZonesCrudList zones={deliveryZones} onChanged={loadDeliveryZones} />
              </CardContent>
            </Card>
          </TabsContent>
        )}
      </Tabs>

      <Dialog open={modalOpen} onOpenChange={setModalOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>
              {user?.role === 'admin' ? "Modifier l'entreprise" : "Modifier le magasin"}
            </DialogTitle>
            <DialogDescription>
              {user?.role === 'admin' 
                ? "Mettez à jour le nom et le logo de votre entreprise" 
                : "Mettez à jour le nom et le logo de votre magasin"}
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleUpdateDetails} className="space-y-4">
            <div className="space-y-2">
              <Label>
                {user?.role === 'admin' ? "Nom de l'entreprise" : "Nom du magasin"}
              </Label>
              <Input
                value={user?.role === 'admin' ? companyName : shopName}
                onChange={(e) => user?.role === 'admin' ? setCompanyName(e.target.value) : setShopName(e.target.value)}
                placeholder={user?.role === 'admin' ? "Nom de l'entreprise" : "Nom du magasin"}
                required
              />
            </div>
            
            <div className="space-y-2">
              <Label>
                {user?.role === 'admin' ? "Logo de l'entreprise" : "Logo du magasin"}
              </Label>
              <Input
                type="file"
                accept="image/*"
                onChange={handleLogoChange}
              />
              {logoPreview && (
                <div className="mt-2 flex justify-center">
                  <img src={logoPreview} alt="Preview" className="h-20 w-20 object-contain rounded-md border" />
                </div>
              )}
            </div>

            <div className="flex gap-2 justify-end pt-4">
              <Button type="button" variant="outline" onClick={() => setModalOpen(false)}>
                Annuler
              </Button>
              <Button type="submit" disabled={updatingDetails}>
                {updatingDetails ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Enregistrement...
                  </>
                ) : (
                  'Enregistrer'
                )}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function ExpenseCategoriesCrudList({ categories, onChanged }: { categories: any[]; onChanged: () => void }) {
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingName, setEditingName] = useState('');
  const [newName, setNewName] = useState('');

  const startEdit = (c: any) => { setEditingId(c.id); setEditingName(c.nom); };

  const saveEdit = async () => {
    if (!editingId || !editingName.trim()) return;
    try {
      await djangoClient.caisse.categories.update(editingId, editingName.trim());
      toast.success('Catégorie renommée');
      setEditingId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const removeCategory = async (c: any) => {
    try {
      await djangoClient.caisse.categories.delete(c.id);
      toast.success('Catégorie supprimée');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la suppression');
    }
  };

  const addCategory = async () => {
    if (!newName.trim()) return;
    try {
      await djangoClient.caisse.categories.create(newName.trim());
      toast.success('Catégorie ajoutée');
      setNewName('');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  return (
    <div>
      <p className="text-sm font-medium mb-2">Toutes les catégories ({categories.length})</p>
      <div className="space-y-2 max-h-72 overflow-y-auto">
        {categories.map((c) => (
          <div key={c.id} className="flex items-center gap-2 border rounded-md px-3 py-2">
            {editingId === c.id ? (
              <>
                <Input value={editingName} onChange={(e) => setEditingName(e.target.value)} className="h-8 flex-1" autoFocus />
                <Button size="sm" onClick={saveEdit}>OK</Button>
                <Button size="sm" variant="ghost" onClick={() => setEditingId(null)}>Annuler</Button>
              </>
            ) : (
              <>
                <span className="flex-1 text-sm">{c.nom}</span>
                <Button size="icon" variant="ghost" onClick={() => startEdit(c)}><Pencil className="h-4 w-4" /></Button>
                <Button size="icon" variant="ghost" onClick={() => removeCategory(c)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
              </>
            )}
          </div>
        ))}
        {categories.length === 0 && <p className="text-sm text-muted-foreground text-center py-4">Aucune catégorie.</p>}
      </div>
      <div className="flex gap-2 mt-3">
        <Input placeholder="Nouvelle catégorie (ex: Transport)" value={newName} onChange={(e) => setNewName(e.target.value)} />
        <Button onClick={addCategory}><Plus className="h-4 w-4 mr-2" /> Ajouter</Button>
      </div>
    </div>
  );
}

const arFmt = (n: number | string) => `${new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0)))} Ar`;

/** CRUD des types de dépense proposés aux livreurs (§ demande). */
function LivreurExpenseTypesCrudList({
  types,
  onChanged,
}: {
  types: any[];
  onChanged: () => void;
}) {
  const [nom, setNom] = useState('');
  const [prix, setPrix] = useState('');
  const [parUnite, setParUnite] = useState(false);

  // Édition en place, même schéma que les zones de livraison.
  const [editionId, setEditionId] = useState<number | null>(null);
  const [editionNom, setEditionNom] = useState('');
  const [editionPrix, setEditionPrix] = useState('');
  const [editionParUnite, setEditionParUnite] = useState(false);

  const ouvrirEdition = (t: any) => {
    setEditionId(t.id);
    setEditionNom(t.nom);
    setEditionPrix(String(t.prix_unitaire));
    setEditionParUnite(!!t.par_unite);
  };

  const enregistrerEdition = async () => {
    if (!editionId || !editionNom.trim()) return;
    try {
      await djangoClient.expenseTypes.update(editionId, {
        nom: editionNom.trim(),
        prix_unitaire: Number(editionPrix) || 0,
        par_unite: editionParUnite,
      });
      toast.success('Type mis à jour');
      setEditionId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const ajouter = async () => {
    if (!nom.trim()) return;
    try {
      await djangoClient.expenseTypes.create({
        nom: nom.trim(),
        prix_unitaire: Number(prix) || 0,
        par_unite: parUnite,
      });
      toast.success('Type de dépense ajouté');
      setNom('');
      setPrix('');
      setParUnite(false);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const basculerActif = async (t: any) => {
    try {
      await djangoClient.expenseTypes.update(t.id, { actif: !t.actif });
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const supprimer = async (t: any) => {
    try {
      await djangoClient.expenseTypes.delete(t.id);
      toast.success('Type supprimé');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la suppression');
    }
  };

  return (
    <div>
      <p className="text-sm font-medium mb-2">Types ({types.length})</p>
      <div className="space-y-2 max-h-96 overflow-y-auto">
        {types.map((t) => (
          <div
            key={t.id}
            className="flex flex-wrap items-center gap-2 border rounded-md px-3 py-2"
          >
            {editionId === t.id ? (
              <>
                <Input
                  value={editionNom}
                  onChange={(e) => setEditionNom(e.target.value)}
                  className="h-8 flex-1 min-w-[140px]"
                  autoFocus
                />
                <Input
                  type="number"
                  min={0}
                  value={editionPrix}
                  onChange={(e) => setEditionPrix(e.target.value)}
                  className="h-8 w-28"
                  placeholder="Montant (Ar)"
                />
                <label className="flex items-center gap-2 text-sm">
                  <Switch
                    checked={editionParUnite}
                    onCheckedChange={setEditionParUnite}
                  />
                  à l&apos;unité
                </label>
                <Button size="sm" onClick={enregistrerEdition}>
                  OK
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setEditionId(null)}>
                  Annuler
                </Button>
              </>
            ) : (
              <>
                <span
                  className={`flex-1 text-sm ${!t.actif ? 'text-muted-foreground line-through' : ''}`}
                >
                  {t.nom}
                </span>
                <Badge variant="secondary">
                  {arFmt(t.prix_unitaire)}
                  {t.par_unite ? ' / unité' : ''}
                </Badge>
                <Switch
                  checked={t.actif}
                  onCheckedChange={() => basculerActif(t)}
                  title="Type actif"
                />
                <Button size="icon" variant="ghost" onClick={() => ouvrirEdition(t)}>
                  <Pencil className="h-4 w-4" />
                </Button>
                <Button size="icon" variant="ghost" onClick={() => supprimer(t)}>
                  <Trash2 className="h-4 w-4 text-red-500" />
                </Button>
              </>
            )}
          </div>
        ))}
        {types.length === 0 && (
          <p className="text-sm text-muted-foreground text-center py-4">
            Aucun type de dépense.
          </p>
        )}
      </div>
      <div className="flex flex-wrap items-center gap-2 mt-3">
        <Input
          placeholder="Nouveau type (ex: Repas)"
          value={nom}
          onChange={(e) => setNom(e.target.value)}
          className="flex-1 min-w-[160px]"
        />
        <Input
          type="number"
          min={0}
          placeholder="Montant (Ar)"
          value={prix}
          onChange={(e) => setPrix(e.target.value)}
          className="w-32"
        />
        <label className="flex items-center gap-2 text-sm">
          <Switch checked={parUnite} onCheckedChange={setParUnite} />
          à l&apos;unité
        </label>
        <Button onClick={ajouter}>
          <Plus className="h-4 w-4 mr-2" /> Ajouter
        </Button>
      </div>
    </div>
  );
}

function DeliveryZonesCrudList({ zones, onChanged }: { zones: any[]; onChanged: () => void }) {
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingName, setEditingName] = useState('');
  const [editingPrix, setEditingPrix] = useState('');
  const [newName, setNewName] = useState('');
  const [newPrix, setNewPrix] = useState('');

  const startEdit = (z: any) => {
    setEditingId(z.id);
    setEditingName(z.nom);
    setEditingPrix(String(z.prix));
  };

  const saveEdit = async () => {
    if (!editingId || !editingName.trim()) return;
    try {
      await djangoClient.zones.update(editingId, { nom: editingName.trim(), prix: Number(editingPrix) || 0 });
      toast.success('Zone mise à jour');
      setEditingId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const toggleActive = async (z: any) => {
    try {
      await djangoClient.zones.update(z.id, { actif: !z.actif });
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const removeZone = async (z: any) => {
    try {
      await djangoClient.zones.delete(z.id);
      toast.success('Zone supprimée');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la suppression');
    }
  };

  const addZone = async () => {
    if (!newName.trim()) return;
    try {
      await djangoClient.zones.create({ nom: newName.trim(), prix: Number(newPrix) || 0 });
      toast.success('Zone ajoutée');
      setNewName('');
      setNewPrix('');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  return (
    <div>
      <p className="text-sm font-medium mb-2">Toutes les zones ({zones.length})</p>
      <div className="space-y-2 max-h-96 overflow-y-auto">
        {zones.map((z) => (
          <div key={z.id} className="flex items-center gap-2 border rounded-md px-3 py-2">
            {editingId === z.id ? (
              <>
                <Input value={editingName} onChange={(e) => setEditingName(e.target.value)} className="h-8 flex-1" autoFocus />
                <Input
                  type="number"
                  min={0}
                  value={editingPrix}
                  onChange={(e) => setEditingPrix(e.target.value)}
                  className="h-8 w-28"
                  placeholder="Prix (Ar)"
                />
                <Button size="sm" onClick={saveEdit}>OK</Button>
                <Button size="sm" variant="ghost" onClick={() => setEditingId(null)}>Annuler</Button>
              </>
            ) : (
              <>
                <span className={`flex-1 text-sm ${!z.actif ? 'text-muted-foreground line-through' : ''}`}>
                  {z.nom}
                </span>
                <Badge variant="secondary">{arFmt(z.prix)}</Badge>
                <Switch checked={z.actif} onCheckedChange={() => toggleActive(z)} title="Zone active" />
                <Button size="icon" variant="ghost" onClick={() => startEdit(z)}><Pencil className="h-4 w-4" /></Button>
                <Button size="icon" variant="ghost" onClick={() => removeZone(z)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
              </>
            )}
          </div>
        ))}
        {zones.length === 0 && <p className="text-sm text-muted-foreground text-center py-4">Aucune zone.</p>}
      </div>
      <div className="flex gap-2 mt-3">
        <Input placeholder="Nouvelle zone (ex: Zone 4)" value={newName} onChange={(e) => setNewName(e.target.value)} className="flex-1" />
        <Input
          type="number"
          min={0}
          placeholder="Prix (Ar)"
          value={newPrix}
          onChange={(e) => setNewPrix(e.target.value)}
          className="w-32"
        />
        <Button onClick={addZone}><Plus className="h-4 w-4 mr-2" /> Ajouter</Button>
      </div>
    </div>
  );
}

