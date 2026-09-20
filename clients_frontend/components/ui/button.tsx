import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-full font-medium whitespace-nowrap transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] disabled:pointer-events-none disabled:opacity-45 [&_svg]:pointer-events-none [&_svg]:shrink-0 active:scale-[0.98]",
  {
    variants: {
      variant: {
        primaire:
          "bg-foreground text-background shadow-[0_10px_30px_-12px_color-mix(in_oklab,var(--foreground)_60%,transparent)] hover:shadow-[0_18px_44px_-16px_color-mix(in_oklab,var(--foreground)_70%,transparent)] hover:-translate-y-px",
        accent:
          "bg-accent text-accent-foreground shadow-[0_10px_30px_-12px_color-mix(in_oklab,var(--accent)_75%,transparent)] hover:shadow-[0_18px_44px_-14px_color-mix(in_oklab,var(--accent)_80%,transparent)] hover:-translate-y-px",
        verre: "glass text-foreground hover:bg-[var(--glass-strong)]",
        contour: "border border-border bg-transparent text-foreground hover:border-foreground/35 hover:bg-foreground/[0.04]",
        fantome: "text-muted hover:bg-foreground/[0.06] hover:text-foreground",
        danger: "bg-rose-600 text-white hover:bg-rose-700",
      },
      size: {
        sm: "h-9 px-4 text-[13px] [&_svg]:size-3.5",
        md: "h-11 px-6 text-sm [&_svg]:size-4",
        lg: "h-13 px-8 text-[15px] [&_svg]:size-[18px]",
        icone: "size-10 [&_svg]:size-[18px]",
        icone_sm: "size-9 [&_svg]:size-4",
      },
    },
    defaultVariants: { variant: "primaire", size: "md" },
  },
);

export type ButtonProps = React.ComponentProps<"button"> & VariantProps<typeof buttonVariants> & { chargement?: boolean };

export function Button({ className, variant, size, chargement, children, disabled, ...props }: ButtonProps) {
  return (
    <button
      className={cn(buttonVariants({ variant, size }), className)}
      disabled={disabled || chargement}
      aria-busy={chargement || undefined}
      {...props}
    >
      {chargement ? <span className="size-4 animate-spin rounded-full border-2 border-current border-t-transparent" aria-hidden /> : null}
      {children}
    </button>
  );
}

export { buttonVariants };
