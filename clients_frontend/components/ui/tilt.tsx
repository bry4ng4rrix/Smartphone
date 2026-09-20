"use client";

import { useCallback, useRef } from "react";
import { cn } from "@/lib/utils";

/**
 * Inclinaison 3D au pointeur : deux variables CSS mises à jour au survol,
 * aucune dépendance, aucun re-rendu React. Désactivée au clavier, sur les
 * pointeurs grossiers (tactile) et si `prefers-reduced-motion` est demandé
 * (voir globals.css).
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
  const ref = useRef<HTMLDivElement>(null);

  const bouger = useCallback(
    (e: React.PointerEvent<HTMLDivElement>) => {
      const el = ref.current;
      if (!el || e.pointerType !== "mouse") return;
      const r = el.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      el.style.setProperty("--tilt-y", `${x * intensite}deg`);
      el.style.setProperty("--tilt-x", `${-y * intensite}deg`);
    },
    [intensite],
  );

  const quitter = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    el.style.setProperty("--tilt-x", "0deg");
    el.style.setProperty("--tilt-y", "0deg");
  }, []);

  return (
    <div ref={ref} onPointerMove={bouger} onPointerLeave={quitter} className={cn("tilt-surface", className)}>
      {children}
    </div>
  );
}
