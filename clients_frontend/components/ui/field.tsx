"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

/** Champ de formulaire : libellé lié, aide, erreurs de l'API (aria-describedby). */
export function Field({
  label,
  htmlFor,
  aide,
  erreurs,
  children,
  className,
}: {
  label: string;
  htmlFor: string;
  aide?: string;
  erreurs?: string[];
  children: React.ReactNode;
  className?: string;
}) {
  const idAide = `${htmlFor}-aide`;
  const idErreur = `${htmlFor}-erreur`;
  return (
    <div className={cn("space-y-1.5", className)}>
      <label htmlFor={htmlFor} className="block text-[13px] font-medium text-foreground">
        {label}
      </label>
      {children}
      {aide && !erreurs?.length ? (
        <p id={idAide} className="text-xs text-muted">
          {aide}
        </p>
      ) : null}
      {erreurs?.length ? (
        <p id={idErreur} className="text-xs whitespace-pre-line text-rose-600 dark:text-rose-400">
          {erreurs.join("\n")}
        </p>
      ) : null}
    </div>
  );
}

const baseChamp =
  "w-full rounded-lg border border-border bg-surface/60 px-4 text-sm text-foreground transition-colors placeholder:text-muted/70 focus:border-accent/60 focus:bg-surface disabled:opacity-50";

export function Input({ className, ...props }: React.ComponentProps<"input">) {
  return <input className={cn(baseChamp, "h-11", className)} {...props} />;
}

export function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
  return <textarea className={cn(baseChamp, "min-h-24 py-3 leading-relaxed", className)} {...props} />;
}

export function Select({ className, children, ...props }: React.ComponentProps<"select">) {
  return (
    <select
      className={cn(
        baseChamp,
        "h-11 appearance-none bg-[length:1rem] bg-[right_0.9rem_center] bg-no-repeat pr-10",
        "bg-[url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 24 24%22 fill=%22none%22 stroke=%22%23888%22 stroke-width=%222%22><path d=%22M6 9l6 6 6-6%22/></svg>')]",
        className,
      )}
      {...props}
    >
      {children}
    </select>
  );
}
