"use client";

import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight } from "lucide-react";

/**
 * Pagination côté client d'une liste déjà filtrée.
 *
 * La page courante est bornée à la volée : si la liste rétrécit (filtre,
 * suppression), on retombe sur la dernière page existante sans effet ni
 * état incohérent. `reset()` remet à la première page (à appeler quand les
 * filtres changent).
 */
export function usePagination<T>(items: T[], pageSize: number) {
  const [page, setPage] = useState(0);
  const total = items.length;
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const current = Math.min(page, pages - 1);
  const slice = useMemo(
    () => items.slice(current * pageSize, (current + 1) * pageSize),
    [items, current, pageSize],
  );
  return {
    slice,
    total,
    pages,
    page: current,
    pageSize,
    setPage,
    reset: () => setPage(0),
  };
}

/** Pied de tableau « 1–50 sur 312 · ‹ 1/7 › ». Ne s'affiche que s'il y a plus d'une page. */
export function TablePager({
  page,
  pages,
  total,
  pageSize,
  onPageChange,
}: {
  page: number;
  pages: number;
  total: number;
  pageSize: number;
  onPageChange: (page: number) => void;
}) {
  if (pages <= 1) return null;
  return (
    <div className="flex items-center justify-between gap-2 px-4 py-2 border-t text-xs text-muted-foreground print:hidden">
      <span>
        {page * pageSize + 1}–{Math.min(total, (page + 1) * pageSize)} sur {total}
      </span>
      <div className="flex items-center gap-1">
        <Button
          variant="outline"
          size="icon"
          className="h-8 w-8"
          disabled={page === 0}
          onClick={() => onPageChange(page - 1)}
          aria-label="Page précédente"
        >
          <ChevronLeft className="h-4 w-4" />
        </Button>
        <span className="px-1">
          {page + 1}/{pages}
        </span>
        <Button
          variant="outline"
          size="icon"
          className="h-8 w-8"
          disabled={page >= pages - 1}
          onClick={() => onPageChange(page + 1)}
          aria-label="Page suivante"
        >
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
