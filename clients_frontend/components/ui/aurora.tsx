import { cn } from "@/lib/utils";

/**
 * Fond dégradé animé : trois halos qui dérivent lentement, chacun sur sa
 * propre trajectoire et sa propre durée (17 s, 23 s, 29 s) pour qu'aucun
 * cycle ne se répète visiblement. Couleurs reprises du logo (turquoise,
 * framboise) et de l'accent de l'interface.
 *
 * `portee="page"` (défaut) : le halo est fixé en haut de la fenêtre et passe
 * DERRIÈRE l'en-tête flottant — sans lui, le fond de page apparaîtrait en
 * bande sombre au-dessus et en dessous de la section. Il s'efface vers le bas
 * pour se fondre dans la page.
 * `portee="bloc"` : le halo reste dans son conteneur (panneau, carte).
 *
 * L'animation ne touche que `transform` et `opacity` : elle est composée par
 * le GPU, sans recalcul de dégradé. `prefers-reduced-motion` la neutralise
 * (voir globals.css) et le halo reste alors simplement statique.
 */
export function Aurora({
  className,
  portee = "page",
  intensite = "normale",
}: {
  className?: string;
  portee?: "page" | "bloc";
  intensite?: "normale" | "discrete";
}) {
  return (
    <div
      aria-hidden
      className={cn(
        "pointer-events-none -z-10 overflow-hidden",
        portee === "page"
          ? "fixed inset-x-0 top-0 h-[min(88vh,900px)] [mask-image:linear-gradient(to_bottom,black_55%,transparent)]"
          : "absolute inset-0",
        intensite === "discrete" && "opacity-50",
        className,
      )}
    >
      <span className="aurora-blob aurora-blob-1" />
      <span className="aurora-blob aurora-blob-2" />
      <span className="aurora-blob aurora-blob-3" />
    </div>
  );
}
