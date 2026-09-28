/**
 * Couche d'accès à l'API de la boutique en ligne (`client_endpoint.md`).
 *
 * Deux contextes, une seule fonction :
 * - Server Component / build : appel direct à Django (`DJANGO_ORIGIN`), pas
 *   de CORS ;
 * - navigateur : appel same-origin `/backend/...`, réécrit vers Django par
 *   `proxy.ts` — l'API n'autorise pas l'origine du front dans ses en-têtes
 *   CORS, et on ne touche pas au backend.
 *
 * Il n'y a NI compte NI jeton : la boutique ne demande pas d'inscription, et
 * toutes les routes qu'elle appelle sont publiques. Rien n'est conservé entre
 * deux visites hormis le panier (localStorage, voir `lib/store.ts`).
 */

const DJANGO_ORIGIN = process.env.DJANGO_ORIGIN ?? "http://localhost:8010";

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

  /** L'endpoint de commande est ouvert : il limite le débit (HTTP 429). */
  get estTropDeRequetes() {
    return this.status === 429;
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

export type RequeteOptions = {
  method?: "GET" | "POST" | "PATCH" | "DELETE";
  body?: unknown;
  params?: Record<string, string | number | boolean | undefined | null>;
  signal?: AbortSignal;
  /** Cache Next côté serveur (catalogue public). */
  revalidate?: number;
};

export async function api<T>(chemin: string, options: RequeteOptions = {}): Promise<T> {
  const { method = "GET", body, params, signal, revalidate } = options;

  const url = new URL(`${baseUrl()}${chemin}`, estNavigateur() ? window.location.origin : DJANGO_ORIGIN);
  if (params) {
    for (const [cle, valeur] of Object.entries(params)) {
      if (valeur !== undefined && valeur !== null && valeur !== "") url.searchParams.set(cle, String(valeur));
    }
  }

  const headers: Record<string, string> = {};
  if (body !== undefined) headers["Content-Type"] = "application/json";

  let reponse: Response;
  try {
    reponse = await fetch(url.toString(), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
      ...(estNavigateur() ? {} : { next: { revalidate: revalidate ?? 0 } }),
    });
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") throw e;
    throw new ApiError(0, {}, "Impossible de joindre le serveur. Vérifiez votre connexion.");
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
  if (e instanceof ApiError) {
    if (e.estTropDeRequetes) return "Trop de commandes envoyées coup sur coup. Patientez une minute.";
    return e.message || secours;
  }
  if (e instanceof Error && e.message) return e.message;
  return secours;
}
