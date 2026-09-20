"use client";

import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";

/** Apparition à l'entrée dans le viewport — un seul IntersectionObserver par bloc. */
export function Reveal({
  children,
  className,
  delai = 0,
}: {
  children: React.ReactNode;
  className?: string;
  delai?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (typeof IntersectionObserver === "undefined") {
      el.dataset.visible = "true";
      return;
    }
    const observateur = new IntersectionObserver(
      ([entree]) => {
        if (entree.isIntersecting) {
          el.dataset.visible = "true";
          observateur.disconnect();
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.05 },
    );
    observateur.observe(el);
    return () => observateur.disconnect();
  }, []);

  return (
    <div ref={ref} className={cn("reveal", className)} style={delai ? { transitionDelay: `${delai}ms` } : undefined}>
      {children}
    </div>
  );
}
