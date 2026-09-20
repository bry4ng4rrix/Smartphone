/**
 * Couche d'accès à l'API client (`client_endpoint.md`).
 *
 * Deux contextes, une seule fonction :
 * - Server Component / build : appel direct à Django (`DJANGO_ORIGIN`), pas
 *   de CORS, pas de jeton (seul le catalogue public est lu côté serveur) ;
 * - navigateur : appel same-origin `/backend/...`, réécrit vers Django par
 *   next.config.ts — l'API n'autorise pas l'origine du front dans ses
 *   en-têtes CORS, et on ne touche pas au backend.
 *
 * Jetons : `access` court + `refresh`. Sur 401, un seul refresh est lancé
 * (les requêtes concurrentes attendent le même), puis la requête est rejouée.
 * Si le refresh échoue, les jetons sont effacés et `auth:logout` est émis.
 */
import type { Tokens } from "./types";

const DJANGO_ORIGIN = process.env.DJANGO_ORIGIN ?? "http://localhost:8010";

export const ACCESS_KEY = "smg_client_access";
export const REFRESH_KEY = "smg_client_refresh";
export const LOGOUT_EVENT = "smg:auth-logout";

const estNavigateur = () => typeof window !== "undefined";

function baseUrl(): string {
  return estNavigateur() ? "/backend" : `${DJANGO_ORIGIN}/api`;
}

/** Les URLs de média renvoyées par Django sont absolues : on les ramène en
 *  same-origin pour passer par le rewrite `/media/...` (et rester valides
 *  quel que soit l'hôte du backend). */
export function mediaUrl(url: string | null | undefined): string | null {
  if (!url) return null;
  if (url.startsWith("/")) return url;
  try {
    const u = new URL(url);
    return `${u.pathname}${u.search}`;
  } catch {
    return url;
  }
}

export function getTokens(): Partial<Tokens> {
  if (!estNavigateur()) return {};
  try {
    return {
      access: localStorage.getItem(ACCESS_KEY) ?? undefined,
      refresh: localStorage.getItem(REFRESH_KEY) ?? undefined,
    };
  } catch {
    return {};
  }
}

export function setTokens(tokens: Partial<Tokens>) {
  if (!estNavigateur()) return;
  try {
    if (tokens.access) localStorage.setItem(ACCESS_KEY, tokens.access);
    if (tokens.refresh) localStorage.setItem(REFRESH_KEY, tokens.refresh);
  } catch {
    /* mode privé / stockage bloqué : la session ne survivra pas au rechargement */
  }
}

export function clearTokens() {
  if (!estNavigateur()) return;
  try {
    localStorage.removeItem(ACCESS_KEY);
    localStorage.removeItem(REFRESH_KEY);
  } catch {
    /* ignore */
  }
}

/** Erreur API : garde le statut, les messages par champ et un message prêt à afficher. */
export class ApiError extends Error {
  readonly status: number;
  readonly champs: Record<string, string[]>;

  constructor(status: number, champs: Record<string, string[]>, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.champs = champs;
  }

  /** Messages d'un champ précis (`telephone`, `items`…). */
  pour(champ: string): string[] {
    return this.champs[champ] ?? [];
  }

  get estHorsLigne() {
    return this.status === 0;
  }
}

function messagesDepuis(corps: unknown): { champs: Record<string, string[]>; message: string } {
  const champs: Record<string, string[]> = {};
  const plats: string[] = [];

  const pousser = (cle: string, valeur: unknown) => {
    const liste = Array.isArray(valeur) ? valeur.map(String) : [String(valeur)];
    champs[cle] = liste;
    plats.push(...liste);
  };

  if (typeof corps === "string") {
    plats.push(corps);
  } else if (Array.isArray(corps)) {
    plats.push(...corps.map(String));
  } else if (corps && typeof corps === "object") {
    for (const [cle, valeur] of Object.entries(corps as Record<string, unknown>)) {
      if (valeur && typeof valeur === "object" && !Array.isArray(valeur)) {
        pousser(cle, JSON.stringify(valeur));
      } else {
        pousser(cle, valeur);
      }
    }
  }

  return { champs, message: plats.filter(Boolean).join("\n") || "Une erreur est survenue." };
}

