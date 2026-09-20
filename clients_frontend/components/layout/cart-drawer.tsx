"use client";

import Link from "next/link";
import { Minus, Plus, ShoppingBag, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ColorDot } from "@/components/ui/color-dot";
import { EmptyState } from "@/components/ui/empty-state";
import { Panel, PanelClose } from "@/components/ui/panel";
import { useCart } from "@/providers/cart-provider";
import { formatAr, pluriel } from "@/lib/utils";

export function CartDrawer() {
  const { lignes, ouvert, fermer, definirQuantite, retirer, nbArticles, sousTotal } = useCart();

  return (
    <Panel
      ouvert={ouvert}
      onOuvertChange={(o) => (o ? undefined : fermer())}
      titre="Votre panier"
      description={nbArticles > 0 ? `${nbArticles} ${pluriel(nbArticles, "article")}` : undefined}
      pied={
        lignes.length > 0 ? (
          <div className="space-y-3">
            <div className="flex items-baseline justify-between">
              <span className="text-sm text-muted">Sous-total articles</span>
              <span className="text-lg font-medium tracking-tight">{formatAr(sousTotal)}</span>
            </div>
            <p className="text-[11px] leading-relaxed text-muted">
              Montant indicatif. Les frais de livraison et le total exact sont calculés par la boutique à la validation.
            </p>
            <PanelClose
              render={<Link href="/checkout">Commander</Link>}
              className="inline-flex h-12 w-full items-center justify-center rounded-full bg-accent text-sm font-medium text-accent-foreground transition-all duration-300 hover:-translate-y-px"
            />
          </div>
        ) : null
      }
    >
      {lignes.length === 0 ? (
        <EmptyState
          icone={ShoppingBag}
          titre="Votre panier est vide"
          description="Parcourez le catalogue et ajoutez vos accessoires préférés."
          action={
            <PanelClose
              render={<Link href="/catalogue">Voir le catalogue</Link>}
              className="inline-flex h-11 items-center justify-center rounded-full border border-border px-6 text-sm font-medium transition-colors hover:border-foreground/35"
            />
          }
        />
      ) : (
        <ul className="divide-y divide-[var(--glass-border)]">
          {lignes.map((l) => (
            <li key={l.varianteId} className="flex gap-3 py-4 first:pt-0">
              <div className="size-16 shrink-0 overflow-hidden rounded-lg bg-surface-2 ring-1 ring-foreground/[0.06]">
                {l.photo ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={l.photo} alt="" className="size-full object-cover" />
                ) : (
                  <span className="flex size-full items-center justify-center">
                    <ColorDot nom={l.couleur} className="size-5" />
                  </span>
                )}
              </div>

              <div className="min-w-0 flex-1">
                <Link href={`/produit/${l.produitId}`} onClick={fermer} className="line-clamp-1 text-sm font-medium hover:text-accent">
                  {l.nomComplet}
                </Link>
                <p className="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                  <ColorDot nom={l.couleur} />
                  {l.couleur}
                </p>

                <div className="mt-2 flex items-center justify-between gap-2">
                  <div className="hairline flex items-center rounded-full">
                    <button
                      type="button"
                      onClick={() => definirQuantite(l.varianteId, l.quantite - 1)}
                      aria-label={`Diminuer la quantité de ${l.nomComplet}`}
                      className="grid size-8 place-items-center rounded-full text-muted transition-colors hover:text-foreground"
                    >
                      <Minus className="size-3.5" aria-hidden />
                    </button>
                    <span className="min-w-6 text-center text-sm tabular-nums">{l.quantite}</span>
                    <button
                      type="button"
                      onClick={() => definirQuantite(l.varianteId, l.quantite + 1)}
                      aria-label={`Augmenter la quantité de ${l.nomComplet}`}
                      className="grid size-8 place-items-center rounded-full text-muted transition-colors hover:text-foreground"
                    >
                      <Plus className="size-3.5" aria-hidden />
                    </button>
                  </div>
                  <span className="text-sm font-medium tabular-nums">{formatAr(l.prix * l.quantite)}</span>
                </div>
              </div>

              <button
                type="button"
                onClick={() => retirer(l.varianteId)}
                aria-label={`Retirer ${l.nomComplet} du panier`}
                className="-m-1 h-fit rounded-md p-1 text-muted transition-colors hover:text-rose-600"
              >
                <Trash2 className="size-4" aria-hidden />
              </button>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}

/** Bouton panier de l'en-tête, avec le compteur d'articles. */
export function CartButton({ className }: { className?: string }) {
  const { nbArticles, ouvrir } = useCart();
  return (
    <Button
      variant="fantome"
      size="icone"
      onClick={ouvrir}
      aria-label={`Ouvrir le panier${nbArticles ? ` (${nbArticles} articles)` : ""}`}
      className={className}
    >
      <span className="relative">
        <ShoppingBag aria-hidden />
        {nbArticles > 0 ? (
          <span className="absolute -top-1.5 -right-2 grid min-w-4 place-items-center rounded-full bg-accent px-1 text-[10px] leading-4 font-semibold text-accent-foreground tabular-nums">
            {nbArticles > 99 ? "99+" : nbArticles}
          </span>
        ) : null}
      </span>
    </Button>
  );
}
