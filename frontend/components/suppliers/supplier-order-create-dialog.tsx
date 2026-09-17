'use client';

/**
 * Nouvel approvisionnement (§ 3) : UN fournisseur, UN produit (référence +
 * couleur), UNE quantité, la devise et le montant total prévu. Les paiements,
 * le transport et les frais se saisissent ensuite sur la fiche.
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
import { Loader2, Search } from 'lucide-react';
import { toast } from 'sonner';
import { DEVISES, fmtAr, messageErreur, type Devise } from './supplier-status';

const AUCUN = 'AUCUN';

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
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);
  const [selectedRef, setSelectedRef] = useState<any | null>(null);
  const [variantId, setVariantId] = useState('');
  const [submitting, setSubmitting] = useState<null | 'BROUILLON' | 'COMMANDE'>(null);

  useEffect(() => {
    if (!open) return;
    setSupplierId(supplierInitial?.id ? String(supplierInitial.id) : AUCUN);
    setDevise((supplierInitial?.devise as Devise) || 'USD');
    setMontantPrevu(''); setDate(appToday()); setDescription(''); setQuantite('');
    setQuery(''); setSuggestions([]); setSelectedRef(null); setVariantId(''); setMagasinId('');
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

  useEffect(() => {
    if (!query.trim() || selectedRef) { setSuggestions([]); setSearching(false); return; }
    setSearching(true);
    const t = setTimeout(() => {
      djangoClient.catalog.references.autocomplete(query.trim()).then(setSuggestions).catch(() => setSuggestions([])).finally(() => setSearching(false));
    }, 250);
    return () => clearTimeout(t);
  }, [query, selectedRef]);

  const supplierChoisi = useMemo(() => suppliers.find((s) => String(s.id) === supplierId) ?? null, [suppliers, supplierId]);
  const variant = useMemo(() => (selectedRef?.couleurs || []).find((c: any) => String(c.variant_id) === variantId) ?? null, [selectedRef, variantId]);

  const submit = async (statut: 'BROUILLON' | 'COMMANDE') => {
    if (!selectedRef || !variantId) { toast.error('Choisissez le produit (référence + couleur).'); return; }
    const q = Math.floor(Number(quantite));
    if (!q || q < 1) { toast.error('Indiquez la quantité de pièces.'); return; }
    if (isAdmin && magasins.length > 1 && !magasinId) { toast.error('Choisissez le magasin destinataire.'); return; }
    setSubmitting(statut);
    try {
      const o = await djangoClient.suppliers.create({
        supplier: supplierId === AUCUN ? null : Number(supplierId), product_variant: Number(variantId), quantite: q, devise,
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
          <DialogDescription>Un approvisionnement = un fournisseur, un produit, une quantité. Pour un autre produit, créez un autre approvisionnement.</DialogDescription>
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
            {selectedRef ? (
              <div className="flex items-center justify-between gap-2">
                <div>
                  <p className="font-medium">{selectedRef.brand_name} {selectedRef.reference_name}</p>
                  <p className="text-xs text-muted-foreground">prix de vente {fmtAr(selectedRef.prix_vente)}</p>
                </div>
                <Button variant="ghost" size="sm" onClick={() => { setSelectedRef(null); setVariantId(''); setQuery(''); }}>Changer</Button>
              </div>
            ) : (
              <div className="relative">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input className="pl-8" placeholder="Rechercher une référence (ex : A15)" value={query} onChange={(e) => setQuery(e.target.value)} autoFocus />
                {(searching || suggestions.length > 0) && query.trim() && (
                  <div className="absolute z-20 mt-1 w-full rounded-md border bg-popover shadow max-h-56 overflow-auto">
                    {searching && <p className="p-2 text-xs text-muted-foreground">Recherche…</p>}
                    {suggestions.map((r) => (
                      <button key={r.id} type="button" className="w-full text-left px-3 py-2 text-sm hover:bg-muted" onClick={() => { setSelectedRef(r); setVariantId(r.couleurs?.length === 1 ? String(r.couleurs[0].variant_id) : ''); setSuggestions([]); }}>
                        {r.brand_name} {r.reference_name} <span className="text-muted-foreground">· {r.type_name}</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>Couleur / variante</Label>
                <Select value={variantId} onValueChange={setVariantId} disabled={!selectedRef}>
                  <SelectTrigger className="w-full"><SelectValue placeholder={selectedRef ? 'Choisir' : 'Référence d’abord'} /></SelectTrigger>
                  <SelectContent>{(selectedRef?.couleurs || []).map((c: any) => <SelectItem key={c.variant_id} value={String(c.variant_id)}>{c.couleur}{typeof c.stock_actuel === 'number' ? ` · stock ${c.stock_actuel}` : ''}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div className="space-y-1"><Label>Quantité (pièces)</Label><Input type="number" min={1} value={quantite} onChange={(e) => setQuantite(e.target.value)} placeholder="Ex : 100" /></div>
            </div>
            {variant && <p className="text-xs text-muted-foreground">Produit : {selectedRef.brand_name} {selectedRef.reference_name} — {variant.couleur}</p>}
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
