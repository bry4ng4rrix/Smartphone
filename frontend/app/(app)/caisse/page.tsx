'use client';

import { useCallback, useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/ui/card';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import {
  Wallet, Store, Plus, Lock, LockOpen, Loader2, RefreshCw, ArrowDownCircle, ArrowUpCircle,
} from 'lucide-react';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const money = (v: any) =>
  `${Number(v ?? 0).toLocaleString('fr-FR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })} Ar`;

const toDatetimeLocalValue = (date: Date) => {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const fromDatetimeLocalValue = (value: string) => (value ? new Date(value).toISOString() : undefined);

const formatDateTime = (value?: string | null) =>
  value ? format(new Date(value), 'dd MMM yyyy HH:mm', { locale: fr }) : '-';

export default function CaissePage() {
  const { user, isAdmin, loading: userLoading } = useCurrentUser();

  const [stores, setStores] = useState<any[]>([]);
  const [selectedMagasinId, setSelectedMagasinId] = useState<number | null>(null);

  const [session, setSession] = useState<any | null>(null);
  const [history, setHistory] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const [openDialogOpen, setOpenDialogOpen] = useState(false);
  const [closeDialogOpen, setCloseDialogOpen] = useState(false);
  const [movementDialogOpen, setMovementDialogOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const [openingBalance, setOpeningBalance] = useState('');
  const [openingNote, setOpeningNote] = useState('');
  const [openedAt, setOpenedAt] = useState('');

  const [closingBalance, setClosingBalance] = useState('');
  const [closingNote, setClosingNote] = useState('');
  const [closedAt, setClosedAt] = useState('');

  const [movementType, setMovementType] = useState<'in' | 'out'>('in');
  const [movementAmount, setMovementAmount] = useState('');
  const [movementReason, setMovementReason] = useState('');

  // Admin has no magasin of their own — resolve which store's caisse to manage.
  const magasinId = isAdmin ? selectedMagasinId : (user?.magasin_id ?? null);

  const fetchStores = useCallback(async () => {
    if (!isAdmin) return;
    try {
      const data = await djangoClient.get<any[]>('/users/magasins/users/');
      setStores(data);
    } catch (err: any) {
      toast.error('Erreur de chargement des magasins: ' + (err.message || err));
    }
  }, [isAdmin]);

  const fetchCaisse = useCallback(async () => {
    if (!magasinId) {
      setSession(null);
      setHistory([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const [current, sessions] = await Promise.all([
        djangoClient.caisse.current(magasinId),
        djangoClient.caisse.listSessions({ magasinId }),
      ]);
      setSession(current);
      setHistory(sessions.filter((s: any) => s.status === 'closed'));
    } catch (err: any) {
      toast.error('Erreur de chargement de la caisse: ' + (err.message || err));
    } finally {
      setLoading(false);
    }
  }, [magasinId]);

  useEffect(() => {
    if (!userLoading) fetchStores();
  }, [userLoading, fetchStores]);

  useEffect(() => {
    if (!userLoading) fetchCaisse();
  }, [userLoading, fetchCaisse]);

  useRealtimeRefresh(['caisse_session', 'caisse_movement'], () => fetchCaisse());

  const movementTotals = (session?.movements || []).reduce(
    (acc: { in: number; out: number }, m: any) => {
      if (m.movement_type === 'in') acc.in += Number(m.amount);
      else acc.out += Number(m.amount);
      return acc;
    },
    { in: 0, out: 0 },
  );
  const expectedBalance = session ? Number(session.opening_balance) + movementTotals.in - movementTotals.out : 0;

  // Pré-remplit le montant (ouverture comme fermeture) avec la valeur de
  // stock actuelle du magasin — recalculée à chaque fois pour rester à jour
  // (le stock bouge avec les ventes pendant la session). Reste modifiable.
  const fetchStockValue = async (): Promise<number | null> => {
    if (!magasinId) return null;
    try {
      const stats = await djangoClient.get<any[]>('/users/magasins/stats/');
      const entry = stats.find((s: any) => s.magasin_id === magasinId);
      return entry?.total_stock_value != null ? Number(entry.total_stock_value) : null;
    } catch {
      return null;
    }
  };

  const openOpenDialog = async () => {
    setOpeningNote('');
    setOpenedAt(toDatetimeLocalValue(new Date()));
    setOpenDialogOpen(true);
    const stockValue = await fetchStockValue();
    setOpeningBalance(stockValue != null ? String(stockValue) : '');
  };

  const openCloseDialog = async () => {
    setClosingNote('');
    setClosedAt(toDatetimeLocalValue(new Date()));
    setCloseDialogOpen(true);
    const stockValue = await fetchStockValue();
    setClosingBalance(stockValue != null ? String(stockValue) : '');
  };

  const openMovementDialog = () => {
    setMovementType('in');
    setMovementAmount('');
    setMovementReason('');
    setMovementDialogOpen(true);
  };

  const handleOpen = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!magasinId) {
      toast.error('Sélectionnez un magasin');
      return;
    }
    setSubmitting(true);
    try {
      await djangoClient.caisse.open({
        magasin_id: magasinId,
        opening_balance: openingBalance || 0,
        opening_note: openingNote || undefined,
        opened_at: fromDatetimeLocalValue(openedAt),
      });
      toast.success('Caisse ouverte');
      setOpenDialogOpen(false);
      fetchCaisse();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de l’ouverture');
    } finally {
      setSubmitting(false);
    }
  };

  const handleClose = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!session || closingBalance === '') {
      toast.error('Montant compté requis');
      return;
    }
    setSubmitting(true);
    try {
      await djangoClient.caisse.close(session.id, {
        closing_balance: closingBalance,
        closing_note: closingNote || undefined,
        closed_at: fromDatetimeLocalValue(closedAt),
      });
      toast.success('Caisse fermée');
      setCloseDialogOpen(false);
      fetchCaisse();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la fermeture');
    } finally {
      setSubmitting(false);
    }
  };

  const handleAddMovement = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!movementAmount || !movementReason) {
      toast.error('Montant et motif requis');
      return;
    }
    setSubmitting(true);
    try {
      await djangoClient.caisse.addMovement({
        session: session?.id,
        movement_type: movementType,
        amount: movementAmount,
        reason: movementReason,
      });
      toast.success('Mouvement ajouté');
      setMovementDialogOpen(false);
      fetchCaisse();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de l’ajout du mouvement');
    } finally {
      setSubmitting(false);
    }
  };

  if (userLoading) {
    return (
      <div className="p-6 space-y-4">
        {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <Wallet className="h-8 w-8 text-blue-600" />Caisse
          </h1>
          <p className="text-muted-foreground mt-1">Ouverture, mouvements et fermeture de la caisse</p>
        </div>
        <Button variant="outline" size="sm" onClick={fetchCaisse} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />Actualiser
        </Button>
      </div>

      {isAdmin && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm font-medium text-muted-foreground shrink-0">Magasin :</span>
          {stores.length === 0 ? (
            <span className="text-sm text-muted-foreground">Aucun magasin</span>
          ) : (
            stores.map((store) => (
              <button
                key={store.magasin_id}
                type="button"
                onClick={() => setSelectedMagasinId(store.magasin_id)}
                className={`flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm transition-colors hover:bg-muted/50 ${
                  selectedMagasinId === store.magasin_id
                    ? 'bg-primary/10 border-primary/30 font-medium'
                    : 'border-border'
                }`}
              >
                {store.shop_logo ? (
                  <img src={store.shop_logo} alt="" className="h-4 w-4 rounded-full object-cover" />
                ) : (
                  <Store className="h-4 w-4 text-muted-foreground" />
                )}
                {store.shop_name}
              </button>
            ))
          )}
        </div>
      )}

      {!magasinId ? (
        <Card><CardContent className="py-12 text-center text-muted-foreground">
          {isAdmin ? 'Sélectionnez un magasin pour gérer sa caisse.' : 'Aucun magasin associé à votre compte.'}
        </CardContent></Card>
      ) : loading ? (
        <div className="space-y-2">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}</div>
      ) : (
        <>
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0">
              <div>
                <CardTitle className="flex items-center gap-2">
                  {session ? <LockOpen className="h-5 w-5 text-green-600" /> : <Lock className="h-5 w-5 text-muted-foreground" />}
                  {session ? 'Caisse ouverte' : 'Caisse fermée'}
                </CardTitle>
                {session && (
                  <CardDescription>
                    Ouverte le {formatDateTime(session.opened_at)}
                    {session.opened_by_name ? ` par ${session.opened_by_name}` : ''}
                  </CardDescription>
                )}
              </div>
              {session ? (
                <div className="flex gap-2">
                  <Button variant="outline" onClick={openMovementDialog}>
                    <Plus className="h-4 w-4 mr-2" />Mouvement
                  </Button>
                  <Button variant="destructive" onClick={openCloseDialog}>
                    <Lock className="h-4 w-4 mr-2" />Fermer la caisse
                  </Button>
                </div>
              ) : (
                <Button onClick={openOpenDialog}>
                  <LockOpen className="h-4 w-4 mr-2" />Ouvrir la caisse
                </Button>
              )}
            </CardHeader>
            {session && (
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                  <div>
                    <p className="text-xs text-muted-foreground">Fond d'ouverture</p>
                    <p className="text-lg font-semibold">{money(session.opening_balance)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Entrées</p>
                    <p className="text-lg font-semibold text-green-600">+{money(movementTotals.in)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Sorties</p>
                    <p className="text-lg font-semibold text-red-600">-{money(movementTotals.out)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Solde attendu</p>
                    <p className="text-lg font-semibold">{money(expectedBalance)}</p>
                  </div>
                </div>

                <div>
                  <Label className="text-sm">Mouvements de la session</Label>
                  <div className="mt-2 border rounded-lg divide-y max-h-64 overflow-y-auto">
                    {(session.movements || []).length === 0 ? (
                      <p className="p-4 text-sm text-muted-foreground text-center">Aucun mouvement pour l'instant</p>
                    ) : (
                      [...session.movements].reverse().map((m: any) => (
                        <div key={m.id} className="flex items-center justify-between gap-2 px-3 py-2">
                          <div className="flex items-center gap-2 min-w-0">
                            {m.movement_type === 'in' ? (
                              <ArrowUpCircle className="h-4 w-4 text-green-600 shrink-0" />
                            ) : (
                              <ArrowDownCircle className="h-4 w-4 text-red-600 shrink-0" />
                            )}
                            <div className="min-w-0">
                              <p className="text-sm font-medium truncate">{m.reason}</p>
                              <p className="text-xs text-muted-foreground">
                                {formatDateTime(m.created_at)}{m.created_by_name ? ` · ${m.created_by_name}` : ''}
                              </p>
                            </div>
                          </div>
                          <span className={`text-sm font-semibold shrink-0 ${m.movement_type === 'in' ? 'text-green-600' : 'text-red-600'}`}>
                            {m.movement_type === 'in' ? '+' : '-'}{money(m.amount)}
                          </span>
                        </div>
                      ))
                    )}
                  </div>
                </div>
              </CardContent>
            )}
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Historique des sessions</CardTitle>
              <CardDescription>{history.length} session(s) fermée(s)</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Ouverte le</TableHead>
                      <TableHead>Fermée le</TableHead>
                      <TableHead>Fond</TableHead>
                      <TableHead>Compté</TableHead>
                      <TableHead>Écart</TableHead>
                      <TableHead>Ouvert / Fermé par</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {history.length === 0 ? (
                      <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Aucune session fermée</TableCell></TableRow>
                    ) : history.map((s: any) => (
                      <TableRow key={s.id}>
                        <TableCell className="text-sm">{formatDateTime(s.opened_at)}</TableCell>
                        <TableCell className="text-sm">{formatDateTime(s.closed_at)}</TableCell>
                        <TableCell className="text-sm">{money(s.opening_balance)}</TableCell>
                        <TableCell className="text-sm">{money(s.closing_balance)}</TableCell>
                        <TableCell>
                          <Badge variant="outline" className={Number(s.difference) === 0 ? 'text-green-700 border-green-200' : 'text-orange-700 border-orange-200'}>
                            {Number(s.difference) > 0 ? '+' : ''}{money(s.difference)}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs text-muted-foreground">
                          {s.opened_by_name || '-'} / {s.closed_by_name || '-'}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        </>
      )}

      {/* Open dialog */}
      <Dialog open={openDialogOpen} onOpenChange={setOpenDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Ouvrir la caisse</DialogTitle>
            <DialogDescription>Renseignez le fond de caisse de départ.</DialogDescription>
          </DialogHeader>
          <form onSubmit={handleOpen} className="space-y-4">
            <div className="space-y-2">
              <Label>Montant d'ouverture (Ar) *</Label>
              <Input type="number" min={0} step="0.01" value={openingBalance} onChange={(e) => setOpeningBalance(e.target.value)} required />
              <p className="text-xs text-muted-foreground">
                Pré-rempli avec la valeur de stock actuelle du magasin — modifiable.
              </p>
            </div>
            <div className="space-y-2">
              <Label>Heure d'ouverture</Label>
              <Input type="datetime-local" value={openedAt} onChange={(e) => setOpenedAt(e.target.value)} max={toDatetimeLocalValue(new Date())} />
              <p className="text-xs text-muted-foreground">Modifiable si la caisse a été ouverte plus tôt dans la journée.</p>
            </div>
            <div className="space-y-2">
              <Label>Note (optionnel)</Label>
              <Textarea value={openingNote} onChange={(e) => setOpeningNote(e.target.value)} placeholder="Ex: Fond de caisse du matin" />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpenDialogOpen(false)} disabled={submitting}>Annuler</Button>
              <Button type="submit" disabled={submitting}>
                {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <LockOpen className="h-4 w-4 mr-2" />}
                Ouvrir
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Close dialog */}
      <Dialog open={closeDialogOpen} onOpenChange={setCloseDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Fermer la caisse</DialogTitle>
            <DialogDescription>
              Solde attendu : <span className="font-medium text-foreground">{money(expectedBalance)}</span> — comptez la caisse et indiquez le montant réel.
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleClose} className="space-y-4">
            <div className="space-y-2">
              <Label>Montant compté (Ar) *</Label>
              <Input type="number" min={0} step="0.01" value={closingBalance} onChange={(e) => setClosingBalance(e.target.value)} required />
              <p className="text-xs text-muted-foreground">
                Pré-rempli avec la valeur de stock actuelle du magasin — modifiable.
              </p>
              {closingBalance !== '' && (
                <p className={`text-xs ${Number(closingBalance) - expectedBalance === 0 ? 'text-green-600' : 'text-orange-600'}`}>
                  Écart : {Number(closingBalance) - expectedBalance > 0 ? '+' : ''}{money(Number(closingBalance) - expectedBalance)}
                </p>
              )}
            </div>
            <div className="space-y-2">
              <Label>Heure de fermeture</Label>
              <Input
                type="datetime-local"
                value={closedAt}
                onChange={(e) => setClosedAt(e.target.value)}
                min={session ? toDatetimeLocalValue(new Date(session.opened_at)) : undefined}
                max={toDatetimeLocalValue(new Date())}
              />
              <p className="text-xs text-muted-foreground">Modifiable si la caisse a été fermée plus tôt.</p>
            </div>
            <div className="space-y-2">
              <Label>Note (optionnel)</Label>
              <Textarea value={closingNote} onChange={(e) => setClosingNote(e.target.value)} placeholder="Ex: Compte OK" />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setCloseDialogOpen(false)} disabled={submitting}>Annuler</Button>
              <Button type="submit" variant="destructive" disabled={submitting}>
                {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Lock className="h-4 w-4 mr-2" />}
                Fermer la caisse
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Add movement dialog */}
      <Dialog open={movementDialogOpen} onOpenChange={setMovementDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Ajouter un mouvement</DialogTitle>
            <DialogDescription>Apport ou retrait d'espèces dans la caisse.</DialogDescription>
          </DialogHeader>
          <form onSubmit={handleAddMovement} className="space-y-4">
            <div className="space-y-2">
              <Label>Type *</Label>
              <RadioGroup value={movementType} onValueChange={(v) => setMovementType(v as 'in' | 'out')} className="flex gap-4">
                <label className="flex items-center gap-2 text-sm cursor-pointer">
                  <RadioGroupItem value="in" /> <ArrowUpCircle className="h-4 w-4 text-green-600" />Entrée
                </label>
                <label className="flex items-center gap-2 text-sm cursor-pointer">
                  <RadioGroupItem value="out" /> <ArrowDownCircle className="h-4 w-4 text-red-600" />Sortie
                </label>
              </RadioGroup>
            </div>
            <div className="space-y-2">
              <Label>Montant (Ar) *</Label>
              <Input type="number" min={0} step="0.01" value={movementAmount} onChange={(e) => setMovementAmount(e.target.value)} required />
            </div>
            <div className="space-y-2">
              <Label>Motif *</Label>
              <Input value={movementReason} onChange={(e) => setMovementReason(e.target.value)} placeholder="Ex: Achat fournitures" required />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setMovementDialogOpen(false)} disabled={submitting}>Annuler</Button>
              <Button type="submit" disabled={submitting}>
                {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Plus className="h-4 w-4 mr-2" />}
                Ajouter
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
