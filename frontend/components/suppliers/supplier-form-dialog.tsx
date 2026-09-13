'use client';

/**
 * Dialog « Nouveau fournisseur » / « Modifier le fournisseur ».
 *
 * Fiche fournisseur (suppliers/suppliers/) : nom (requis), pays, contact,
 * téléphone, e-mail, adresse, notes, devise habituelle et — en édition —
 * le statut actif/inactif.
 */

import { useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { toast } from 'sonner';
import { DEVISES, messageErreur, type Devise } from './supplier-status';

export interface SupplierFormValues {
  nom: string;
  pays: string;
  contact: string;
  telephone: string;
  email: string;
  adresse: string;
  notes: string;
  devise: Devise;
  actif: boolean;
}

const VIDE: SupplierFormValues = {
  nom: '', pays: '', contact: '', telephone: '', email: '', adresse: '', notes: '', devise: 'USD', actif: true,
};

export function SupplierFormDialog({
  open,
  onOpenChange,
  supplier,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  /** Fiche à modifier ; `null`/`undefined` = création. */
  supplier?: any | null;
  /** Appelé avec la fiche renvoyée par l'API après création / modification. */
  onSaved?: (supplier: any) => void;
}) {
  const edition = !!supplier?.id;
  const [values, setValues] = useState<SupplierFormValues>(VIDE);
  const [submitting, setSubmitting] = useState(false);
  const [erreurs, setErreurs] = useState<Partial<Record<keyof SupplierFormValues, string>>>({});

  useEffect(() => {
    if (!open) return;
    setErreurs({});
    if (supplier?.id) {
      setValues({
        nom: supplier.nom ?? '',
        pays: supplier.pays ?? '',
        contact: supplier.contact ?? '',
        telephone: supplier.telephone ?? '',
        email: supplier.email ?? '',
        adresse: supplier.adresse ?? '',
        notes: supplier.notes ?? '',
        devise: (supplier.devise as Devise) || 'USD',
        actif: supplier.actif !== false,
      });
    } else {
      setValues(VIDE);
    }
  }, [open, supplier]);

  const set = <K extends keyof SupplierFormValues>(k: K, v: SupplierFormValues[K]) => {
    setValues((prev) => ({ ...prev, [k]: v }));
    if (erreurs[k]) setErreurs((prev) => ({ ...prev, [k]: undefined }));
  };

  const valider = () => {
    const e: typeof erreurs = {};
    if (!values.nom.trim()) e.nom = 'Le nom est requis.';
    if (values.email.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email.trim())) {
      e.email = 'Adresse e-mail invalide.';
    }
    setErreurs(e);
    return Object.keys(e).length === 0;
  };

  const submit = async () => {
    if (!valider()) return;
    setSubmitting(true);
    try {
      const payload = {
        nom: values.nom.trim(),
        pays: values.pays.trim(),
        contact: values.contact.trim(),
        telephone: values.telephone.trim(),
        email: values.email.trim(),
        adresse: values.adresse.trim(),
        notes: values.notes.trim(),
        devise: values.devise,
        actif: values.actif,
      };
      const saved = edition
        ? await djangoClient.suppliers.supplierUpdate(supplier.id, payload)
        : await djangoClient.suppliers.supplierCreate(payload);
      toast.success(edition ? 'Fournisseur modifié' : 'Fournisseur créé');
      onSaved?.(saved);
      onOpenChange(false);
    } catch (err) {
      toast.error(messageErreur(err, edition ? 'Modification impossible' : 'Création impossible'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !submitting && onOpenChange(o)}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{edition ? 'Modifier le fournisseur' : 'Nouveau fournisseur'}</DialogTitle>
          <DialogDescription>
            {edition
              ? 'Mettez à jour les coordonnées et la devise habituelle de ce fournisseur.'
              : 'Renseignez la fiche du fournisseur : coordonnées et devise habituelle des achats.'}
          </DialogDescription>
        </DialogHeader>

        <form
          className="space-y-3"
          onSubmit={(e) => { e.preventDefault(); submit(); }}
        >
          <div className="space-y-1">
            <Label htmlFor="sf-nom">Nom <span className="text-red-500">*</span></Label>
            <Input
              id="sf-nom"
              value={values.nom}
              onChange={(e) => set('nom', e.target.value)}
              placeholder="Ex : Shenzhen Mobile Parts Co."
              autoFocus
              aria-invalid={!!erreurs.nom}
            />
            {erreurs.nom && <p className="text-xs text-red-600">{erreurs.nom}</p>}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label htmlFor="sf-pays">Pays</Label>
              <Input id="sf-pays" value={values.pays} onChange={(e) => set('pays', e.target.value)} placeholder="Ex : Chine" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="sf-devise">Devise habituelle</Label>
              <Select value={values.devise} onValueChange={(v) => set('devise', v as Devise)}>
                <SelectTrigger id="sf-devise" className="w-full"><SelectValue placeholder="Devise" /></SelectTrigger>
                <SelectContent>
                  {DEVISES.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label htmlFor="sf-contact">Contact</Label>
              <Input id="sf-contact" value={values.contact} onChange={(e) => set('contact', e.target.value)} placeholder="Nom de l'interlocuteur" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="sf-tel">Téléphone</Label>
              <Input id="sf-tel" type="tel" value={values.telephone} onChange={(e) => set('telephone', e.target.value)} placeholder="+86 …" />
            </div>
          </div>

          <div className="space-y-1">
            <Label htmlFor="sf-email">E-mail</Label>
            <Input
              id="sf-email"
              type="email"
              value={values.email}
              onChange={(e) => set('email', e.target.value)}
              placeholder="contact@fournisseur.com"
              aria-invalid={!!erreurs.email}
            />
            {erreurs.email && <p className="text-xs text-red-600">{erreurs.email}</p>}
          </div>

          <div className="space-y-1">
            <Label htmlFor="sf-adresse">Adresse</Label>
            <Textarea id="sf-adresse" rows={2} value={values.adresse} onChange={(e) => set('adresse', e.target.value)} placeholder="Adresse complète" />
          </div>

          <div className="space-y-1">
            <Label htmlFor="sf-notes">Notes</Label>
            <Textarea id="sf-notes" rows={2} value={values.notes} onChange={(e) => set('notes', e.target.value)} placeholder="Conditions de paiement, délais habituels, remarques…" />
          </div>

          {edition && (
            <div className="flex items-center justify-between rounded-lg border px-3 py-2">
              <div>
                <p className="text-sm font-medium">Fournisseur actif</p>
                <p className="text-xs text-muted-foreground">Un fournisseur inactif n'est plus proposé pour les nouveaux approvisionnements.</p>
              </div>
              <Switch checked={values.actif} onCheckedChange={(v) => set('actif', v)} />
            </div>
          )}

          <DialogFooter className="pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={submitting}>Annuler</Button>
            <Button type="submit" disabled={submitting}>
              {submitting ? 'Enregistrement…' : edition ? 'Enregistrer' : 'Créer le fournisseur'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
