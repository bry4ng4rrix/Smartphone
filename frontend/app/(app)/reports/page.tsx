'use client';

import { useEffect, useState, useCallback, useMemo } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import {
  RefreshCw, TrendingUp, Package, DollarSign, ShoppingBag, AlertTriangle,
  Users, Store, ArrowDownRight, ArrowUpRight, ArrowLeftRight, CircleCheck,
} from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';

const fmt = (n: number) => new Intl.NumberFormat('fr-MG').format(Math.round(n));
const PERIODS = [7, 30, 90] as const;

export default function ReportsPage() {
  const { isAdmin } = useCurrentUser();
  const [sales, setSales] = useState<any[]>([]);
  const [products, setProducts] = useState<any[]>([]);
  const [movements, setMovements] = useState<any[]>([]);
  const [dashboardKpis, setDashboardKpis] = useState<any>({});
  const [loading, setLoading] = useState(true);
  const [period, setPeriod] = useState<typeof PERIODS[number]>(30);

  const fetchData = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const [s, p, m, dashboard] = await Promise.all([
        djangoClient.sales.list(),
        djangoClient.products.list(),
        djangoClient.movements.list(),
        djangoClient.get<any>('/users/dashboard/').catch(() => ({})),
      ]);
      setSales(s);
      setProducts(p);
      setMovements(Array.isArray(m) ? m : (m as any)?.results || []);
      setDashboardKpis(dashboard?.kpis || {});
    } catch (err) {
      console.error(err);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(['product_variant', 'order', 'stock_movement'], () => fetchData(true));

  useEffect(() => { fetchData(); }, [fetchData]);

  const today = useMemo(() => new Date(), []);

  const totalRevenue = sales.reduce((s, x) => s + Number(x.total_price || 0), 0);
  const totalProfit = sales.reduce((s, x) => s + Number(x.total_profit || 0), 0);
  const totalQty = sales.reduce((s, x) => s + (x.quantity || 0), 0);
  const totalStock = products.reduce((s, p) => s + (p.initial_quantity || 0), 0);

  const unpaidSales = sales.filter(
    (s) => !s.is_paid || Number(s.payment_amount || 0) < Number(s.total_price || 0)
  );
  const unpaidValue = unpaidSales.reduce(
    (sum, s) => sum + Math.max(Number(s.total_price || 0) - Number(s.payment_amount || 0), 0),
    0
  );

  const expiredCount = products.filter((p) => p.expiry_date && new Date(p.expiry_date) < today).length;
  const lowStockCount = products.filter(
    (p) => (p.initial_quantity ?? 0) <= (p.alert_threshold ?? 0)
  ).length;

  // Sales by product (qty, CA, profit)
  const byProduct: Record<string, { qty: number; revenue: number; profit: number }> = {};
  sales.forEach((s) => {
    const name = s.product_name || 'Inconnu';
    if (!byProduct[name]) byProduct[name] = { qty: 0, revenue: 0, profit: 0 };
    byProduct[name].qty += s.quantity || 0;
    byProduct[name].revenue += Number(s.total_price || 0);
    byProduct[name].profit += Number(s.total_profit || 0);
  });
  const topProducts = Object.entries(byProduct)
    .map(([name, v]) => ({ name, ...v }))
    .sort((a, b) => b.qty - a.qty)
    .slice(0, 10);

  // Sales by seller
  const bySeller: Record<string, { count: number; revenue: number; profit: number }> = {};
  sales.forEach((s) => {
    const name = s.seller_name || 'Non attribué';
    if (!bySeller[name]) bySeller[name] = { count: 0, revenue: 0, profit: 0 };
    bySeller[name].count += 1;
    bySeller[name].revenue += Number(s.total_price || 0);
    bySeller[name].profit += Number(s.total_profit || 0);
  });
  const topSellers = Object.entries(bySeller)
    .map(([name, v]) => ({ name, ...v }))
    .sort((a, b) => b.revenue - a.revenue)
    .slice(0, 8);

  // Sales by shop (admin only — cross-magasin comparison)
  const byShop: Record<string, { qty: number; revenue: number; profit: number }> = {};
  if (isAdmin) {
    sales.forEach((s) => {
      const name = s.shop_name || 'Magasin inconnu';
      if (!byShop[name]) byShop[name] = { qty: 0, revenue: 0, profit: 0 };
      byShop[name].qty += s.quantity || 0;
      byShop[name].revenue += Number(s.total_price || 0);
      byShop[name].profit += Number(s.total_profit || 0);
    });
  }
  const topShops = Object.entries(byShop)
    .map(([name, v]) => ({ name, ...v }))
    .sort((a, b) => b.revenue - a.revenue);

  // Revenue chart over the selected period
  const dayBuckets: Record<string, number> = {};
  for (let i = period - 1; i >= 0; i--) {
    const d = new Date(); d.setDate(d.getDate() - i);
    dayBuckets[d.toISOString().split('T')[0]] = 0;
  }
  sales.forEach((s) => {
    const day = new Date(s.sold_at).toISOString().split('T')[0];
    if (day in dayBuckets) dayBuckets[day] += Number(s.total_price || 0);
  });
  const revenueChart = Object.entries(dayBuckets).map(([date, revenue]) => ({
    date: date.slice(5),
    revenue,
  }));

  // Movement type breakdown over the selected period
  const periodStart = new Date();
  periodStart.setDate(periodStart.getDate() - period);
  const movementsInPeriod = movements.filter((m) => new Date(m.created_at) >= periodStart);
  const movementCounts = { Entrée: 0, Sortie: 0, Transfert: 0 } as Record<string, number>;
  movementsInPeriod.forEach((m) => {
    const type = m.movement_type;
    if (type in movementCounts) movementCounts[type] += 1;
  });

  const unpaidSorted = [...unpaidSales].sort((a, b) => {
    if (!a.payment_due_date) return 1;
    if (!b.payment_due_date) return -1;
    return new Date(a.payment_due_date).getTime() - new Date(b.payment_due_date).getTime();
  }).slice(0, 8);

  const kpis = [
    { label: "Chiffre d'affaires", value: `${fmt(totalRevenue)} Ar`, icon: DollarSign, color: 'text-green-600' },
    { label: 'Bénéfice net', value: `${fmt(totalProfit)} Ar`, icon: TrendingUp, color: 'text-emerald-600' },
    { label: 'Unités vendues', value: `${fmt(totalQty)}`, icon: ShoppingBag, color: 'text-blue-600' },
    { label: 'Transactions', value: sales.length, icon: ShoppingBag, color: 'text-purple-600' },
    { label: 'Ventes impayées', value: unpaidSales.length, icon: AlertTriangle, color: 'text-orange-600' },
    { label: 'Montant impayé', value: `${fmt(unpaidValue)} Ar`, icon: AlertTriangle, color: 'text-red-600' },
    { label: 'Produits en stock', value: `${fmt(totalStock)} u.`, icon: Package, color: 'text-indigo-600' },
    { label: 'Alertes stock', value: lowStockCount + expiredCount, icon: AlertTriangle, color: 'text-amber-600' },
  ];

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Rapports</h1>
          <p className="text-muted-foreground mt-1">Analyse des ventes, du stock et des performances</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => fetchData()} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />Actualiser
        </Button>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {kpis.map(({ label, value, icon: Icon, color }) => (
          <Card key={label}>
            <CardHeader className="pb-2">
              <CardTitle className={`text-sm font-medium flex items-center gap-2 ${color}`}>
                <Icon className="h-4 w-4" />{label}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {loading ? <Skeleton className="h-8 w-24" /> : <div className={`text-2xl font-bold ${color}`}>{value}</div>}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Revenue chart */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0">
          <div>
            <CardTitle>Chiffre d'affaires — {period} derniers jours</CardTitle>
            <CardDescription>Évolution journalière du CA</CardDescription>
          </div>
          <div className="flex gap-1">
            {PERIODS.map((p) => (
              <Button
                key={p}
                size="sm"
                variant={period === p ? 'default' : 'outline'}
                className="h-7 px-2.5 text-xs"
                onClick={() => setPeriod(p)}
              >
                {p}j
              </Button>
            ))}
          </div>
        </CardHeader>
        <CardContent>
          {loading ? <Skeleton className="h-64 w-full" /> : (
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={revenueChart}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="date" tick={{ fontSize: 10 }} interval={Math.max(Math.floor(period / 8), 0)} />
                <YAxis tickFormatter={(v) => fmt(v)} tick={{ fontSize: 11 }} />
                <Tooltip formatter={(v: number) => `${fmt(v)} Ar`} />
                <Bar dataKey="revenue" fill="#3b82f6" radius={[2, 2, 0, 0]} name="CA" />
              </BarChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>

      {/* Top products */}
      <Card>
        <CardHeader>
          <CardTitle>Top produits vendus</CardTitle>
          <CardDescription>Classement par quantités vendues</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? <Skeleton className="h-48 w-full" /> : topProducts.length === 0 ? (
            <p className="text-muted-foreground text-sm text-center py-8">Aucune vente enregistrée</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>#</TableHead>
                  <TableHead>Produit</TableHead>
                  <TableHead className="text-right">Qté vendue</TableHead>
                  <TableHead className="text-right">CA généré</TableHead>
                  <TableHead className="text-right">Bénéfice</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {topProducts.map((p, i) => (
                  <TableRow key={p.name}>
                    <TableCell className="font-medium text-muted-foreground">{i + 1}</TableCell>
                    <TableCell className="font-medium">{p.name}</TableCell>
                    <TableCell className="text-right font-semibold">{p.qty}</TableCell>
                    <TableCell className="text-right">{fmt(p.revenue)} Ar</TableCell>
                    <TableCell className="text-right text-emerald-600 font-medium">{fmt(p.profit)} Ar</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Ventes à crédit / impayées */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-orange-500" />
              Ventes à crédit
            </CardTitle>
            <CardDescription>Paiements en attente ou partiels</CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? <Skeleton className="h-48 w-full" /> : unpaidSorted.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-8 text-center text-muted-foreground">
                <CircleCheck className="h-8 w-8 text-green-500" />
                <p className="text-sm">Aucune vente impayée</p>
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Client</TableHead>
                    <TableHead>Produit</TableHead>
                    <TableHead className="text-right">Restant dû</TableHead>
                    <TableHead>Statut</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {unpaidSorted.map((s) => {
                    const remaining = Math.max(Number(s.total_price || 0) - Number(s.payment_amount || 0), 0);
                    const overdue = s.payment_due_date && new Date(s.payment_due_date) < today;
                    return (
                      <TableRow key={s.id}>
                        <TableCell className="font-medium">{s.customer_name || 'Client anonyme'}</TableCell>
                        <TableCell className="text-muted-foreground">{s.product_name}</TableCell>
                        <TableCell className="text-right font-semibold text-red-600">{fmt(remaining)} Ar</TableCell>
                        <TableCell>
                          <Badge variant={overdue ? 'destructive' : 'outline'} className="text-[10px]">
                            {overdue ? 'En retard' : 'En attente'}
                          </Badge>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        {/* Performance des vendeurs */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Users className="h-5 w-5 text-blue-500" />
              Performance des vendeurs
            </CardTitle>
            <CardDescription>Classement par chiffre d'affaires</CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? <Skeleton className="h-48 w-full" /> : topSellers.length === 0 ? (
              <p className="text-muted-foreground text-sm text-center py-8">Aucune vente enregistrée</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Vendeur</TableHead>
                    <TableHead className="text-right">Ventes</TableHead>
                    <TableHead className="text-right">CA</TableHead>
                    <TableHead className="text-right">Bénéfice</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {topSellers.map((s) => (
                    <TableRow key={s.name}>
                      <TableCell className="font-medium">{s.name}</TableCell>
                      <TableCell className="text-right">{s.count}</TableCell>
                      <TableCell className="text-right">{fmt(s.revenue)} Ar</TableCell>
                      <TableCell className="text-right text-emerald-600 font-medium">{fmt(s.profit)} Ar</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Performance par magasin (admin uniquement, comparaison multi-magasins) */}
      {isAdmin && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Store className="h-5 w-5 text-violet-500" />
              Performance par magasin
            </CardTitle>
            <CardDescription>Comparaison du chiffre d'affaires entre magasins</CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? <Skeleton className="h-48 w-full" /> : topShops.length === 0 ? (
              <p className="text-muted-foreground text-sm text-center py-8">Aucune vente enregistrée</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Magasin</TableHead>
                    <TableHead className="text-right">Qté vendue</TableHead>
                    <TableHead className="text-right">CA</TableHead>
                    <TableHead className="text-right">Bénéfice</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {topShops.map((s) => (
                    <TableRow key={s.name}>
                      <TableCell className="font-medium">{s.name}</TableCell>
                      <TableCell className="text-right">{s.qty}</TableCell>
                      <TableCell className="text-right">{fmt(s.revenue)} Ar</TableCell>
                      <TableCell className="text-right text-emerald-600 font-medium">{fmt(s.profit)} Ar</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      )}

      {/* Mouvements de stock */}
      <Card>
        <CardHeader>
          <CardTitle>Mouvements de stock — {period} derniers jours</CardTitle>
          <CardDescription>Entrées, sorties et transferts enregistrés</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? <Skeleton className="h-20 w-full" /> : (
            <div className="grid grid-cols-3 gap-4">
              <div className="flex items-center gap-3 rounded-lg border p-4">
                <ArrowUpRight className="h-5 w-5 text-green-600" />
                <div>
                  <div className="text-xl font-bold text-green-600">{movementCounts['Entrée']}</div>
                  <p className="text-xs text-muted-foreground">Entrées</p>
                </div>
              </div>
              <div className="flex items-center gap-3 rounded-lg border p-4">
                <ArrowDownRight className="h-5 w-5 text-red-600" />
                <div>
                  <div className="text-xl font-bold text-red-600">{movementCounts['Sortie']}</div>
                  <p className="text-xs text-muted-foreground">Sorties</p>
                </div>
              </div>
              <div className="flex items-center gap-3 rounded-lg border p-4">
                <ArrowLeftRight className="h-5 w-5 text-cyan-600" />
                <div>
                  <div className="text-xl font-bold text-cyan-600">{movementCounts['Transfert']}</div>
                  <p className="text-xs text-muted-foreground">Transferts</p>
                </div>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
