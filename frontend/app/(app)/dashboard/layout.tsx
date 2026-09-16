'use client';

import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Printer } from 'lucide-react';
import { SECTIONS, granulariteAuto, periodeDepuisPreset, sectionDepuisPathname, sectionHref } from '@/lib/reports';
import { ReportFilters, type Filtres } from '@/components/reports/report-filters';
import { ReportTabs } from '@/components/reports/report-tabs';
import { invalidateReports } from '@/components/reports/use-report';
import { ReportsProvider } from '@/components/reports/reports-context';

/**
 * Tableau de bord du gérant = le centre de rapports (§ demande : la page
 * Rapports remplace l'ancien tableau de bord). Chaque rapport est une PAGE
 * (/dashboard, /dashboard/sales, /dashboard/financial…) et ce layout — onglets,
 * filtres de période, bouton d'impression — reste monté d'une page à l'autre :
 * comme pour le sidebar, seul le contenu du rapport se charge, les filtres et
 * le cache des sections sont conservés (§ demande « plus fluide »).
 */
export default function DashboardLayout({ children }: { children: ReactNode }) {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const router = useRouter();
  const pathname = usePathname();
  const actif = sectionDepuisPathname(pathname);

  const [filtres, setFiltres] = useState<Filtres>({ preset: 'month', date: '', granularity: 'auto' });
  const [rechargement, setRechargement] = useState(0);

  const period = useMemo(() => periodeDepuisPreset(filtres.preset, filtres.date || undefined), [filtres.preset, filtres.date]);
  const granularity = filtres.granularity === 'auto' ? granulariteAuto(period) : filtres.granularity;

  // Paramètres communs à toutes les sections — même clé de cache tant
  // qu'ils ne changent pas. `_r` force un rechargement manuel.
  const params = useMemo(
    () => ({
      date_from: period.from,
      date_to: period.to,
      prev_from: period.prevFrom,
      prev_to: period.prevTo,
      granularity,
      _r: rechargement || undefined,
    }),
    [period, granularity, rechargement],
  );
  const value = useMemo(() => ({ filtres, period, params }), [filtres, period, params]);

  // Les 8 pages sont pré-chargées dès l'arrivée : le passage d'un rapport à
  // l'autre est immédiat (seul l'appel API de la section reste à faire).
  useEffect(() => {
    if (!isGerant) return;
    for (const s of SECTIONS) router.prefetch(sectionHref(s.key));
  }, [isGerant, router]);

  const recharger = () => {
    invalidateReports();
    setRechargement((n) => n + 1);
  };

  if (userLoading) {
    return (
      <div className="p-4 sm:p-6 space-y-4">
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (!isGerant) {
    return (
      <div className="p-6">
        <h1 className="text-2xl font-bold">Tableau de bord</h1>
        <p className="text-sm text-muted-foreground mt-2">Accès refusé — le tableau de bord est réservé au gérant.</p>
      </div>
    );
  }

  return (
    <ReportsProvider value={value}>
      <div className="p-4 sm:p-6 space-y-4 print:p-0">
        {/* Onglets des rapports tout en haut de la page (§ demande) : chaque
            onglet est un lien vers sa page. */}
        <ReportTabs actif={actif} onChange={(s) => router.push(sectionHref(s))} />

        {/* Pas de titre ni de sous-titre (§ demande) : filtres et bouton
            d'impression sur la même ligne. */}
        <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-3">
          <div className="min-w-0 flex-1">
            <ReportFilters filtres={filtres} period={period} onChange={setFiltres} onReload={recharger} />
          </div>
          <Button variant="outline" size="sm" className="print:hidden self-start sm:self-end h-9" onClick={() => window.print()}>
            <Printer className="h-4 w-4 mr-2" /> Imprimer / PDF
          </Button>
        </div>

        <div className="hidden print:block text-xs text-muted-foreground">
          {SECTIONS.find((s) => s.key === actif)?.label} — Période du {period.from} au {period.to} (comparée à {period.prevFrom} → {period.prevTo})
        </div>

        {children}
      </div>
    </ReportsProvider>
  );
}
