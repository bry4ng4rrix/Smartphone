'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { djangoClient } from '@/lib/django-client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Badge } from '@/components/ui/badge';
import { Activity, Cpu, HardDrive, MemoryStick, Database, Zap, MonitorSmartphone } from 'lucide-react';

const POLL_INTERVAL_MS = 4000;
const HISTORY_LENGTH = 20;

const formatBytes = (bytes: number | null | undefined) => {
  if (bytes == null) return '-';
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return `${value.toFixed(1)} ${units[i]}`;
};

function Sparkline({ values, colorClass }: { values: number[]; colorClass: string }) {
  if (values.length === 0) return <div className="h-8" />;
  const max = Math.max(...values, 1);
  return (
    <div className="flex items-end gap-0.5 h-8">
      {values.map((v, i) => (
        <div
          key={i}
          className={`w-1.5 rounded-t ${colorClass}`}
          style={{ height: `${Math.max(4, (v / max) * 100)}%` }}
        />
      ))}
    </div>
  );
}

export default function LabelMonitoringPage() {
  const [metrics, setMetrics] = useState<any | null>(null);
  const [backendLatency, setBackendLatency] = useState<number | null>(null);
  const [frontendLatency, setFrontendLatency] = useState<number | null>(null);
  const [backendHistory, setBackendHistory] = useState<number[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const mountedRef = useRef(true);

  const fetchMetrics = useCallback(async () => {
    const t0 = performance.now();
    try {
      const data = await djangoClient.platformAdmin.getMonitoring();
      const t1 = performance.now();
      if (!mountedRef.current) return;
      const backendMs = Math.round(t1 - t0);
      setMetrics(data);
      setBackendLatency(backendMs);
      setBackendHistory((prev) => [...prev.slice(-(HISTORY_LENGTH - 1)), backendMs]);
      setError(null);
      setLastUpdated(new Date());
      requestAnimationFrame(() => {
        if (!mountedRef.current) return;
        setFrontendLatency(Math.round(performance.now() - t1));
      });
    } catch (err: any) {
      if (!mountedRef.current) return;
      setError(err.message || 'Erreur de connexion au serveur');
    }
  }, []);

  useEffect(() => {
    mountedRef.current = true;
    fetchMetrics();
    const interval = setInterval(fetchMetrics, POLL_INTERVAL_MS);
    return () => {
      mountedRef.current = false;
      clearInterval(interval);
    };
  }, [fetchMetrics]);

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight flex items-center gap-2">
            <Activity className="h-7 w-7 text-blue-600" />Monitoring
          </h1>
          <p className="text-muted-foreground mt-1 text-sm sm:text-base">
            Métriques serveur en temps réel (rafraîchi toutes les {POLL_INTERVAL_MS / 1000}s)
          </p>
        </div>
        {error ? (
          <Badge variant="outline" className="bg-red-50 text-red-700">Déconnecté</Badge>
        ) : (
          <Badge variant="outline" className="bg-green-50 text-green-700">
            En ligne{lastUpdated ? ` — ${lastUpdated.toLocaleTimeString('fr-FR')}` : ''}
          </Badge>
        )}
      </div>

      {error && (
        <Card className="border-red-200">
          <CardContent className="py-4 text-sm text-red-600">{error}</CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Cpu className="h-4 w-4 text-blue-500" />CPU
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{metrics ? `${metrics.cpu_percent.toFixed(1)}%` : '-'}</div>
            <Progress value={metrics?.cpu_percent ?? 0} className="mt-2" />
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <MemoryStick className="h-4 w-4 text-green-500" />RAM
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{metrics ? `${metrics.ram_percent.toFixed(1)}%` : '-'}</div>
            <Progress value={metrics?.ram_percent ?? 0} className="mt-2" />
            <p className="text-xs text-muted-foreground mt-1">
              {metrics ? `${formatBytes(metrics.ram_used)} / ${formatBytes(metrics.ram_total)}` : '-'}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <HardDrive className="h-4 w-4 text-orange-500" />Stockage
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{metrics ? `${metrics.disk_percent.toFixed(1)}%` : '-'}</div>
            <Progress value={metrics?.disk_percent ?? 0} className="mt-2" />
            <p className="text-xs text-muted-foreground mt-1">
              {metrics ? `${formatBytes(metrics.disk_used)} / ${formatBytes(metrics.disk_total)}` : '-'}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Database className="h-4 w-4 text-purple-500" />Base de données
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{formatBytes(metrics?.db_size_bytes)}</div>
            <p className="text-xs text-muted-foreground mt-1">Taille du fichier SQLite</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Zap className="h-4 w-4 text-yellow-500" />Latence backend
            </CardTitle>
            <CardDescription>Aller-retour de la requête de monitoring</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{backendLatency !== null ? `${backendLatency} ms` : '-'}</div>
            <div className="mt-2">
              <Sparkline values={backendHistory} colorClass="bg-yellow-500/60" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <MonitorSmartphone className="h-4 w-4 text-cyan-500" />Latence frontend
            </CardTitle>
            <CardDescription>Temps de rendu après réception des données</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{frontendLatency !== null ? `${frontendLatency} ms` : '-'}</div>
            <p className="text-xs text-muted-foreground mt-1">
              Mesure approximative (temps entre réponse reçue et rendu React)
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
