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
import { Skeleton } from '@/components/ui/skeleton';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { toast } from 'sonner';
import { User, Lock, Building2, Loader2, Plus, Pencil, Trash2, Wallet } from 'lucide-react';

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

