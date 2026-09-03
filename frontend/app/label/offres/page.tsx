'use client';

import { useEffect, useState, useCallback } from 'react';
import { djangoClient } from '@/lib/django-client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { toast } from 'sonner';
import { Tag, RefreshCw, Plus, Pencil, Trash2, Smartphone } from 'lucide-react';

const emptyForm = {
  name: '',
  price: '',
  max_devices: '',
  duration_months: '',
  is_active: true,
};

type FormErrors = Partial<Record<'name' | 'price' | 'max_devices' | 'duration_months', string>>;

function validateForm(form: typeof emptyForm): FormErrors {
  const errors: FormErrors = {};
  if (!form.name.trim()) {
    errors.name = "Le nom de l'offre est obligatoire.";
  }
  const price = Number(form.price);
  if (form.price === '' || Number.isNaN(price) || price < 0) {
    errors.price = 'Le prix doit être un nombre positif.';
  }
  const maxDevices = Number(form.max_devices);
  if (form.max_devices === '' || !Number.isInteger(maxDevices) || maxDevices < 1) {
    errors.max_devices = "Le nombre d'appareils doit être un entier d'au moins 1.";
  }
  const durationMonths = Number(form.duration_months);
  if (form.duration_months === '' || !Number.isInteger(durationMonths) || durationMonths < 1) {
    errors.duration_months = "La durée doit être un entier d'au moins 1 mois.";
  }
  return errors;
}