let refreshEnCours: Promise<string | null> | null = null;

async function rafraichir(): Promise<string | null> {
  const { refresh } = getTokens();
  if (!refresh) return null;
  if (!refreshEnCours) {
    refreshEnCours = (async () => {
      try {
        const res = await fetch(`${baseUrl()}/client/refresh/`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refresh }),
        });
        if (!res.ok) return null;
        const data = (await res.json()) as { access?: string };
        if (!data.access) return null;
        setTokens({ access: data.access });
        return data.access;
      } catch {
        return null;
      } finally {
        // Laisse la micro-tâche courante lire le résultat avant de réarmer.
        setTimeout(() => {
          refreshEnCours = null;
        }, 0);
      }
    })();
  }
  return refreshEnCours;
}

function deconnecter() {
  clearTokens();
  if (estNavigateur()) window.dispatchEvent(new CustomEvent(LOGOUT_EVENT));
}

export type RequeteOptions = {
  method?: "GET" | "POST" | "PATCH" | "DELETE";
  body?: unknown;
  /** Joint le jeton d'accès et gère le refresh automatique. */
  auth?: boolean;
  params?: Record<string, string | number | boolean | undefined | null>;
  signal?: AbortSignal;
  /** Cache Next côté serveur (catalogue public). */
  revalidate?: number;
};

export async function api<T>(chemin: string, options: RequeteOptions = {}): Promise<T> {
  const { method = "GET", body, auth = false, params, signal, revalidate } = options;

  const url = new URL(`${baseUrl()}${chemin}`, estNavigateur() ? window.location.origin : DJANGO_ORIGIN);
  if (params) {
    for (const [cle, valeur] of Object.entries(params)) {
      if (valeur !== undefined && valeur !== null && valeur !== "") url.searchParams.set(cle, String(valeur));
    }
  }

  const envoyer = async (jeton?: string) => {
    const headers: Record<string, string> = {};
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (jeton) headers.Authorization = `Bearer ${jeton}`;
    return fetch(url.toString(), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
      ...(estNavigateur() ? {} : { next: { revalidate: revalidate ?? 0 } }),
    });
  };

  let reponse: Response;
  try {
    reponse = await envoyer(auth ? getTokens().access : undefined);
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") throw e;
    throw new ApiError(0, {}, "Impossible de joindre le serveur. Vérifiez votre connexion.");
  }

  if (reponse.status === 401 && auth) {
    const nouveau = await rafraichir();
    if (!nouveau) {
      deconnecter();
      throw new ApiError(401, {}, "Votre session a expiré. Reconnectez-vous.");
    }
    try {
      reponse = await envoyer(nouveau);
    } catch {
      throw new ApiError(0, {}, "Impossible de joindre le serveur. Vérifiez votre connexion.");
    }
    if (reponse.status === 401) {
      deconnecter();
      throw new ApiError(401, {}, "Votre session a expiré. Reconnectez-vous.");
    }
  }

  if (reponse.status === 204) return undefined as T;

  const texte = await reponse.text();
  let donnees: unknown = null;
  if (texte) {
    try {
      donnees = JSON.parse(texte);
    } catch {
      donnees = texte;
    }
  }

  if (!reponse.ok) {
    const { champs, message } = messagesDepuis(donnees);
    throw new ApiError(reponse.status, champs, message);
  }

  return donnees as T;
}

/** Message d'erreur affichable, quelle que soit l'origine de l'exception. */
export function messageErreur(e: unknown, secours = "Une erreur est survenue."): string {
  if (e instanceof ApiError) return e.message || secours;
  if (e instanceof Error && e.message) return e.message;
  return secours;
}
