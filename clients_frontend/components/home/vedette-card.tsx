"use client";

import { useState } from "react";
import Image from "next/image";
import { Star } from "lucide-react";
import { ColorDot } from "@/components/ui/color-dot";
import { Tilt } from "@/components/ui/tilt";
import { couleurCss } from "@/lib/couleurs";
import { formatAr, cn } from "@/lib/utils";
import type { ProduitVedette } from "@/lib/vedettes";

export function VedetteCard({ produit }: { produit: ProduitVedette }) {
  const [index, setIndex] = useState(0);
  const couleur = produit.couleurs[index];

  const teintes = produit.couleurs.slice(0, 3).map((c) => couleurCss(c.nom));
  const fond = `radial-gradient(90% 70% at 25% 20%, ${teintes[0]}3d, transparent 62%), radial-gradient(70% 60% at 78% 78%, ${
    teintes[1] ?? teintes[0]
  }33, transparent 62%), radial-gradient(60% 50% at 55% 50%, ${teintes[2] ?? teintes[0]}24, transparent 65%)`;

  return (
    <Tilt className="group hairline relative flex h-full flex-col overflow-hidden rounded-xl bg-surface/70 backdrop-blur-sm" intensite={5}>
      <article className="flex h-full flex-col">
        <div className="relative aspect-square w-full overflow-hidden bg-surface-2">
          {couleur.photo ? (
            <Image
              key={couleur.photo}
              src={couleur.photo}
              alt={`${produit.modele} — ${couleur.nom}`}
              fill
              sizes="(min-width: 1280px) 22vw, (min-width: 640px) 33vw, 50vw"
              className="object-contain p-8 transition-transform duration-700 ease-[cubic-bezier(0.22,1,0.36,1)] group-hover:scale-[1.04]"
            />
          ) : (
            <div
              className="degrade-anime relative flex h-full flex-col items-center justify-center gap-1 px-4 text-center"
              style={{ backgroundImage: fond }}
            >
              <div className="grain absolute inset-0" aria-hidden />
              <span className="relative text-[10px] font-medium tracking-[0.22em] text-muted uppercase">
                {produit.marque}
              </span>
              <span className="relative text-sm font-medium tracking-tight text-foreground/70">
                {produit.sousType}
              </span>
            </div>
          )}
        </div>

        <div className="flex flex-1 flex-col gap-2 p-4">
          <p className="text-[10px] font-medium tracking-[0.18em] text-muted uppercase">
            {produit.marque} · {produit.sousType}
          </p>

          <h3 className="text-sm leading-snug font-medium tracking-tight">{produit.modele}</h3>

          <p className="line-clamp-2 text-xs leading-relaxed text-muted">{produit.description}</p>

          <div className="flex items-center gap-0.5" aria-label={`Note ${produit.note.toFixed(1)} sur 5`}>
            {Array.from({ length: 5 }).map((_, i) => (
              <Star
                key={i}
                className={cn("size-3", i < Math.round(produit.note) ? "fill-amber-400 text-amber-400" : "text-muted/30")}
                aria-hidden
              />
            ))}
            <span className="ml-1 text-[11px] text-muted tabular-nums">{produit.note.toFixed(1)}/5</span>
          </div>

          <div className="flex flex-wrap items-center gap-1.5" aria-label={`${produit.couleurs.length} couleurs`}>
            {produit.couleurs.map((c, i) => (
              <button
                key={c.nom}
                type="button"
                onClick={() => setIndex(i)}
                aria-label={c.nom}
                aria-pressed={i === index}
                className={cn(
                  "grid size-5 place-items-center rounded-full ring-1 ring-transparent transition-all duration-200",
                  i === index && "ring-foreground/60",
                )}
              >
                <ColorDot nom={c.nom} className="size-3" />
              </button>
            ))}
          </div>

          <div className="mt-auto flex items-end justify-between gap-2 pt-2">
            <p className="text-[15px] font-semibold tracking-tight tabular-nums">{formatAr(produit.prix)}</p>
            <p className="text-[11px] text-muted tabular-nums">{produit.quantite} en stock</p>
          </div>
        </div>
      </article>
    </Tilt>
  );
}
