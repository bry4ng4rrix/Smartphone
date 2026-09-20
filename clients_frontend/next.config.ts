import type { NextConfig } from "next";

/**
 * L'API Django tourne sur un autre port (8010) et n'autorise pas l'origine
 * du front client dans ses en-têtes CORS. Plutôt que de toucher au backend,
 * les appels navigateur passent par un proxy same-origin :
 *
 *   navigateur → /backend/...  → (rewrite serveur) → http://localhost:8010/api/...
 *   navigateur → /media/...    → (rewrite serveur) → http://localhost:8010/media/...
 *
 * Les Server Components, eux, appellent Django directement (aucune notion de
 * CORS côté serveur) — voir lib/api.ts.
 */
const DJANGO_ORIGIN = process.env.DJANGO_ORIGIN ?? "http://localhost:8010";

const nextConfig: NextConfig = {
  // Image Docker minimale : `next build` produit un serveur autonome
  // (.next/standalone) qui n'embarque que les dépendances réellement usées.
  output: "standalone",

  // Django exige la barre oblique finale (`APPEND_SLASH`). Sans cette option,
  // Next normalise `/backend/boutiques/` en `/backend/boutiques` AVANT le
  // rewrite, et Django renvoie alors une redirection vers son propre domaine
  // — que le navigateur bloque (CORS). Les routes de l'app n'utilisent pas de
  // barre finale, ce réglage ne change donc rien pour elles.
  skipTrailingSlashRedirect: true,

  async rewrites() {
    return [
      // La barre finale est ajoutée côté destination : Next normalise le
      // chemin entrant en la retirant, alors que Django l'exige (APPEND_SLASH).
      { source: "/backend/:path*", destination: `${DJANGO_ORIGIN}/api/:path*/` },
      { source: "/media/:path*", destination: `${DJANGO_ORIGIN}/media/:path*` },
    ];
  },
};

export default nextConfig;
