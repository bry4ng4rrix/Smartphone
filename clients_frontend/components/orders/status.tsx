import { Check, Circle } from "lucide-react";
import { CLASSES_TON, DESCRIPTION_STATUT, EST_TERMINAL, ETAPES_SUIVI, TON_STATUT } from "@/lib/statuts";
import { cn, formatDateTime } from "@/lib/utils";
import type { Commande, Statut } from "@/lib/types";
import { Tilt } from "@/components/ui/tilt";

export function StatutBadge({ statut, label, className }: { statut: Statut; label: string; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset",
        CLASSES_TON[TON_STATUT[statut]],
        className,
      )}
    >
      <span className="size-1.5 rounded-full bg-current" aria-hidden />
      {label}
    </span>
  );
}

/** Suivi de commande : l'avancement réel vient du statut renvoyé par l'API. */
export function Timeline({ commande }: { commande: Commande }) {
  const terminee = EST_TERMINAL[commande.statut];
  const horsParcours = terminee && commande.statut !== "LIVRE";

  if (horsParcours) {
    return (
      <Tilt className="hairline relative rounded-xl bg-surface/50 p-5" intensite={3}>
        <StatutBadge statut={commande.statut} label={commande.statut_label} />
        <p className="mt-3 text-sm text-muted">{DESCRIPTION_STATUT[commande.statut]}</p>
        <p className="mt-1 text-xs text-muted">Dernière mise à jour le {formatDateTime(commande.updated_at)}</p>
      </Tilt>
    );
  }

  const index = ETAPES_SUIVI.indexOf(commande.statut);

  return (
    <ol className="hairline space-y-0 rounded-xl bg-surface/50 p-5">
      {ETAPES_SUIVI.map((etape, i) => {
        const passe = i < index;
        const actif = i === index;
        return (
          <li key={etape} className="flex gap-3.5 pb-5 last:pb-0">
            <div className="flex flex-col items-center">
              <span
                className={cn(
                  "grid size-6 shrink-0 place-items-center rounded-full ring-1 transition-colors",
                  actif
                    ? "bg-accent text-accent-foreground ring-accent"
                    : passe
                      ? "bg-foreground/[0.07] text-foreground ring-transparent"
                      : "text-muted/50 ring-border",
                )}
                aria-hidden
              >
                {passe ? <Check className="size-3" /> : <Circle className={cn("size-1.5", actif && "fill-current")} />}
              </span>
              {i < ETAPES_SUIVI.length - 1 ? (
                <span className={cn("mt-1 w-px flex-1", passe ? "bg-foreground/20" : "bg-border")} aria-hidden />
              ) : null}
            </div>

            <div className="-mt-0.5 pb-1">
              <p className={cn("text-sm", actif ? "font-medium" : passe ? "text-foreground" : "text-muted")}>
                {etape === commande.statut ? commande.statut_label : LIBELLES[etape]}
              </p>
              {actif ? <p className="mt-0.5 text-xs text-muted">{DESCRIPTION_STATUT[etape]}</p> : null}
            </div>
          </li>
        );
      })}
    </ol>
  );
}

/** Libellés d'étape (l'API ne renvoie que celui du statut courant). */
const LIBELLES: Record<Statut, string> = {
  EN_ATTENTE_APPROBATION: "En attente d'approbation",
  NOUVELLE: "Validée par la boutique",
  EN_PREPARATION: "En préparation",
  PRETE: "Prête",
  EN_LIVRAISON: "En livraison",
  LIVRE: "Livrée",
  RETOUR: "Retour",
  ANNULEE: "Annulée",
};
