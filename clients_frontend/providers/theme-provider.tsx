"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

/** Préférence visuelle claire/sombre — frontend uniquement, mémorisée par navigateur. */
export type Theme = "clair" | "sombre";
const CLE = "smg_client_theme";

type ThemeApi = { theme: Theme; basculer: () => void; pret: boolean };
const ThemeContext = createContext<ThemeApi | null>(null);

/** Script injecté avant le premier rendu : évite le flash de thème clair. */
export const SCRIPT_THEME = `(function(){try{var t=localStorage.getItem("${CLE}");var sombre=t?t==="sombre":matchMedia("(prefers-color-scheme: dark)").matches;document.documentElement.classList.toggle("dark",sombre);document.documentElement.style.colorScheme=sombre?"dark":"light";}catch(e){}})();`;

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>("clair");
  const [pret, setPret] = useState(false);

  useEffect(() => {
    setTheme(document.documentElement.classList.contains("dark") ? "sombre" : "clair");
    setPret(true);
  }, []);

  const basculer = useCallback(() => {
    setTheme((actuel) => {
      const suivant: Theme = actuel === "sombre" ? "clair" : "sombre";
      document.documentElement.classList.toggle("dark", suivant === "sombre");
      document.documentElement.style.colorScheme = suivant === "sombre" ? "dark" : "light";
      try {
        localStorage.setItem(CLE, suivant);
      } catch {
        /* ignore */
      }
      return suivant;
    });
  }, []);

  const valeur = useMemo<ThemeApi>(() => ({ theme, basculer, pret }), [theme, basculer, pret]);
  return <ThemeContext.Provider value={valeur}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeApi {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme doit être utilisé dans <ThemeProvider>");
  return ctx;
}
