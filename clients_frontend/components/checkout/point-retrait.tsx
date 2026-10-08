import { MapPin, Phone, Store } from "lucide-react";
import { cn } from "@/lib/utils";
import type { CoordonneesBoutique } from "@/lib/types";

/**
 * Où venir chercher sa commande.
 *
 * Les coordonnées viennent toujours du serveur — du magasin qui détient les
 * produits commandés (`GET /api/boutiques/{id}/zones/` pendant le tunnel,
 * puis l'accusé de commande). Le client ne connaît pas d'autre adresse : sans
 * ce bloc, « Retrait sur place » ne lui dit ni où aller ni qui appeler.
 *
 * Rend `null` quand la boutique n'a rien renseigné, plutôt qu'un cadre vide.
 */
export function PointRetrait({
  nom,
  coordonnees,
  className,
}: {
  nom: string;
  coordonnees: CoordonneesBoutique;
  className?: string;
}) {
  const { adresse, telephone, telephone_2: telephone2 } = coordonnees;
  if (!adresse && !telephone) return null;

  return (
    <div className={cn("rounded-xl bg-foreground/[0.04] p-4", className)}>
      <p className="flex items-center gap-2 text-sm font-medium">
        <Store className="size-4 shrink-0 text-accent" aria-hidden />
        {nom}
      </p>
      <dl className="mt-2 space-y-1.5 text-sm text-muted">
        {adresse ? (
          <div className="flex items-start gap-2">
            <dt className="mt-0.5 shrink-0">
              <MapPin className="size-3.5" aria-hidden />
              <span className="sr-only">Adresse</span>
            </dt>
            <dd>{adresse}</dd>
          </div>
        ) : null}
        {telephone ? (
          <div className="flex items-start gap-2">
            <dt className="mt-0.5 shrink-0">
              <Phone className="size-3.5" aria-hidden />
              <span className="sr-only">Téléphone</span>
            </dt>
            <dd className="tabular-nums">
              <a href={`tel:${telephone}`} className="hover:text-foreground hover:underline">
                {telephone}
              </a>
              {telephone2 ? (
                <>
                  {" / "}
                  <a href={`tel:${telephone2}`} className="hover:text-foreground hover:underline">
                    {telephone2}
                  </a>
                </>
              ) : null}
            </dd>
          </div>
        ) : null}
      </dl>
    </div>
  );
}
