'use client';

import { useEffect, useState, useCallback } from 'react';
import { djangoClient } from '@/lib/django-client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AlertTriangle, Package, RefreshCw } from 'lucide-react';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';

const fmt = (n: number) => new Intl.NumberFormat('fr-MG').format(Math.round(n));

export default function AlertsPage() {
  const [products, setProducts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchData = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const data = await djangoClient.products.list();
      setProducts(data);
    } catch (err) {
      console.error(err);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(['product_variant', 'order'], () => fetchData(true));

  useEffect(() => { fetchData(); }, [fetchData]);

  const today = new Date();
  const in30Days = new Date(); in30Days.setDate(today.getDate() + 30);

  const lowStock = products.filter(p => p.initial_quantity > 0 && p.initial_quantity <= p.alert_threshold);
  const outOfStock = products.filter(p => p.initial_quantity === 0);
  const expiringSoon = products.filter(p => p.expiry_date && new Date(p.expiry_date) <= in30Days && new Date(p.expiry_date) >= today);
  const expired = products.filter(p => p.expiry_date && new Date(p.expiry_date) < today);

  const AlertTable = ({ items, emptyMsg, columns }: { items: any[]; emptyMsg: string; columns: { key: string; label: string }[] }) => (
    loading ? <Skeleton className="h-24 w-full" /> :
    items.length === 0 ? (
      <p className="text-sm text-muted-foreground text-center py-6">{emptyMsg}</p>
    ) : (
      <Table>
        <TableHeader>
          <TableRow>
            {columns.map(c => <TableHead key={c.key}>{c.label}</TableHead>)}
          </TableRow>
        </TableHeader>
        <TableBody>
          {items.map(p => (
            <TableRow key={p.id}>
              {columns.map(c => (
                <TableCell key={c.key}>
                  {c.key === 'status_badge' ? (
                    <Badge className={p.initial_quantity === 0 ? 'bg-red-100 text-red-800' : 'bg-orange-100 text-orange-800'}>
                      {p.initial_quantity === 0 ? 'Rupture' : 'Faible'}
                    </Badge>
                  ) : c.key === 'expiry_badge' ? (
                    <Badge className={new Date(p.expiry_date) < today ? 'bg-red-100 text-red-800' : 'bg-orange-100 text-orange-800'}>
                      {new Date(p.expiry_date).toLocaleDateString('fr-FR')}
                    </Badge>
                  ) : c.key === 'initial_quantity' ? (
                    <span className="font-semibold">{p.initial_quantity}</span>
                  ) : (
                    p[c.key] ?? '-'
                  )}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    )
  );

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Alertes</h1>
          <p className="text-muted-foreground mt-1">Produits nécessitant une attention</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => fetchData()} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />Actualiser
        </Button>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[
          { label: 'Rupture de stock', count: outOfStock.length, color: 'text-red-600', icon: Package },
          { label: 'Stock faible', count: lowStock.length, color: 'text-orange-500', icon: AlertTriangle },
          { label: 'Expirent bientôt', count: expiringSoon.length, color: 'text-yellow-600', icon: AlertTriangle },
          { label: 'Expirés', count: expired.length, color: 'text-red-700', icon: AlertTriangle },
        ].map(({ label, count, color, icon: Icon }) => (
          <Card key={label}>
            <CardHeader className="pb-2">
              <CardTitle className={`text-sm font-medium flex items-center gap-2 ${color}`}>
                <Icon className="h-4 w-4" />{label}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {loading ? <Skeleton className="h-8 w-12" /> : (
                <div className={`text-2xl font-bold ${color}`}>{count}</div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Out of stock */}
      <Card>
        <CardHeader>
          <CardTitle className="text-red-600 flex items-center gap-2">
            <Package className="h-5 w-5" />Rupture de stock ({outOfStock.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          <AlertTable
            items={outOfStock}
            emptyMsg="Aucun produit en rupture de stock"
            columns={[
              { key: 'name', label: 'Produit' },
              { key: 'reference', label: 'Référence' },
              { key: 'category', label: 'Catégorie' },
              { key: 'status_badge', label: 'Statut' },
            ]}
          />
        </CardContent>
      </Card>

      {/* Low stock */}
      <Card>
        <CardHeader>
          <CardTitle className="text-orange-600 flex items-center gap-2">
            <AlertTriangle className="h-5 w-5" />Stock faible ({lowStock.length})
          </CardTitle>
          <CardDescription>Quantité en dessous du seuil d'alerte</CardDescription>
        </CardHeader>
        <CardContent>
          <AlertTable
            items={lowStock}
            emptyMsg="Tous les stocks sont au-dessus du seuil d'alerte"
            columns={[
              { key: 'name', label: 'Produit' },
              { key: 'reference', label: 'Référence' },
              { key: 'initial_quantity', label: 'Qté actuelle' },
              { key: 'alert_threshold', label: 'Seuil' },
              { key: 'status_badge', label: 'Statut' },
            ]}
          />
        </CardContent>
      </Card>

      {/* Expiring soon */}
      {(expiringSoon.length > 0 || expired.length > 0) && (
        <Card>
          <CardHeader>
            <CardTitle className="text-yellow-600 flex items-center gap-2">
              <AlertTriangle className="h-5 w-5" />Dates de péremption ({expiringSoon.length + expired.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <AlertTable
              items={[...expired, ...expiringSoon]}
              emptyMsg="Aucun produit proche de la péremption"
              columns={[
                { key: 'name', label: 'Produit' },
                { key: 'reference', label: 'Référence' },
                { key: 'initial_quantity', label: 'Qté' },
                { key: 'expiry_badge', label: 'Date expiration' },
              ]}
            />
          </CardContent>
        </Card>
      )}
    </div>
  );
}
