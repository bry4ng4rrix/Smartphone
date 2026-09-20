"use client";

import { createContext, useCallback, useContext, useMemo, useState } from "react";
import { CheckCircle2, CircleAlert, Info, X } from "lucide-react";
import { cn } from "@/lib/utils";

type Ton = "succes" | "erreur" | "info";
type Toast = { id: number; ton: Ton; titre: string; detail?: string };

type ToastApi = {
  succes: (titre: string, detail?: string) => void;
  erreur: (titre: string, detail?: string) => void;
  info: (titre: string, detail?: string) => void;
};

const ToastContext = createContext<ToastApi | null>(null);

const ICONES: Record<Ton, typeof Info> = { succes: CheckCircle2, erreur: CircleAlert, info: Info };
const COULEURS: Record<Ton, string> = {
  succes: "text-emerald-600 dark:text-emerald-400",
  erreur: "text-rose-600 dark:text-rose-400",
  info: "text-accent",
};

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const retirer = useCallback((id: number) => setToasts((t) => t.filter((x) => x.id !== id)), []);

  const pousser = useCallback(
    (ton: Ton, titre: string, detail?: string) => {
      const id = Date.now() + Math.random();
      setToasts((t) => [...t.slice(-2), { id, ton, titre, detail }]);
      setTimeout(() => retirer(id), ton === "erreur" ? 7000 : 4000);
    },
    [retirer],
  );

  const api = useMemo<ToastApi>(
    () => ({
      succes: (titre, detail) => pousser("succes", titre, detail),
      erreur: (titre, detail) => pousser("erreur", titre, detail),
      info: (titre, detail) => pousser("info", titre, detail),
    }),
    [pousser],
  );

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div
        aria-live="polite"
        aria-atomic="false"
        className="pointer-events-none fixed inset-x-0 bottom-0 z-[90] flex flex-col items-center gap-2 p-4 sm:bottom-auto sm:top-20 sm:right-4 sm:left-auto sm:items-end"
      >
        {toasts.map((t) => {
          const Icone = ICONES[t.ton];
          return (
            <div
              key={t.id}
              role="status"
              className="glass-strong pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-lg px-4 py-3 duration-300 animate-in fade-in slide-in-from-bottom-2 sm:slide-in-from-top-2"
            >
              <Icone className={cn("mt-0.5 size-4 shrink-0", COULEURS[t.ton])} aria-hidden />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium">{t.titre}</p>
                {t.detail ? <p className="mt-0.5 text-xs whitespace-pre-line text-muted">{t.detail}</p> : null}
              </div>
              <button
                type="button"
                onClick={() => retirer(t.id)}
                aria-label="Fermer la notification"
                className="-m-1 rounded-md p-1 text-muted transition-colors hover:text-foreground"
              >
                <X className="size-3.5" aria-hidden />
              </button>
            </div>
          );
        })}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastApi {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast doit être utilisé dans <ToastProvider>");
  return ctx;
}
