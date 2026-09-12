'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import type { Section } from '@/lib/reports';

export type ReportParams = Record<string, string | number | undefined | null>;

export interface ReportState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  reload: () => void;
}

// Cache mémoire par (section, paramètres) : revenir sur un onglet déjà
// consulté est instantané, et un changement de filtre ne recharge que la
// section affichée. Vidé au rechargement de la page.
const cache = new Map<string, unknown>();
const CACHE_MAX = 60;

function cle(section: Section, params: ReportParams) {
  return `${section}:${JSON.stringify(params)}`;
}

export function invalidateReports() {
  cache.clear();
}

/**
 * Charge une section du centre de rapports. `enabled` = false quand
 * l'onglet n'est pas affiché : rien n'est demandé au serveur.
 */
export function useReport<T>(section: Section, params: ReportParams, enabled = true): ReportState<T> {
  const k = cle(section, params);
  const [data, setData] = useState<T | null>(() => (cache.get(k) as T) ?? null);
  const [loading, setLoading] = useState(enabled && !cache.has(k));
  const [error, setError] = useState<string | null>(null);
  const version = useRef(0);

  const charger = useCallback(
    async (force = false) => {
      if (!enabled) return;
      const id = ++version.current;
      if (!force && cache.has(k)) {
        setData(cache.get(k) as T);
        setLoading(false);
        setError(null);
        return;
      }
      setLoading(true);
      setError(null);
      try {
        const res = await djangoClient.reports.section<T>(section, params);
        if (id !== version.current) return;
        if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value as string);
        cache.set(k, res);
        setData(res);
      } catch (e: unknown) {
        if (id !== version.current) return;
        setError((e as Error)?.message || 'Erreur de chargement');
      } finally {
        if (id === version.current) setLoading(false);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [k, section, enabled],
  );

  useEffect(() => {
    charger();
  }, [charger]);

  // Une commande ou un mouvement de stock modifié ailleurs : on invalide tout
  // et on recharge silencieusement la section affichée.
  useRealtimeRefresh(['order', 'order_status_history', 'stock_movement', 'caisse_movement'], () => {
    cache.clear();
    if (enabled) charger(true);
  });

  return { data, loading, error, reload: () => charger(true) };
}
