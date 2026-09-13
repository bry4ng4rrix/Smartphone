'use client';

/**
 * Dialog « Nouvel approvisionnement » (POST /api/suppliers/orders/).
 *
 * Fournisseur (facultatif), devise + taux de change (Ar pour 1 unité, requis
 * hors MGA), date, description, méthode d'allocation des frais, destination,
 * lignes d'articles (référence du catalogue → couleur/variante, quantité,
 * prix unitaire fournisseur dans la devise) et récapitulatif.
 *
 * Deux sorties : « Enregistrer en brouillon » (BROUILLON) ou « Créer et
 * commander » (COMMANDE). Le parent reçoit l'approvisionnement créé et
 * redirige vers sa page de détail.
 */

import { useEffect, useMemo, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { appToday } from '@/lib/timezone';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Info, Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import {
  DEVISES, METHODES_ALLOCATION, fmtAr, fmtDevise, fmtNombre, messageErreur, type Devise,
} from './supplier-status';

interface Ligne {
  key: string;
  variant_id: number;
  reference_label: string;
  couleur: string;
  prix_vente: number;
  quantite: number;
  prix_unitaire: number;
}

const AUCUN = '__aucun__';

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
  const [devise, setDevise] = useState<Devise>('MGA');
  const [tauxChange, setTauxChange] = useState('');
  const [date, setDate] = useState(appToday());
  const [description, setDescription] = useState('');
  const [methodeAllocation, setMethodeAllocation] = useState<'VALEUR' | 'QUANTITE' | 'MANUEL'>('VALEUR');
  const [destination, setDestination] = useState('Madagascar');
  const [lignes, setLignes] = useState<Ligne[]>([]);
  const [submitting, setSubmitting] = useState<null | 'BROUILLON' | 'COMMANDE'>(null);

  // Réinitialisation à chaque ouverture + chargement des listes.
  useEffect(() => {
    if (!open) return;
    setSupplierId(supplierInitial?.id ? String(supplierInitial.id) : AUCUN);
    setDevise((supplierInitial?.devise as Devise) || 'MGA');
    setTauxChange('');
    setDate(appToday());
    setDescription('');
    setMethodeAllocation('VALEUR');
    setDestination('Madagascar');
    setLignes([]);
    setSubmitting(null);
    setMagasinId('');

    djangoClient.suppliers.suppliersList({ actif: true })
      .then((list) => {
        // Le fournisseur pré-sélectionné doit rester visible même s'il est inactif.
        if (supplierInitial?.id && !list.some((s: any) => s.id === supplierInitial.id)) {
          setSuppliers([supplierInitial, ...list]);
        } else {
          setSuppliers(list);
        }
      })
      .catch(() => setSuppliers(supplierInitial?.id ? [supplierInitial] : []));

    if (isAdmin) {
      djangoClient.users.list()
        .then((list: any[]) => {
          const mags = (list || [])
            .filter((m) => m?.magasin_id)
            .map((m) => ({ magasin_id: Number(m.magasin_id), shop_name: String(m.shop_name || `Magasin ${m.magasin_id}`) }));
          setMagasins(mags);
          if (mags.length === 1) setMagasinId(String(mags[0].magasin_id));
        })
        .catch(() => setMagasins([]));
    } else {
      setMagasins([]);
    }
  }, [open, supplierInitial, isAdmin]);

  const supplierChoisi = useMemo(
    () => suppliers.find((s) => String(s.id) === supplierId) ?? null,
    [suppliers, supplierId],
  );

  const changerFournisseur = (v: string) => {
    setSupplierId(v);
    const s = suppliers.find((x) => String(x.id) === v);
    if (s?.devise) setDevise(s.devise as Devise);
  };

  const horsMga = devise !== 'MGA';
  const taux = Number(tauxChange);
  const tauxValide = !horsMga || (tauxChange.trim() !== '' && Number.isFinite(taux) && taux > 0);
  const symbole = DEVISES.find((d) => d.value === devise)?.symbole ?? devise;

  const totalQty = lignes.reduce((s, l) => s + l.quantite, 0);
  const totalDevise = lignes.reduce((s, l) => s + l.quantite * l.prix_unitaire, 0);
  const totalAr = horsMga ? (tauxValide ? totalDevise * taux : null) : totalDevise;

  const majLigne = (key: string, patch: Partial<Ligne>) =>
    setLignes((prev) => prev.map((l) => (l.key === key ? { ...l, ...patch } : l)));

  const ajouterLigne = (l: Omit<Ligne, 'key'>) => {
    setLignes((prev) => {
      // Même variante déjà présente : on cumule la quantité et on garde le dernier prix.
      const idx = prev.findIndex((x) => x.variant_id === l.variant_id);
      if (idx >= 0) {
        const copie = [...prev];
        copie[idx] = { ...copie[idx], quantite: copie[idx].quantite + l.quantite, prix_unitaire: l.prix_unitaire };
        return copie;
      }
      return [...prev, { ...l, key: `${l.variant_id}-${Date.now()}` }];
    });
  };

  const submit = async (statut: 'BROUILLON' | 'COMMANDE') => {
    if (lignes.length === 0) { toast.error('Ajoutez au moins un article.'); return; }
    if (!tauxValide) { toast.error(`Indiquez le taux de change (Ar pour 1 ${symbole}).`); return; }
    if (lignes.some((l) => !l.quantite || l.quantite < 1)) { toast.error('Chaque ligne doit avoir une quantité d\'au moins 1.'); return; }
    if (lignes.some((l) => !Number.isFinite(l.prix_unitaire) || l.prix_unitaire < 0)) { toast.error('Prix unitaire invalide.'); return; }
    if (isAdmin && magasins.length > 1 && !magasinId) { toast.error('Choisissez le magasin destinataire.'); return; }

    setSubmitting(statut);
    try {
      const order = await djangoClient.suppliers.create({
        supplier: supplierId === AUCUN ? null : Number(supplierId),
        devise,
        taux_change: horsMga ? tauxChange.trim() : null,
        methode_allocation: methodeAllocation,
        date: date || undefined,
        destination: destination.trim() || 'Madagascar',
        description: description.trim(),
        statut,
        lines: lignes.map((l) => ({
          product_variant: l.variant_id,
          quantite: l.quantite,
          prix_unitaire: String(l.prix_unitaire),
        })),
        ...(magasinId ? { magasin_id: Number(magasinId) } : {}),
      });
      toast.success(
        statut === 'COMMANDE'
          ? `Approvisionnement ${order?.numero ?? ''} créé et commandé`
          : `Brouillon ${order?.numero ?? ''} enregistré`,
      );
      onOpenChange(false);
      onCreated?.(order);
    } catch (err) {
      toast.error(messageErreur(err, 'Création impossible'));
    } finally {
      setSubmitting(null);
    }
  };

  const allocation = METHODES_ALLOCATION.find((m) => m.value === methodeAllocation);

  return (
    <Dialog open={open} onOpenChange={(o) => !submitting && onOpenChange(o)}>
      <DialogContent className="max-w-3xl max-h-[92vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Nouvel approvisionnement</DialogTitle>
          <DialogDescription>
            Commande passée à un fournisseur. Les paiements, le transport, la douane et les frais
            s'ajoutent ensuite depuis la fiche de l'approvisionnement pour obtenir le coût de revient par pièce.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* Informations générales */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Fournisseur</Label>
              <Select value={supplierId} onValueChange={changerFournisseur}>
                <SelectTrigger className="w-full"><SelectValue placeholder="Fournisseur" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={AUCUN}>— Sans fournisseur —</SelectItem>
                  {suppliers.map((s) => (
                    <SelectItem key={s.id} value={String(s.id)}>
                      {s.nom}{s.pays ? ` (${s.pays})` : ''}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {supplierChoisi?.devise && supplierChoisi.devise !== devise && (
                <p className="text-xs text-muted-foreground">Devise habituelle de ce fournisseur : {supplierChoisi.devise}.</p>
              )}
            </div>

            {isAdmin && magasins.length > 1 && (
              <div className="space-y-1">
                <Label>Magasin destinataire <span className="text-red-500">*</span></Label>
                <Select value={magasinId} onValueChange={setMagasinId}>
                  <SelectTrigger className="w-full"><SelectValue placeholder="Choisir le magasin" /></SelectTrigger>
                  <SelectContent>
                    {magasins.map((m) => <SelectItem key={m.magasin_id} value={String(m.magasin_id)}>{m.shop_name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            )}

            <div className="space-y-1">
              <Label>Date</Label>
              <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>

            <div className="space-y-1">
              <Label>Devise de la commande</Label>
              <Select value={devise} onValueChange={(v) => setDevise(v as Devise)}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {DEVISES.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>

            {horsMga && (
              <div className="space-y-1">
                <Label>Taux de change <span className="text-red-500">*</span></Label>
                <Input
                  type="number"
                  min={0}
                  step="any"
                  inputMode="decimal"
                  placeholder={`Ar pour 1 ${symbole}`}
                  value={tauxChange}
                  onChange={(e) => setTauxChange(e.target.value)}
                  aria-invalid={tauxChange !== '' && !tauxValide}
                />
                <p className="text-xs text-muted-foreground">
                  {tauxValide ? `1 ${symbole} = ${fmtAr(taux)}` : `Nombre d'ariary pour 1 ${symbole}.`}
                </p>
              </div>
            )}

            <div className="space-y-1">
              <Label>Destination</Label>
              <Input value={destination} onChange={(e) => setDestination(e.target.value)} placeholder="Madagascar" />
            </div>

            <div className="space-y-1 sm:col-span-2">
              <Label>Méthode d'allocation des frais</Label>
              <Select value={methodeAllocation} onValueChange={(v) => setMethodeAllocation(v as 'VALEUR' | 'QUANTITE' | 'MANUEL')}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {METHODES_ALLOCATION.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}
                </SelectContent>
              </Select>
              {allocation && (
                <p className="text-xs text-muted-foreground flex items-start gap-1">
                  <Info className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                  <span>
                    {allocation.description}
                    {' '}Les frais (transport, douane, taxes…) seront répartis entre les lignes selon cette méthode.
                  </span>
                </p>
              )}
            </div>

            <div className="space-y-1 sm:col-span-2">
              <Label>Description</Label>
              <Textarea
                rows={2}
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Ex : lot coques Samsung — commande de septembre"
              />
            </div>
          </div>

          {/* Lignes d'articles */}
          <SelecteurArticle devise={devise} symbole={symbole} onAdd={ajouterLigne} />

          {lignes.length > 0 ? (
            <div className="rounded-lg border overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-muted/50 text-xs text-muted-foreground">
                  <tr>
                    <th className="text-left font-medium px-3 py-2">Article</th>
                    <th className="text-right font-medium px-3 py-2 w-24">Quantité</th>
                    <th className="text-right font-medium px-3 py-2 w-36">Prix unit. ({symbole})</th>
                    <th className="text-right font-medium px-3 py-2 w-32">Total ligne</th>
                    <th className="px-2 py-2 w-10" />
                  </tr>
                </thead>
                <tbody>
                  {lignes.map((l) => (
                    <tr key={l.key} className="border-t">
                      <td className="px-3 py-2">
                        <p className="font-medium">{l.reference_label}</p>
                        <p className="text-xs text-muted-foreground">
                          {l.couleur} · prix de vente {fmtAr(l.prix_vente)}
                        </p>
                      </td>
                      <td className="px-3 py-2 text-right">
                        <Input
                          type="number"
                          min={1}
                          className="h-8 text-right"
                          value={l.quantite}
                          onChange={(e) => majLigne(l.key, { quantite: Math.max(0, Math.floor(Number(e.target.value) || 0)) })}
                        />
                      </td>
                      <td className="px-3 py-2 text-right">
                        <Input
                          type="number"
                          min={0}
                          step="any"
                          inputMode="decimal"
                          className="h-8 text-right"
                          value={l.prix_unitaire}
                          onChange={(e) => majLigne(l.key, { prix_unitaire: Number(e.target.value) || 0 })}
                        />
                      </td>
                      <td className="px-3 py-2 text-right tabular-nums font-medium whitespace-nowrap">
                        {fmtDevise(l.quantite * l.prix_unitaire, devise)}
                      </td>
                      <td className="px-2 py-2 text-right">
                        <Button
                          type="button"
                          size="icon"
                          variant="ghost"
                          aria-label="Retirer la ligne"
                          onClick={() => setLignes((prev) => prev.filter((x) => x.key !== l.key))}
                        >
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground text-center py-3 border rounded-lg border-dashed">
              Aucun article. Recherchez une référence ci-dessus pour l'ajouter.
            </p>
          )}

          {/* Récapitulatif */}
          <div className="rounded-lg border bg-muted/30 p-3 text-sm space-y-1">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Quantité totale</span>
              <span className="font-medium tabular-nums">{fmtNombre(totalQty)} pièce{totalQty > 1 ? 's' : ''}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Valeur d'achat ({devise})</span>
              <span className="font-medium tabular-nums">{fmtDevise(totalDevise, devise)}</span>
            </div>
            {horsMga && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">≈ en ariary</span>
                <span className="font-medium tabular-nums">
                  {totalAr === null ? 'Taux de change requis' : fmtAr(totalAr)}
                </span>
              </div>
            )}
            {totalQty > 0 && totalAr !== null && (
              <div className="flex justify-between border-t pt-1 mt-1">
                <span className="text-muted-foreground">Valeur d'achat moyenne par pièce (hors frais)</span>
                <span className="tabular-nums">{fmtAr(totalAr / totalQty)}</span>
              </div>
            )}
          </div>
        </div>

        <DialogFooter className="gap-2 sm:gap-2">
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={!!submitting}>Annuler</Button>
          <Button type="button" variant="secondary" onClick={() => submit('BROUILLON')} disabled={!!submitting}>
            {submitting === 'BROUILLON' ? 'Enregistrement…' : 'Enregistrer en brouillon'}
          </Button>
          <Button type="button" onClick={() => submit('COMMANDE')} disabled={!!submitting}>
            {submitting === 'COMMANDE' ? 'Création…' : 'Créer et commander'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Recherche d'une référence du catalogue (autocomplete), choix de la couleur
 * (variante), quantité et prix unitaire fournisseur → ajout d'une ligne.
 */
function SelecteurArticle({
  devise,
  symbole,
  onAdd,
}: {
  devise: Devise;
  symbole: string;
  onAdd: (l: Omit<Ligne, 'key'>) => void;
}) {
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);
  const [selectedRef, setSelectedRef] = useState<any | null>(null);
  const [variantId, setVariantId] = useState<string>('');
  const [quantite, setQuantite] = useState('');
  const [prix, setPrix] = useState('');

  useEffect(() => {
    if (!query.trim()) { setSuggestions([]); setSearching(false); return; }
    setSearching(true);
    const t = setTimeout(() => {
      djangoClient.catalog.references
        .autocomplete(query.trim())
        .then(setSuggestions)
        .catch(() => setSuggestions([]))
        .finally(() => setSearching(false));
    }, 250);
    return () => clearTimeout(t);
  }, [query]);

  const reset = () => {
    setQuery(''); setSuggestions([]); setSelectedRef(null); setVariantId(''); setQuantite(''); setPrix('');
  };

  const ajouter = () => {
    if (!selectedRef || !variantId) { toast.error('Sélectionnez une référence et une couleur.'); return; }
    const variant = (selectedRef.couleurs || []).find((c: any) => String(c.variant_id) === variantId);
    if (!variant) return;
    const qty = Math.floor(Number(quantite));
    if (!qty || qty < 1) { toast.error('Quantité invalide.'); return; }
    const pu = Number(prix);
    if (prix.trim() === '' || !Number.isFinite(pu) || pu < 0) { toast.error(`Indiquez le prix unitaire fournisseur (${symbole}).`); return; }
    onAdd({
      variant_id: Number(variantId),
      reference_label: `${selectedRef.brand_name} ${selectedRef.reference_name}`,
      couleur: variant.couleur,
      prix_vente: Number(selectedRef.prix_vente || 0),
      quantite: qty,
      prix_unitaire: pu,
    });
    reset();
  };

  return (
    <div className="rounded-lg border bg-muted/30 p-3 sm:p-4 space-y-3">
      <p className="text-sm font-medium">Ajouter un article</p>
      <div className="relative">
        <Input
          placeholder="Rechercher une référence du catalogue (ex : A15)"
          value={selectedRef ? `${selectedRef.brand_name} ${selectedRef.reference_name}` : query}
          onChange={(e) => { setQuery(e.target.value); setSelectedRef(null); setVariantId(''); }}
        />
        {!selectedRef && query.trim() && (
          <div className="absolute z-20 mt-1 w-full bg-background border rounded-md shadow-md max-h-56 overflow-y-auto">
            {searching ? (
              <p className="px-3 py-2 text-sm text-muted-foreground">Recherche…</p>
            ) : suggestions.length === 0 ? (
              <p className="px-3 py-2 text-sm text-muted-foreground">Aucune référence trouvée.</p>
            ) : (
              suggestions.map((s) => (
                <button
                  type="button"
                  key={s.id}
                  className="w-full text-left px-3 py-2 text-sm hover:bg-muted flex justify-between gap-3"
                  onClick={() => { setSelectedRef(s); setQuery(''); setSuggestions([]); }}
                >
                  <span>
                    {s.brand_name} {s.reference_name}{' '}
                    <span className="text-muted-foreground">({s.type_name})</span>
                  </span>
                  <span className="text-muted-foreground whitespace-nowrap">PV {fmtAr(s.prix_vente)}</span>
                </button>
              ))
            )}
          </div>
        )}
      </div>

      {selectedRef && (
        <div className="grid grid-cols-1 sm:grid-cols-4 gap-3 items-end">
          <div className="space-y-1">
            <Label>Couleur</Label>
            <Select value={variantId} onValueChange={setVariantId}>
              <SelectTrigger className="w-full"><SelectValue placeholder="Couleur" /></SelectTrigger>
              <SelectContent>
                {(selectedRef.couleurs || []).length === 0 ? (
                  <div className="px-2 py-1.5 text-sm text-muted-foreground">Aucune couleur définie</div>
                ) : (
                  selectedRef.couleurs.map((c: any) => (
                    <SelectItem key={c.variant_id} value={String(c.variant_id)}>
                      {c.couleur} <span className="text-muted-foreground">(stock : {c.stock_actuel})</span>
                    </SelectItem>
                  ))
                )}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Quantité</Label>
            <Input type="number" min={1} placeholder="Ex : 50" value={quantite} onChange={(e) => setQuantite(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label>Prix unitaire ({symbole})</Label>
            <Input
              type="number"
              min={0}
              step="any"
              inputMode="decimal"
              placeholder={devise === 'MGA' ? 'Ex : 15000' : 'Ex : 3.5'}
              value={prix}
              onChange={(e) => setPrix(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); ajouter(); } }}
            />
          </div>
          <Button type="button" variant="secondary" onClick={ajouter}>
            <Plus className="h-4 w-4 mr-2" /> Ajouter
          </Button>
          <div className="sm:col-span-4 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <Badge variant="secondary">{selectedRef.type_name}</Badge>
            <span>Prix de vente catalogue : {fmtAr(selectedRef.prix_vente)}</span>
            <button type="button" className="underline ml-auto" onClick={reset}>Changer de référence</button>
          </div>
        </div>
      )}
    </div>
  );
}
