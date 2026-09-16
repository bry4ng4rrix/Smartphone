'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { appToday } from '@/lib/timezone';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';

/**
 * Badge « Bilan du jour » du menu du gérant (§ demande, sur le modèle du
 * badge « Chats ») : nombre de MOUVEMENTS faits sur le bilan par les
 * livreurs depuis la dernière ouverture de la page — chaque passage
 * « Livré » ou « Retour » d'une commande du jour compte pour un.
 *
 * La page Bilan n'a pas de compteur serveur : on relit les commandes du jour
 * (même requête que la page, `date_debut = date_fin = aujourd'hui`) et l'on
 * compte les entrées d'historique LIVRE / RETOUR postérieures au dernier
 * « vu ». Le « vu » est mémorisé sur cet appareil (localStorage, par
 * compte) : ouvrir /bilan remet le compteur à 0, et il reste à 0 tant que la
 * page est affichée.
 *
 * Relu toutes les 30 s, à chaque changement de page et à chaque événement
 * temps réel sur les commandes.
 */
export const STATUTS_MOUVEMENT_BILAN = new Set(['LIVRE', 'RETOUR']);

const cleVu = (userId: number | string | null | undefined) => `bilan_vu_at:${userId ?? 'anonyme'}`;

function lireVu(userId: number | string | null | undefined): number {
  try {
    const v = window.localStorage.getItem(cleVu(userId));
    return v ? Number(v) || 0 : 0;
  } catch {
    return 0;
  }
}

function ecrireVu(userId: number | string | null | undefined, instant: number) {
  try {
    window.localStorage.setItem(cleVu(userId), String(instant));
  } catch {
    /* stockage indisponible : le badge se comporte comme « jamais vu » */
  }
}

/** Nombre de mouvements LIVRE / RETOUR postérieurs à `depuis` (ms). */
export function compterMouvementsBilan(orders: any[], depuis: number): number {
  let n = 0;
  for (const o of orders) {
    for (const h of o?.status_history ?? []) {
      if (!STATUTS_MOUVEMENT_BILAN.has(h?.nouveau_statut)) continue;
      const t = h?.timestamp ? new Date(h.timestamp).getTime() : 0;
      if (t > depuis) n += 1;
    }
  }
  return n;
}

export function useBilanMouvements(opts: {
  actif: boolean;
  userId: number | string | null | undefined;
  /** Vrai quand la page Bilan est affichée : tout est alors marqué vu. */
  surLaPage: boolean;
}) {
  const { actif, userId, surLaPage } = opts;
  const [count, setCount] = useState(0);
  const surLaPageRef = useRef(surLaPage);
  surLaPageRef.current = surLaPage;

  const refresh = useCallback(async () => {
    if (!actif || !djangoClient.isAuthenticated()) return;
    try {
      const jour = appToday();
      const orders = await djangoClient.orders.list({ date_debut: jour, date_fin: jour } as any);
      if (surLaPageRef.current) {
        // Le gérant regarde le bilan : tout ce qui est arrivé est vu.
        ecrireVu(userId, Date.now());
        setCount(0);
        return;
      }
      setCount(compterMouvementsBilan(orders, lireVu(userId)));
    } catch {
      /* comme le badge Chats : une erreur ne fait pas disparaître la valeur */
    }
  }, [actif, userId]);

  // Ouverture de la page Bilan : remise à zéro immédiate, sans attendre la
  // requête.
  useEffect(() => {
    if (!actif) return;
    if (surLaPage) {
      ecrireVu(userId, Date.now());
      setCount(0);
    }
  }, [actif, surLaPage, userId]);

  useEffect(() => {
    if (!actif) {
      setCount(0);
      return;
    }
    refresh();
    const id = setInterval(refresh, 30000);
    return () => clearInterval(id);
  }, [actif, refresh, surLaPage]);

  useRealtimeRefresh(['order', 'order_status_history'], refresh, { silent: true });

  return count;
}
