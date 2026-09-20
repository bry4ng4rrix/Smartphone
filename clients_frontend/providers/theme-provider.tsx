"use client";

import { createContext, useCallback, useContext, useMemo, useSyncExternalStore } from "react";
import { creerStorePersistant } from "@/lib/store";

/** Préférence visuelle claire/sombre — frontend uniquement, par navigateur. */
export type Theme = "clair" | "sombre";
const CLE = "smg_client_theme";

/** Script injecté avant le premier rendu : évite le flash de thème clair. */
export const SCRIPT_THEME = `(function(){try{var t=JSON.parse(localStorage.getItem("${CLE}")||'null');var sombre=t?t==="sombre":matchMedia("(prefers-color-scheme: dark)").matches;document.documentElement.classList.toggle("dark",sombre);document.documentElement.style.colorScheme=sombre?"dark":"light";}catch(e){}})();`;

const store = creerStorePersistant<Theme | null>(CLE, null, (donnees) =>
  donnees === "clair" || donnees === "sombre" ? donnees : null,
);

type ThemeApi = { theme: Theme; basculer: () => void };
const ThemeContext = createContext<ThemeApi | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const enregistre = useSyncExternalStore(store.subscribe, store.get, store.getServer);
  // Aucun choix mémorisé : on suit la préférence du système, comme le script.
  const systemeSombre = typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches;
  const theme: Theme = enregistre ?? (systemeSombre ? "sombre" : "clair");

  const basculer = useCallback(() => {
    const suivant: Theme = (store.get() ?? (window.matchMedia("(prefers-color-scheme: dark)").matches ? "sombre" : "clair")) === "sombre" ? "clair" : "sombre";
    document.documentElement.classList.toggle("dark", suivant === "sombre");
    document.documentElement.style.colorScheme = suivant === "sombre" ? "dark" : "light";
    store.set(suivant);
  }, []);

  const valeur = useMemo<ThemeApi>(() => ({ theme, basculer }), [theme, basculer]);
  return <ThemeContext.Provider value={valeur}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeApi {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme doit être utilisé dans <ThemeProvider>");
  return ctx;
}
