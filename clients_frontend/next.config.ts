import type { NextConfig } from "next";

/**
 * Le proxy vers l'API Django vit dans `proxy.ts` (et non dans `rewrites()`) :
 * il doit lire `DJANGO_ORIGIN` à l'exécution, alors que les rewrites de cette
 * configuration sont figés au moment du build de l'image.
 */
const nextConfig: NextConfig = {
  // Image Docker minimale : `next build` produit un serveur autonome
  // (.next/standalone) qui n'embarque que les dépendances réellement usées.
  output: "standalone",

  // Django exige la barre oblique finale (`APPEND_SLASH`). Sans cette option,
  // Next normalise `/backend/boutiques/` en `/backend/boutiques` avant que le
  // proxy ne s'exécute. Les routes de l'app n'utilisent pas de barre finale,
  // ce réglage ne change donc rien pour elles.
  skipTrailingSlashRedirect: true,
};

export default nextConfig;
