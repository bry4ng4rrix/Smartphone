"use client";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  TransferProductsPanel,
  type TransferCartItem,
  type TransferStore,
} from "@/components/transfer-products-panel";

export type { TransferCartItem, TransferStore };

interface TransferProductsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  sourceStore: TransferStore | null;
  stores: TransferStore[];
  initialCart?: TransferCartItem[];
  onSuccess?: () => void;
}

export function TransferProductsDialog({
  open,
  onOpenChange,
  sourceStore,
  stores,
  initialCart = [],
  onSuccess,
}: TransferProductsDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[97vw] max-w-[97vw] h-[95vh] max-h-[95vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <DialogTitle>Transfert de produits</DialogTitle>
          <DialogDescription>
            Depuis{" "}
            <span className="font-medium text-foreground">
              {sourceStore?.shop_name}
            </span>{" "}
            — sélectionnez des produits (et leurs variantes) et choisissez le
            magasin de destination.
          </DialogDescription>
        </DialogHeader>

        {sourceStore && (
          <TransferProductsPanel
            key={sourceStore.magasin_id}
            sourceStore={sourceStore}
            stores={stores}
            initialCart={initialCart}
            onSuccess={() => {
              onOpenChange(false);
              onSuccess?.();
            }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}
