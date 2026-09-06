'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
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
import { Plus, Trash2, Truck, Package, RefreshCw, Phone, ShoppingCart, Wrench, Boxes, CheckCircle2, Undo2, UserCheck } from 'lucide-react';
import { toast } from 'sonner';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';

const STATUTS = [
  { value: 'NOUVELLE', label: 'Nouvelle', color: 'bg-slate-100 text-slate-800' },
  { value: 'EN_PREPARATION', label: 'En préparation', color: 'bg-amber-100 text-amber-800' },
  { value: 'PRETE', label: 'Prête', color: 'bg-blue-100 text-blue-800' },
  { value: 'EN_LIVRAISON', label: 'En livraison', color: 'bg-purple-100 text-purple-800' },
  { value: 'LIVRE', label: 'Livré', color: 'bg-green-100 text-green-800' },
  { value: 'RETOUR', label: 'Retour', color: 'bg-red-100 text-red-800' },
];
const statutInfo = (s: string) => STATUTS.find((x) => x.value === s) || STATUTS[0];

const ZONES = [
  { value: 'ZONE1', label: 'Zone 1 (3 000 Ar)', frais: 3000 },
  { value: 'ZONE2', label: 'Zone 2 (4 000 Ar)', frais: 4000 },
  { value: 'ZONE3', label: 'Zone 3 (5 000 Ar)', frais: 5000 },
  { value: 'RECUPERATION', label: 'Récupération (0 Ar)', frais: 0 },
];

interface CartItem {
  key: string;
  type_id: number;
  type_name: string;
  reference_id: number;
  reference_label: string;
  prix_vente: number;
  variant_id: number;
  couleur: string;
  stock_actuel: number;
  quantite: number;
}

