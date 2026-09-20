"use client";

import { createContext, useCallback, useContext, useMemo, useSyncExternalStore } from "react";
import { creerStorePersistant } from "@/lib/store";

/**
 * Favoris — fonctionnalité 100 % frontend : la liste d'identifiants produit
 * vit dans le localStorage du navigateur, l'API n'en sait rien. Les fiches
 * sont rechargées depuis `/produit/{id}/` à l'affichage, donc jamais périmées.
 */
const VIDE: number[] = [];

const store = creerStorePersistant<number[]>("smg_client_favoris", VIDE, (donnees) =>
  Array.isArray(donnees) ? donnees.filter((n): n is number => typeof n === "number") : null,
);

type WishlistApi = {
  ids: number[];
  estFavori: (id: number) => boolean;
  /** Renvoie `true` si le produit vient d'être ajouté. */
  basculer: (id: number) => boolean;
  retirer: (id: number) => void;
};

const WishlistContext = createContext<WishlistApi | null>(null);

export function WishlistProvider({ children }: { children: React.ReactNode }) {
  const ids = useSyncExternalStore(store.subscribe, store.get, store.getServer);

  const basculer = useCallback((id: number) => {
    const ajoute = !store.get().includes(id);
    store.set((actuels) => (ajoute ? [...actuels, id] : actuels.filter((x) => x !== id)));
    return ajoute;
  }, []);

  const valeur = useMemo<WishlistApi>(
    () => ({
      ids,
      estFavori: (id) => ids.includes(id),
      basculer,
      retirer: (id) => store.set((a) => a.filter((x) => x !== id)),
    }),
    [ids, basculer],
  );

  return <WishlistContext.Provider value={valeur}>{children}</WishlistContext.Provider>;
}

export function useWishlist(): WishlistApi {
  const ctx = useContext(WishlistContext);
  if (!ctx) throw new Error("useWishlist doit être utilisé dans <WishlistProvider>");
  return ctx;
}
