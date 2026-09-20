"use client";

import { useEffect, useState } from "react";
import { Heart } from "lucide-react";
import { ButtonLink } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { GrilleSkeleton } from "@/components/ui/skeleton";
import { ProductCard } from "@/components/catalog/product-card";
import { catalogue } from "@/lib/endpoints";
import { useWishlist } from "@/providers/wishlist-provider";
import type { Produit } from "@/lib/types";

export function FavorisVue() {
  const { ids, retirer } = useWishlist();
  const [produits, setProduits] = useState<Produit[] | null>(null);

  // Les favoris ne stockent que des identifiants : les fiches (prix,
  // disponibilité) sont toujours relues côté API.
  useEffect(() => {
    let annule = false;
    (async () => {
      if (ids.length === 0) {
        setProduits([]);
        return;
      }
      const fiches = await Promise.all(
        ids.map(async (id) => {
          try {
            return await catalogue.produit(id);
          } catch {
            // Produit retiré du catalogue : on nettoie la liste locale.
            if (!annule) retirer(id);
            return null;
          }
        }),
      );
      if (!annule) setProduits(fiches.filter((p): p is Produit => p !== null));
    })();
    return () => {
      annule = true;
    };
  }, [ids, retirer]);

  if (produits === null) return <div className="mt-8"><GrilleSkeleton nb={4} /></div>;

  if (produits.length === 0) {
    return (
      <EmptyState
        icone={Heart}
        titre="Aucun favori pour l'instant"
        description="Touchez le cœur sur un produit pour le retrouver ici."
        className="hairline mt-8 bg-surface/40"
        action={
          <ButtonLink href="/catalogue" variant="primaire">
            Parcourir le catalogue
          </ButtonLink>
        }
      />
    );
  }

  return (
    <div className="mt-8 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
      {produits.map((p) => (
        <ProductCard key={p.id} produit={p} />
      ))}
    </div>
  );
}
