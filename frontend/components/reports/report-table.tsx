'use client';

import { useMemo, useState, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AlertCircle, ChevronLeft, ChevronRight, Download } from 'lucide-react';
import { exporterExcel } from './export';

export interface Colonne<T> {
  key: string;
  label: string;
  align?: 'left' | 'right' | 'center';
  /** Rendu de la cellule ; par défaut la valeur brute. */
  render?: (row: T, index: number) => ReactNode;
  /** Valeur exportée (Excel) ; par défaut row[key]. */
  export?: (row: T) => string | number | null | undefined;
  className?: string;
}

/**
 * Tableau de rapport : états chargement / erreur / vide, défilement
 * horizontal sur mobile, pagination côté client et export Excel.
 */
export function ReportTable<T>({
  titre,
  description,
  colonnes,
  lignes,
  loading,
  error,
  vide = 'Aucune donnée sur la période.',
  pageSize = 15,
  rowKey,
  exportNom,
  actions,
  compact,
}: {
  titre?: string;
  description?: ReactNode;
  colonnes: Colonne<T>[];
  lignes: T[] | null | undefined;
  loading?: boolean;
  error?: string | null;
  vide?: string;
  pageSize?: number;
  rowKey?: (row: T, index: number) => string | number;
  exportNom?: string;
  actions?: ReactNode;
  compact?: boolean;
}) {
  const [page, setPage] = useState(0);
  const total = lignes?.length ?? 0;
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const pageCourante = Math.min(page, pages - 1);
  const visibles = useMemo(
    () => (lignes ?? []).slice(pageCourante * pageSize, (pageCourante + 1) * pageSize),
    [lignes, pageCourante, pageSize],
  );

  const exporter = () => {
    if (!lignes?.length) return;
    const rows = lignes.map((row) => {
      const o: Record<string, unknown> = {};
      for (const c of colonnes) {
        o[c.label] = c.export ? c.export(row) : (row as Record<string, unknown>)[c.key];
      }
      return o;
    });
    exporterExcel([{ nom: (titre || exportNom || 'Rapport').slice(0, 30), lignes: rows }], exportNom || titre || 'rapport');
  };

  const align = (a?: string) => (a === 'right' ? 'text-right' : a === 'center' ? 'text-center' : '');

  const corps = () => {
    if (loading) {
      return (
        <div className="p-4 space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-8 w-full" />
          ))}
        </div>
      );
    }
    if (error) {
      return (
        <div className="flex items-center gap-2 p-6 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      );
    }
    if (!total) {
      return <p className="text-sm text-muted-foreground text-center py-8">{vide}</p>;
    }
    return (
      <div className="overflow-x-auto">
        <Table className={compact ? 'text-xs' : 'text-sm'}>
          <TableHeader>
            <TableRow>
              {colonnes.map((c) => (
                <TableHead key={c.key} className={`whitespace-nowrap ${align(c.align)} ${c.className || ''}`}>
                  {c.label}
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {visibles.map((row, i) => {
              const index = pageCourante * pageSize + i;
              return (
                <TableRow key={rowKey ? rowKey(row, index) : index}>
                  {colonnes.map((c) => (
                    <TableCell key={c.key} className={`${align(c.align)} ${c.className || ''}`}>
                      {c.render ? c.render(row, index) : String((row as Record<string, unknown>)[c.key] ?? '')}
                    </TableCell>
                  ))}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
    );
  };

  return (
    <Card className="print:break-inside-avoid">
      {(titre || actions || exportNom) && (
        <CardHeader className="flex flex-row items-start justify-between gap-2 space-y-0 pb-3">
          <div className="min-w-0">
            {titre && <CardTitle className="text-base">{titre}</CardTitle>}
            {description && <CardDescription className="text-xs mt-0.5">{description}</CardDescription>}
          </div>
          <div className="flex items-center gap-1 shrink-0 print:hidden">
            {actions}
            {exportNom && (
              <Button variant="ghost" size="sm" className="h-8 px-2" onClick={exporter} disabled={!total} aria-label="Exporter en Excel">
                <Download className="h-4 w-4" />
              </Button>
            )}
          </div>
        </CardHeader>
      )}
      <CardContent className="p-0">
        {corps()}
        {!loading && !error && pages > 1 && (
          <div className="flex items-center justify-between gap-2 px-4 py-2 border-t text-xs text-muted-foreground print:hidden">
            <span>
              {pageCourante * pageSize + 1}–{Math.min(total, (pageCourante + 1) * pageSize)} sur {total}
            </span>
            <div className="flex items-center gap-1">
              <Button variant="outline" size="icon" className="h-7 w-7" disabled={pageCourante === 0} onClick={() => setPage(pageCourante - 1)} aria-label="Page précédente">
                <ChevronLeft className="h-4 w-4" />
              </Button>
              <span className="px-1">
                {pageCourante + 1}/{pages}
              </span>
              <Button variant="outline" size="icon" className="h-7 w-7" disabled={pageCourante >= pages - 1} onClick={() => setPage(pageCourante + 1)} aria-label="Page suivante">
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
