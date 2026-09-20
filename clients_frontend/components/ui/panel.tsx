"use client";

import { Dialog } from "@base-ui/react/dialog";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Panneau latéral / feuille mobile, bâti sur Base UI Dialog (piège de focus,
 * Échap, `aria-modal`, verrouillage du défilement déjà gérés).
 * `cote` = "droite" pour le panier, "bas" pour les filtres sur mobile.
 */
export function Panel({
  ouvert,
  onOuvertChange,
  titre,
  description,
  cote = "droite",
  children,
  pied,
  className,
}: {
  ouvert: boolean;
  onOuvertChange: (ouvert: boolean) => void;
  titre: string;
  description?: string;
  cote?: "droite" | "bas";
  children: React.ReactNode;
  pied?: React.ReactNode;
  className?: string;
}) {
  return (
    <Dialog.Root open={ouvert} onOpenChange={onOuvertChange}>
      <Dialog.Portal>
        <Dialog.Backdrop className="fixed inset-0 z-[80] bg-black/35 backdrop-blur-[2px] transition-opacity duration-300 data-[ending-style]:opacity-0 data-[starting-style]:opacity-0" />
        <Dialog.Popup
          className={cn(
            "glass-strong fixed z-[81] flex flex-col transition-transform duration-400 ease-[cubic-bezier(0.22,1,0.36,1)]",
            cote === "droite"
              ? "inset-y-0 right-0 w-full max-w-md rounded-l-2xl data-[ending-style]:translate-x-full data-[starting-style]:translate-x-full"
              : "inset-x-0 bottom-0 max-h-[88vh] rounded-t-2xl data-[ending-style]:translate-y-full data-[starting-style]:translate-y-full",
            className,
          )}
        >
          <div className="flex items-start justify-between gap-4 border-b border-[var(--glass-border)] px-5 py-4">
            <div className="min-w-0">
              <Dialog.Title className="text-base font-medium tracking-tight">{titre}</Dialog.Title>
              {description ? <Dialog.Description className="mt-0.5 text-xs text-muted">{description}</Dialog.Description> : null}
            </div>
            <Dialog.Close
              aria-label="Fermer"
              className="-m-2 rounded-full p-2 text-muted transition-colors hover:bg-foreground/[0.06] hover:text-foreground"
            >
              <X className="size-4" aria-hidden />
            </Dialog.Close>
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 py-4">{children}</div>
          {pied ? <div className="border-t border-[var(--glass-border)] px-5 py-4">{pied}</div> : null}
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

/** Boîte de dialogue centrée (confirmations). */
export function Modal({
  ouvert,
  onOuvertChange,
  titre,
  description,
  children,
  className,
}: {
  ouvert: boolean;
  onOuvertChange: (ouvert: boolean) => void;
  titre: string;
  description?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <Dialog.Root open={ouvert} onOpenChange={onOuvertChange}>
      <Dialog.Portal>
        <Dialog.Backdrop className="fixed inset-0 z-[80] bg-black/40 backdrop-blur-[2px] transition-opacity duration-300 data-[ending-style]:opacity-0 data-[starting-style]:opacity-0" />
        <Dialog.Popup
          className={cn(
            "glass-strong fixed top-1/2 left-1/2 z-[81] w-[calc(100vw-2rem)] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-2xl p-6",
            "transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] data-[ending-style]:scale-95 data-[ending-style]:opacity-0 data-[starting-style]:scale-95 data-[starting-style]:opacity-0",
            className,
          )}
        >
          <Dialog.Title className="text-lg font-medium tracking-tight">{titre}</Dialog.Title>
          {description ? <Dialog.Description className="mt-2 text-sm text-muted">{description}</Dialog.Description> : null}
          <div className="mt-5">{children}</div>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const PanelClose = Dialog.Close;
