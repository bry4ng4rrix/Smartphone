"use client";

import { useMemo, useState } from "react";
import { PackageSearch } from "lucide-react";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { ProductCard } from "@/components/catalog/product-card";
import { catalogue } from "@/lib/endpoints";
import { messageErreur } from "@/lib/api";
import type { Page, Produit } from "@/lib/types";

/**
 * Grille du catalogue : la première page vient du serveur (SEO), les
 * suivantes sont chargées à la demande via l'API paginée.
 *
 * Les produits affichés sont triés par nom (A → Z) : `GET /api/produit/`
 * n'expose pas de paramètre d'ordre (voir « Propositions d'évolution API »
 * dans client_endpoint.md).
 */
export function CatalogGrid({
  pageInitiale,
  params,
}: {
  pageInitiale: Page<Produit>;
  params: Record<string, string | number | undefined>;
}) {
  const [produits, setProduits] = useState(pageInitiale.results);
  const [suivante, setSuivante] = useState<string | null>(pageInitiale.next);
  const [page, setPage] = useState(1);
  const [chargement, setChargement] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  // À chaque changement de filtres, la page parente remonte ce composant
  // (`key` dérivée des paramètres) : l'état repart donc de la page 1.

  const affiches = useMemo(
    () => [...produits].sort((a, b) => a.nom_complet.localeCompare(b.nom_complet, "fr")),
    [produits],
  );

  const charger = async () => {
    setChargement(true);
    setErreur(null);
    try {
      const suivant = await catalogue.produits({ ...params, page: page + 1 });
      setProduits((actuels) => {
        const connus = new Set(actuels.map((p) => p.id));
        return [...actuels, ...suivant.results.filter((p) => !connus.has(p.id))];
      });
      setSuivante(suivant.next);
      setPage((p) => p + 1);
    } catch (e) {
      setErreur(messageErreur(e, "Impossible de charger la suite du catalogue."));
    } finally {
      setChargement(false);
    }
  };

  if (pageInitiale.count === 0) {
    return (
      <EmptyState
        icone={PackageSearch}
        titre="Aucun produit trouvé."
        description="Essayez d'élargir votre recherche ou de retirer quelques filtres."
        className="hairline bg-surface/40"
      />
    );
  }

  return (
    <div>
      <p className="mb-5 text-sm text-muted" aria-live="polite">
        <span className="font-medium text-foreground tabular-nums">{pageInitiale.count}</span> produit
        {pageInitiale.count > 1 ? "s" : ""}
        {produits.length < pageInitiale.count ? ` · ${produits.length} affichés` : ""}
      </p>

      <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3 xl:grid-cols-4">
        {affiches.map((p, i) => (
          <ProductCard key={p.id} produit={p} priority={i < 4} />
        ))}
      </div>

      {erreur ? (
        <p role="alert" className="mt-6 text-center text-sm text-rose-600 dark:text-rose-400">
          {erreur}
        </p>
      ) : null}

      {suivante ? (
        <div className="mt-10 flex justify-center">
          <Button variant="contour" size="lg" onClick={charger} chargement={chargement}>
            {chargement ? "Chargement…" : "Charger plus de produits"}
          </Button>
        </div>
      ) : null}
    </div>
  );
}