export default function OrdersPage() {
  const { user, isGerant, isPreparateur, isLivreur, loading: userLoading } = useCurrentUser();
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [statutFilter, setStatutFilter] = useState<string>('ALL');
  const [detail, setDetail] = useState<any | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [actionNote, setActionNote] = useState<{ order: any; target: string } | null>(null);
  const [assignTarget, setAssignTarget] = useState<{ order: any; role: 'PREPARATEUR' | 'LIVREUR' } | null>(null);

  const fetchOrders = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const filters: any = {};
      if (isGerant && statutFilter !== 'ALL') filters.statut = statutFilter;
      const data = await djangoClient.orders.list(filters);
      setOrders(data);
    } catch (err: any) {
      toast.error(err.message || 'Erreur de chargement des commandes');
    } finally {
      if (!silent) setLoading(false);
    }
  }, [isGerant, statutFilter]);

  useRealtimeRefresh(['order', 'order_status_history'], () => fetchOrders(true));
  useEffect(() => { if (!userLoading) fetchOrders(); }, [userLoading, fetchOrders]);

  const title = isPreparateur ? 'Dépôt — Commandes à préparer' : isLivreur ? 'Ma tournée' : 'Commandes';
  const description = isPreparateur
    ? 'Commandes reçues à préparer, puis à marquer "Prête" pour le livreur.'
    : isLivreur
    ? 'Commandes prêtes à récupérer, puis "Livré" ou "Retour" une fois la tournée faite.'
    : 'Suivi complet des commandes clients (§5-§7.1 du cahier des charges).';

  const nextAction = (order: any): { label: string; target: string; icon: any } | null => {
    if (isPreparateur) {
      if (order.statut_courant === 'NOUVELLE') return { label: 'Commencer la préparation', target: 'EN_PREPARATION', icon: Package };
      if (order.statut_courant === 'EN_PREPARATION') return { label: 'Commande prête', target: 'PRETE', icon: Package };
      return null;
    }
    if (isLivreur) {
      if (order.statut_courant === 'PRETE') return { label: 'Récupérer (en livraison)', target: 'EN_LIVRAISON', icon: Truck };
      if (order.statut_courant === 'EN_LIVRAISON') return { label: 'Livré', target: 'LIVRE', icon: Truck };
      return null;
    }
    // Gérant : désigne un préparateur/livreur libre pour faire avancer la
    // commande (les retraits sur place se gèrent sur la page Récupération).
    if (isGerant) {
      if (order.statut_courant === 'NOUVELLE') return { label: 'Assigner un préparateur', target: 'EN_PREPARATION', icon: UserCheck };
      if (order.statut_courant === 'PRETE' && order.livraison_zone !== 'RECUPERATION') {
        return { label: 'Assigner un livreur', target: 'EN_LIVRAISON', icon: UserCheck };
      }
      return null;
    }
    return null;
  };

  const doChangeStatus = async (order: any, target: string, note?: string, assignee?: { preparateur_id?: number; livreur_id?: number }) => {
    try {
      await djangoClient.orders.changeStatus(order.id, target, note, assignee);
      toast.success(`Commande ${order.numero} → ${statutInfo(target).label}`);
      fetchOrders(true);
      setActionNote(null);
      setAssignTarget(null);
    } catch (err: any) {
      toast.error(err.message || 'Action impossible');
    }
  };

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">{title}</h1>
          <p className="text-sm text-muted-foreground">{description}</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="icon" onClick={() => fetchOrders()}>
            <RefreshCw className="h-4 w-4" />
          </Button>
          {isGerant && (
            <Button onClick={() => setCreateOpen(true)}>
              <Plus className="h-4 w-4 mr-2" /> Nouvelle commande
            </Button>
          )}
        </div>
      </div>

      {isGerant && (
        <div className="flex flex-wrap gap-2">
          <Button
            variant={statutFilter === 'ALL' ? 'default' : 'outline'}
            size="sm"
            onClick={() => setStatutFilter('ALL')}
          >
            Toutes
          </Button>
          {STATUTS.map((s) => (
            <Button
              key={s.value}
              variant={statutFilter === s.value ? 'default' : 'outline'}
              size="sm"
              onClick={() => setStatutFilter(s.value)}
            >
              {s.label}
            </Button>
          ))}
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <div className="p-6"><Skeleton className="h-64 w-full" /></div>
          ) : orders.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">Aucune commande.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>N° commande</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Client</TableHead>
                    {isLivreur && <TableHead>Téléphone</TableHead>}
                    <TableHead>Produit</TableHead>
                    <TableHead>Zone</TableHead>
                    {isLivreur && <TableHead>Adresse</TableHead>}
                    {!isPreparateur && <TableHead>Total</TableHead>}
                    <TableHead>Statut</TableHead>
                    <TableHead className="text-right">Action</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {orders.map((order) => {
                    const action = nextAction(order);
                    return (
                      <TableRow key={order.id} className="cursor-pointer" onClick={() => setDetail(order)}>
                        <TableCell className="font-medium">{order.numero}</TableCell>
                        <TableCell className="whitespace-nowrap text-xs text-muted-foreground">
                          {order.date_commande ? new Date(order.date_commande).toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '-'}
                        </TableCell>
                        <TableCell>{order.client_nom}</TableCell>
                        {isLivreur && (
                          <TableCell>
                            <a
                              href={`tel:${order.telephone}`}
                              onClick={(e) => e.stopPropagation()}
                              className="flex items-center gap-1 text-blue-600 hover:underline"
                            >
                              <Phone className="h-3 w-3" /> {order.telephone}
                            </a>
                          </TableCell>
                        )}
                        <TableCell className="max-w-[220px] truncate">
                          {(order.items || []).map((it: any) => `${it.reference_name} (${it.couleur}) x${it.quantite}`).join(', ')}
                        </TableCell>
                        <TableCell>{ZONES.find((z) => z.value === order.livraison_zone)?.label.split(' (')[0] || order.livraison_zone}</TableCell>
                        {isLivreur && <TableCell className="max-w-[180px] truncate">{order.adresse_livraison || '-'}</TableCell>}
                        {!isPreparateur && <TableCell>{fmt(order.total_a_payer)}</TableCell>}
                        <TableCell>
                          <Badge className={statutInfo(order.statut_courant).color}>{statutInfo(order.statut_courant).label}</Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          {action && (
                            <Button
                              size="sm"
                              onClick={(e) => {
                                e.stopPropagation();
                                if (isLivreur && order.statut_courant === 'EN_LIVRAISON') {
                                  setActionNote({ order, target: action.target });
                                } else if (isGerant) {
                                  setAssignTarget({ order, role: action.target === 'EN_PREPARATION' ? 'PREPARATEUR' : 'LIVREUR' });
                                } else {
                                  doChangeStatus(order, action.target);
                                }
                              }}
                            >
                              <action.icon className="h-4 w-4 mr-1" /> {action.label}
                            </Button>
                          )}
                          {isLivreur && order.statut_courant === 'EN_LIVRAISON' && (
                            <Button
                              size="sm"
                              variant="outline"
                              className="ml-2 text-red-600"
                              onClick={(e) => { e.stopPropagation(); setActionNote({ order, target: 'RETOUR' }); }}
                            >
                              Retour
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Détail commande */}
      <Dialog open={!!detail} onOpenChange={(o) => !o && setDetail(null)}>
        <DialogContent className="max-w-lg">
          {detail && (
            <>
              <DialogHeader>
                <DialogTitle>Commande {detail.numero}</DialogTitle>
                <DialogDescription>{detail.client_nom} — {detail.telephone}</DialogDescription>
              </DialogHeader>
              <div className="space-y-3 text-sm">
                <div className="flex justify-between"><span className="text-muted-foreground">Statut</span><Badge className={statutInfo(detail.statut_courant).color}>{statutInfo(detail.statut_courant).label}</Badge></div>
                {detail.date_commande && (
                  <div className="flex justify-between"><span className="text-muted-foreground">Date commande</span><span>{new Date(detail.date_commande).toLocaleString('fr-FR')}</span></div>
                )}
                <div className="flex justify-between"><span className="text-muted-foreground">Zone</span><span>{ZONES.find((z) => z.value === detail.livraison_zone)?.label}</span></div>
                {detail.adresse_livraison && (
                  <div className="flex justify-between gap-4"><span className="text-muted-foreground shrink-0">Adresse</span><span className="text-right">{detail.adresse_livraison}</span></div>
                )}
                {detail.total_a_payer != null && (
                  <div className="flex justify-between"><span className="text-muted-foreground">Total à payer</span><span className="font-semibold">{fmt(detail.total_a_payer)}</span></div>
                )}
                {detail.preparateur_name && (
                  <div className="flex justify-between"><span className="text-muted-foreground">Préparateur</span><span>{detail.preparateur_name}</span></div>
                )}
                {detail.livreur_name && (
                  <div className="flex justify-between"><span className="text-muted-foreground">Livreur</span><span>{detail.livreur_name}</span></div>
                )}
                {detail.note && <div><span className="text-muted-foreground">Note</span><p>{detail.note}</p></div>}
                <div>
                  <p className="text-muted-foreground mb-1">Articles</p>
                  <ul className="space-y-1">
                    {(detail.items || []).map((it: any) => (
                      <li key={it.id} className="flex justify-between">
                        <span>{it.reference_name} ({it.couleur}) x{it.quantite}</span>
                        {it.prix_unitaire != null && <span>{fmt(Number(it.prix_unitaire) * it.quantite)}</span>}
                      </li>
                    ))}
                  </ul>
                </div>
                {detail.status_history && (
                  <>
                    <div className="border-t pt-3">
                      <p className="text-muted-foreground mb-2">Chronologie</p>
                      <OrderTimeline order={detail} />
                    </div>
                    <div>
                      <p className="text-muted-foreground mb-1">Historique détaillé</p>
                      <ul className="space-y-1">
                        {detail.status_history.map((h: any) => (
                          <li key={h.id} className="text-xs text-muted-foreground">
                            {statutInfo(h.nouveau_statut).label} — {h.changed_by_name || 'Système'} — {new Date(h.timestamp).toLocaleString('fr-FR')}
                            {h.note && ` (${h.note})`}
                          </li>
                        ))}
                      </ul>
                    </div>
                  </>
                )}
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Note livreur (Livré / Retour) */}
      <Dialog open={!!actionNote} onOpenChange={(o) => !o && setActionNote(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{actionNote?.target === 'RETOUR' ? 'Marquer un retour' : 'Marquer comme livré'}</DialogTitle>
            <DialogDescription>Commande {actionNote?.order?.numero} — note optionnelle (ex: "client absent").</DialogDescription>
          </DialogHeader>
          <NoteForm onSubmit={(note) => actionNote && doChangeStatus(actionNote.order, actionNote.target, note)} />
        </DialogContent>
      </Dialog>

      {isGerant && (
        <CreateOrderDialog
          open={createOpen}
          onOpenChange={setCreateOpen}
          onCreated={() => { setCreateOpen(false); fetchOrders(); }}
        />
      )}

      {isGerant && (
        <AssignStaffDialog
          target={assignTarget}
          onOpenChange={(o) => !o && setAssignTarget(null)}
          onAssign={(userId) =>
            assignTarget &&
            doChangeStatus(
              assignTarget.order,
              assignTarget.role === 'PREPARATEUR' ? 'EN_PREPARATION' : 'EN_LIVRAISON',
              undefined,
              assignTarget.role === 'PREPARATEUR' ? { preparateur_id: userId } : { livreur_id: userId },
            )
          }
        />
      )}
    </div>
  );
}

// Résumé "Prête le / En livraison depuis le / Livrée le" — une ligne par
// statut effectivement atteint, dérivée de l'historique complet, pour une
// lecture immédiate sans avoir à parcourir la liste détaillée en dessous.
const TIMELINE_MILESTONES: { status: string; icon: any; label: string }[] = [
  { status: 'EN_PREPARATION', icon: Wrench, label: 'Préparation commencée le' },
  { status: 'PRETE', icon: Boxes, label: 'Prête le' },
  { status: 'EN_LIVRAISON', icon: Truck, label: 'En livraison depuis le' },
  { status: 'LIVRE', icon: CheckCircle2, label: 'Livrée le' },
  { status: 'RETOUR', icon: Undo2, label: 'Retour le' },
];

function OrderTimeline({ order }: { order: any }) {
  const timestamps = new Map<string, string>();
  for (const h of order.status_history || []) {
    if (!timestamps.has(h.nouveau_statut)) timestamps.set(h.nouveau_statut, h.timestamp);
  }

  const rows = [
    { icon: ShoppingCart, label: 'Commande créée le', date: order.date_commande, reached: true },
    ...TIMELINE_MILESTONES.map((m) => ({
      icon: m.icon,
      label: m.label,
      date: timestamps.get(m.status),
      reached: timestamps.has(m.status),
    })),
  ].filter((r) => r.reached);

  return (
    <ul className="space-y-2">
      {rows.map((r) => (
        <li key={r.label} className="flex items-center gap-2 text-sm">
          <r.icon className="h-4 w-4 text-primary shrink-0" />
          <span className="text-muted-foreground">{r.label}</span>
          <span className="font-semibold">{r.date ? new Date(r.date).toLocaleString('fr-FR') : '—'}</span>
        </li>
      ))}
    </ul>
  );
}

function NoteForm({ onSubmit }: { onSubmit: (note: string) => void }) {
  const [note, setNote] = useState('');
  return (
    <div className="space-y-4">
      <Textarea placeholder="Note (optionnel)" value={note} onChange={(e) => setNote(e.target.value)} />
      <DialogFooter>
        <Button onClick={() => onSubmit(note)}>Confirmer</Button>
      </DialogFooter>
    </div>
  );
}

// Le gérant désigne un préparateur/livreur — seuls ceux libres (pas déjà en
// charge d'une autre commande) sont sélectionnables.
function AssignStaffDialog({
  target,
  onOpenChange,
  onAssign,
}: {
  target: { order: any; role: 'PREPARATEUR' | 'LIVREUR' } | null;
  onOpenChange: (o: boolean) => void;
  onAssign: (userId: number) => void;
}) {
  const [staff, setStaff] = useState<{ id: number; full_name: string; available: boolean }[]>([]);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<string>('');

  useEffect(() => {
    if (!target) return;
    setSelected('');
    setLoading(true);
    djangoClient.orders
      .availableStaff(target.role, target.order.magasin)
      .then(setStaff)
      .catch(() => setStaff([]))
      .finally(() => setLoading(false));
  }, [target]);

  const roleLabel = target?.role === 'PREPARATEUR' ? 'préparateur' : 'livreur';

  return (
    <Dialog open={!!target} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Assigner un {roleLabel}</DialogTitle>
          <DialogDescription>
            Commande {target?.order?.numero} — seul un {roleLabel} libre peut être désigné.
          </DialogDescription>
        </DialogHeader>
        {loading ? (
          <Skeleton className="h-24 w-full" />
        ) : staff.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-6">
            Aucun {roleLabel} enregistré pour ce magasin.
          </p>
        ) : (
          <div className="space-y-2">
            {staff.map((s) => (
              <button
                key={s.id}
                type="button"
                disabled={!s.available}
                onClick={() => setSelected(String(s.id))}
                className={`w-full flex items-center justify-between rounded-md border px-3 py-2 text-sm text-left transition-colors ${
                  !s.available
                    ? 'opacity-50 cursor-not-allowed bg-muted/30'
                    : selected === String(s.id)
                    ? 'border-primary bg-primary/5'
                    : 'hover:bg-muted/50'
                }`}
              >
                <span>{s.full_name}</span>
                <Badge variant="outline" className={s.available ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}>
                  {s.available ? 'Libre' : 'Occupé'}
                </Badge>
              </button>
            ))}
          </div>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button disabled={!selected} onClick={() => onAssign(Number(selected))}>
            Assigner
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// Format un Date en valeur locale pour <input type="datetime-local"> (pas d'UTC).
function toDatetimeLocalValue(d: Date) {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function CreateOrderDialog({ open, onOpenChange, onCreated }: { open: boolean; onOpenChange: (o: boolean) => void; onCreated: () => void }) {
  const [clientNom, setClientNom] = useState('');
  const [telephone, setTelephone] = useState('+261');
  const [zone, setZone] = useState('ZONE1');
  const [adresseLivraison, setAdresseLivraison] = useState('');
  const [dateCommande, setDateCommande] = useState('');
  const [note, setNote] = useState('');
  const [items, setItems] = useState<CartItem[]>([]);
  const [submitting, setSubmitting] = useState(false);

  // Sélecteur en cours d'ajout — filtres Catégorie → Sous-type + Marque,
  // combinés à la recherche texte (§6 du cahier des charges : "Type produit"
  // filtre "Marque", recherche autocomplete dans le catalogue).
  const [categories, setCategories] = useState<any[]>([]);
  const [types, setTypes] = useState<any[]>([]);
  const [brands, setBrands] = useState<any[]>([]);
  const [categoryId, setCategoryId] = useState<number | null>(null);
  const [typeId, setTypeId] = useState<number | null>(null);
  const [brandId, setBrandId] = useState<number | null>(null);
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);
  const [selectedRef, setSelectedRef] = useState<any | null>(null);
  const [variantId, setVariantId] = useState<number | null>(null);
  const [quantite, setQuantite] = useState(1);

  useEffect(() => {
    if (!open) return;
    djangoClient.catalog.categories.list().then(setCategories).catch(() => {});
    djangoClient.catalog.types.list().then(setTypes).catch(() => {});
    djangoClient.catalog.brands.list().then(setBrands).catch(() => {});
    setClientNom(''); setTelephone('+261'); setZone('ZONE1'); setAdresseLivraison('');
    setDateCommande(toDatetimeLocalValue(new Date())); setNote(''); setItems([]);
    setCategoryId(null); setTypeId(null); setBrandId(null);
    setQuery(''); setSuggestions([]); setSelectedRef(null); setVariantId(null); setQuantite(1);
  }, [open]);

  const typesForCategory = categoryId ? types.filter((t) => t.category === categoryId) : types;

  // La recherche se déclenche dès qu'un filtre est choisi (même sans texte),
  // pour afficher directement les éléments correspondant à la sélection.
  useEffect(() => {
    if (!query && !typeId && !brandId && !categoryId) { setSuggestions([]); return; }
    setSearching(true);
    const t = setTimeout(() => {
      djangoClient.catalog.references
        .autocomplete(query, { type: typeId ?? undefined, brand: brandId ?? undefined, category: categoryId ?? undefined })
        .then(setSuggestions)
        .catch(() => setSuggestions([]))
        .finally(() => setSearching(false));
    }, 250);
    return () => clearTimeout(t);
  }, [query, typeId, brandId, categoryId]);

  const zoneInfo = ZONES.find((z) => z.value === zone)!;
  const itemsTotal = items.reduce((s, it) => s + it.prix_vente * it.quantite, 0);
  const total = itemsTotal + zoneInfo.frais;

  const addItem = () => {
    if (!selectedRef || !variantId) { toast.error('Sélectionnez une référence et une couleur'); return; }
    const variant = selectedRef.couleurs.find((c: any) => c.variant_id === variantId);
    if (!variant) return;
    if (quantite > variant.stock_actuel) { toast.error(`Stock insuffisant (disponible: ${variant.stock_actuel})`); return; }
    setItems((prev) => [...prev, {
      key: `${variantId}-${Date.now()}`,
      type_id: selectedRef.type, type_name: selectedRef.type_name,
      reference_id: selectedRef.id, reference_label: `${selectedRef.brand_name} ${selectedRef.reference_name}`,
      prix_vente: Number(selectedRef.prix_vente),
      variant_id: variantId, couleur: variant.couleur, stock_actuel: variant.stock_actuel, quantite,
    }]);
    setQuery(''); setSuggestions([]); setSelectedRef(null); setVariantId(null); setQuantite(1);
  };

  const submit = async () => {
    if (!clientNom.trim()) { toast.error('Nom du client requis'); return; }
    if (!/^\+261\d{9}$/.test(telephone)) { toast.error('Téléphone au format +261XXXXXXXXX'); return; }
    if (items.length === 0) { toast.error('Ajoutez au moins un article'); return; }
    setSubmitting(true);
    try {
      await djangoClient.orders.create({
        client_nom: clientNom.trim(),
        telephone,
        livraison_zone: zone as any,
        adresse_livraison: adresseLivraison.trim(),
        // Champ vidé par l'utilisateur -> pas envoyé -> le serveur prend "maintenant" (heure précise).
        ...(dateCommande ? { date_commande: new Date(dateCommande).toISOString() } : {}),
        note,
        items: items.map((it) => ({ product_variant: it.variant_id, quantite: it.quantite })),
      });
      toast.success('Commande créée');
      onCreated();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la création');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Nouvelle commande</DialogTitle>
          <DialogDescription>Vente Facebook ou sur place — §6 du cahier des charges.</DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label>Nom client</Label>
            <Input value={clientNom} onChange={(e) => setClientNom(e.target.value)} placeholder="Rakoto Jean" />
          </div>
          <div className="space-y-2">
            <Label>Téléphone</Label>
            <Input value={telephone} onChange={(e) => setTelephone(e.target.value)} placeholder="+261340000000" />
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label>Date et heure de la commande</Label>
            <Input
              type="datetime-local"
              value={dateCommande}
              onChange={(e) => setDateCommande(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">Vide = maintenant.</p>
          </div>
          <div className="space-y-2">
            <Label>Livraison</Label>
            <Select value={zone} onValueChange={setZone}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {ZONES.map((z) => <SelectItem key={z.value} value={z.value}>{z.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>

        <div className="space-y-2">
          <Label>Adresse de livraison</Label>
          <Input
            value={adresseLivraison}
            onChange={(e) => setAdresseLivraison(e.target.value)}
            placeholder="Ex: Lot II M 45 Antanimena, Antananarivo"
          />
        </div>

        <div className="border rounded-lg p-4 space-y-3 bg-muted/30">
          <p className="text-sm font-medium">Ajouter un article</p>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <Select
              value={categoryId ? String(categoryId) : ''}
              onValueChange={(v) => { setCategoryId(Number(v)); setTypeId(null); }}
            >
              <SelectTrigger><SelectValue placeholder="Catégorie" /></SelectTrigger>
              <SelectContent>
                {categories.map((c) => <SelectItem key={c.id} value={String(c.id)}>{c.nom}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={typeId ? String(typeId) : ''} onValueChange={(v) => setTypeId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Sous-type" /></SelectTrigger>
              <SelectContent>
                {typesForCategory.map((t) => <SelectItem key={t.id} value={String(t.id)}>{t.nom}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={brandId ? String(brandId) : ''} onValueChange={(v) => setBrandId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Marque" /></SelectTrigger>
              <SelectContent>
                {brands.map((b) => <SelectItem key={b.id} value={String(b.id)}>{b.nom}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          {(categoryId || typeId || brandId) && (
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-xs text-muted-foreground">Filtres :</span>
              {categoryId && (
                <Badge variant="secondary" className="gap-1">
                  {categories.find((c) => c.id === categoryId)?.nom}
                  <button type="button" onClick={() => { setCategoryId(null); setTypeId(null); }}>×</button>
                </Badge>
              )}
              {typeId && (
                <Badge variant="secondary" className="gap-1">
                  {types.find((t) => t.id === typeId)?.nom}
                  <button type="button" onClick={() => setTypeId(null)}>×</button>
                </Badge>
              )}
              {brandId && (
                <Badge variant="secondary" className="gap-1">
                  {brands.find((b) => b.id === brandId)?.nom}
                  <button type="button" onClick={() => setBrandId(null)}>×</button>
                </Badge>
              )}
            </div>
          )}

          <div className="relative">
            <Input
              placeholder="Rechercher une référence (ex: A15)"
              value={selectedRef ? `${selectedRef.brand_name} ${selectedRef.reference_name}` : query}
              onChange={(e) => { setQuery(e.target.value); setSelectedRef(null); setVariantId(null); }}
            />
            {!selectedRef && (query || typeId || brandId || categoryId) && (
              <div className="absolute z-10 mt-1 w-full bg-background border rounded-md shadow-md max-h-56 overflow-y-auto">
                {searching ? (
                  <p className="px-3 py-2 text-sm text-muted-foreground">Recherche…</p>
                ) : suggestions.length === 0 ? (
                  <p className="px-3 py-2 text-sm text-muted-foreground">Aucun résultat pour cette sélection.</p>
                ) : (
                  suggestions.map((s) => (
                    <button
                      type="button"
                      key={s.id}
                      className="w-full text-left px-3 py-2 text-sm hover:bg-muted flex justify-between"
                      onClick={() => { setSelectedRef(s); setQuery(''); setSuggestions([]); }}
                    >
                      <span>{s.brand_name} {s.reference_name} <span className="text-muted-foreground">({s.type_name})</span></span>
                      <span>{fmt(s.prix_vente)}</span>
                    </button>
                  ))
                )}
              </div>
            )}
          </div>

          {selectedRef && (
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 items-end">
              <div className="space-y-1">
                <Label>Couleur</Label>
                <Select value={variantId ? String(variantId) : ''} onValueChange={(v) => setVariantId(Number(v))}>
                  <SelectTrigger><SelectValue placeholder="Couleur" /></SelectTrigger>
                  <SelectContent>
                    {selectedRef.couleurs.map((c: any) => (
                      <SelectItem key={c.variant_id} value={String(c.variant_id)} disabled={c.stock_actuel <= 0}>
                        {c.couleur} (stock: {c.stock_actuel})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label>Quantité</Label>
                <Input type="number" min={1} value={quantite} onChange={(e) => setQuantite(Math.max(1, Number(e.target.value)))} />
              </div>
              <div className="space-y-1">
                <Label>Prix (Ar)</Label>
                <Input value={fmt(selectedRef.prix_vente)} readOnly disabled />
              </div>
              <Button type="button" className="sm:col-span-3" variant="secondary" onClick={addItem}>
                <Plus className="h-4 w-4 mr-2" /> Ajouter à la commande
              </Button>
            </div>
          )}
        </div>

        {items.length > 0 && (
          <div className="space-y-2">
            {items.map((it, idx) => (
              <div key={it.key} className="flex items-center justify-between text-sm border rounded-md px-3 py-2">
                <span>{it.reference_label} ({it.couleur}) x{it.quantite}</span>
                <div className="flex items-center gap-3">
                  <span>{fmt(it.prix_vente * it.quantite)}</span>
                  <Button size="icon" variant="ghost" onClick={() => setItems((prev) => prev.filter((_, i) => i !== idx))}>
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}

        <div className="space-y-2">
          <Label>Note (optionnel)</Label>
          <Textarea value={note} onChange={(e) => setNote(e.target.value)} />
        </div>

        <div className="flex justify-between items-center border-t pt-3 text-sm">
          <span>Frais de livraison</span>
          <span>{fmt(zoneInfo.frais)}</span>
        </div>
        <div className="flex justify-between items-center font-semibold">
          <span>Total à payer</span>
          <span>{fmt(total)}</span>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button onClick={submit} disabled={submitting}>{submitting ? 'Création…' : 'Créer la commande'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
