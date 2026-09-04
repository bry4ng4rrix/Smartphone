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
import { User, Lock, Building2, Loader2, Tag, Plus, Check, Pencil, Trash2, FolderPlus } from 'lucide-react';

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
  const [categories, setCategories] = useState<any[]>([]);
  const [types, setTypes] = useState<any[]>([]);
  const [colors, setColors] = useState<any[]>([]);

  const loadCatalogue = () => {
    if (!isGerant) return;
    djangoClient.catalog.brands.list().then(setBrands).catch(() => {});
    djangoClient.catalog.categories.list().then(setCategories).catch(() => {});
    djangoClient.catalog.types.list().then(setTypes).catch(() => {});
    djangoClient.catalog.colors.list().then(setColors).catch(() => {});
  };

  useEffect(loadCatalogue, [isGerant]);

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
          <TabsContent value="catalogue" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Marques</CardTitle>
                <CardDescription>
                  Ajoutez une marque courante en un clic, ou gérez la liste complète (renommer, supprimer).
                </CardDescription>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2 mb-4">
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
                <BrandsCrudList brands={brands} onChanged={loadCatalogue} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Sous-types (catégories produit)</CardTitle>
                <CardDescription>
                  Le niveau entre la catégorie (ex. Housse, Cache écran) et la marque — ex. Flip cover,
                  Privacy, Chargeur, Écouteur. Analysé depuis le catalogue actuel : renommez, supprimez
                  ou ajoutez-en de nouveaux.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <CategoriesTypesCrud categories={categories} types={types} onChanged={loadCatalogue} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Couleurs</CardTitle>
                <CardDescription>
                  Liste des couleurs proposées dans le sélecteur de variante (module Produits). Analysée
                  depuis les couleurs déjà utilisées dans le catalogue actuel.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ColorsCrudList colors={colors} onChanged={loadCatalogue} />
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

