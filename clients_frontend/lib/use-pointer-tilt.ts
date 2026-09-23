"use client";

import type React from "react";
import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Inclinaison 3D pilotée par le pointeur, plus un reflet qui suit le curseur.
 *
 * Le hook écrit des variables CSS (`--tilt-x`, `--tilt-y`, `--tilt-rz`,
 * `--mx`, `--my`) au lieu de styles inline : aucun rendu React pendant le
 * déplacement, et le rendu du transform est laissé au compositeur. Les
 * mesures sont regroupées dans une `requestAnimationFrame` pour ne lire la
 * géométrie qu'une fois par image.
 *
 * Rien n'est posé quand l'appareil n'a pas de pointeur fin (tactile : il n'y
 * a pas de survol) ou que l'utilisateur demande moins d'animations — la
 * carte reste alors parfaitement plate, et aucun écouteur n'est attaché.
 */
export function usePointerTilt<T extends HTMLElement>(maxDeg = 5) {
  const ref = useRef<T>(null);
  const frame = useRef(0);
  const [actif, setActif] = useState(false);

  useEffect(() => {
    const fin = window.matchMedia("(hover: hover) and (pointer: fine)");
    const calme = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setActif(fin.matches && !calme.matches);
    sync();
    fin.addEventListener("change", sync);
    calme.addEventListener("change", sync);
    return () => {
      fin.removeEventListener("change", sync);
      calme.removeEventListener("change", sync);
    };
  }, []);

  useEffect(() => () => cancelAnimationFrame(frame.current), []);

  const onPointerMove = useCallback(
    (event: React.PointerEvent<T>) => {
      const el = ref.current;
      if (!actif || !el) return;
      const { clientX, clientY } = event;
      cancelAnimationFrame(frame.current);
      frame.current = requestAnimationFrame(() => {
        const r = el.getBoundingClientRect();
        const px = (clientX - r.left) / r.width;
        const py = (clientY - r.top) / r.height;
        // X et Y : la carte se penche vers le pointeur.
        el.style.setProperty("--tilt-y", `${(px - 0.5) * maxDeg * 2}deg`);
        el.style.setProperty("--tilt-x", `${(0.5 - py) * maxDeg * 2}deg`);
        // Z : un roulis discret (quart de l'amplitude) — au-delà, la carte
        // paraît de travers au lieu de paraître en volume.
        el.style.setProperty("--tilt-rz", `${(px - 0.5) * maxDeg * 0.5}deg`);
        // Position du reflet.
        el.style.setProperty("--mx", `${px * 100}%`);
        el.style.setProperty("--my", `${py * 100}%`);
      });
    },
    [actif, maxDeg],
  );

  const onPointerLeave = useCallback(() => {
    const el = ref.current;
    cancelAnimationFrame(frame.current);
    if (!el) return;
    el.style.setProperty("--tilt-x", "0deg");
    el.style.setProperty("--tilt-y", "0deg");
    el.style.setProperty("--tilt-rz", "0deg");
  }, []);

  // Sans pointeur fin, on ne renvoie que la ref : pas d'attribut `data-tilt`,
  // donc aucune règle CSS 3D ne s'applique.
  return actif ? { ref, onPointerMove, onPointerLeave, "data-tilt": true as const } : { ref };
}
