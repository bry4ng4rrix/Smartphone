"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Skeleton } from "@/components/ui/skeleton";
import { useAuth } from "@/providers/auth-provider";

/**
 * Écran réservé aux clients connectés. Tant que la session est en cours de
 * vérification on affiche un squelette ; si elle est absente, on renvoie
 * vers la connexion en mémorisant la page demandée.
 */
export function AuthGuard({ children }: { children: React.ReactNode }) {
  const { statut } = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (statut === "anonyme") router.replace(`/connexion?suite=${encodeURIComponent(pathname)}`);
  }, [statut, router, pathname]);

  if (statut !== "connecte") {
    return (
      <div className="space-y-4" aria-busy="true" aria-live="polite">
        <Skeleton className="h-8 w-52" />
        <Skeleton className="h-40 w-full" />
        <Skeleton className="h-24 w-full" />
        <span className="sr-only">Vérification de votre session…</span>
      </div>
    );
  }

  return <>{children}</>;
}
