'use client';

import { useCallback, useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Plus, Trash2, Truck, PackageCheck, RefreshCw } from 'lucide-react';
import { toast } from 'sonner';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';

const STATUT_LABEL: Record<string, string> = {
  BROUILLON: 'Brouillon', COMMANDE: 'Commandé', RECU: 'Reçu',
};
const STATUT_COLOR: Record<string, string> = {
  BROUILLON: 'bg-slate-100 text-slate-800', COMMANDE: 'bg-blue-100 text-blue-800', RECU: 'bg-green-100 text-green-800',
};

export default function SuppliersPage() {
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [createOpen, setCreateOpen] = useState(false);
  const [detail, setDetail] = useState<any | null>(null);

  const fetchOrders = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const data = await djangoClient.suppliers.list();
      setOrders(data);
    } catch (err: any) {
      toast.error(err.message || 'Erreur de chargement');
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(['supplier_order'], () => fetchOrders(true));
  useEffect(() => { fetchOrders(); }, [fetchOrders]);

  const receive = async (order: any) => {
    try {
      await djangoClient.suppliers.receive(order.id);
      toast.success(`Commande ${order.numero} reçue — stock mis à jour`);
      fetchOrders();
      setDetail(null);
    } catch (err: any) {
      toast.error(err.message || 'Réception impossible');
    }
  };

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><Truck className="h-6 w-6" /> Fournisseurs</h1>
          <p className="text-sm text-muted-foreground">Coût de revient réel : marchandise + fret/import + douane + pub Meta Ads (§7.6 du cahier des charges).</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="icon" onClick={() => fetchOrders()}><RefreshCw className="h-4 w-4" /></Button>
          <Button onClick={() => setCreateOpen(true)}><Plus className="h-4 w-4 mr-2" /> Commande fournisseur</Button>
        </div>
      </div>

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <div className="p-6"><Skeleton className="h-64 w-full" /></div>
          ) : orders.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">Aucune commande fournisseur.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>N°</TableHead>
                    <TableHead>Description</TableHead>
                    <TableHead>Coût total</TableHead>
                    <TableHead>Coût unitaire</TableHead>
                    <TableHead>Statut</TableHead>
                    <TableHead className="text-right">Action</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {orders.map((o) => (
                    <TableRow key={o.id} className="cursor-pointer" onClick={() => setDetail(o)}>
                      <TableCell className="font-medium">{o.numero}</TableCell>
                      <TableCell>{o.description || '-'}</TableCell>
                      <TableCell>{fmt(o.cout_total)}</TableCell>
                      <TableCell>{fmt(o.cout_unitaire)}</TableCell>
                      <TableCell><Badge className={STATUT_COLOR[o.statut]}>{STATUT_LABEL[o.statut]}</Badge></TableCell>
                      <TableCell className="text-right">
                        {o.statut !== 'RECU' && (
                          <Button size="sm" onClick={(e) => { e.stopPropagation(); receive(o); }}>
                            <PackageCheck className="h-4 w-4 mr-1" /> Réceptionner
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!detail} onOpenChange={(o) => !o && setDetail(null)}>
        <DialogContent className="max-w-lg">
          {detail && (
            <>
              <DialogHeader>
                <DialogTitle>Commande fournisseur {detail.numero}</DialogTitle>
                <DialogDescription>{detail.description}</DialogDescription>
              </DialogHeader>
              <div className="space-y-2 text-sm">
                <div className="grid grid-cols-2 gap-2">
                  <div><p className="text-muted-foreground text-xs">Prix fournisseur</p><p>{fmt(detail.prix_fournisseur)}</p></div>
                  <div><p className="text-muted-foreground text-xs">Fret/import</p><p>{fmt(detail.fret_import)}</p></div>
                  <div><p className="text-muted-foreground text-xs">Douane</p><p>{fmt(detail.douane)}</p></div>
                  <div><p className="text-muted-foreground text-xs">Pub Meta Ads</p><p>{fmt(detail.meta_ads)}</p></div>
                </div>
                <div className="flex justify-between border-t pt-2 font-medium">
                  <span>Coût total ({detail.total_qty} u.)</span><span>{fmt(detail.cout_total)}</span>
                </div>
                <div className="flex justify-between"><span>Coût unitaire</span><span>{fmt(detail.cout_unitaire)}</span></div>
                <div>
                  <p className="text-muted-foreground mb-1">Lignes</p>
                  <ul className="space-y-1">
                    {(detail.lines || []).map((l: any) => (
                      <li key={l.id} className="flex justify-between">
                        <span>{l.reference_name} ({l.couleur}) x{l.quantite}</span>
                        <span>Marge unitaire: {fmt(l.marge_unitaire)}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
              {detail.statut !== 'RECU' && (
                <DialogFooter>
                  <Button onClick={() => receive(detail)}><PackageCheck className="h-4 w-4 mr-2" /> Réceptionner (entrée stock)</Button>
                </DialogFooter>
              )}
            </>
          )}
        </DialogContent>
      </Dialog>

      <CreateSupplierOrderDialog open={createOpen} onOpenChange={setCreateOpen} onCreated={() => { setCreateOpen(false); fetchOrders(); }} />
    </div>
  );
}

interface Line { key: string; variant_id: number; label: string; quantite: number }

function CreateSupplierOrderDialog({ open, onOpenChange, onCreated }: { open: boolean; onOpenChange: (o: boolean) => void; onCreated: () => void }) {
  const [description, setDescription] = useState('');
  const [prixFournisseur, setPrixFournisseur] = useState('0');
  const [fretImport, setFretImport] = useState('0');
  const [douane, setDouane] = useState('0');
  const [metaAds, setMetaAds] = useState('0');
  const [lines, setLines] = useState<Line[]>([]);
  const [references, setReferences] = useState<any[]>([]);
  const [referenceId, setReferenceId] = useState('');
  const [variantId, setVariantId] = useState('');
  const [quantite, setQuantite] = useState(1);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open) return;
    setDescription(''); setPrixFournisseur('0'); setFretImport('0'); setDouane('0'); setMetaAds('0');
    setLines([]); setReferenceId(''); setVariantId(''); setQuantite(1);
    djangoClient.catalog.references.list().then(setReferences).catch(() => {});
  }, [open]);

  const selectedRef = references.find((r) => String(r.id) === referenceId);

  const addLine = () => {
    if (!variantId) { toast.error('Choisissez une couleur'); return; }
    const variant = selectedRef?.variants?.find((v: any) => String(v.id) === variantId);
    if (!variant) return;
    setLines((prev) => [...prev, {
      key: `${variantId}-${Date.now()}`, variant_id: Number(variantId),
      label: `${selectedRef.brand_name} ${selectedRef.reference_name} (${variant.couleur})`, quantite,
    }]);
    setReferenceId(''); setVariantId(''); setQuantite(1);
  };

  const totalQty = lines.reduce((s, l) => s + l.quantite, 0);
  const coutTotal = Number(prixFournisseur || 0) + Number(fretImport || 0) + Number(douane || 0) + Number(metaAds || 0);
  const coutUnitaire = totalQty > 0 ? coutTotal / totalQty : 0;

  const submit = async () => {
    if (lines.length === 0) { toast.error('Ajoutez au moins une ligne'); return; }
    setSubmitting(true);
    try {
      await djangoClient.suppliers.create({
        description,
        prix_fournisseur: prixFournisseur, fret_import: fretImport, douane, meta_ads: metaAds,
        lines: lines.map((l) => ({ product_variant: l.variant_id, quantite: l.quantite })),
      });
      toast.success('Commande fournisseur créée');
      onCreated();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Nouvelle commande fournisseur</DialogTitle>
          <DialogDescription>§7.6 — coût de revient réel calculé automatiquement.</DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1">
            <Label>Description</Label>
            <Textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Ex: réappro coques Samsung — lot Chine mars" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1"><Label>Prix fournisseur (Ar)</Label><Input type="number" value={prixFournisseur} onChange={(e) => setPrixFournisseur(e.target.value)} /></div>
            <div className="space-y-1"><Label>Fret/import (Ar)</Label><Input type="number" value={fretImport} onChange={(e) => setFretImport(e.target.value)} /></div>
            <div className="space-y-1"><Label>Douane (Ar)</Label><Input type="number" value={douane} onChange={(e) => setDouane(e.target.value)} /></div>
            <div className="space-y-1"><Label>Pub Meta Ads (Ar)</Label><Input type="number" value={metaAds} onChange={(e) => setMetaAds(e.target.value)} /></div>
          </div>

          <div className="border rounded-lg p-3 space-y-2 bg-muted/30">
            <p className="text-sm font-medium">Ajouter une ligne</p>
            <Select value={referenceId} onValueChange={(v) => { setReferenceId(v); setVariantId(''); }}>
              <SelectTrigger><SelectValue placeholder="Référence" /></SelectTrigger>
              <SelectContent>
                {references.map((r) => <SelectItem key={r.id} value={String(r.id)}>{r.brand_name} {r.reference_name}</SelectItem>)}
              </SelectContent>
            </Select>
            {selectedRef && (
              <div className="grid grid-cols-2 gap-2">
                <Select value={variantId} onValueChange={setVariantId}>
                  <SelectTrigger><SelectValue placeholder="Couleur" /></SelectTrigger>
                  <SelectContent>
                    {(selectedRef.variants || []).map((v: any) => <SelectItem key={v.id} value={String(v.id)}>{v.couleur}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Input type="number" min={1} value={quantite} onChange={(e) => setQuantite(Math.max(1, Number(e.target.value)))} />
              </div>
            )}
            <Button type="button" variant="secondary" size="sm" onClick={addLine}><Plus className="h-4 w-4 mr-2" /> Ajouter</Button>
          </div>

          {lines.length > 0 && (
            <div className="space-y-1">
              {lines.map((l, idx) => (
                <div key={l.key} className="flex items-center justify-between text-sm border rounded-md px-3 py-2">
                  <span>{l.label} x{l.quantite}</span>
                  <Button size="icon" variant="ghost" onClick={() => setLines((prev) => prev.filter((_, i) => i !== idx))}>
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </div>
              ))}
            </div>
          )}

          <div className="border-t pt-2 text-sm space-y-1">
            <div className="flex justify-between"><span>Coût total ({totalQty} u.)</span><span className="font-medium">{fmt(coutTotal)}</span></div>
            <div className="flex justify-between"><span>Coût unitaire estimé</span><span className="font-medium">{fmt(coutUnitaire)}</span></div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>{submitting ? 'Création…' : 'Créer'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
