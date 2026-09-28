"use client";

import { Check } from "lucide-react";
import { ETAPES, indexEtape, type Etape } from "@/lib/commande";
import { cn } from "@/lib/utils";

/**
 * Fil d'Ariane du tunnel : où l'on en est, et ce qu'il reste.
 *
 * Les étapes déjà franchies sont cliquables — c'est ce qui rend chaque
 * information modifiable jusqu'au bout, sans jamais perdre la saisie.
 */
export function Etapes({
  courante,
  atteinte,
  onAller,
}: {
  courante: Etape;
  /** Étape la plus avancée déjà validée : on ne saute pas en avant. */
  atteinte: Etape;
  onAller: (etape: Etape) => void;
}) {
  const iCourante = indexEtape(courante);
  const iAtteinte = indexEtape(atteinte);

  return (
    <ol className="mb-8 flex flex-wrap items-center gap-x-2 gap-y-3" aria-label="Étapes de la commande">
      {ETAPES.map((etape, i) => {
        const passee = i < iCourante;
        const active = i === iCourante;
        const accessible = i <= iAtteinte;

        return (
          <li key={etape.cle} className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => accessible && onAller(etape.cle)}
              disabled={!accessible}
              aria-current={active ? "step" : undefined}
              className={cn(
                "flex items-center gap-2 rounded-full py-1.5 pr-3.5 pl-1.5 text-[13px] transition-colors",
                active && "bg-foreground text-background",
                !active && accessible && "text-muted hover:bg-foreground/[0.05] hover:text-foreground",
                !accessible && "cursor-not-allowed text-muted/50",
              )}
            >
              <span
                className={cn(
                  "grid size-6 shrink-0 place-items-center rounded-full text-[11px] font-semibold tabular-nums",
                  active ? "bg-background/20" : passee ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400" : "bg-foreground/[0.07]",
                )}
              >
                {passee ? <Check className="size-3.5" aria-hidden /> : i + 1}
              </span>
              <span className="font-medium">{etape.titre}</span>
            </button>

            {i < ETAPES.length - 1 ? (
              <span className="h-px w-4 bg-border sm:w-6" aria-hidden />
            ) : null}
          </li>
        );
      })}
    </ol>
  );
}
