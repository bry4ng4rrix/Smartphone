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
  async rewrites() {
    return [
      { source: "/backend/:path*", destination: `${DJANGO_ORIGIN}/api/:path*` },
      { source: "/media/:path*", destination: `${DJANGO_ORIGIN}/media/:path*` },
    ];
  },
};

export default nextConfig;
