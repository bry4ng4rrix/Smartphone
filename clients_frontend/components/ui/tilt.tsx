"use client";

import { usePointerTilt } from "@/lib/use-pointer-tilt";
import { cn } from "@/lib/utils";

/**
 * Enveloppe une carte pour la mettre en volume au survol (voir
 * `usePointerTilt` pour le détail et les garde-fous).
 *
 * À utiliser quand la carte est un élément à soi ; sur un élément qui existe
 * déjà (un `<Link>`, un `<article>`…), préférer le hook et répandre ses
 * propriétés directement dessus, pour ne pas ajouter un `<div>` de plus.
 */
export function Tilt({
  children,
  className,
  intensite = 6,
}: {
  children: React.ReactNode;
  className?: string;
  intensite?: number;
}) {
  const tilt = usePointerTilt<HTMLDivElement>(intensite);
  return (
    <div {...tilt} className={cn(className)}>
      {children}
    </div>
  );
}
