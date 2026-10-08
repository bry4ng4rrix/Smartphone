"use client";

import Link from "next/link";
import { Heart, Plus } from "lucide-react";
import { ColorDot } from "@/components/ui/color-dot";
import { ProductImage } from "@/components/product/product-image";
import { Tilt } from "@/components/ui/tilt";
import { useCart } from "@/providers/cart-provider";
import { useToast } from "@/providers/toast-provider";
import { useWishlist } from "@/providers/wishlist-provider";
import { formatAr, cn } from "@/lib/utils";
import type { Produit, Variante } from "@/lib/types";

export function ProductCard({ produit, priority = false }: { produit: Produit; priority?: boolean }) {
  const { ajouter, ouvrir } = useCart();
  const { estFavori, basculer } = useWishlist();
  const toast = useToast();

  const disponibles = produit.variantes.filter((v) => v.disponible);
  const favori = estFavori(produit.id);

  // Le panier accepte plusieurs boutiques : rien à arbitrer ici, c'est le
  // serveur qui route chaque article vers la sienne à la commande.
  const ajoutRapide = (variante: Variante) => {
    ajouter(produit, variante, 1);
    toast.succes("Ajouté au panier", `${produit.nom_complet} · ${variante.couleur}`);
    ouvrir();
  };

  // `elevate-hover` retiré : le survol 3D porte désormais la levée et
  // l'ombre (voir [data-tilt] dans globals.css), les cumuler doublait
  // l'ombre portée.
  return (
    <Tilt className="group hairline relative flex h-full flex-col overflow-hidden rounded-xl bg-surface/70 backdrop-blur-sm" intensite={5}>
      <article className="flex h-full flex-col">
        <Link href={`/produit/${produit.id}`} className="block focus-visible:outline-none" aria-label={produit.nom_complet}>
          <ProductImage produit={produit} className="aspect-square w-full" priority={priority} />
        </Link>

        <button
          type="button"
          onClick={() => {
            const ajoute = basculer(produit.id);
            toast.info(ajoute ? "Ajouté aux favoris" : "Retiré des favoris", produit.nom_complet);
          }}
          aria-pressed={favori}
          aria-label={favori ? `Retirer ${produit.nom_complet} des favoris` : `Ajouter ${produit.nom_complet} aux favoris`}
          className="glass absolute top-3 right-3 grid size-9 place-items-center rounded-full transition-transform duration-300 hover:scale-105"
        >
          <Heart className={cn("size-4 transition-colors", favori ? "fill-rose-500 text-rose-500" : "text-muted")} aria-hidden />
        </button>

        {!produit.disponible ? (
          <span className="glass absolute top-3 left-3 rounded-full px-2.5 py-1 text-[10px] font-medium tracking-wide uppercase">
            Épuisé
          </span>
        ) : null}

        <div className="flex flex-1 flex-col gap-2 p-4">
          <p className="text-[10px] font-medium tracking-[0.18em] text-muted uppercase">
            {produit.marque.nom} · {produit.sous_type.nom}
          </p>

          <h3 className="text-sm leading-snug font-medium tracking-tight">
            <Link href={`/produit/${produit.id}`} className="after:absolute after:inset-0 after:content-['']">
              {produit.nom_complet}
            </Link>
          </h3>

          {produit.variantes.length > 0 ? (
            <div className="flex flex-wrap items-center gap-1" aria-label={`${produit.variantes.length} couleurs`}>
              {produit.variantes.slice(0, 6).map((v) => (
                <ColorDot key={v.id} nom={v.couleur} className={cn("size-2.5", !v.disponible && "opacity-30")} />
              ))}
              {produit.variantes.length > 6 ? (
                <span className="text-[10px] text-muted">+{produit.variantes.length - 6}</span>
              ) : null}
            </div>
          ) : null}

          <div className="mt-auto flex items-end justify-between gap-2 pt-2">
            <p className="text-[15px] font-semibold tracking-tight tabular-nums">{formatAr(produit.prix_vente)}</p>

            {/* Ajout direct seulement quand il n'y a pas de choix à faire :
                sinon la couleur se choisit sur la fiche produit. */}
            {disponibles.length === 1 ? (
              <button
                type="button"
                onClick={() => ajoutRapide(disponibles[0])}
                aria-label={`Ajouter ${produit.nom_complet} au panier`}
                className="relative z-10 grid size-9 shrink-0 place-items-center rounded-full bg-foreground text-background transition-all duration-300 hover:scale-105 sm:opacity-0 sm:group-hover:opacity-100 sm:focus-visible:opacity-100"
              >
                <Plus className="size-4" aria-hidden />
              </button>
            ) : null}
          </div>
        </div>
      </article>
    </Tilt>
  );
}
