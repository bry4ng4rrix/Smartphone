'use client';

import { useEffect, useRef } from 'react';
import { useDataSync, type DataModel } from '@/lib/contexts/DataSyncContext';

/**
 * Re-fetch data when relevant WebSocket events arrive.
 * Debounces rapid consecutive events (e.g. sale → product → movement).
 */
export function useRealtimeRefresh(
  models: DataModel[],
  onRefresh: () => void,
  options: { debounceMs?: number; silent?: boolean } = {},
) {
  const { subscribe } = useDataSync();
  const onRefreshRef = useRef(onRefresh);
  const modelsRef = useRef(models);
  const debounceRef = useRef<NodeJS.Timeout | null>(null);
  const { debounceMs = 400 } = options;

  useEffect(() => {
    onRefreshRef.current = onRefresh;
  }, [onRefresh]);

  useEffect(() => {
    modelsRef.current = models;
  }, [models]);

  useEffect(() => {
    const unsubscribe = subscribe((event) => {
      if (!modelsRef.current.includes(event.model)) return;

      if (debounceRef.current) clearTimeout(debounceRef.current);
      debounceRef.current = setTimeout(() => {
        onRefreshRef.current();
      }, debounceMs);
    });

    return () => {
      unsubscribe();
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [subscribe, debounceMs]);
}
