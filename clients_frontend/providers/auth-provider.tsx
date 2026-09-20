"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { clearTokens, LOGOUT_EVENT, setTokens } from "@/lib/api";
import { compte } from "@/lib/endpoints";
import type { ClientProfil } from "@/lib/types";

type Statut = "chargement" | "connecte" | "anonyme";

type AuthApi = {
  statut: Statut;
  client: ClientProfil | null;
  connexion: (email: string, password: string) => Promise<ClientProfil>;
  inscription: (data: { email: string; password: string; nom: string; telephone: string; adresse?: string }) => Promise<ClientProfil>;
  deconnexion: () => void;
  appliquerProfil: (profil: ClientProfil) => void;
};

const AuthContext = createContext<AuthApi | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [statut, setStatut] = useState<Statut>("chargement");
  const [client, setClient] = useState<ClientProfil | null>(null);

  // Session restaurée au chargement : le jeton stocké est validé par un
  // appel réel (`/client/me/`), qui déclenche au besoin le refresh.
  useEffect(() => {
    let annule = false;
    (async () => {
      try {
        const profil = await compte.moi();
        if (!annule) {
          setClient(profil);
          setStatut("connecte");
        }
      } catch {
        if (!annule) {
          setClient(null);
          setStatut("anonyme");
        }
      }
    })();
    return () => {
      annule = true;
    };
  }, []);

  // Émis par lib/api.ts quand le refresh échoue : la session est morte.
  useEffect(() => {
    const surDeconnexion = () => {
      setClient(null);
      setStatut("anonyme");
    };
    window.addEventListener(LOGOUT_EVENT, surDeconnexion);
    return () => window.removeEventListener(LOGOUT_EVENT, surDeconnexion);
  }, []);

  const connexion = useCallback(async (email: string, password: string) => {
    const reponse = await compte.connexion({ email, password });
    setTokens({ access: reponse.access, refresh: reponse.refresh });
    setClient(reponse.client);
    setStatut("connecte");
    return reponse.client;
  }, []);

  const inscription = useCallback<AuthApi["inscription"]>(async (data) => {
    const reponse = await compte.inscription(data);
    setTokens({ access: reponse.access, refresh: reponse.refresh });
    setClient(reponse.client);
    setStatut("connecte");
    return reponse.client;
  }, []);

  const deconnexion = useCallback(() => {
    clearTokens();
    setClient(null);
    setStatut("anonyme");
  }, []);

  const valeur = useMemo<AuthApi>(
    () => ({ statut, client, connexion, inscription, deconnexion, appliquerProfil: setClient }),
    [statut, client, connexion, inscription, deconnexion],
  );

  return <AuthContext.Provider value={valeur}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthApi {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth doit être utilisé dans <AuthProvider>");
  return ctx;
}
