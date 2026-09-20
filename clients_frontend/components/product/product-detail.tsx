"use client";

import { useState } from "react";
import Link from "next/link";
import { Check, Heart, Minus, Plus, ShieldCheck, ShoppingBag, Store, Truck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ColorDot } from "@/components/ui/color-dot";
import { Modal } from "@/components/ui/panel";
import { ProductImage } from "@/components/product/product-image";
import { Tilt } from "@/components/ui/tilt";
import { useCart } from "@/providers/cart-provider";
import { useToast } from "@/providers/toast-provider";
import { useWishlist } from "@/providers/wishlist-provider";
import { cn, formatAr } from "@/lib/utils";
import type { Produit, Variante } from "@/lib/types";

export function ProductDetail({ produit }: { produit: Produit }) {
  const { ajouter, remplacerPar, ouvrir } = useCart();
  const { estFavori, basculer } = useWishlist();
  const toast = useToast();

  const premiereDispo = produit.variantes.find((v) => v.disponible) ?? produit.variantes[0] ?? null;
  const [variante, setVariante] = useState<Variante | null>(premiereDispo);
  const [quantite, setQuantite] = useState(1);
  const [conflit, setConflit] = useState(false);

  const favori = estFavori(produit.id);
  const indisponible = !variante || !variante.disponible;

  const ajouterAuPanier = () => {
    if (!variante) return;
    if (ajouter(produit, variante, quantite)) {
      toast.succes("Ajouté au panier", `${produit.nom_complet} · ${variante.couleur} × ${quantite}`);
      ouvrir();
    } else {
      setConflit(true);
    }
  };

  return (
    <>
      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,440px)] lg:gap-14">
        {/* Visuel */}
        <div className="lg:sticky lg:top-24 lg:self-start">
          <Tilt intensite={7}>
            <div className="hairline overflow-hidden rounded-2xl bg-surface/60">
              <ProductImage
                produit={produit}
                className="aspect-square w-full"
                sizes="(min-width: 1024px) 55vw, 100vw"
                priority
              />
            </div>
          </Tilt>

          {produit.variantes.length > 1 ? (
            <ul className="mt-4 flex flex-wrap gap-2" aria-label="Coloris du produit">
              {produit.variantes.map((v) => (
                <li key={v.id}>
                  <button
                    type="button"
                    onClick={() => setVariante(v)}
                    aria-pressed={variante?.id === v.id}
                    className={cn(
                      "flex items-center gap-2 rounded-full px-3 py-2 text-xs transition-all duration-200",
                      variante?.id === v.id ? "glass-strong ring-1 ring-accent/45" : "hairline text-muted hover:text-foreground",
                      !v.disponible && "opacity-45",
                    )}
                  >
                    <ColorDot nom={v.couleur} />
                    {v.couleur}
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>

        {/* Informations */}
        <div>
          <nav aria-label="Fil d'Ariane" className="text-[11px] tracking-[0.18em] text-muted uppercase">
            <Link href={`/catalogue?category=${produit.categorie.id}`} className="transition-colors hover:text-foreground">
              {produit.categorie.nom}
            </Link>
            <span className="px-1.5">/</span>
            <Link href={`/catalogue?sous_type=${produit.sous_type.id}`} className="transition-colors hover:text-foreground">
              {produit.sous_type.nom}
            </Link>
          </nav>

          <h1 className="mt-3 text-3xl leading-tight font-semibold tracking-tight sm:text-4xl">{produit.nom_complet}</h1>

          <div className="mt-3 flex flex-wrap items-center gap-3">
            <Link
              href={`/catalogue?brand=${produit.marque.id}`}
              className="hairline rounded-full px-3 py-1 text-xs text-muted transition-colors hover:text-foreground"
            >
              {produit.marque.nom}
            </Link>
            <span
              className={cn(
                "inline-flex items-center gap-1.5 text-xs",
                produit.disponible ? "text-emerald-600 dark:text-emerald-400" : "text-muted",
              )}
            >
              <span className={cn("size-1.5 rounded-full", produit.disponible ? "bg-emerald-500" : "bg-muted")} aria-hidden />
              {produit.disponible ? "Disponible" : "Épuisé"}
            </span>
          </div>

          <p className="mt-6 text-3xl font-semibold tracking-tight tabular-nums">{formatAr(produit.prix_vente)}</p>
          <p className="mt-1 text-xs text-muted">Prix affiché par la boutique. Les frais de livraison s&apos;ajoutent selon la zone choisie.</p>

          {/* Couleur */}
          {produit.variantes.length > 0 ? (
            <fieldset className="mt-7">
              <legend className="text-[11px] font-medium tracking-[0.18em] text-muted uppercase">
                Coloris{variante ? ` · ${variante.couleur}` : ""}
              </legend>
              <div className="mt-3 flex flex-wrap gap-2">
                {produit.variantes.map((v) => (
                  <button
                    key={v.id}
                    type="button"
                    onClick={() => setVariante(v)}
                    disabled={!v.disponible}
                    aria-pressed={variante?.id === v.id}
                    aria-label={`${v.couleur}${v.disponible ? "" : " — épuisé"}`}
                    className={cn(
                      "relative grid size-10 place-items-center rounded-full transition-all duration-200",
                      variante?.id === v.id ? "ring-2 ring-accent ring-offset-2 ring-offset-background" : "ring-1 ring-border",
                      !v.disponible && "cursor-not-allowed opacity-40",
                    )}
                  >
                    <ColorDot nom={v.couleur} className="size-6" />
                    {variante?.id === v.id ? <Check className="absolute size-3.5 text-white mix-blend-difference" aria-hidden /> : null}
                  </button>
                ))}
              </div>
              {variante && !variante.disponible ? (
                <p className="mt-2 text-xs text-amber-600 dark:text-amber-400">Ce coloris est épuisé — choisissez-en un autre.</p>
              ) : null}
            </fieldset>
          ) : null}

          {/* Quantité + panier */}
          <div className="mt-7 flex flex-wrap items-center gap-3">
            <div className="hairline flex h-12 items-center rounded-full px-1">
              <button
                type="button"
                onClick={() => setQuantite((q) => Math.max(1, q - 1))}
                aria-label="Diminuer la quantité"
                className="grid size-10 place-items-center rounded-full text-muted transition-colors hover:text-foreground"
              >
                <Minus className="size-4" aria-hidden />
              </button>
              <span className="min-w-8 text-center text-sm font-medium tabular-nums" aria-live="polite">
                {quantite}
              </span>
              <button
                type="button"
                onClick={() => setQuantite((q) => Math.min(99, q + 1))}
                aria-label="Augmenter la quantité"
                className="grid size-10 place-items-center rounded-full text-muted transition-colors hover:text-foreground"
              >
                <Plus className="size-4" aria-hidden />
              </button>
            </div>

            <Button variant="accent" size="lg" onClick={ajouterAuPanier} disabled={indisponible} className="flex-1 sm:flex-none">
              <ShoppingBag aria-hidden />
              {indisponible ? "Indisponible" : "Ajouter au panier"}
            </Button>

            <Button
              variant="contour"
              size="icone"
              onClick={() => {
                const ajoute = basculer(produit.id);
                toast.info(ajoute ? "Ajouté aux favoris" : "Retiré des favoris", produit.nom_complet);
              }}
              aria-pressed={favori}
              aria-label={favori ? "Retirer des favoris" : "Ajouter aux favoris"}
              className="size-12"
            >
              <Heart className={cn("transition-colors", favori && "fill-rose-500 text-rose-500")} aria-hidden />
            </Button>
          </div>

          {/* Informations boutique — uniquement ce que l'API expose */}
          <dl className="mt-8 space-y-3 border-t border-border/70 pt-6 text-sm">
            <div className="flex items-start gap-3">
              <Store className="mt-0.5 size-4 shrink-0 text-muted" aria-hidden />
              <div>
                <dt className="font-medium">Vendu par {produit.boutique.nom}</dt>
                <dd className="text-xs text-muted">Une commande ne peut regrouper que des articles d&apos;une même boutique.</dd>
              </div>
            </div>
            <div className="flex items-start gap-3">
              <Truck className="mt-0.5 size-4 shrink-0 text-muted" aria-hidden />
              <div>
                <dt className="font-medium">Livraison ou retrait sur place</dt>
                <dd className="text-xs text-muted">Les zones et leurs frais sont proposés à la commande.</dd>
              </div>
            </div>
            <div className="flex items-start gap-3">
              <ShieldCheck className="mt-0.5 size-4 shrink-0 text-muted" aria-hidden />
              <div>
                <dt className="font-medium">Validation par la boutique</dt>
                <dd className="text-xs text-muted">Votre commande est confirmée après vérification, et reste modifiable jusque-là.</dd>
              </div>
            </div>
          </dl>
        </div>
      </div>

      <Modal
        ouvert={conflit}
        onOuvertChange={setConflit}
        titre="Changer de boutique ?"
        description="Votre panier contient déjà des articles d'une autre boutique. Une commande ne peut concerner qu'une seule boutique : continuer videra le panier actuel."
      >
        <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
          <Button variant="contour" onClick={() => setConflit(false)}>
            Garder mon panier
          </Button>
          <Button
            variant="accent"
            onClick={() => {
              if (variante) {
                remplacerPar(produit, variante, quantite);
                toast.succes("Panier remplacé", `${produit.nom_complet} · ${variante.couleur}`);
                setConflit(false);
                ouvrir();
              }
            }}
          >
            Vider et ajouter
          </Button>
        </div>
      </Modal>
    </>
  );
}
