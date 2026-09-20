import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

export function EmptyState({
  icone: Icone,
  titre,
  description,
  action,
  className,
}: {
  icone: LucideIcon;
  titre: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center justify-center rounded-xl px-6 py-16 text-center", className)}>
      <span className="glass mb-5 flex size-14 items-center justify-center rounded-full text-muted">
        <Icone className="size-6" aria-hidden />
      </span>
      <p className="text-lg font-medium tracking-tight">{titre}</p>
      {description ? <p className="mt-2 max-w-sm text-sm text-muted">{description}</p> : null}
      {action ? <div className="mt-6">{action}</div> : null}
    </div>
  );
}
