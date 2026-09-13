'use client';

import { useCallback, useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { DateTimeInput } from '@/components/ui/datetime-input';
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
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Collapsible, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Wallet, Store, Plus, Lock, LockOpen, Loader2, RefreshCw, ArrowDownCircle, ArrowUpCircle, Pencil, Trash2,
  CalendarRange, ChevronDown, Filter, History, ListOrdered, Megaphone, PiggyBank, Receipt, TrendingUp,
} from 'lucide-react';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { periodeDepuisPreset, type PeriodPreset } from '@/lib/reports';
import { IndicateursCaisse, type Indicateurs } from '@/components/caisse/indicateurs';
import { SectionLivraison, type StatsLivraison } from '@/components/caisse/section-livraison';
import { SectionGain, TableVentes, type LigneVenteResultat, type RepartitionPct, type StatsGain } from '@/components/caisse/section-gain';
import { SectionEncaissements, type Encaissements } from '@/components/caisse/section-encaissements';
import { SectionJournal, type LigneJournal } from '@/components/caisse/section-journal';
import { SectionEpargne, type MouvementEpargne } from '@/components/caisse/section-epargne';
import { SectionBoost, type Boost } from '@/components/caisse/section-boost';
import { NEG, POS } from '@/components/caisse/ui';

interface Tresorerie {
  indicateurs: Indicateurs;
  periode: { from: string; to: string };
  gain: StatsGain;
  repartition_pct: RepartitionPct;
  livraison: { periode: StatsLivraison; jour: StatsLivraison; semaine: StatsLivraison; mois: StatsLivraison };
  boosts: Boost[];
  encaissements: Encaissements;
  epargne: { solde: number; verse_periode: number; retire_periode: number };
}

const PERIODES: { key: PeriodPreset; label: string }[] = [
  { key: 'today', label: "Aujourd'hui" },
  { key: 'week', label: 'Cette semaine' },
  { key: 'month', label: 'Ce mois' },
  { key: 'custom', label: 'Personnalisée' },
];

// Nature d'un mouvement saisi à la main (journal de trésorerie).
const ORIGINES_ENTREE = [['AUTRE_ENTREE', 'Autre entrée'], ['PAIEMENT_CLIENT', 'Paiement client (hors commande)']] as const;
const ORIGINES_SORTIE = [['DEPENSE', 'Dépense'], ['ACHAT_STOCK', 'Achat stock'], ['BOOST', 'Boost / publicité'], ['RETRAIT', 'Retrait'], ['AUTRE_SORTIE', 'Autre sortie']] as const;

const money = (v: any) =>
  `${Number(v ?? 0).toLocaleString('fr-FR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })} Ar`;

