'use client';

import { Suspense, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { SECTIONS } from '@/lib/reports';
import { ReportSection } from '@/components/reports/section-router';

/**
 * /dashboard = rapport « Vue générale ». Les autres rapports sont des pages
 * sœurs (/dashboard/sales, /dashboard/financial…) sous le même layout — voir
 * app/(app)/dashboard/layout.tsx. Les anciens liens `/dashboard?tab=…` sont
 * redirigés vers la page correspondante.
 */
export default function DashboardPage() {
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
