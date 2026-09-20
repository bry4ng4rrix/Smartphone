/**
 * Petit magasin persistant (localStorage) consommé par `useSyncExternalStore` :
 * pas de `setState` dans un effet, pas de flash au montage, et la
 * synchronisation entre onglets vient gratuitement de l'événement `storage`.
 */
export type Store<T> = {
  get: () => T;
  /** Instantané stable rendu côté serveur (et au premier rendu client). */
  getServer: () => T;
  set: (maj: T | ((actuel: T) => T)) => void;
  subscribe: (ecouteur: () => void) => () => void;
};

export function creerStorePersistant<T>(cle: string, vide: T, valider: (donnees: unknown) => T | null): Store<T> {
  let cache: T = vide;
  let charge = false;
  const ecouteurs = new Set<() => void>();

  const lireDisque = (): T => {
    try {
      const brut = localStorage.getItem(cle);
      if (!brut) return vide;
      return valider(JSON.parse(brut)) ?? vide;
    } catch {
      return vide;
    }
  };

  const notifier = () => ecouteurs.forEach((e) => e());

  const get = (): T => {
    if (typeof window === "undefined") return vide;
    if (!charge) {
      cache = lireDisque();
      charge = true;
    }
    return cache;
  };

  return {
    get,
    getServer: () => vide,
    set: (maj) => {
      const suivant = typeof maj === "function" ? (maj as (actuel: T) => T)(get()) : maj;
      cache = suivant;
      charge = true;
      try {
        localStorage.setItem(cle, JSON.stringify(suivant));
      } catch {
        /* stockage indisponible : la valeur reste en mémoire pour la session */
      }
      notifier();
    },
    subscribe: (ecouteur) => {
      ecouteurs.add(ecouteur);
      const surStorage = (e: StorageEvent) => {
        if (e.key !== cle) return;
        cache = lireDisque();
        charge = true;
        notifier();
      };
      window.addEventListener("storage", surStorage);
      return () => {
        ecouteurs.delete(ecouteur);
        window.removeEventListener("storage", surStorage);
      };
    },
  };
}
