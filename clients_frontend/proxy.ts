import { NextResponse, type NextRequest } from "next/server";

/**
 * Proxy d'API same-origin (voir « 9.11 » dans client_endpoint.md).
 *
 * L'API Django n'autorise pas l'origine du front client dans ses en-têtes
 * CORS, et on ne touche pas au backend. Le navigateur appelle donc toujours
 * ce serveur :
 *
 *   /backend/<chemin>  →  <DJANGO_ORIGIN>/api/<chemin>/
 *   /media/<fichier>   →  <DJANGO_ORIGIN>/media/<fichier>
 *
 * Pourquoi ici et pas dans `rewrites()` de next.config.ts : les rewrites de
 * la configuration sont figés au moment du `next build` (sortie standalone),
 * alors que `DJANGO_ORIGIN` doit pouvoir changer d'un environnement à
 * l'autre sans reconstruire l'image. Le proxy, lui, s'exécute à chaque
 * requête et relit la variable.
 */
const DJANGO_ORIGIN = process.env.DJANGO_ORIGIN ?? "http://localhost:8010";

export function proxy(request: NextRequest) {
  const { pathname, search } = request.nextUrl;

  if (pathname.startsWith("/backend/")) {
    const chemin = pathname.slice("/backend/".length);
    // Django exige la barre oblique finale (APPEND_SLASH) ; sans elle, il
    // renvoie une redirection vers son propre domaine, que le navigateur
    // refuserait (CORS).
    const avecSlash = chemin.endsWith("/") ? chemin : `${chemin}/`;
    return NextResponse.rewrite(new URL(`/api/${avecSlash}${search}`, DJANGO_ORIGIN));
  }

  if (pathname.startsWith("/media/")) {
    return NextResponse.rewrite(new URL(`${pathname}${search}`, DJANGO_ORIGIN));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/backend/:path*", "/media/:path*"],
};
