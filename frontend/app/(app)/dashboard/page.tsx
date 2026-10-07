'use client';

import { Suspense, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { SECTIONS } from '@/lib/reports';
import { ReportSection } from '@/components/reports/section-router';
import { DashboardGerant } from '@/components/dashboard/dashboard-gerant';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';

/**
 * Deux tableaux de bord derrière la même route (mission § 25) :
 *
 *  - ADMIN GLOBAL : /dashboard = rapport « Vue générale », les 7 autres sont
 *    des pages sœurs sous le layout de rapports.
 *  - GÉRANT DE MAGASIN : tableau de bord d'exploitation de sa boutique, sans
 *    bénéfice, marge ni coût. L'API qui l'alimente n'en renvoie aucun.
 */
export default function DashboardPage() {
  const { isMagasin, loading } = useCurrentUser();

  if (loading) return null;
  if (isMagasin) return <DashboardGerant />;

  return (
    <Suspense fallback={null}>
      <RedirectionAncienOnglet />
      <ReportSection section="overview" />
    </Suspense>
  );
}

function RedirectionAncienOnglet() {
  const router = useRouter();
  const tab = useSearchParams().get('tab');
  useEffect(() => {
    if (tab && tab !== 'overview' && SECTIONS.some((s) => s.key === tab)) router.replace(`/dashboard/${tab}`);
  }, [tab, router]);
  return null;
}
