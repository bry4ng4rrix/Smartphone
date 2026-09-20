import { couleurCss } from "@/lib/couleurs";
import { cn } from "@/lib/utils";

export function ColorDot({ nom, className }: { nom: string; className?: string }) {
  return (
    <span
      aria-hidden
      className={cn("inline-block size-3 shrink-0 rounded-full ring-1 ring-black/10 dark:ring-white/15", className)}
      style={{ background: couleurCss(nom) }}
    />
  );
}
