import Image from "next/image";
import { couleurCss } from "@/lib/couleurs";
import { cn } from "@/lib/utils";
import type { Produit } from "@/lib/types";

/**
 * Visuel du produit. `photo` est souvent `null` côté API : plutôt qu'une
 * image factice, on compose un aplat sobre à partir des vraies données du
 * produit (marque, sous-type, couleurs des variantes).
 */
export function ProductImage({
  produit,
  className,
  sizes = "(min-width: 1280px) 22vw, (min-width: 640px) 33vw, 50vw",
  priority = false,
}: {
  produit: Produit;
  className?: string;
  sizes?: string;
  priority?: boolean;
}) {
  if (produit.photo) {
    return (
      <div className={cn("relative overflow-hidden bg-surface-2", className)}>
        <Image
          src={produit.photo}
          alt={produit.nom_complet}
          fill
          sizes={sizes}
          priority={priority}
          className="object-cover transition-transform duration-700 ease-[cubic-bezier(0.22,1,0.36,1)] group-hover:scale-[1.04]"
        />
      </div>
    );
  }

  const teintes = produit.variantes.slice(0, 3).map((v) => couleurCss(v.couleur));
  const fond =
    teintes.length > 0
      ? `radial-gradient(90% 70% at 25% 20%, ${teintes[0]}3d, transparent 62%), radial-gradient(70% 60% at 78% 78%, ${
          teintes[1] ?? teintes[0]
        }33, transparent 62%), radial-gradient(60% 50% at 55% 50%, ${teintes[2] ?? teintes[0]}24, transparent 65%)`
      : undefined;

  return (
    <div
      className={cn("relative flex items-center justify-center overflow-hidden bg-surface-2", fond && "degrade-anime", className)}
      style={fond ? { backgroundImage: fond } : undefined}
      role="img"
      aria-label={`${produit.nom_complet} — visuel non disponible`}
    >
      <div className="grain absolute inset-0" aria-hidden />
      <div className="relative flex flex-col items-center gap-1 px-4 text-center">
        <span className="text-[10px] font-medium tracking-[0.22em] text-muted uppercase">{produit.marque.nom}</span>
        <span className="text-sm font-medium tracking-tight text-foreground/70">{produit.sous_type.nom}</span>
      </div>
    </div>
  );
}
