"use client";

import Link from "next/link";
import { Minus, Plus, ShoppingBag, Trash2 } from "lucide-react";
import { ButtonLink } from "@/components/ui/button";
import { ColorDot } from "@/components/ui/color-dot";
import { EmptyState } from "@/components/ui/empty-state";
import { useCart } from "@/providers/cart-provider";
import { formatAr, pluriel } from "@/lib/utils";

export function PanierVue() {
  const { lignes, nbArticles, sousTotal, definirQuantite, retirer, vider } = useCart();

  if (lignes.length === 0) {
    return (
      <EmptyState
        icone={ShoppingBag}
        titre="Votre panier est vide"
        description="Parcourez le catalogue et ajoutez vos accessoires préférés."
        className="hairline mt-8 bg-surface/40"
        action={
          <Link href="/catalogue" className="inline-flex h-11 items-center rounded-full bg-foreground px-6 text-sm font-medium text-background">
            Voir le catalogue
          </Link>
        }
      />
    );
  }

  return (
    <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_340px] lg:items-start">
      <div>
        <div className="mb-4 flex items-center justify-between">
          <p className="text-sm text-muted">
            {nbArticles} {pluriel(nbArticles, "article")} · {lignes[0].boutiqueNom}
          </p>
          <button type="button" onClick={vider} className="text-xs text-muted transition-colors hover:text-rose-600">
            Vider le panier
          </button>
        </div>

        <ul className="hairline divide-y divide-border/70 rounded-xl bg-surface/50">
          {lignes.map((l) => (
            <li key={l.varianteId} className="flex gap-4 p-4">
              <Link
                href={`/produit/${l.produitId}`}
                className="size-20 shrink-0 overflow-hidden rounded-lg bg-surface-2 ring-1 ring-foreground/[0.06] sm:size-24"
              >
                {l.photo ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={l.photo} alt="" className="size-full object-cover" />
                ) : (
                  <span className="flex size-full items-center justify-center">
                    <ColorDot nom={l.couleur} className="size-6" />
                  </span>
                )}
              </Link>

              <div className="flex min-w-0 flex-1 flex-col">
                <Link href={`/produit/${l.produitId}`} className="text-sm font-medium hover:text-accent">
                  {l.nomComplet}
                </Link>
                <p className="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                  <ColorDot nom={l.couleur} />
                  {l.couleur}
                </p>
                <p className="mt-1 text-xs text-muted tabular-nums">{formatAr(l.prix)} / unité</p>

                <div className="mt-auto flex flex-wrap items-center justify-between gap-3 pt-3">
                  <div className="hairline flex items-center rounded-full">
                    <button
                      type="button"
                      onClick={() => definirQuantite(l.varianteId, l.quantite - 1)}
                      aria-label={`Diminuer la quantité de ${l.nomComplet}`}
                      className="grid size-9 place-items-center rounded-full text-muted transition-colors hover:text-foreground"
                    >
                      <Minus className="size-3.5" aria-hidden />
                    </button>
                    <span className="min-w-7 text-center text-sm tabular-nums">{l.quantite}</span>
                    <button
                      type="button"
                      onClick={() => definirQuantite(l.varianteId, l.quantite + 1)}
                      aria-label={`Augmenter la quantité de ${l.nomComplet}`}
                      className="grid size-9 place-items-center rounded-full text-muted transition-colors hover:text-foreground"
                    >
                      <Plus className="size-3.5" aria-hidden />
                    </button>
                  </div>

                  <div className="flex items-center gap-3">
                    <span className="text-sm font-semibold tabular-nums">{formatAr(l.prix * l.quantite)}</span>
                    <button
                      type="button"
                      onClick={() => retirer(l.varianteId)}
                      aria-label={`Retirer ${l.nomComplet}`}
                      className="rounded-md p-1 text-muted transition-colors hover:text-rose-600"
                    >
                      <Trash2 className="size-4" aria-hidden />
                    </button>
                  </div>
                </div>
              </div>
            </li>
          ))}
        </ul>
      </div>

      <aside className="glass sticky top-24 rounded-xl p-5">
        <h2 className="text-sm font-medium tracking-tight">Récapitulatif</h2>
        <dl className="mt-4 space-y-2 text-sm">
          <div className="flex items-baseline justify-between">
            <dt className="text-muted">Articles</dt>
            <dd className="tabular-nums">{formatAr(sousTotal)}</dd>
          </div>
          <div className="flex items-baseline justify-between">
            <dt className="text-muted">Livraison</dt>
            <dd className="text-xs text-muted">Calculée à l&apos;étape suivante</dd>
          </div>
        </dl>

        <div className="mt-4 flex items-baseline justify-between border-t border-[var(--glass-border)] pt-4">
          <span className="text-sm font-medium">Total estimé</span>
          <span className="text-xl font-semibold tracking-tight tabular-nums">{formatAr(sousTotal)}</span>
        </div>
        <p className="mt-2 text-[11px] leading-relaxed text-muted">
          Montant indicatif : le total réel, frais de livraison compris, est calculé par la boutique à la validation de la commande.
        </p>

        <ButtonLink href="/checkout" variant="accent" size="lg" className="mt-5 w-full">
          Passer la commande
        </ButtonLink>

        <Link href="/catalogue" className="mt-3 block text-center text-xs text-muted transition-colors hover:text-foreground">
          Continuer mes achats
        </Link>
      </aside>
    </div>
  );
}
