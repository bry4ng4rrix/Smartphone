'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  RefreshCw,
  TrendingUp,
  TrendingDown,
  Truck,
  Package,
  Undo2,
  Wallet,
  ShieldAlert,
  ArrowUpRight,
  ArrowDownRight,
  ArrowLeftRight,
} from 'lucide-react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  ComposedChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { APP_TIME_ZONE, appToday } from '@/lib/timezone';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';
const nb = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Number(n || 0));

/** Jour court pour les axes : « 09/09 ». */
const jourCourt = (iso: string) =>
  new Date(`${iso}T12:00:00+03:00`).toLocaleDateString('fr-FR', {
    timeZone: APP_TIME_ZONE,
    day: '2-digit',
    month: '2-digit',
  });

const PERIODES = [
  { jours: 7, label: '7 jours' },
  { jours: 30, label: '30 jours' },
  { jours: 90, label: '90 jours' },
] as const;

/** Recule de `jours` jours depuis aujourd'hui, en date d'Antananarivo. */
function depuis(jours: number) {
  const d = new Date(`${appToday()}T12:00:00+03:00`);
  d.setDate(d.getDate() - (jours - 1));
  return d.toISOString().slice(0, 10);
}

function Kpi({
  titre,
  valeur,
  detail,
  icon: Icon,
  couleur = 'text-foreground',
}: {
  titre: string;
  valeur: string;
  detail?: string;
  icon: any;
  couleur?: string;
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription className="flex items-center gap-1.5">
          <Icon className="h-3.5 w-3.5" />
          {titre}
        </CardDescription>
        <CardTitle className={`text-xl ${couleur}`}>{valeur}</CardTitle>
      </CardHeader>
      {detail && (
        <CardContent className="pt-0">
          <p className="text-xs text-muted-foreground">{detail}</p>
        </CardContent>
      )}
    </Card>
  );
}

