'use client';

import { createContext, useContext } from 'react';
import type { Period } from '@/lib/reports';
import type { Filtres } from '@/components/reports/report-filters';
import type { ReportParams } from '@/components/reports/use-report';

/**
 * Filtres du centre de rapports, portés par app/(app)/dashboard/layout.tsx
 * et partagés avec chaque page de rapport (/dashboard, /dashboard/sales…).
 * Le layout reste monté quand on change d'onglet : seul le contenu de la
 * page change, comme pour le sidebar (§ demande).
 */
export interface ReportsContextValue {
  filtres: Filtres;
  period: Period;
  /** Paramètres communs envoyés à chaque section (clé de cache). */
  params: ReportParams;
}

const ReportsContext = createContext<ReportsContextValue | null>(null);

export const ReportsProvider = ReportsContext.Provider;

export function useReportsParams(): ReportsContextValue {
  const ctx = useContext(ReportsContext);
  if (!ctx) {
    throw new Error('useReportsParams doit être utilisé sous app/(app)/dashboard/layout.tsx');
  }
  return ctx;
}
