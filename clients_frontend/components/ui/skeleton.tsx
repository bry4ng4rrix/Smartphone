import { cn } from "@/lib/utils";

export function Skeleton({ className, ...props }: React.ComponentProps<"div">) {
  return <div className={cn("animate-pulse rounded-lg bg-foreground/[0.07]", className)} aria-hidden {...props} />;
}

/** Grille de cartes produit en cours de chargement. */
export function GrilleSkeleton({ nb = 8 }: { nb?: number }) {
  return (
    <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3 xl:grid-cols-4">
      {Array.from({ length: nb }).map((_, i) => (
        <div key={i} className="hairline overflow-hidden rounded-xl bg-surface/50">
          <Skeleton className="aspect-square rounded-none" />
          <div className="space-y-2 p-4">
            <Skeleton className="h-3 w-1/3" />
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-4 w-1/2" />
          </div>
        </div>
      ))}
    </div>
  );
}
