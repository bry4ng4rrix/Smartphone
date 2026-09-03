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
import { User, Lock, Building2, Loader2, Tag, Plus, Check } from 'lucide-react';

const roleLabel: Record<string, string> = {
  admin: 'Administrateur',
  magasin: 'Gérant de magasin',
  employer: 'Commercial',
};

// Marques de téléphones courantes (§8.1 du cahier des charges) — proposées
// en un clic pour éviter de les retaper à chaque nouvelle référence produit.
const SUGGESTED_BRANDS = [
  'Samsung', 'iPhone', 'Huawei', 'Redmi', 'Xiaomi', 'Tecno', 'Infinix',
  'Itel', 'Oppo', 'Realme', 'Google Pixel', 'Poco', 'Vivo', 'Honor',
];

export default function SettingsPage() {
  const { user, isGerant, loading: userLoading } = useCurrentUser();
  const [brands, setBrands] = useState<any[]>([]);
  const [addingBrand, setAddingBrand] = useState<string | null>(null);

  useEffect(() => {
    if (!isGerant) return;
    djangoClient.catalog.brands.list().then(setBrands).catch(() => {});
  }, [isGerant]);

  const addSuggestedBrand = async (nom: string) => {
    setAddingBrand(nom);
    try {
      const created = await djangoClient.catalog.brands.create({ nom });
      setBrands((prev) => [...prev, created]);
      toast.success(`Marque "${nom}" ajoutée`);
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de l\'ajout');
    } finally {
      setAddingBrand(null);
    }
  };
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
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
      setCompanyName(user.company_name || '');
      setShopName(user.shop_name || '');
    }
  }, [user]);

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
      await djangoClient.users.updateProfile({ full_name: fullName, phone });
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
            <TabsTrigger value="catalogue">
              <Tag className="h-4 w-4 mr-2" />Catalogue
            </TabsTrigger>
          )}
        </TabsList>

        {/* Profile tab */}
        <TabsContent value="profile">
          <Card>
            <CardHeader>
              <CardTitle>Informations personnelles</CardTitle>
              <CardDescription>Mettez à jour vos informations</CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleUpdateProfile} className="space-y-4 max-w-md">
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
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="phone">Téléphone</Label>
                  <Input
                    id="phone"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="+261 XX XXX XX XX"
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
                <Button type="submit" disabled={saving}>
                  {saving ? 'Enregistrement...' : 'Enregistrer'}
                </Button>
              </form>
            </CardContent>
          </Card>
        </TabsContent>

        {/* Security tab */}
        <TabsContent value="security">
          <Card>
            <CardHeader>
              <CardTitle>Changer le mot de passe</CardTitle>
              <CardDescription>Sécurisez votre compte</CardDescription>
            </CardHeader>
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
          </Card>
        </TabsContent>

        {/* Catalogue tab — gérant uniquement (§8.1 du cahier des charges) */}
        {isGerant && (
          <TabsContent value="catalogue">
            <Card>
              <CardHeader>
                <CardTitle>Marques suggérées</CardTitle>
                <CardDescription>
                  Marques de téléphones courantes — ajoutez-les en un clic pour les retrouver
                  facilement lors de la création d'une référence produit.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2">
                  {SUGGESTED_BRANDS.map((nom) => {
                    const already = brands.some((b) => b.nom.toLowerCase() === nom.toLowerCase());
                    return (
                      <Button
                        key={nom}
                        type="button"
                        size="sm"
                        variant={already ? 'secondary' : 'outline'}
                        disabled={already || addingBrand === nom}
                        onClick={() => addSuggestedBrand(nom)}
                      >
                        {already ? <Check className="h-3.5 w-3.5 mr-1.5" /> : <Plus className="h-3.5 w-3.5 mr-1.5" />}
                        {nom}
                      </Button>
                    );
                  })}
                </div>
                <p className="text-xs text-muted-foreground mt-4">
                  Gestion complète des marques (renommer, supprimer) : page Produits → bouton « Marques ».
                </p>
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
