'use client';

import { useEffect, useState, useCallback } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import {
  BarChart, Bar, PieChart, Pie, Cell, LineChart, Line,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
} from 'recharts';
import {
  Package, AlertTriangle, TrendingUp, DollarSign, Users,
  ArrowUp, ArrowDown, CheckCircle2,
} from 'lucide-react';
import { AIAnalysis } from '@/components/ai-analysis';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';

const CHART_COLORS = ['#3b82f6', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981', '#ef4444', '#6366f1', '#f97316'];

const fmt = (n: number) =>
  new Intl.NumberFormat('fr-MG', { minimumFractionDigits: 0 }).format(Math.round(n));

export default function DashboardPage() {
  const { user } = useCurrentUser();
  const [loading, setLoading] = useState(true);
  const [role, setRole] = useState<string>('employee');

  // KPIs
  const [kpis, setKpis] = useState({
    totalProducts: 0,
    totalQuantity: 0,
    totalValue: 0,
    totalEmployees: 0,
    lowStockCount: 0,
    outOfStockCount: 0,
    mySalesToday: 0,
    totalAmountSold: 0,
    totalSalesAllStores: 0,
    clientsCount: 0,
    totalProfit: 0,
    unpaidSalesCount: 0,
    unpaidAmount: 0,
  });

  // Charts
  const [weeklyTrend, setWeeklyTrend] = useState<any[]>([]);
  const [categoryChart, setCategoryChart] = useState<any[]>([]);
  const [recentMovements, setRecentMovements] = useState<any[]>([]);
  const [lowStockProducts, setLowStockProducts] = useState<any[]>([]);
  const [expiringProducts, setExpiringProducts] = useState<any[]>([]);
  const [movementStats, setMovementStats] = useState<{ fastest: any[], slowest: any[] }>({ fastest: [], slowest: [] });

  const fetchDashboard = useCallback(async (silent = false) => {
    try {
      if (!silent) setLoading(true);

      // Fetch from Django REST API
      const dashboardData = await djangoClient.get<any>('/users/dashboard/');
      const products = await djangoClient.products.list();

      const userRole = dashboardData.role || 'employee';
      setRole(userRole);

      const rKpis = dashboardData.kpis || {};
      const rLists = dashboardData.lists || {};

      // Compute statistics and category mapping from products
      let totalQuantity = 0;
      let totalValue = 0;
      let lowStockCount = 0;
      let outOfStockCount = 0;
      const categoryMap: Record<string, number> = {};
      const lowProducts: any[] = [];

      products.forEach((p: any) => {
        const qty = p.initial_quantity ?? 0;
        totalQuantity += qty;
        totalValue += qty * (p.unit_price ?? 0);

        const alertThreshold = p.alert_threshold ?? 5;
        if (qty === 0) {
          outOfStockCount++;
          lowProducts.push({ ...p, status: 'out_of_stock', quantity: qty });
        } else if (qty <= alertThreshold) {
          lowStockCount++;
          lowProducts.push({ ...p, status: 'low', quantity: qty });
        }

        categoryMap[p.category || 'Autre'] = (categoryMap[p.category || 'Autre'] || 0) + qty;
      });

      // Weekly trend computed from recent sales
      const days = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
      const last7Days: { fullDate: string; label: string; entrées: number; sorties: number }[] = [];
      for (let i = 6; i >= 0; i--) {
        const d = new Date();
        d.setDate(d.getDate() - i);
        last7Days.push({
          fullDate: d.toISOString().split('T')[0],
          label: days[d.getDay()],
          entrées: 0,
          sorties: 0,
        });
      }

      const salesList = rLists.recent_sales || [];
      salesList.forEach((sale: any) => {
        const soldDateStr = sale.sold_at?.split('T')[0];
        const dayMatch = last7Days.find((d) => d.fullDate === soldDateStr);
        if (dayMatch) {
          dayMatch.sorties += sale.quantity || 0;
        }
      });

      setWeeklyTrend(last7Days);

      const stockValue = rKpis.total_stock_value ?? rKpis.stock_value ?? totalValue;

      setKpis({
        totalProducts: products.length,
        totalQuantity,
        totalValue: stockValue,
        totalEmployees: rKpis.total_employers || rKpis.total_magasins || 0,
        lowStockCount: rKpis.low_stock_count || lowStockCount,
        outOfStockCount,
        mySalesToday: rKpis.my_sales_today || rKpis.sales_today || 0,
        totalAmountSold: rKpis.total_amount_sold || rKpis.total_revenue || 0,
        totalSalesAllStores: rKpis.total_revenue || 0,
        clientsCount: rKpis.clients_count || rKpis.total_sales || 0,
        totalProfit: rKpis.total_profit || 0,
        unpaidSalesCount: rKpis.unpaid_sales_count || 0,
        unpaidAmount: rKpis.unpaid_sales_value || 0,
      });

      setCategoryChart(
        Object.entries(categoryMap)
          .map(([name, value]) => ({ name, value }))
          .sort((a, b) => b.value - a.value),
      );

      setLowStockProducts(lowProducts.slice(0, 8));

      // Expiring products (within 30 days)
      const today = new Date();
      const thirtyDaysFromNow = new Date();
      thirtyDaysFromNow.setDate(today.getDate() + 30);

      const expiring = products
        .filter((p: any) => p.expiry_date && new Date(p.expiry_date) <= thirtyDaysFromNow)
        .sort((a: any, b: any) => new Date(a.expiry_date!).getTime() - new Date(b.expiry_date!).getTime())
        .map((p: any) => ({ ...p, quantity: p.initial_quantity }));

      setExpiringProducts(expiring.slice(0, 8));

      setRecentMovements(salesList.slice(0, 8));

      // Movement Stats for AI推荐
      const topSales = rLists.top_products || [];
      const fastest = topSales.map((t: any) => ({
        name: t.product__name || t.name || 'Produit',
        outQty: t.qty_sold || t.quantity_sold || 0,
      }));
      setMovementStats({
        fastest,
        slowest: products
          .filter((p: any) => !topSales.some((t: any) => (t.product__name || t.name) === p.name))
          .slice(0, 5)
          .map((p: any) => ({ name: p.name, outQty: 0 })),
      });

    } catch (err) {
      console.error('Dashboard error:', err);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(['product_variant', 'order', 'stock_movement'], () => fetchDashboard(true));

  useEffect(() => {
    fetchDashboard();
  }, [fetchDashboard]);

  // ── KPI Card helper ───────────────────────────────────────────
  const KpiCard = ({
    title, value, sub, icon: Icon, color = 'text-muted-foreground', accent,
  }: {
    title: string;
    value: string | number;
    sub: string;
    icon: any;
    color?: string;
    accent?: string;
  }) => (
    <Card className={accent}>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <Icon className={`h-4 w-4 ${color}`} />
      </CardHeader>
      <CardContent>
        {loading ? (
          <Skeleton className="h-8 w-32" />
        ) : (
          <>
            <div className={`text-2xl font-bold ${color !== 'text-muted-foreground' ? color : ''}`}>{value}</div>
            <p className="text-xs text-muted-foreground mt-1">{sub}</p>
          </>
        )}
      </CardContent>
    </Card>
  );

  return (
    <div className="p-6 space-y-8">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Tableau de bord</h1>
        <p className="text-muted-foreground mt-1">
          {user?.store_name ? `Magasin : ${user.store_name}` : 'Gestion des stocks cosmétiques'}
        </p>
      </div>

     



      {/* ── KPI Cards ─────────────────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-4">
        {role === 'employer' ? (
          <>
            <div className="xl:col-span-2">
              <KpiCard
                title="Mes ventes du jour"
                value={`${kpis.mySalesToday} ventes`}
                sub="Transactions effectuées aujourd'hui"
                icon={TrendingUp}
                color="text-green-600"
              />
            </div>
            <div className="xl:col-span-2">
              <KpiCard
                title="Chiffre d'affaires personnel"
                value={`${fmt(kpis.totalAmountSold)} Ar`}
                sub="Montant total vendu par vous"
                icon={DollarSign}
                color="text-blue-600"
              />
            </div>
            <div className="xl:col-span-2">
              <KpiCard
                title="Clients servis"
                value={kpis.clientsCount}
                sub="Nombre total de transactions"
                icon={Users}
              />
            </div>
            <div className="xl:col-span-2">
              <KpiCard
                title="Ventes impayées"
                value={kpis.unpaidSalesCount}
                sub="Transactions avec paiement en attente"
                icon={AlertTriangle}
                color="text-orange-600"
              />
            </div>
            <div className="xl:col-span-2">
              <KpiCard
                title="Montant impayé"
                value={`${fmt(kpis.unpaidAmount)} Ar`}
                sub="Somme due sur ventes impayées"
                icon={DollarSign}
                color="text-red-600"
              />
            </div>
          </>
        ) : (
          <>
            <div className="xl:col-span-2">
              <KpiCard
                title="Ventes totales "
                value={`${fmt(kpis.totalSalesAllStores)} Ar`}
                sub="Chiffre d'affaires global"
                icon={TrendingUp}
                color="text-green-600"
              />
            </div>
            <div className="xl:col-span-2">
              <KpiCard
                title="Valeur du stock"
                value={`${fmt(kpis.totalValue)} Ar`}
                sub="Valeur totale de l'inventaire"
                icon={DollarSign}
              />
            </div>



          {role === "admin" && (
  <div className="xl:col-span-2">
    <KpiCard
      title="Bénéfice total"
      value={`${fmt(kpis.totalProfit)} Ar`}
      sub="Profit net (vente - achat)"
      icon={CheckCircle2}
      color="text-emerald-600"
    />
  </div>
)}
           





            <div className="xl:col-span-2">
              <KpiCard
                title="Ventes impayées"
                value={kpis.unpaidSalesCount}
                sub="Transactions avec paiement en attente"
                icon={AlertTriangle}
                color="text-orange-600"
              />
            </div>
            <div className="xl:col-span-2">
              <KpiCard
                title="Montant impayé"
                value={`${fmt(kpis.unpaidAmount)} Ar`}
                sub="Somme due sur ventes impayées"
                icon={DollarSign}
                color="text-red-600"
              />
            </div>
            <div className="xl:col-span-2">
              <KpiCard
                title="Produits"
                value={`${fmt(kpis.totalQuantity)} unité${kpis.totalQuantity > 1 ? 's' : ''} sur ${kpis.totalProducts} produit${kpis.totalProducts > 1 ? 's' : ''}`}
                sub="Stock total du catalogue"
                icon={Package}
              />
            </div>

           {role === "admin" && (
             <KpiCard
              title="Admins/Magasins"
              value={kpis.totalEmployees}
              sub="Personnel enregistré"
              icon={Users}
            />
           )}


            <KpiCard
              title="Alertes stock"
              value={kpis.lowStockCount + kpis.outOfStockCount}
              sub={`${kpis.outOfStockCount} rupture(s), ${kpis.lowStockCount} faible(s)`}
              icon={AlertTriangle}
              color="text-orange-600"
              accent={kpis.lowStockCount + kpis.outOfStockCount > 0 ? 'border-orange-200 bg-orange-50 dark:bg-orange-950/20' : ''}
            />
          </>
        )}
      </div>

      <AIAnalysis
        fastest={movementStats.fastest}
        slowest={movementStats.slowest}
        expiring={expiringProducts}
      />

      {/* ── Charts ────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Weekly trend */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Ventes — 7 derniers jours</CardTitle>
            <CardDescription>Évolution journalière des sorties</CardDescription>
          </CardHeader>
          <CardContent className="pt-4">
            {loading ? (
              <Skeleton className="h-64 w-full" />
            ) : (
              <ResponsiveContainer width="100%" height={260}>
                <LineChart data={weeklyTrend}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="label" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line type="monotone" dataKey="sorties" name="Quantités vendues" stroke="#ef4444" strokeWidth={2} dot={false} />
                </LineChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>

        {/* Category distribution */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Stock par catégorie</CardTitle>
            <CardDescription>Unités par famille de produits</CardDescription>
          </CardHeader>
          <CardContent className="pt-4">
            {loading ? (
              <Skeleton className="h-64 w-full" />
            ) : categoryChart.length === 0 ? (
              <div className="flex items-center justify-center h-64 text-muted-foreground text-sm">
                Aucune donnée
              </div>
            ) : categoryChart.length <= 5 ? (
              <ResponsiveContainer width="100%" height={260}>
                <PieChart>
                  <Pie
                    data={categoryChart}
                    cx="50%"
                    cy="50%"
                    outerRadius={90}
                    dataKey="value"
                    label={({ name, value }) => `${name}: ${value}`}
                    labelLine={false}
                  >
                    {categoryChart.map((_, i) => (
                      <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={categoryChart} layout="vertical">
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis type="number" />
                  <YAxis type="category" dataKey="name" width={100} tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="value" fill="#3b82f6" radius={[0, 4, 4, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ── Recent Sales + Low Stock ─────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent Sales */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <TrendingUp className="h-5 w-5" />
              Ventes récentes
            </CardTitle>
            <CardDescription>8 dernières transactions enregistrées</CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="space-y-3">
                {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}
              </div>
            ) : recentMovements.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-8">Aucune vente enregistrée</p>
            ) : (
              <div className="space-y-3">
                {recentMovements.map((m, i) => (
                  <div key={i} className="flex items-center gap-3 p-3 rounded-lg border">
                    <div className="flex-shrink-0 p-1.5 rounded-full bg-red-100 text-red-700">
                      <ArrowDown className="h-4 w-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm truncate">{m.product_name ?? 'Produit inconnu'}</p>
                      <p className="text-xs text-muted-foreground">
                        {new Date(m.sold_at).toLocaleDateString('fr-FR', {
                          day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
                        })}
                        {m.seller_name && (
                          <span className="ml-1">· {m.seller_name}</span>
                        )}
                        {m.shop_name && (
                          <span className="ml-1">· ({m.shop_name})</span>
                        )}
                      </p>
                    </div>
                    <div className="text-right">
                      <span className="text-sm font-semibold text-red-600">
                        -{m.quantity}
                      </span>
                      <p className="text-[10px] text-muted-foreground font-mono">{fmt(m.total_price || 0)} Ar</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Low Stock */}
        <Card className={lowStockProducts.length > 0 ? 'border-orange-200' : ''}>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <AlertTriangle className={`h-5 w-5 ${lowStockProducts.length > 0 ? 'text-orange-500' : 'text-muted-foreground'}`} />
              Alertes de stock
            </CardTitle>
            <CardDescription>Produits à réapprovisionner</CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="space-y-3">
                {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}
              </div>
            ) : lowStockProducts.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8 text-center">
                <CheckCircle2 className="h-10 w-10 text-green-500 mb-2" />
                <p className="text-sm font-medium text-green-700">Tous les stocks sont OK</p>
                <p className="text-xs text-muted-foreground mt-1">Aucun produit en alerte</p>
              </div>
            ) : (
              <div className="space-y-3">
                {lowStockProducts.map((p) => (
                  <div key={p.id} className="flex items-center justify-between p-3 rounded-lg border bg-card">
                    <div className="min-w-0">
                      <p className="font-medium text-sm truncate">{p.name}</p>
                      <p className="text-xs text-muted-foreground font-mono">{p.sku}</p>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <span className={`text-sm font-semibold ${p.status === 'out_of_stock' ? 'text-red-600' : 'text-orange-600'
                        }`}>
                        {p.quantity ?? 0} u.
                      </span>
                      <Badge className={
                        p.status === 'out_of_stock'
                          ? 'bg-red-100 text-red-800'
                          : 'bg-orange-100 text-orange-800'
                      }>
                        {p.status === 'out_of_stock' ? 'Rupture' : 'Faible'}
                      </Badge>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

