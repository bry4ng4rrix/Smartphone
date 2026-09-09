'use client';

import { useCallback, useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';

export interface DeliveryZoneOption {
  id: number;
  code: string;
  nom: string;
  prix: number;
  actif: boolean;
}

/**
 * Zones de livraison configurables (nom + prix), CRUD dans Paramètres
 * (§ demande) — voir orders/models.py::DeliveryZoneOption. Chaque composant
 * qui en a besoin (formulaires de commande, tableau, Paramètres) appelle ce
 * hook indépendamment ; la liste est petite et change rarement, un fetch par
 * montage reste largement suffisant.
 */
export function useDeliveryZones() {
  const [zones, setZones] = useState<DeliveryZoneOption[]>([]);
  const [loading, setLoading] = useState(true);

  const refetch = useCallback(() => {
    setLoading(true);
    return djangoClient.zones
      .list()
      .then(setZones)
      .catch(() => setZones([]))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { zones, loading, refetch };
}
