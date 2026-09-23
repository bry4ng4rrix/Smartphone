"use client";

import { CheckCircle2, PackageSearch, XCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ProductCard } from "@/components/catalog/product-card";
import { formatAr, pluriel } from "@/lib/utils";
import { DELAI_COMMANDE_SPECIALE_JOURS, TAUX_ACOMPTE, prixIndicatif } from "@/lib/compatibilite";
import type { Produit } from "@/lib/types";

function Section({
  ton,
  titre,
  produits,
}: {
  ton: "ok" | "ko";
  titre: string;
  produits: Produit[];
}) {
  const Icone = ton === "ok" ? CheckCircle2 : XCircle;
  return (
    <section className="mt-8 first:mt-0">
      <h3 className="mb-4 flex items-center gap-2 text-sm font-medium">
        <Icone
          className={ton === "ok" ? "size-4 text-emerald-600 dark:text-emerald-400" : "size-4 text-muted"}
          aria-hidden
        />
        {titre}
      </h3>
      <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3 xl:grid-cols-4">
        {produits.map((p, i) => (
          <ProductCard key={p.id} produit={p} priority={ton === "ok" && i < 4} />
        ))}
      </div>
    </section>
  );
}

/**
 * Étape 2 : ce que la boutique a pour ce téléphone.
 *
 * Les produits sont séparés en deux blocs plutôt que mélangés : l'état de
 * chaque résultat doit se lire d'un coup d'œil. La carte produit reste celle
 * du catalogue — le parcours d'achat (panier, fiche, couleurs) est donc
 * exactement le même que partout ailleurs.
 */
export function ResultatsCompatibles({
  libelle,
  accroche,
  telephone,
  produits,
  onCommandeSpeciale,
}: {
  libelle: string;
  accroche: string;
  telephone: string;
  produits: Produit[];
  onCommandeSpeciale: () => void;
}) {
  const disponibles = produits.filter((p) => p.disponible);
  const epuises = produits.filter((p) => !p.disponible);

  // Aucun produit en stock : la commande spéciale n'est pas un message
  // d'erreur déguisé, c'est la suite normale du parcours.
  if (disponibles.length === 0) {
    const depart = prixIndicatif(epuises);
    return (
      <div className="hairline rounded-xl bg-surface/60 px-6 py-12 text-center sm:px-10">
        <span className="glass mx-auto mb-5 flex size-14 items-center justify-center rounded-full text-muted">
          <PackageSearch className="size-6" aria-hidden />
        </span>

        <h2 className="text-lg font-medium tracking-tight">Aucun produit disponible</h2>
        <p className="mx-auto mt-2 max-w-md text-sm text-muted">
          Nous n&apos;avons actuellement aucun {libelle.toLowerCase()} en stock pour&nbsp;:
        </p>
        <p className="mt-3 text-base font-medium tracking-tight">{telephone}</p>

        <p className="mx-auto mt-5 max-w-md text-sm text-muted">
          Vous pouvez cependant en faire la demande : la boutique le commande pour vous.
        </p>

        <dl className="mx-auto mt-6 grid max-w-sm grid-cols-2 gap-3 text-left">
          <div className="hairline rounded-lg bg-surface/60 px-4 py-3">
            <dt className="text-[11px] tracking-wide text-muted uppercase">Délai estimé</dt>
            <dd className="mt-1 text-sm font-medium tabular-nums">{DELAI_COMMANDE_SPECIALE_JOURS} jours</dd>
          </div>
          <div className="hairline rounded-lg bg-surface/60 px-4 py-3">
            <dt className="text-[11px] tracking-wide text-muted uppercase">Acompte requis</dt>
            <dd className="mt-1 text-sm font-medium tabular-nums">{Math.round(TAUX_ACOMPTE * 100)} %</dd>
          </div>
        </dl>

        {depart !== null ? (
          <p className="mt-4 text-xs text-muted">
            À titre indicatif, ce produit était proposé à partir de {formatAr(depart)}. Le montant exact est confirmé par
            la boutique.
          </p>
        ) : null}

        <div className="mt-7">
          <Button variant="accent" size="lg" onClick={onCommandeSpeciale}>
            Commander spécialement
          </Button>
        </div>

        {epuises.length > 0 ? (
          <Section
            ton="ko"
            titre={`${epuises.length} ${pluriel(epuises.length, "produit")} ${pluriel(epuises.length, "compatible")} ${pluriel(epuises.length, "mais épuisé", "mais épuisés")}`}
            produits={epuises}
          />
        ) : null}
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6">
        <h2 className="text-lg font-medium tracking-tight sm:text-xl">
          {libelle}s compatibles avec {telephone}
        </h2>
        <p className="mt-1.5 text-sm text-muted" aria-live="polite">
          <span className="font-medium text-foreground tabular-nums">{disponibles.length}</span>{" "}
          {pluriel(disponibles.length, "produit")} {pluriel(disponibles.length, "disponible")}
          {epuises.length > 0 ? ` · ${epuises.length} épuisé${epuises.length > 1 ? "s" : ""}` : ""}
        </p>
      </div>

      <Section ton="ok" titre="Disponible" produits={disponibles} />

      {epuises.length > 0 ? (
        <>
          <Section ton="ko" titre="Non disponible" produits={epuises} />
          <div className="mt-8 hairline flex flex-col items-start gap-3 rounded-xl bg-surface/60 p-5 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-sm text-muted">
              Le {accroche.replace(/s$/, "")} que vous cherchez est épuisé ? La boutique peut le commander pour vous.
            </p>
            <Button variant="contour" onClick={onCommandeSpeciale} className="shrink-0">
              Commande spéciale
            </Button>
          </div>
        </>
      ) : null}
    </div>
  );
}