export default function ReportsPage() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const [data, setData] = useState<any | null>(null);
  const [loading, setLoading] = useState(true);
  const [periode, setPeriode] = useState<number>(30);
  const [dateFrom, setDateFrom] = useState(() => depuis(30));
  const [dateTo, setDateTo] = useState(() => appToday());

  const charger = useCallback(
    async (silent = false) => {
      if (!silent) setLoading(true);
      try {
        setData(await djangoClient.reports.get(dateFrom, dateTo));
      } catch {
        setData(null);
      } finally {
        if (!silent) setLoading(false);
      }
    },
    [dateFrom, dateTo],
  );

  useRealtimeRefresh(['order', 'order_status_history'], () => charger(true));
  useEffect(() => {
    if (!userLoading && isGerant) charger();
  }, [userLoading, isGerant, charger]);

  const choisirPeriode = (jours: number) => {
    setPeriode(jours);
    setDateFrom(depuis(jours));
    setDateTo(appToday());
  };

  const t = data?.totaux;
  const parJour = useMemo(
    () =>
      (data?.par_jour || []).map((j: any) => ({
        ...j,
        jour: jourCourt(j.date),
        ca: Number(j.ca),
        depenses: Number(j.depenses),
        difference: Number(j.difference),
      })),
    [data],
  );
  const mouvements = useMemo(
    () =>
      (data?.mouvements_par_jour || []).map((m: any) => ({
        ...m,
        jour: jourCourt(m.date),
      })),
    [data],
  );

  if (!userLoading && !isGerant) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-20 text-center">
            <ShieldAlert className="h-12 w-12 text-red-500 mb-4" />
            <h2 className="text-xl font-bold">Accès refusé</h2>
            <p className="text-muted-foreground mt-2">
              Les rapports sont réservés au gérant.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  if (loading || !data) {
    return (
      <div className="p-4 sm:p-6 space-y-4">
        <Skeleton className="h-10 w-64" />
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <Skeleton key={i} className="h-24 w-full" />
          ))}
        </div>
        <Skeleton className="h-72 w-full" />
      </div>
    );
  }

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col lg:flex-row lg:items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Rapports</h1>
          <p className="text-sm text-muted-foreground">
            Du {jourCourt(data.periode.from)} au {jourCourt(data.periode.to)} —
            chiffre d&apos;affaires, dépenses, performance des équipes.
          </p>
        </div>
        <div className="flex flex-wrap items-end gap-2">
          {PERIODES.map((p) => (
            <Button
              key={p.jours}
              size="sm"
              variant={periode === p.jours ? 'default' : 'outline'}
              onClick={() => choisirPeriode(p.jours)}
            >
              {p.label}
            </Button>
          ))}
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Du</Label>
            <Input
              type="date"
              value={dateFrom}
              onChange={(e) => {
                setDateFrom(e.target.value);
                setPeriode(0);
              }}
              className="w-auto"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Au</Label>
            <Input
              type="date"
              value={dateTo}
              onChange={(e) => {
                setDateTo(e.target.value);
                setPeriode(0);
              }}
              className="w-auto"
            />
          </div>
          <Button variant="outline" size="icon" onClick={() => charger()}>
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Les chiffres de la période */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Kpi
          titre="Chiffre d'affaires"
          valeur={fmt(t.chiffre_affaires)}
          detail={`Produits ${fmt(t.ca_produits)} + frais ${fmt(t.frais_livraison)}`}
          icon={TrendingUp}
        />
        <Kpi
          titre="Marge sur produits"
          valeur={fmt(t.marge_produits)}
          detail={`Vendus ${fmt(t.ca_produits)} − coût ${fmt(t.cout_produits)}`}
          icon={ArrowUpRight}
          couleur="text-emerald-600 dark:text-emerald-400"
        />
        <Kpi
          titre="Total dépenses"
          valeur={fmt(t.depenses_totales)}
          detail={`Caisse ${fmt(t.depenses_caisse)} + livreurs ${fmt(t.depenses_livreur)}`}
          icon={ArrowDownRight}
          couleur="text-red-600"
        />
        <Kpi
          titre="Résultat"
          valeur={fmt(t.resultat)}
          detail="Marge + frais − dépenses"
          icon={Number(t.resultat) >= 0 ? TrendingUp : TrendingDown}
          couleur={
            Number(t.resultat) >= 0
              ? 'text-emerald-600 dark:text-emerald-400'
              : 'text-red-600'
          }
        />
        <Kpi
          titre="Frais de livraison"
          valeur={fmt(t.frais_livraison)}
          detail={`${nb(t.nb_livrees)} livraison(s)`}
          icon={Truck}
        />
        <Kpi
          titre="Dépenses livreurs"
          valeur={fmt(t.depenses_livreur)}
          detail="Frais de tournée validés"
          icon={Wallet}
          couleur="text-red-600"
        />
        <Kpi
          titre="Retours"
          valeur={nb(t.nb_retours)}
          detail={`${fmt(t.montant_retours)} non encaissés`}
          icon={Undo2}
          couleur="text-red-600"
        />
        <Kpi
          titre="Taux de livraison"
          valeur={`${t.taux_livraison} %`}
          detail={`${nb(t.nb_livrees)} livrées sur ${nb(t.nb_commandes)}`}
          icon={Package}
        />
      </div>

      {/* Recettes, dépenses et écart, jour par jour */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Recettes et dépenses par jour</CardTitle>
          <CardDescription>
            La courbe donne l&apos;écart du jour : ce que la journée a
            réellement laissé une fois les dépenses retirées.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="h-72 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={parJour}>
                <CartesianGrid strokeDasharray="3 3" opacity={0.3} />
                <XAxis dataKey="jour" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} width={70} />
                <Tooltip formatter={(v: any) => fmt(v)} />
                <Legend />
                <Bar dataKey="ca" name="Recettes" fill="#2563eb" />
                <Bar dataKey="depenses" name="Dépenses" fill="#dc2626" />
                <Line
                  type="monotone"
                  dataKey="difference"
                  name="Écart"
                  stroke="#16a34a"
                  strokeWidth={2}
                  dot={false}
                />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Mouvements de stock */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <ArrowLeftRight className="h-4 w-4" /> Mouvements de stock par jour
            </CardTitle>
            <CardDescription>
              Entrées et sorties enregistrées sur la période.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-64 w-full">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={mouvements}>
                  <CartesianGrid strokeDasharray="3 3" opacity={0.3} />
                  <XAxis dataKey="jour" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="entrees" name="Entrées" fill="#16a34a" />
                  <Bar dataKey="sorties" name="Sorties" fill="#ea580c" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        {/* Part de l'activité par jour */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Activité par jour</CardTitle>
            <CardDescription>
              Part des mouvements de stock de chaque journée dans la période —
              elle montre où se concentre l&apos;activité.
            </CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto max-h-64">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Jour</TableHead>
                    <TableHead className="text-right">Commandes</TableHead>
                    <TableHead className="text-right">Livrées</TableHead>
                    <TableHead className="text-right">Retours</TableHead>
                    <TableHead className="text-right">Mouvements</TableHead>
                    <TableHead className="text-right">Part</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {parJour.map((j: any) => (
                    <TableRow key={j.date}>
                      <TableCell className="whitespace-nowrap">{j.jour}</TableCell>
                      <TableCell className="text-right">{nb(j.commandes)}</TableCell>
                      <TableCell className="text-right">{nb(j.livrees)}</TableCell>
                      <TableCell className="text-right text-red-600">
                        {j.retours || '-'}
                      </TableCell>
                      <TableCell className="text-right">{nb(j.mouvements)}</TableCell>
                      <TableCell className="text-right font-medium">
                        {j.part_mouvements} %
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Produits les plus vendus */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Produits les plus vendus</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <ProduitsTable rows={data.top_produits} vide="Aucune vente sur la période." />
          </CardContent>
        </Card>

        {/* Produits les moins vendus */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Produits les moins vendus</CardTitle>
            <CardDescription>
              Parmi ceux qui se sont vendus — un produit jamais vendu
              n&apos;apparaît pas ici, il est dans le catalogue.
            </CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <ProduitsTable
              rows={data.produits_moins_vendus}
              vide="Aucune vente sur la période."
            />
          </CardContent>
        </Card>
      </div>

      {/* Performance des livreurs */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Truck className="h-4 w-4" /> Performance des livreurs
          </CardTitle>
          <CardDescription>
            Livraisons réussies, retours, argent rapporté et frais de tournée.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          {data.livreurs.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-10">
              Aucune commande assignée sur la période.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Livreur</TableHead>
                    <TableHead className="text-right">Assignées</TableHead>
                    <TableHead className="text-right">Livrées</TableHead>
                    <TableHead className="text-right">Retours</TableHead>
                    <TableHead className="text-right">Réussite</TableHead>
                    <TableHead className="text-right">Encaissé</TableHead>
                    <TableHead className="text-right">Frais</TableHead>
                    <TableHead className="text-right">Dépenses</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.livreurs.map((l: any) => (
                    <TableRow key={l.id}>
                      <TableCell className="font-medium">{l.nom}</TableCell>
                      <TableCell className="text-right">{nb(l.assignees)}</TableCell>
                      <TableCell className="text-right">{nb(l.livrees)}</TableCell>
                      <TableCell className="text-right text-red-600">
                        {l.retours || '-'}
                      </TableCell>
                      <TableCell className="text-right font-medium">
                        {l.taux_reussite} %
                      </TableCell>
                      <TableCell className="text-right">{fmt(l.ca)}</TableCell>
                      <TableCell className="text-right">
                        {fmt(l.frais_livraison)}
                      </TableCell>
                      <TableCell className="text-right text-red-600">
                        {Number(l.depenses) > 0 ? `-${fmt(l.depenses)}` : '-'}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Préparateurs */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Package className="h-4 w-4" /> Commandes préparées
          </CardTitle>
          <CardDescription>
            Par préparateur sur la période, avec le détail des journées.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {data.preparateurs.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-10">
              Aucune préparation sur la période.
            </p>
          ) : (
            <div className="space-y-4">
              {data.preparateurs.map((p: any) => (
                <div key={p.id} className="space-y-1">
                  <div className="flex items-center justify-between text-sm">
                    <span className="font-medium">{p.nom}</span>
                    <span className="text-muted-foreground">
                      {nb(p.total)} commande(s)
                    </span>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {p.par_jour.map((j: any) => (
                      <span
                        key={j.date}
                        className="text-[11px] rounded-full border px-2 py-0.5 text-muted-foreground"
                      >
                        {jourCourt(j.date)} · {j.nb}
                      </span>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function ProduitsTable({ rows, vide }: { rows: any[]; vide: string }) {
  if (!rows || rows.length === 0) {
    return (
      <p className="text-sm text-muted-foreground text-center py-10">{vide}</p>
    );
  }
  return (
    <div className="overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Produit</TableHead>
            <TableHead>Marque</TableHead>
            <TableHead className="text-right">Vendus</TableHead>
            <TableHead className="text-right">CA</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((p, i) => (
            <TableRow key={`${p.label}-${i}`}>
              <TableCell className="font-medium">{p.label}</TableCell>
              <TableCell className="text-muted-foreground">
                {p.marque || '-'}
              </TableCell>
              <TableCell className="text-right">{nb(p.quantite)}</TableCell>
              <TableCell className="text-right">{fmt(p.ca)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
