'use client';

import { Suspense, useCallback, useMemo, useState } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Printer } from 'lucide-react';
import {
  SECTIONS,
  granulariteAuto,
  periodeDepuisPreset,
  type Section,
} from '@/lib/reports';
import { ReportFilters, type Filtres } from '@/components/reports/report-filters';
import { ReportTabs } from '@/components/reports/report-tabs';
import { invalidateReports } from '@/components/reports/use-report';
import { SectionOverview } from '@/components/reports/section-overview';
import { SectionSales } from '@/components/reports/section-sales';
import { SectionFinancial } from '@/components/reports/section-financial';
import { SectionExpenses } from '@/components/reports/section-expenses';
import { SectionStock } from '@/components/reports/section-stock';
import { SectionOrders } from '@/components/reports/section-orders';
import { SectionDeliveries } from '@/components/reports/section-deliveries';
import { SectionMarketing } from '@/components/reports/section-marketing';

/**
 * Tableau de bord du gérant = le centre de rapports (§ demande : la page
 * Rapports remplace l'ancien tableau de bord, et /reports n'existe plus).
 * 8 rapports dans une seule page, un seul affiché à la fois (onglets / menu
 * « Liste des rapports » sur mobile), filtres de période communs, données
 * agrégées côté serveur (orders/reporting.py) et mises en cache par section.
 */
export default function DashboardPage() {
  return (
    <Suspense fallback={<div className="p-6"><Skeleton className="h-64 w-full" /></div>}>
      <ReportsCenter />
    </Suspense>
  );
}

const SECTION_KEYS = new Set<string>(SECTIONS.map((s) => s.key));

function ReportsCenter() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const tabUrl = searchParams.get('tab');
  const actif: Section = tabUrl && SECTION_KEYS.has(tabUrl) ? (tabUrl as Section) : 'overview';
  const changerOnglet = useCallback(
    (s: Section) => {
      const q = new URLSearchParams(searchParams.toString());
      q.set('tab', s);
      router.replace(`${pathname}?${q.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams],
  );

  const [filtres, setFiltres] = useState<Filtres>({
    preset: 'month',
    custom: { from: '', to: '' },
    granularity: 'auto',
  });
  const [rechargement, setRechargement] = useState(0);

  const period = useMemo(() => periodeDepuisPreset(filtres.preset, filtres.custom), [filtres.preset, filtres.custom]);
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

  const recharger = () => {
    invalidateReports();
    setRechargement((n) => n + 1);
  };

  if (userLoading) {
    return (
      <div className="p-4 sm:p-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-10 w-full" />
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

  const section = SECTIONS.find((s) => s.key === actif)!;

  return (
    <div className="p-4 sm:p-6 space-y-4 print:p-0">
      <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Tableau de bord</h1>
          <p className="text-sm text-muted-foreground">
            <span className="font-medium text-foreground">{section.label}</span> — {section.description}
          </p>
        </div>
        <Button variant="outline" size="sm" className="print:hidden self-start" onClick={() => window.print()}>
          <Printer className="h-4 w-4 mr-2" /> Imprimer / PDF
        </Button>
      </div>

      <ReportFilters filtres={filtres} period={period} onChange={setFiltres} onReload={recharger} />
      <ReportTabs actif={actif} onChange={changerOnglet} />

      <div className="hidden print:block text-xs text-muted-foreground">
        Période du {period.from} au {period.to} (comparée à {period.prevFrom} → {period.prevTo})
      </div>

      {/* Une seule section montée à la fois : rien n'est chargé pour les autres. */}
      {actif === 'overview' && <SectionOverview params={params} enabled />}
      {actif === 'sales' && <SectionSales params={params} enabled />}
      {actif === 'financial' && <SectionFinancial params={params} enabled />}
      {actif === 'expenses' && <SectionExpenses params={params} enabled />}
      {actif === 'stock' && <SectionStock params={params} enabled />}
      {actif === 'orders' && <SectionOrders params={params} enabled />}
      {actif === 'deliveries' && <SectionDeliveries params={params} enabled />}
      {actif === 'marketing' && <SectionMarketing params={params} enabled />}
    </div>
  );
}