export default function LabelOffresPage() {
  const [offers, setOffers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const [formOpen, setFormOpen] = useState(false);
  const [formMode, setFormMode] = useState<'create' | 'edit'>('create');
  const [formTarget, setFormTarget] = useState<any | null>(null);
  const [formData, setFormData] = useState(emptyForm);
  const [formErrors, setFormErrors] = useState<FormErrors>({});
  const [saving, setSaving] = useState(false);

  const [deleteTarget, setDeleteTarget] = useState<any | null>(null);
  const [deleting, setDeleting] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const data = await djangoClient.platformAdmin.listOffers();
      setOffers(data);
    } catch (err) {
      console.error(err);
      toast.error('Erreur lors du chargement des offres');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const openCreate = () => {
    setFormMode('create');
    setFormTarget(null);
    setFormData(emptyForm);
    setFormErrors({});
    setFormOpen(true);
  };

  const openEdit = (offer: any) => {
    setFormMode('edit');
    setFormTarget(offer);
    setFormData({
      name: offer.name || '',
      price: String(offer.price ?? ''),
      max_devices: String(offer.max_devices ?? ''),
      duration_months: String(offer.duration_months ?? ''),
      is_active: offer.is_active,
    });
    setFormErrors({});
    setFormOpen(true);
  };

  const handleSaveForm = async () => {
    const errors = validateForm(formData);
    setFormErrors(errors);
    if (Object.keys(errors).length > 0) return;

    setSaving(true);
    try {
      const payload = {
        name: formData.name.trim(),
        price: Number(formData.price),
        max_devices: Number(formData.max_devices),
        duration_months: Number(formData.duration_months),
        is_active: formData.is_active,
      };
      if (formMode === 'create') {
        await djangoClient.platformAdmin.createOffer(payload);
        toast.success('Offre créée');
      } else if (formTarget) {
        await djangoClient.platformAdmin.updateOffer(formTarget.id, payload);
        toast.success('Offre mise à jour');
      }
      setFormOpen(false);
      fetchData();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'enregistrement");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await djangoClient.platformAdmin.deleteOffer(deleteTarget.id);
      toast.success('Offre supprimée');
      setDeleteTarget(null);
      fetchData();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la suppression');
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight flex items-center gap-2">
            <Tag className="h-7 w-7 text-blue-600" />Offres d'abonnement
          </h1>
          <p className="text-muted-foreground mt-1 text-sm sm:text-base">
            Catalogue des plans proposés aux sociétés (nom, prix, appareils autorisés)
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={fetchData} disabled={loading}>
            <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
            Actualiser
          </Button>
          <Button size="sm" onClick={openCreate}>
            <Plus className="h-4 w-4 mr-2" />
            Nouvelle offre
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Catalogue</CardTitle>
          <CardDescription>{offers.length} offre{offers.length > 1 ? 's' : ''} au total</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="space-y-2">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          ) : offers.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-8">
              Aucune offre créée pour le moment
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nom</TableHead>
                    <TableHead>Prix</TableHead>
                    <TableHead>Durée</TableHead>
                    <TableHead>Appareils connectés</TableHead>
                    <TableHead>Sociétés</TableHead>
                    <TableHead>Statut</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {offers.map((o) => (
                    <TableRow key={o.id}>
                      <TableCell className="font-medium">{o.name}</TableCell>
                      <TableCell>{o.price}</TableCell>
                      <TableCell>{o.duration_months} mois</TableCell>
                      <TableCell>
                        <Badge variant="outline" className="font-normal flex items-center gap-1 w-fit">
                          <Smartphone className="h-3 w-3" />
                          {o.max_devices}
                        </Badge>
                      </TableCell>
                      <TableCell>{o.subscriptions_count}</TableCell>
                      <TableCell>
                        <Badge
                          variant="outline"
                          className={o.is_active ? 'bg-green-50 text-green-700' : 'bg-muted text-muted-foreground'}
                        >
                          {o.is_active ? 'Active' : 'Inactive'}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openEdit(o)}>
                          <Pencil className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-red-600 hover:text-red-700"
                          onClick={() => setDeleteTarget(o)}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Create/Edit dialog */}
      <Dialog open={formOpen} onOpenChange={setFormOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{formMode === 'create' ? 'Nouvelle offre' : "Modifier l'offre"}</DialogTitle>
            <DialogDescription>
              Définissez le nom, le prix, la durée et le nombre d'appareils connectés autorisés pour ce plan.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label>Nom de l'offre</Label>
              <Input
                value={formData.name}
                onChange={(e) => setFormData((f) => ({ ...f, name: e.target.value }))}
                placeholder="Ex: Standard, Pro, Entreprise..."
              />
              {formErrors.name && <p className="text-xs text-red-600">{formErrors.name}</p>}
            </div>
            <div className="space-y-1.5">
              <Label>Prix</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={formData.price}
                onChange={(e) => setFormData((f) => ({ ...f, price: e.target.value }))}
                placeholder="0.00"
              />
              {formErrors.price && <p className="text-xs text-red-600">{formErrors.price}</p>}
            </div>
            <div className="space-y-1.5">
              <Label>Nombre d'appareils connectés autorisés</Label>
              <Input
                type="number"
                min="1"
                step="1"
                value={formData.max_devices}
                onChange={(e) => setFormData((f) => ({ ...f, max_devices: e.target.value }))}
                placeholder="Ex: 3"
              />
              {formErrors.max_devices && <p className="text-xs text-red-600">{formErrors.max_devices}</p>}
            </div>
            <div className="space-y-1.5">
              <Label>Durée (mois)</Label>
              <Input
                type="number"
                min="1"
                step="1"
                value={formData.duration_months}
                onChange={(e) => setFormData((f) => ({ ...f, duration_months: e.target.value }))}
                placeholder="Ex: 1"
              />
              {formErrors.duration_months && <p className="text-xs text-red-600">{formErrors.duration_months}</p>}
            </div>
            <div className="flex items-center justify-between rounded-md border p-3">
              <div>
                <Label>Offre active</Label>
                <p className="text-xs text-muted-foreground">
                  Les offres inactives restent assignées mais ne sont plus proposées.
                </p>
              </div>
              <Switch
                checked={formData.is_active}
                onCheckedChange={(v) => setFormData((f) => ({ ...f, is_active: v }))}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setFormOpen(false)}>
              Annuler
            </Button>
            <Button onClick={handleSaveForm} disabled={saving}>
              {saving ? 'Enregistrement...' : 'Enregistrer'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation dialog */}
      <Dialog open={!!deleteTarget} onOpenChange={(open) => !open && setDeleteTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="text-red-600">Supprimer "{deleteTarget?.name}" ?</DialogTitle>
            <DialogDescription>
              {deleteTarget?.subscriptions_count > 0
                ? `Cette offre est assignée à ${deleteTarget.subscriptions_count} société(s). Ces sociétés reviendront à la limite d'appareils par défaut.`
                : 'Cette action est irréversible.'}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              Annuler
            </Button>
            <Button variant="destructive" disabled={deleting} onClick={handleDelete}>
              {deleting ? 'Suppression...' : 'Supprimer'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
