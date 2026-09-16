'use client';

import { useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { SECTIONS, type Section } from '@/lib/reports';
import { ReportSection } from '@/components/reports/section-router';

/**
 * /dashboard/<section> : une page par rapport (sales, financial, expenses,
 * stock, orders, deliveries, marketing). Le layout parent (onglets, filtres)
 * reste monté : seul ce contenu change d'une page à l'autre.
 */
export default function DashboardSectionPage() {
  const router = useRouter();
  const { section } = useParams<{ section: string }>();
  const valide = SECTIONS.some((s) => s.key === section);

  useEffect(() => {
    // Clé inconnue ou « overview » (dont l'URL canonique est /dashboard).
    if (!valide || section === 'overview') router.replace('/dashboard');
  }, [valide, section, router]);

  if (!valide || section === 'overview') return null;
  return <ReportSection section={section as Section} />;
}