function BrandsCrudList({ brands, onChanged }: { brands: any[]; onChanged: () => void }) {
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingName, setEditingName] = useState('');
  const [newName, setNewName] = useState('');

  const startEdit = (b: any) => { setEditingId(b.id); setEditingName(b.nom); };

  const saveEdit = async () => {
    if (!editingId || !editingName.trim()) return;
    try {
      await djangoClient.catalog.brands.update(editingId, { nom: editingName.trim() });
      toast.success('Marque renommée');
      setEditingId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const removeBrand = async (b: any) => {
    try {
      await djangoClient.catalog.brands.delete(b.id);
      toast.success('Marque supprimée');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Suppression impossible (marque utilisée par des références)');
    }
  };

  const addBrand = async () => {
    if (!newName.trim()) return;
    try {
      await djangoClient.catalog.brands.create({ nom: newName.trim() });
      toast.success('Marque ajoutée');
      setNewName('');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  return (
    <div className="border-t pt-4">
      <p className="text-sm font-medium mb-2">Toutes les marques ({brands.length})</p>
      <div className="space-y-2 max-h-72 overflow-y-auto">
        {brands.map((b) => (
          <div key={b.id} className="flex items-center gap-2 border rounded-md px-3 py-2">
            {editingId === b.id ? (
              <>
                <Input value={editingName} onChange={(e) => setEditingName(e.target.value)} className="h-8 flex-1" autoFocus />
                <Button size="sm" onClick={saveEdit}>OK</Button>
                <Button size="sm" variant="ghost" onClick={() => setEditingId(null)}>Annuler</Button>
              </>
            ) : (
              <>
                <span className="flex-1 text-sm">{b.nom}</span>
                <Button size="icon" variant="ghost" onClick={() => startEdit(b)}><Pencil className="h-4 w-4" /></Button>
                <Button size="icon" variant="ghost" onClick={() => removeBrand(b)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
              </>
            )}
          </div>
        ))}
        {brands.length === 0 && <p className="text-sm text-muted-foreground text-center py-4">Aucune marque.</p>}
      </div>
      <div className="flex gap-2 mt-3">
        <Input placeholder="Nouvelle marque" value={newName} onChange={(e) => setNewName(e.target.value)} />
        <Button onClick={addBrand}><Plus className="h-4 w-4 mr-2" /> Ajouter</Button>
      </div>
    </div>
  );
}

function CategoriesTypesCrud({
  categories, types, onChanged,
}: { categories: any[]; types: any[]; onChanged: () => void }) {
  const [editingCatId, setEditingCatId] = useState<number | null>(null);
  const [editingCatName, setEditingCatName] = useState('');
  const [newCatName, setNewCatName] = useState('');

  const [editingTypeId, setEditingTypeId] = useState<number | null>(null);
  const [editingTypeName, setEditingTypeName] = useState('');
  const [newTypeNameByCategory, setNewTypeNameByCategory] = useState<Record<number, string>>({});

  const startEditCat = (c: any) => { setEditingCatId(c.id); setEditingCatName(c.nom); };
  const saveEditCat = async () => {
    if (!editingCatId || !editingCatName.trim()) return;
    try {
      await djangoClient.catalog.categories.update(editingCatId, { nom: editingCatName.trim() });
      toast.success('Catégorie renommée');
      setEditingCatId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };
  const removeCategory = async (c: any) => {
    try {
      await djangoClient.catalog.categories.delete(c.id);
      toast.success('Catégorie supprimée');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Suppression impossible (des sous-types en dépendent encore)');
    }
  };
  const addCategory = async () => {
    if (!newCatName.trim()) return;
    try {
      await djangoClient.catalog.categories.create({ nom: newCatName.trim(), ordre: categories.length });
      toast.success('Catégorie ajoutée');
      setNewCatName('');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  const startEditType = (t: any) => { setEditingTypeId(t.id); setEditingTypeName(t.nom); };
  const saveEditType = async () => {
    if (!editingTypeId || !editingTypeName.trim()) return;
    try {
      await djangoClient.catalog.types.update(editingTypeId, { nom: editingTypeName.trim() });
      toast.success('Sous-type renommé');
      setEditingTypeId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };
  const removeType = async (t: any) => {
    try {
      await djangoClient.catalog.types.delete(t.id);
      toast.success('Sous-type supprimé');
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Suppression impossible (des références en dépendent encore)');
    }
  };
  const addType = async (categoryId: number) => {
    const nom = (newTypeNameByCategory[categoryId] || '').trim();
    if (!nom) return;
    try {
      await djangoClient.catalog.types.create({ category: categoryId, nom });
      toast.success('Sous-type ajouté');
      setNewTypeNameByCategory((prev) => ({ ...prev, [categoryId]: '' }));
      onChanged();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    }
  };

  return (
    <div className="space-y-4">
      {categories.map((c) => {
        const typesForCat = types.filter((t) => t.category === c.id);
        return (
          <div key={c.id} className="border rounded-md p-3">
            <div className="flex items-center gap-2 mb-2">
              {editingCatId === c.id ? (
                <>
                  <Input value={editingCatName} onChange={(e) => setEditingCatName(e.target.value)} className="h-8 flex-1 font-medium" autoFocus />
                  <Button size="sm" onClick={saveEditCat}>OK</Button>
                  <Button size="sm" variant="ghost" onClick={() => setEditingCatId(null)}>Annuler</Button>
                </>
              ) : (
                <>
                  <Tag className="h-4 w-4 text-muted-foreground" />
                  <span className="flex-1 text-sm font-semibold">{c.nom}</span>
                  <Button size="icon" variant="ghost" onClick={() => startEditCat(c)}><Pencil className="h-4 w-4" /></Button>
                  <Button size="icon" variant="ghost" onClick={() => removeCategory(c)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                </>
              )}
            </div>
            <div className="space-y-1.5 pl-6">
              {typesForCat.map((t) => (
                <div key={t.id} className="flex items-center gap-2">
                  {editingTypeId === t.id ? (
                    <>
                      <Input value={editingTypeName} onChange={(e) => setEditingTypeName(e.target.value)} className="h-8 flex-1" autoFocus />
                      <Button size="sm" onClick={saveEditType}>OK</Button>
                      <Button size="sm" variant="ghost" onClick={() => setEditingTypeId(null)}>Annuler</Button>
                    </>
                  ) : (
                    <>
                      <span className="flex-1 text-sm text-muted-foreground">{t.nom}</span>
                      <Button size="icon" variant="ghost" onClick={() => startEditType(t)}><Pencil className="h-3.5 w-3.5" /></Button>
                      <Button size="icon" variant="ghost" onClick={() => removeType(t)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                    </>
                  )}
                </div>
              ))}
              {typesForCat.length === 0 && <p className="text-xs text-muted-foreground">Aucun sous-type.</p>}
              <div className="flex gap-2 pt-1">
                <Input
                  placeholder="Nouveau sous-type (ex. Chargeur, Écouteur)"
                  value={newTypeNameByCategory[c.id] || ''}
                  onChange={(e) => setNewTypeNameByCategory((prev) => ({ ...prev, [c.id]: e.target.value }))}
                  className="h-8"
                />
                <Button size="sm" onClick={() => addType(c.id)}><Plus className="h-3.5 w-3.5 mr-1" /> Ajouter</Button>
              </div>
            </div>
          </div>
        );
      })}
      {categories.length === 0 && <p className="text-sm text-muted-foreground text-center py-4">Aucune catégorie.</p>}
      <div className="flex gap-2 border-t pt-4">
        <Input placeholder="Nouvelle catégorie (ex. Accessoires)" value={newCatName} onChange={(e) => setNewCatName(e.target.value)} />
        <Button onClick={addCategory}><FolderPlus className="h-4 w-4 mr-2" /> Ajouter</Button>
      </div>
    </div>
  );
}
