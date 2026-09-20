import { cn } from "@/lib/utils";

export function Badge({ className, children, ...props }: React.ComponentProps<"span">) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-medium tracking-wide ring-1 ring-inset",
        "bg-foreground/[0.06] text-muted ring-foreground/10",
        className,
      )}
      {...props}
    >
      {children}
    </span>
  );
}
