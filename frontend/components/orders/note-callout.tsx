"use client";

import { ClipboardList, Truck } from "lucide-react";

/**
 * Note destinée au préparateur ou au livreur — encart très visible (fond
 * coloré, bordure épaisse, icône, texte agrandi) pour que la consigne du
 * gérant ne passe pas inaperçue sur la liste, la fiche et la confirmation
 * (§ demande). Ambre = préparateur, bleu = livreur.
 */
export function NoteCallout({
  role,
  text,
  compact = false,
  className = "",
}: {
  role: "preparateur" | "livreur";
  text?: string | null;
  /** Variante réduite pour une ligne de tableau ou une carte. */
  compact?: boolean;
  className?: string;
}) {
  const contenu = (text || "").trim();
  if (!contenu) return null;
  const prep = role === "preparateur";
  const Icon = prep ? ClipboardList : Truck;
  const couleurs = prep
    ? "border-amber-400 bg-amber-50 text-amber-950 dark:border-amber-500 dark:bg-amber-950/40 dark:text-amber-100"
    : "border-sky-400 bg-sky-50 text-sky-950 dark:border-sky-500 dark:bg-sky-950/40 dark:text-sky-100";
  const accent = prep ? "text-amber-700 dark:text-amber-300" : "text-sky-700 dark:text-sky-300";
  return (
    <div
      role="note"
      className={`rounded-md border-l-4 border ${couleurs} ${compact ? "px-2.5 py-1.5" : "px-3 py-2.5"} ${className}`}
    >
      <div className={`flex items-center gap-1.5 font-semibold uppercase tracking-wide ${accent} ${compact ? "text-[10px]" : "text-xs"}`}>
        <Icon className={compact ? "h-3.5 w-3.5" : "h-4 w-4"} />
        {prep ? "Note pour le préparateur" : "Note pour le livreur"}
      </div>
      <p className={`mt-0.5 whitespace-pre-wrap break-words font-medium leading-snug ${compact ? "text-sm" : "text-base"}`}>
        {contenu}
      </p>
    </div>
  );
}
