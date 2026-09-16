'use client';

import type { Section } from '@/lib/reports';
import { useReportsParams } from '@/components/reports/reports-context';
import { SectionOverview } from '@/components/reports/section-overview';
import { SectionSales } from '@/components/reports/section-sales';
import { SectionFinancial } from '@/components/reports/section-financial';
import { SectionExpenses } from '@/components/reports/section-expenses';
import { SectionStock } from '@/components/reports/section-stock';
import { SectionOrders } from '@/components/reports/section-orders';
import { SectionDeliveries } from '@/components/reports/section-deliveries';
import { SectionMarketing } from '@/components/reports/section-marketing';

/** Contenu d'une page de rapport : la section demandée, avec les filtres du layout. */
export function ReportSection({ section }: { section: Section }) {
  const { params } = useReportsParams();
  switch (section) {
    case 'sales':
      return <SectionSales params={params} enabled />;
    case 'financial':
      return <SectionFinancial params={params} enabled />;
    case 'expenses':
      return <SectionExpenses params={params} enabled />;
    case 'stock':
      return <SectionStock params={params} enabled />;
    case 'orders':
      return <SectionOrders params={params} enabled />;
    case 'deliveries':
      return <SectionDeliveries params={params} enabled />;
    case 'marketing':
      return <SectionMarketing params={params} enabled />;
    case 'overview':
    default:
      return <SectionOverview params={params} enabled />;
  }
}
