"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowRight, PackageOpen } from "lucide-react";
import { ButtonLink } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { StatutBadge } from "@/components/orders/status";
import { messageErreur } from "@/lib/api";
import { commandes as apiCommandes } from "@/lib/endpoints";
import { formatAr, formatDate, pluriel } from "@/lib/utils";
import type { Commande } from "@/lib/types";

export function CommandesListe() {
  const [liste, setListe] = useState<Commande[] | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);

  useEffect(() => {
    let annule = false;
    (async () => {
      try {
        const donnees = await apiCommandes.liste();
        if (!annule) setListe(donnees);
      } catch (e) {
        if (!annule) {
          setErreur(messageErreur(e, "Impossible de charger vos commandes."));
          setListe([]);
        }
      }
    })();
    return () => {
      annule = true;
    };
  }, []);

  if (liste === null) {
    return (
      <div className="space-y-3" aria-busy="true">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-28 w-full" />
        ))}
      </div>
    );
  }

  if (erreur) {
    return (
      <p role="alert" className="rounded-lg bg-rose-500/10 px-4 py-3 text-sm text-rose-700 dark:text-rose-300">
        {erreur}
      </p>
    );
  }

  if (liste.length === 0) {
    return (
      <EmptyState
        icone={PackageOpen}
        titre="Vous n'avez pas encore passé de commande."
        description="Vos commandes et leur suivi apparaîtront ici."
        className="hairline bg-surface/40"
        action={<ButtonLink href="/catalogue" variant="primaire">Découvrir le catalogue</ButtonLink>}
      />
    );
  }

  return (
    <ul className="space-y-3">
      {liste.map((c) => {
        const articles = c.items.reduce((n, i) => n + i.quantite, 0);
        return (
          <li key={c.id}>
            <Link
              href={`/compte/commandes/${c.id}`}
              className="hairline elevate hover:elevate-hover group flex flex-col gap-3 rounded-xl bg-surface/50 p-5 sm:flex-row sm:items-center sm:justify-between"
            >
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium tracking-tight">{c.numero}</span>
                  <StatutBadge statut={c.statut} label={c.statut_label} />
                </div>
                <p className="mt-1.5 text-sm text-muted">
                  {formatDate(c.date_commande)} · {c.boutique.nom} · {articles} {pluriel(articles, "article")}
                </p>
                <p className="mt-0.5 line-clamp-1 text-xs text-muted">{c.items.map((i) => `${i.produit.nom_complet} (${i.variante.couleur})`).join(" · ")}</p>
              </div>

              <div className="flex items-center gap-4 sm:shrink-0">
                <span className="text-lg font-semibold tracking-tight tabular-nums">{formatAr(c.total_a_payer)}</span>
                <ArrowRight className="size-4 text-muted transition-transform duration-300 group-hover:translate-x-0.5" aria-hidden />
              </div>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
