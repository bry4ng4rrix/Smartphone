"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

/**
 * Favoris — fonctionnalité 100 % frontend : la liste d'identifiants produit
 * vit dans le localStorage du navigateur, l'API n'en sait rien. Les fiches
 * sont rechargées depuis `/produit/{id}/` à l'affichage, donc jamais périmées.
 */
const CLE = "smg_client_favoris";

type WishlistApi = {
  ids: number[];
  pret: boolean;
  estFavori: (id: number) => boolean;
  basculer: (id: number) => boolean;
  retirer: (id: number) => void;
};

const WishlistContext = createContext<WishlistApi | null>(null);

function lire(): number[] {
  try {
    const brut = localStorage.getItem(CLE);
    const data: unknown = brut ? JSON.parse(brut) : [];
    return Array.isArray(data) ? data.filter((n): n is number => typeof n === "number") : [];
  } catch {
    return [];
  }
}

export function WishlistProvider({ children }: { children: React.ReactNode }) {
  const [ids, setIds] = useState<number[]>([]);
  const [pret, setPret] = useState(false);

  useEffect(() => {
    setIds(lire());
    setPret(true);
  }, []);

  useEffect(() => {
    if (!pret) return;
    try {
      localStorage.setItem(CLE, JSON.stringify(ids));
    } catch {
      /* ignore */
    }
  }, [ids, pret]);

  const basculer = useCallback((id: number) => {
    let ajoute = false;
    setIds((actuels) => {
      ajoute = !actuels.includes(id);
      return ajoute ? [...actuels, id] : actuels.filter((x) => x !== id);
    });
    return ajoute;
  }, []);

  const valeur = useMemo<WishlistApi>(
    () => ({
      ids,
      pret,
      estFavori: (id) => ids.includes(id),
      basculer,
      retirer: (id) => setIds((a) => a.filter((x) => x !== id)),
    }),
    [ids, pret, basculer],
  );

  return <WishlistContext.Provider value={valeur}>{children}</WishlistContext.Provider>;
}

export function useWishlist(): WishlistApi {
  const ctx = useContext(WishlistContext);
  if (!ctx) throw new Error("useWishlist doit être utilisé dans <WishlistProvider>");
  return ctx;
}
