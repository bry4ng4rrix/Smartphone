'use client';

import { useEffect, useState } from 'react';

/**
 * Renvoie `value` avec un léger délai, pour découpler la saisie (toujours
 * instantanée) du filtrage/recalcul déclenché par cette valeur — évite de
 * refiltrer/re-render une liste à chaque frappe (recherche "saccadée").
 */
export function useDebouncedValue<T>(value: T, delayMs = 250): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(t);
  }, [value, delayMs]);

  return debounced;
}
