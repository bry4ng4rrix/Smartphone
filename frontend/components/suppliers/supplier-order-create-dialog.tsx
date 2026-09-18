'use client';

/**
 * Nouvel approvisionnement (§ 3) : UN fournisseur, UN sous-type de produit
 * (FLIP COVER, Z-FOLD… — la même liste que le filtre « sous-type » de la
 * page Produits, sans couleur : le module est indépendant du stock), UNE
 * quantité, la devise et le montant total prévu. Les paiements, le transport
 * et les frais se saisissent ensuite sur la fiche.
 */
import { useEffect, useMemo, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { appToday } from '@/lib/timezone';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { DEVISES, messageErreur, type Devise } from './supplier-status';

const AUCUN = 'AUCUN';
const fmtNombreOuVide = (q: string) => (q && Number(q) > 0 ? `${Number(q)} pièce(s)` : 'quantité à saisir');

export function SupplierOrderCreateDialog({
  open,
  onOpenChange,
  onCreated,
  supplierInitial,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  /** Reçoit l'approvisionnement créé (réponse de l'API). */
  onCreated?: (order: any) => void;
  /** Fournisseur pré-sélectionné (fiche complète ou `{id, nom, devise}`). */
  supplierInitial?: any | null;
}) {
  const { isAdmin } = useCurrentUser();
  const [suppliers, setSuppliers] = useState<any[]>([]);
  const [magasins, setMagasins] = useState<{ magasin_id: number; shop_name: string }[]>([]);
  const [supplierId, setSupplierId] = useState<string>(AUCUN);
  const [magasinId, setMagasinId] = useState<string>('');
  const [devise, setDevise] = useState<Devise>('USD');
  const [montantPrevu, setMontantPrevu] = useState('');
  const [date, setDate] = useState(appToday());
  const [description, setDescription] = useState('');
  const [quantite, setQuantite] = useState('');
  const [types, setTypes] = useState<any[]>([]);
  const [typeId, setTypeId] = useState('');
  const [submitting, setSubmitting] = useState<null | 'BROUILLON' | 'COMMANDE'>(null);

  useEffect(() => {
    if (!open) return;
    setSupplierId(supplierInitial?.id ? String(supplierInitial.id) : AUCUN);
    setDevise((supplierInitial?.devise as Devise) || 'USD');
    setMontantPrevu(''); setDate(appToday()); setDescription(''); setQuantite('');
    setTypeId(''); setMagasinId('');
    // Sous-types du catalogue (GET /catalog/types/), comme la page Produits.
    djangoClient.catalog.types.list().then((l: any[]) => setTypes(l || [])).catch(() => setTypes([]));
    djangoClient.suppliers.suppliersList({ actif: true })
      .then((list: any[]) => {
        if (supplierInitial?.id && !list.some((s) => s.id === supplierInitial.id)) setSuppliers([supplierInitial, ...list]);
        else setSuppliers(list);
      })
      .catch(() => setSuppliers(supplierInitial?.id ? [supplierInitial] : []));
    if (isAdmin) {
      djangoClient.users.list()
        .then((list: any[]) => {
          const mags = (list || []).filter((m) => m?.magasin_id).map((m) => ({ magasin_id: Number(m.magasin_id), shop_name: String(m.shop_name || `Magasin ${m.magasin_id}`) }));
          setMagasins(mags);
          if (mags.length === 1) setMagasinId(String(mags[0].magasin_id));
        })
        .catch(() => setMagasins([]));
    } else {
      setMagasins([]);
    }
  }, [open, supplierInitial, isAdmin]);

  const supplierChoisi = useMemo(() => suppliers.find((s) => String(s.id) === supplierId) ?? null, [suppliers, supplierId]);
  const typeChoisi = useMemo(() => types.find((t) => String(t.id) === typeId) ?? null, [types, typeId]);

  const submit = async (statut: 'BROUILLON' | 'COMMANDE') => {
    if (!typeId) { toast.error('Choisissez le sous-type.'); return; }
    const q = Math.floor(Number(quantite));
    if (!q || q < 1) { toast.error('Indiquez la quantité de pièces.'); return; }
    if (isAdmin && magasins.length > 1 && !magasinId) { toast.error('Choisissez le magasin destinataire.'); return; }
    setSubmitting(statut);
    try {
      const o = await djangoClient.suppliers.create({
        supplier: supplierId === AUCUN ? null : Number(supplierId), product_type: Number(typeId), quantite: q, devise,
        montant_prevu: montantPrevu.trim() === '' ? 0 : Number(montantPrevu), description: description.trim(), date, statut,
        ...(magasinId ? { magasin_id: Number(magasinId) } : {}),
      });
      toast.success(`Approvisionnement ${o.numero} créé`);
      onCreated?.(o);
      onOpenChange(false);
    } catch (e) {
      toast.error(messageErreur(e, "Impossible de créer l'approvisionnement"));
    } finally {
      setSubmitting(null);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle>Nouvel approvisionnement</DialogTitle>
          <DialogDescription>Un approvisionnement = un fournisseur, un sous-type, une quantité. Pour un autre sous-type, créez un autre approvisionnement.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Fournisseur</Label>
              <Select value={supplierId} onValueChange={(v) => { setSupplierId(v); const s = suppliers.find((x) => String(x.id) === v); if (s?.devise) setDevise(s.devise); }}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={AUCUN}>— Sans fournisseur —</SelectItem>
                  {suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.nom}{s.pays ? ` · ${s.pays}` : ''}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1"><Label>Date</Label><Input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          {isAdmin && magasins.length > 1 && (
            <div className="space-y-1">
              <Label>Magasin destinataire</Label>
              <Select value={magasinId} onValueChange={setMagasinId}>
                <SelectTrigger className="w-full"><SelectValue placeholder="Choisir un magasin" /></SelectTrigger>
                <SelectContent>{magasins.map((m) => <SelectItem key={m.magasin_id} value={String(m.magasin_id)}>{m.shop_name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          )}

          <div className="rounded-md border p-3 space-y-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Produit</p>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>Sous-type</Label>
                <Select value={typeId} onValueChange={setTypeId}>
                  <SelectTrigger className="w-full"><SelectValue placeholder="Choisir un sous-type" /></SelectTrigger>
                  <SelectContent>
                    {types.map((t) => <SelectItem key={t.id} value={String(t.id)}>{t.nom}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1"><Label>Quantité (pièces)</Label><Input type="number" min={1} value={quantite} onChange={(e) => setQuantite(e.target.value)} placeholder="Ex : 100" /></div>
            </div>
            {typeChoisi && <p className="text-xs text-muted-foreground">Sous-type : {typeChoisi.nom} — {fmtNombreOuVide(quantite)}</p>}
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Devise du fournisseur</Label>
              <Select value={devise} onValueChange={(v) => setDevise(v as Devise)}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>{DEVISES.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-1"><Label>Montant total prévu ({devise}) — facultatif</Label><Input type="number" min={0} step="0.01" value={montantPrevu} onChange={(e) => setMontantPrevu(e.target.value)} placeholder="Ex : 2000" /></div>
          </div>
          <div className="space-y-1"><Label>Description</Label><Input value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Ex : Envoi #001 — Coques iPhone" /></div>
          {supplierChoisi?.pays && <p className="text-xs text-muted-foreground">Fournisseur : {supplierChoisi.nom} ({supplierChoisi.pays})</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={!!submitting}>Annuler</Button>
          <Button variant="secondary" onClick={() => submit('BROUILLON')} disabled={!!submitting}>{submitting === 'BROUILLON' ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Enregistrer en brouillon'}</Button>
          <Button onClick={() => submit('COMMANDE')} disabled={!!submitting}>{submitting === 'COMMANDE' ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Créer la commande'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