const toDatetimeLocalValue = (date: Date) => {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const fromDatetimeLocalValue = (value: string) => (value ? new Date(value).toISOString() : undefined);

const formatDateTime = (value?: string | null) =>
  value ? format(new Date(value), 'dd MMM yyyy HH:mm', { locale: fr }) : '-';

const formatDate = (value?: string | null) =>
  value ? format(new Date(`${value}T12:00:00`), 'dd MMM yyyy', { locale: fr }) : '-';

/** Écart constaté à la fermeture d'une session (0 = caisse juste). */
function EcartBadge({ difference }: { difference: number | string | null }) {
  const d = Number(difference ?? 0);
  return (
    <Badge
      variant="outline"
      className={`tabular-nums whitespace-nowrap ${
        d === 0
          ? 'text-emerald-700 border-emerald-300 dark:text-emerald-400 dark:border-emerald-800'
          : 'text-amber-700 border-amber-300 dark:text-amber-400 dark:border-amber-800'
      }`}
    >
      {d > 0 ? '+' : ''}{money(d)}
    </Badge>
  );
}

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
  const [movementCategory, setMovementCategory] = useState<string>('');
  // Mouvement en cours de modification (null = ajout) et cible de suppression (§ demande).
  const [editingMovement, setEditingMovement] = useState<any | null>(null);
  const [deleteMovementTarget, setDeleteMovementTarget] = useState<any | null>(null);
  const [movementOrigine, setMovementOrigine] = useState<string>('AUTRE_ENTREE');
  const [expenseCategories, setExpenseCategories] = useState<any[]>([]);

  // Trésorerie (finance/) : indicateurs, gain réel, livraison, journal,
  // épargne, boosts — tout est calculé côté serveur, filtré par période.
  const [preset, setPreset] = useState<PeriodPreset>('month');
  const [custom, setCustom] = useState({ from: '', to: '' });
  // Période personnalisée = plage libre (du → au) ; les préréglages viennent de lib/reports.
  const period = (() => {
    if (preset === 'custom' && custom.from && custom.to) {
      const [from, to] = custom.from <= custom.to ? [custom.from, custom.to] : [custom.to, custom.from];
      return { from, to };
    }
    const p = periodeDepuisPreset(preset === 'custom' ? 'month' : preset);
    return { from: p.from, to: p.to };
  })();
  const [tresorerie, setTresorerie] = useState<Tresorerie | null>(null);
  const [journal, setJournal] = useState<LigneJournal[] | null>(null);
  const [ventes, setVentes] = useState<LigneVenteResultat[] | null>(null);
  const [epargneHistorique, setEpargneHistorique] = useState<MouvementEpargne[] | null>(null);
  const [tresoLoading, setTresoLoading] = useState(false);
  const [tresoError, setTresoError] = useState<string | null>(null);
  // Présentation uniquement : onglet affiché et filtres repliés sur mobile.
  const [onglet, setOnglet] = useState('tresorerie');
  const [filtresOuverts, setFiltresOuverts] = useState(false);

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

  const fetchTresorerie = useCallback(async () => {
    if (!magasinId) {
      setTresorerie(null);
      setJournal(null);
      setVentes(null);
      setEpargneHistorique(null);
      return;
    }
    setTresoLoading(true);
    setTresoError(null);
    try {
      const params = { magasinId, dateFrom: period.from, dateTo: period.to };
      const [dash, jr, vt, ep] = await Promise.all([
        djangoClient.finance.dashboard(params),
        djangoClient.finance.journal(params),
        djangoClient.finance.ventes(params),
        djangoClient.finance.epargne(magasinId),
      ]);
      setTresorerie(dash);
      setJournal(jr.lignes);
      setVentes(vt.ventes);
      setEpargneHistorique(ep.historique);
    } catch (err: any) {
      setTresoError(err.message || 'Erreur de chargement de la trésorerie');
    } finally {
      setTresoLoading(false);
    }
  }, [magasinId, period.from, period.to]);

  useEffect(() => {
    djangoClient.caisse.categories.list().then(setExpenseCategories).catch(() => {});
  }, []);

  useEffect(() => {
    if (!userLoading) fetchStores();
  }, [userLoading, fetchStores]);

  useEffect(() => {
    if (!userLoading) fetchCaisse();
  }, [userLoading, fetchCaisse]);

  useEffect(() => {
    if (!userLoading) fetchTresorerie();
  }, [userLoading, fetchTresorerie]);

  useRealtimeRefresh(['caisse_session', 'caisse_movement', 'tresorerie', 'order'], () => { fetchCaisse(); fetchTresorerie(); });

  const movementTotals = (session?.movements || []).reduce(
    (acc: { in: number; out: number }, m: any) => {
      if (m.movement_type === 'in') acc.in += Number(m.amount);
      else acc.out += Number(m.amount);
      return acc;
    },
    { in: 0, out: 0 },
  );
  const expectedBalance = session ? Number(session.opening_balance) + movementTotals.in - movementTotals.out : 0;

  // Le fond d'ouverture est pré-rempli avec le montant compté à la dernière
  // fermeture (continuité des espèces), la fermeture avec le solde attendu —
  // la valeur du stock n'est pas de l'argent en caisse (voir indicateurs).
  const openOpenDialog = () => {
    setOpeningNote('');
    setOpenedAt(toDatetimeLocalValue(new Date()));
    const derniere = history[0];
    setOpeningBalance(derniere?.closing_balance != null ? String(Number(derniere.closing_balance)) : '');
    setOpenDialogOpen(true);
  };

  const openCloseDialog = () => {
    setClosingNote('');
    setClosedAt(toDatetimeLocalValue(new Date()));
    setClosingBalance(String(expectedBalance));
    setCloseDialogOpen(true);
  };

  const openMovementDialog = () => {
    setEditingMovement(null);
    setMovementType('in');
    setMovementOrigine('AUTRE_ENTREE');
    setMovementAmount('');
    setMovementReason('');
    setMovementCategory('');
    setMovementDialogOpen(true);
  };

  const openEditMovementDialog = (m: any) => {
    setEditingMovement(m);
    setMovementType(m.movement_type === 'out' ? 'out' : 'in');
    setMovementOrigine(m.origine && m.origine !== 'MANUEL' ? m.origine : m.movement_type === 'out' ? 'DEPENSE' : 'AUTRE_ENTREE');
    setMovementAmount(String(Number(m.amount) || ''));
    setMovementReason(m.reason || '');
    setMovementCategory(m.category ? String(m.category) : '');
    setMovementDialogOpen(true);
  };

  const handleDeleteMovement = async () => {
    if (!deleteMovementTarget) return;
    setSubmitting(true);
    try {
      await djangoClient.caisse.deleteMovement(deleteMovementTarget.id);
      toast.success('Mouvement supprimé');
      setDeleteMovementTarget(null);
      fetchCaisse();
      fetchTresorerie();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la suppression');
    } finally {
      setSubmitting(false);
    }
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
      if (editingMovement) {
        await djangoClient.caisse.updateMovement(editingMovement.id, {
          movement_type: movementType,
          amount: movementAmount,
          reason: movementReason,
          category: movementType === 'out' && movementCategory ? Number(movementCategory) : null,
          origine: movementOrigine,
        });
        toast.success('Mouvement modifié');
      } else {
        await djangoClient.caisse.addMovement({
          session: session?.id,
          movement_type: movementType,
          amount: movementAmount,
          reason: movementReason,
          category: movementType === 'out' && movementCategory ? Number(movementCategory) : undefined,
          origine: movementOrigine,
        });
        toast.success('Mouvement ajouté');
      }
      setMovementDialogOpen(false);
      fetchCaisse();
      fetchTresorerie();
    } catch (err: any) {
      toast.error(err.message || (editingMovement ? 'Erreur lors de la modification du mouvement' : 'Erreur lors de l’ajout du mouvement'));
    } finally {
      setSubmitting(false);
    }
  };

  if (userLoading) {
    return (
      <div className="p-4 sm:p-6 space-y-4">
        <Skeleton className="h-8 w-40" />
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 w-full" />)}</div>
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  const enChargement = loading || tresoLoading;
  const periodeLabel = PERIODES.find((p) => p.key === preset)?.label ?? '';

  return (
    <div className="mx-auto w-full max-w-[1600px] p-3 sm:p-4 lg:p-6 space-y-4 lg:space-y-6 overflow-x-hidden">
      {/* En-tête compact */}
      <header className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight flex items-center gap-2">
            <Wallet className="h-6 w-6 sm:h-7 sm:w-7 text-primary shrink-0" aria-hidden />Caisse
          </h1>
          <p className="text-sm text-muted-foreground mt-0.5 hidden sm:block">Caisse, trésorerie, gain réel, livraison, épargne et boost</p>
        </div>
        <Button
          variant="outline"
          size="sm"
          className="h-9 shrink-0"
          onClick={() => { fetchCaisse(); fetchTresorerie(); }}
          disabled={enChargement}
          aria-label="Actualiser"
        >
          <RefreshCw className={`h-4 w-4 sm:mr-2 ${enChargement ? 'animate-spin' : ''}`} aria-hidden />
          <span className="hidden sm:inline">Actualiser</span>
        </Button>
      </header>

      {isAdmin && (
        <div className="flex items-center gap-2 -mx-3 px-3 sm:mx-0 sm:px-0 overflow-x-auto" role="group" aria-label="Choix du magasin">
          <span className="text-sm font-medium text-muted-foreground shrink-0">Magasin :</span>
          {stores.length === 0 ? (
            <span className="text-sm text-muted-foreground">Aucun magasin</span>
          ) : (
            stores.map((store) => (
              <button
                key={store.magasin_id}
                type="button"
                aria-pressed={selectedMagasinId === store.magasin_id}
                onClick={() => setSelectedMagasinId(store.magasin_id)}
                className={`flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm whitespace-nowrap transition-colors hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${
                  selectedMagasinId === store.magasin_id
                    ? 'bg-primary/10 border-primary/30 font-medium'
                    : 'border-border'
                }`}
              >
                {store.shop_logo ? (
                  <img src={store.shop_logo} alt="" className="h-4 w-4 rounded-full object-cover" />
                ) : (
                  <Store className="h-4 w-4 text-muted-foreground" aria-hidden />
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
        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 w-full" />)}</div>
          <Skeleton className="h-40 w-full" />
          <Skeleton className="h-64 w-full" />
        </div>
      ) : (
        <>
          {/* 1. Les 4 indicateurs */}
          <IndicateursCaisse data={tresorerie?.indicateurs ?? null} loading={tresoLoading && !tresorerie} />
          {tresoError && (
            <div className="flex flex-col sm:flex-row sm:items-center gap-2 rounded-lg border border-destructive/40 bg-destructive/5 px-3 py-2 text-sm text-destructive" role="alert">
              <span className="flex-1">{tresoError}</span>
              <Button size="sm" variant="outline" className="h-8 self-start" onClick={fetchTresorerie}>Réessayer</Button>
            </div>
          )}

          {/* 2. Session de caisse */}
          <Card className={`gap-4 py-4 border-l-4 ${session ? 'border-l-emerald-500' : 'border-l-border'}`}>
            <CardHeader className="px-4 sm:px-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between space-y-0">
              <div className="min-w-0">
                <CardTitle className="flex items-center gap-2 text-base sm:text-lg">
                  {session ? <LockOpen className={`h-5 w-5 ${POS}`} aria-hidden /> : <Lock className="h-5 w-5 text-muted-foreground" aria-hidden />}
                  {session ? 'Caisse ouverte' : 'Caisse fermée'}
                </CardTitle>
                {session ? (
                  <CardDescription className="text-xs">
                    Ouverte le {formatDateTime(session.opened_at)}
                    {session.opened_by_name ? ` par ${session.opened_by_name}` : ''}
                  </CardDescription>
                ) : (
                  <CardDescription className="text-xs">Ouvrez la caisse pour saisir des mouvements et enregistrer les remises.</CardDescription>
                )}
              </div>
              {session ? (
                <div className="grid grid-cols-2 sm:flex gap-2">
                  <Button onClick={openMovementDialog} className="h-10 sm:h-9">
                    <Plus className="h-4 w-4 mr-2" aria-hidden />Mouvement
                  </Button>
                  <Button variant="outline" onClick={openCloseDialog} className="h-10 sm:h-9 text-destructive hover:text-destructive">
                    <Lock className="h-4 w-4 mr-2" aria-hidden />Fermer
                  </Button>
                </div>
              ) : (
                <Button onClick={openOpenDialog} className="h-10 sm:h-9 w-full sm:w-auto">
                  <LockOpen className="h-4 w-4 mr-2" aria-hidden />Ouvrir la caisse
                </Button>
              )}
            </CardHeader>
            {session && (
              <CardContent className="px-4 sm:px-6 space-y-4">
                <dl className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                  {(
                    [
                      ["Fond d'ouverture", money(session.opening_balance), ''],
                      ['Entrées', `+${money(movementTotals.in)}`, POS],
                      ['Sorties', `−${money(movementTotals.out)}`, NEG],
                      ['Solde attendu', money(expectedBalance), 'font-bold'],
                    ] as const
                  ).map(([label, val, cls]) => (
                    <div key={label} className="rounded-lg bg-muted/40 px-3 py-2 min-w-0">
                      <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</dt>
                      <dd className={`text-base sm:text-lg font-semibold tabular-nums leading-tight break-words ${cls}`}>{val}</dd>
                    </div>
                  ))}
                </dl>

                <div>
                  <p className="text-sm font-medium mb-2">Mouvements de la session <span className="text-muted-foreground font-normal">({(session.movements || []).length})</span></p>
                  <ul className="border rounded-lg divide-y max-h-72 overflow-y-auto overscroll-contain">
                    {(session.movements || []).length === 0 ? (
                      <li className="p-6 text-sm text-muted-foreground text-center">Aucun mouvement pour l&apos;instant — cliquez sur « Mouvement » pour en saisir un.</li>
                    ) : (
                      [...session.movements].reverse().map((m: any) => (
                        <li key={m.id} className="flex items-center gap-2 px-3 py-2">
                          {m.movement_type === 'in' ? (
                            <ArrowUpCircle className={`h-4 w-4 shrink-0 ${POS}`} aria-hidden />
                          ) : (
                            <ArrowDownCircle className={`h-4 w-4 shrink-0 ${NEG}`} aria-hidden />
                          )}
                          <div className="min-w-0 flex-1">
                            <p className="text-sm font-medium truncate">{m.reason}</p>
                            <p className="text-xs text-muted-foreground truncate">
                              {formatDateTime(m.created_at)}{m.created_by_name ? ` · ${m.created_by_name}` : ''}{m.category_name ? ` · ${m.category_name}` : ''}
                            </p>
                          </div>
                          <span className={`text-sm font-semibold tabular-nums whitespace-nowrap ${m.movement_type === 'in' ? POS : NEG}`}>
                            {m.movement_type === 'in' ? '+' : '−'}{money(m.amount)}
                          </span>
                          {/* Correction / suppression tant que la session est ouverte (§ demande) —
                              sauf les mouvements automatiques (vente remise, frais de tournée…), pièces comptables. */}
                          {session.status === 'open' && !m.reference && (
                            <div className="flex shrink-0">
                              <Button size="icon" variant="ghost" className="h-8 w-8" aria-label={`Modifier le mouvement ${m.reason}`} onClick={() => openEditMovementDialog(m)}>
                                <Pencil className="h-3.5 w-3.5" aria-hidden />
                              </Button>
                              <Button size="icon" variant="ghost" className="h-8 w-8 text-destructive hover:text-destructive" aria-label={`Supprimer le mouvement ${m.reason}`} onClick={() => setDeleteMovementTarget(m)}>
                                <Trash2 className="h-3.5 w-3.5" aria-hidden />
                              </Button>
                            </div>
                          )}
                        </li>
                      ))
                    )}
                  </ul>
                </div>
              </CardContent>
            )}
          </Card>

          {/* 3. Filtre de période commun aux sections de trésorerie */}
          <Collapsible open={filtresOuverts} onOpenChange={setFiltresOuverts} className="rounded-lg border bg-card">
            <div className="flex items-center justify-between gap-2 px-3 py-2">
              <div className="flex items-center gap-2 min-w-0">
                <CalendarRange className="h-4 w-4 text-muted-foreground shrink-0" aria-hidden />
                <span className="text-sm font-medium">Période</span>
                <Badge variant="secondary" className="truncate">{preset === 'custom' ? `${formatDate(period.from)} → ${formatDate(period.to)}` : periodeLabel}</Badge>
              </div>
              <CollapsibleTrigger asChild>
                <Button variant="ghost" size="sm" className="h-8 sm:hidden" aria-label={filtresOuverts ? 'Masquer les filtres' : 'Afficher les filtres'}>
                  <Filter className="h-4 w-4 mr-1" aria-hidden />Filtres
                  <ChevronDown className={`h-4 w-4 ml-1 transition-transform ${filtresOuverts ? 'rotate-180' : ''}`} aria-hidden />
                </Button>
              </CollapsibleTrigger>
            </div>
            <div className={`${filtresOuverts ? '' : 'hidden'} sm:block border-t px-3 py-2`}>
              <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                <div className="flex flex-wrap gap-1.5" role="group" aria-label="Période rapide">
                  {PERIODES.map((p) => (
                    <Button key={p.key} size="sm" variant={preset === p.key ? 'default' : 'outline'} className="h-9 sm:h-8 text-xs" aria-pressed={preset === p.key} onClick={() => setPreset(p.key)}>
                      {p.label}
                    </Button>
                  ))}
                </div>
                <div className="grid grid-cols-2 gap-2 sm:flex sm:items-center sm:ml-auto">
                  <div className="space-y-1">
                    <Label htmlFor="caisse-du" className="text-[11px] text-muted-foreground sm:sr-only">Du</Label>
                    <Input id="caisse-du" type="date" value={preset === 'custom' ? custom.from : period.from} onChange={(e) => { setPreset('custom'); setCustom({ from: e.target.value, to: preset === 'custom' ? custom.to : period.to }); }} className="h-9 sm:h-8 w-full sm:w-auto" />
                  </div>
                  <span className="hidden sm:inline text-sm text-muted-foreground" aria-hidden>→</span>
                  <div className="space-y-1">
                    <Label htmlFor="caisse-au" className="text-[11px] text-muted-foreground sm:sr-only">Au</Label>
                    <Input id="caisse-au" type="date" value={preset === 'custom' ? custom.to : period.to} onChange={(e) => { setPreset('custom'); setCustom({ from: preset === 'custom' ? custom.from : period.from, to: e.target.value }); }} className="h-9 sm:h-8 w-full sm:w-auto" />
                  </div>
                </div>
              </div>
            </div>
          </Collapsible>

          {/* 4. Sections : un onglet à la fois, liste défilante sur mobile */}
          <Tabs value={onglet} onValueChange={setOnglet} className="gap-4">
            <div className="-mx-3 px-3 sm:mx-0 sm:px-0 overflow-x-auto">
              <TabsList className="h-auto w-max min-w-full sm:min-w-0 sm:w-fit gap-1 p-1">
                {(
                  [
                    ['tresorerie', 'Trésorerie', TrendingUp],
                    ['journal', 'Journal', ListOrdered],
                    ['ventes', 'Ventes', Receipt],
                    ['epargne', 'Épargne', PiggyBank],
                    ['boost', 'Boost', Megaphone],
                    ['sessions', 'Sessions', History],
                  ] as const
                ).map(([key, label, Icon]) => (
                  <TabsTrigger key={key} value={key} className="h-9 px-3 flex-none">
                    <Icon className="h-4 w-4" aria-hidden />
                    {label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </div>

            <TabsContent value="tresorerie" className="space-y-4">
              <SectionGain
                gain={tresorerie?.gain ?? null}
                pct={tresorerie?.repartition_pct ?? null}
                periode={tresorerie?.periode}
                loading={tresoLoading && !tresorerie}
                magasinId={magasinId}
                onSettingsChanged={fetchTresorerie}
              />
              <SectionEncaissements
                data={tresorerie?.encaissements ?? null}
                loading={tresoLoading && !tresorerie}
                magasinId={magasinId}
                sessionOuverte={!!session}
                onChanged={() => { fetchCaisse(); fetchTresorerie(); }}
              />
              <SectionLivraison data={tresorerie?.livraison ?? null} loading={tresoLoading && !tresorerie} />
            </TabsContent>

            <TabsContent value="journal">
              <SectionJournal lignes={journal} loading={tresoLoading && !journal} error={tresoError} />
            </TabsContent>

            <TabsContent value="ventes">
              <TableVentes ventes={ventes} loading={tresoLoading && !ventes} error={tresoError} />
            </TabsContent>

            <TabsContent value="epargne">
              <SectionEpargne
                solde={tresorerie?.epargne.solde ?? null}
                historique={epargneHistorique}
                loading={tresoLoading && !tresorerie}
                error={tresoError}
                magasinId={magasinId}
                onChanged={fetchTresorerie}
                versePeriode={tresorerie?.epargne.verse_periode}
                retirePeriode={tresorerie?.epargne.retire_periode}
              />
            </TabsContent>

            <TabsContent value="boost">
              <SectionBoost boosts={tresorerie?.boosts ?? null} loading={tresoLoading && !tresorerie} error={tresoError} magasinId={magasinId} sessionOuverte={!!session} onChanged={fetchTresorerie} />
            </TabsContent>

            <TabsContent value="sessions">
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-base">Historique des sessions</CardTitle>
                  <CardDescription className="text-xs">{history.length} session(s) fermée(s)</CardDescription>
                </CardHeader>
                <CardContent className="p-0">
                  {history.length === 0 ? (
                    <p className="text-center py-8 text-sm text-muted-foreground">Aucune session fermée pour l&apos;instant.</p>
                  ) : (
                    <>
                      {/* Mobile : une carte par session */}
                      <ul className="md:hidden divide-y">
                        {history.map((s: any) => (
                          <li key={s.id} className="px-4 py-3 space-y-1">
                            <div className="flex items-start justify-between gap-2">
                              <div className="min-w-0">
                                <p className="text-sm font-medium">{formatDateTime(s.opened_at)}</p>
                                <p className="text-xs text-muted-foreground">→ {formatDateTime(s.closed_at)}</p>
                              </div>
                              <EcartBadge difference={s.difference} />
                            </div>
                            <dl className="grid grid-cols-2 gap-x-3 text-xs">
                              <dt className="text-muted-foreground">Fond</dt><dd className="text-right tabular-nums">{money(s.opening_balance)}</dd>
                              <dt className="text-muted-foreground">Compté</dt><dd className="text-right tabular-nums">{money(s.closing_balance)}</dd>
                            </dl>
                            <p className="text-xs text-muted-foreground">{s.opened_by_name || '-'} / {s.closed_by_name || '-'}</p>
                          </li>
                        ))}
                      </ul>
                      <div className="hidden md:block overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Ouverte le</TableHead>
                              <TableHead>Fermée le</TableHead>
                              <TableHead className="text-right">Fond</TableHead>
                              <TableHead className="text-right">Compté</TableHead>
                              <TableHead className="text-right">Écart</TableHead>
                              <TableHead>Ouvert / Fermé par</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {history.map((s: any) => (
                              <TableRow key={s.id}>
                                <TableCell className="text-sm whitespace-nowrap">{formatDateTime(s.opened_at)}</TableCell>
                                <TableCell className="text-sm whitespace-nowrap">{formatDateTime(s.closed_at)}</TableCell>
                                <TableCell className="text-sm text-right tabular-nums">{money(s.opening_balance)}</TableCell>
                                <TableCell className="text-sm text-right tabular-nums">{money(s.closing_balance)}</TableCell>
                                <TableCell className="text-right"><EcartBadge difference={s.difference} /></TableCell>
                                <TableCell className="text-xs text-muted-foreground">
                                  {s.opened_by_name || '-'} / {s.closed_by_name || '-'}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </div>
                    </>
                  )}
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
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
              <Label htmlFor="ouverture-montant">Montant d'ouverture (Ar) *</Label>
              <Input id="ouverture-montant" inputMode="decimal" type="number" min={0} step="0.01" value={openingBalance} onChange={(e) => setOpeningBalance(e.target.value)} required />
              <p className="text-xs text-muted-foreground">
                Pré-rempli avec le montant compté à la dernière fermeture — modifiable.
              </p>
            </div>
            <div className="space-y-2">
              <Label>Heure d'ouverture</Label>
              <DateTimeInput value={openedAt} onChange={setOpenedAt} max={toDatetimeLocalValue(new Date())} />
              <p className="text-xs text-muted-foreground">Modifiable si la caisse a été ouverte plus tôt dans la journée.</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="ouverture-note">Note (optionnel)</Label>
              <Textarea id="ouverture-note" value={openingNote} onChange={(e) => setOpeningNote(e.target.value)} placeholder="Ex: Fond de caisse du matin" />
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
              <Label htmlFor="fermeture-montant">Montant compté (Ar) *</Label>
              <Input id="fermeture-montant" inputMode="decimal" type="number" min={0} step="0.01" value={closingBalance} onChange={(e) => setClosingBalance(e.target.value)} required />
              <p className="text-xs text-muted-foreground">
                Pré-rempli avec le solde attendu — remplacez-le par le montant réellement compté.
              </p>
              {closingBalance !== '' && (
                <p className={`text-xs ${Number(closingBalance) - expectedBalance === 0 ? POS : 'text-amber-600 dark:text-amber-400'}`} aria-live="polite">
                  Écart : {Number(closingBalance) - expectedBalance > 0 ? '+' : ''}{money(Number(closingBalance) - expectedBalance)}
                </p>
              )}
            </div>
            <div className="space-y-2">
              <Label>Heure de fermeture</Label>
              <DateTimeInput
                value={closedAt}
                onChange={setClosedAt}
                min={session ? toDatetimeLocalValue(new Date(session.opened_at)) : undefined}
                max={toDatetimeLocalValue(new Date())}
              />
              <p className="text-xs text-muted-foreground">Modifiable si la caisse a été fermée plus tôt.</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="fermeture-note">Note (optionnel)</Label>
              <Textarea id="fermeture-note" value={closingNote} onChange={(e) => setClosingNote(e.target.value)} placeholder="Ex: Compte OK" />
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
            <DialogTitle>{editingMovement ? 'Modifier le mouvement' : 'Ajouter un mouvement'}</DialogTitle>
            <DialogDescription>
              {editingMovement
                ? `Correction du mouvement du ${formatDateTime(editingMovement.created_at)} — le solde attendu est recalculé.`
                : "Apport ou retrait d'espèces dans la caisse."}
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleAddMovement} className="space-y-4">
            <div className="space-y-2">
              <Label>Type *</Label>
              <RadioGroup value={movementType} onValueChange={(v) => { setMovementType(v as 'in' | 'out'); setMovementOrigine(v === 'in' ? 'AUTRE_ENTREE' : 'DEPENSE'); }} className="flex gap-4">
                <label className="flex items-center gap-2 text-sm cursor-pointer">
                  <RadioGroupItem value="in" /> <ArrowUpCircle className={`h-4 w-4 ${POS}`} aria-hidden />Entrée
                </label>
                <label className="flex items-center gap-2 text-sm cursor-pointer">
                  <RadioGroupItem value="out" /> <ArrowDownCircle className={`h-4 w-4 ${NEG}`} aria-hidden />Sortie
                </label>
              </RadioGroup>
            </div>
            <div className="space-y-2">
              <Label>Nature</Label>
              <Select value={movementOrigine} onValueChange={setMovementOrigine}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(movementType === 'in' ? ORIGINES_ENTREE : ORIGINES_SORTIE).map(([c, l]) => (
                    <SelectItem key={c} value={c}>{l}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">Les ventes livrées entrent en caisse automatiquement (remise) : ne les saisissez pas ici.</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="mvt-montant">Montant (Ar) *</Label>
              <Input id="mvt-montant" inputMode="decimal" type="number" min={0} step="0.01" value={movementAmount} onChange={(e) => setMovementAmount(e.target.value)} required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="mvt-motif">Motif *</Label>
              <Input id="mvt-motif" value={movementReason} onChange={(e) => setMovementReason(e.target.value)} placeholder="Ex: Achat fournitures" required />
            </div>
            {movementType === 'out' && (
              <div className="space-y-2">
                <Label>Catégorie (optionnel)</Label>
                <Select value={movementCategory} onValueChange={setMovementCategory}>
                  <SelectTrigger><SelectValue placeholder="Aucune catégorie" /></SelectTrigger>
                  <SelectContent>
                    {expenseCategories.map((c) => (
                      <SelectItem key={c.id} value={String(c.id)}>{c.nom}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">
                  Gérez les catégories dans Paramètres &gt; Dépenses.
                </p>
              </div>
            )}
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setMovementDialogOpen(false)} disabled={submitting}>Annuler</Button>
              <Button type="submit" disabled={submitting}>
                {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : editingMovement ? <Pencil className="h-4 w-4 mr-2" /> : <Plus className="h-4 w-4 mr-2" />}
                {editingMovement ? 'Enregistrer' : 'Ajouter'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete movement dialog */}
      <Dialog open={!!deleteMovementTarget} onOpenChange={(o) => !o && setDeleteMovementTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Supprimer ce mouvement ?</DialogTitle>
            <DialogDescription>
              {deleteMovementTarget && (
                <>
                  {deleteMovementTarget.movement_type === 'in' ? 'Entrée' : 'Sortie'} de {money(deleteMovementTarget.amount)} — « {deleteMovementTarget.reason} »
                  {deleteMovementTarget.created_at ? ` (${formatDateTime(deleteMovementTarget.created_at)})` : ''}.
                  Le solde attendu de la session est recalculé. Cette action est irréversible.
                </>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteMovementTarget(null)} disabled={submitting}>Annuler</Button>
            <Button variant="destructive" onClick={handleDeleteMovement} disabled={submitting}>
              {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Trash2 className="h-4 w-4 mr-2" />}
              Supprimer
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
