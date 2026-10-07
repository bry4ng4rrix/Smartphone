'use client';

import { useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { SECTIONS, type Section } from '@/lib/reports';
import { ReportSection } from '@/components/reports/section-router';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';

/**
 * /dashboard/<section> : une page par rapport (sales, financial, expenses,
 * stock, orders, deliveries, marketing). Le layout parent (onglets, filtres)
 * reste monté : seul ce contenu change d'une page à l'autre.
 */
export default function DashboardSectionPage() {
  const router = useRouter();
  const { section } = useParams<{ section: string }>();
  const { isMagasin, loading } = useCurrentUser();
  const valide = SECTIONS.some((s) => s.key === section);

  useEffect(() => {
    if (loading) return;
    // Les rapports chiffrés sont réservés à l'admin global : un gérant qui
    // tape l'URL à la main revient à son tableau de bord. L'API refuserait
    // de toute façon (403) — ceci évite seulement un écran d'erreur.
    if (isMagasin) {
      router.replace('/dashboard');
      return;
    }
    // Clé inconnue ou « overview » (dont l'URL canonique est /dashboard).
    if (!valide || section === 'overview') router.replace('/dashboard');
  }, [valide, section, router, isMagasin, loading]);

  if (loading || isMagasin) return null;
  if (!valide || section === 'overview') return null;
  return <ReportSection section={section as Section} />;
}
