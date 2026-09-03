"use client";

import { useEffect, useState } from "react";
import { djangoClient } from "@/lib/django-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Store,
  ArrowLeftRight,
  ShoppingCart,
  Search,
  X,
  Check,
  Loader2,
  ChevronDown,
  ChevronRight,
  Plus,
} from "lucide-react";
import { toast } from "sonner";

export interface TransferCartItem {
  id: number;
  name: string;
  reference: string;
  quantity: number;
  maxQuantity: number;
  variantId?: number;
  variantLabel?: string;
}

export interface TransferStore {
  magasin_id: number;
  shop_name: string;
  shop_logo?: string | null;
}

interface ProductVariant {
  id: number;
  size: string | null;
  color: string | null;
  quantity: number;
}

interface TransferProductsPanelProps {
  sourceStore: TransferStore;
  stores: TransferStore[];
  initialCart?: TransferCartItem[];
  onSuccess?: () => void;
}

const SIZE_ORDER = ["XS", "S", "M", "L", "XL", "2XL", "3XL", "4XL"];

const formatVariantLabel = (size?: string | null, color?: string | null) => {
  const parts = [size, color].filter((p): p is string =>
    Boolean(p && p.trim()),
  );
  return parts.join(" / ");
};

const cartKey = (id: number, variantId?: number | null) =>
  variantId != null ? `${id}:${variantId}` : `${id}`;

/**
 * Guts of the product-transfer flow (source product list, cart, destination
 * picker), shared by TransferProductsDialog (modal) and the dedicated
 * /transferts page. Remount it (e.g. via a `key` on sourceStore.magasin_id)
 * to reset its internal state when the source store changes.
 */
export function TransferProductsPanel({
  sourceStore,
  stores,
  initialCart = [],
  onSuccess,
}: TransferProductsPanelProps) {
  const [destinationStoreId, setDestinationStoreId] = useState<number | "">("");
  const [destinationSearchTerm, setDestinationSearchTerm] = useState("");
  const [sourceProducts, setSourceProducts] = useState<any[]>([]);
  const [productSearchTerm, setProductSearchTerm] = useState("");
  const [transferCart, setTransferCart] = useState<TransferCartItem[]>(initialCart);
  const [qtyInputs, setQtyInputs] = useState<Record<string, number>>(() =>
    initialCart.reduce<Record<string, number>>((acc, item) => {
      acc[cartKey(item.id, item.variantId)] = item.quantity;
      return acc;
    }, {}),
  );
  const [expandedProductIds, setExpandedProductIds] = useState<Set<number>>(
    new Set(),
  );
  const [loadingProducts, setLoadingProducts] = useState(false);
  const [submittingTransfer, setSubmittingTransfer] = useState(false);

  useEffect(() => {
    const magasinId = sourceStore.magasin_id;
    if (!magasinId) {
      setSourceProducts([]);
      return;
    }
    const fetchProducts = async () => {
      setLoadingProducts(true);
      try {
        const products = await djangoClient.products.list({
          magasin_id: magasinId,
        });
        setSourceProducts(
          products.filter((p) => Number(p.magasin) === Number(magasinId)),
        );
      } catch (err) {
        console.error("Failed to load source products", err);
        toast.error("Erreur de chargement des produits");
      } finally {
        setLoadingProducts(false);
      }
    };
    fetchProducts();
  }, [sourceStore.magasin_id]);

  const getQtyInput = (key: string, max: number) => {
    const raw = qtyInputs[key] ?? 1;
    return Math.min(Math.max(1, raw), Math.max(max, 1));
  };

  const setQtyInput = (key: string, value: number, max: number) => {
    const clamped = Math.min(Math.max(1, value), Math.max(max, 1));
    setQtyInputs((prev) => ({ ...prev, [key]: clamped }));
  };

  const toggleExpand = (productId: number) => {
    setExpandedProductIds((prev) => {
      const next = new Set(prev);
      if (next.has(productId)) next.delete(productId);
      else next.add(productId);
      return next;
    });
  };

  const addToTransferCart = (product: any) => {
    const stock = Number(product.initial_quantity ?? 0);
    if (stock <= 0) {
      toast.error(`${product.name} : stock insuffisant`);
      return;
    }
    if (
      transferCart.some(
        (item) => item.id === product.id && item.variantId == null,
      )
    ) {
      toast.info(`${product.name} est déjà dans le panier`);
      return;
    }
    const quantity = getQtyInput(cartKey(product.id), stock);
    setTransferCart((prev) => [
      ...prev,
      {
        id: product.id,
        name: product.name,
        reference: product.reference,
        quantity,
        maxQuantity: stock,
      },
    ]);
    toast.success(`${quantity} × ${product.name} ajouté au panier`);
  };

  const addVariantToTransferCart = (product: any, variant: ProductVariant) => {
    const stock = Number(variant.quantity ?? 0);
    if (stock <= 0) {
      toast.error(`${product.name} : stock insuffisant pour cette variante`);
      return;
    }
    if (
      transferCart.some(
        (item) => item.id === product.id && item.variantId === variant.id,
      )
    ) {
      toast.info("Cette variante est déjà dans le panier");
      return;
    }
    const quantity = getQtyInput(cartKey(product.id, variant.id), stock);
    const variantLabel = formatVariantLabel(variant.size, variant.color);
    setTransferCart((prev) => [
      ...prev,
      {
        id: product.id,
        name: product.name,
        reference: product.reference,
        quantity,
        maxQuantity: stock,
        variantId: variant.id,
        variantLabel,
      },
    ]);
    toast.success(
      `${quantity} × ${product.name}${variantLabel ? ` (${variantLabel})` : ""} ajouté au panier`,
    );
  };

  const removeFromTransferCart = (productId: number, variantId?: number) => {
    setTransferCart((prev) =>
      prev.filter(
        (item) => !(item.id === productId && item.variantId === variantId),
      ),
    );
  };

  const updateTransferCartQuantity = (
    productId: number,
    variantId: number | undefined,
    value: number,
  ) => {
    setTransferCart((prev) =>
      prev.map((item) =>
        item.id === productId && item.variantId === variantId
          ? {
              ...item,
              quantity: Math.min(Math.max(1, value), item.maxQuantity),
            }
          : item,
      ),
    );
  };

  const transferCartTotalQty = transferCart.reduce(
    (sum, item) => sum + item.quantity,
    0,
  );

  const filteredSourceProducts = sourceProducts.filter(
    (p) =>
      p.name?.toLowerCase().includes(productSearchTerm.toLowerCase()) ||
      p.reference?.toLowerCase().includes(productSearchTerm.toLowerCase()),
  );

  const destinationStores = stores.filter(
    (s) =>
      s.magasin_id !== sourceStore.magasin_id &&
      s.shop_name.toLowerCase().includes(destinationSearchTerm.toLowerCase()),
  );

  const selectedDestinationStore = stores.find(
    (s) => s.magasin_id === destinationStoreId,
  );

  const handleTransferSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!destinationStoreId || transferCart.length === 0) {
      toast.error("Sélectionnez des produits et un magasin de destination");
      return;
    }
    setSubmittingTransfer(true);
    try {
      const items = transferCart
        .filter((p) => p.variantId != null)
        .map((p) => ({ variant_id: p.variantId as number, quantity: p.quantity }));
      if (items.length === 0) {
        toast.error("Sélectionnez au moins une couleur à transférer");
        return;
      }
      await djangoClient.transfers.transfer(
        sourceStore.magasin_id,
        destinationStoreId as number,
        items,
      );
      toast.success("Transfert effectué");
      onSuccess?.();
    } catch (err) {
      console.error(err);
      toast.error("Erreur lors du transfert");
    } finally {
      setSubmittingTransfer(false);
    }
  };

  return (
    <form
      onSubmit={handleTransferSubmit}
      className="flex flex-col gap-4 min-h-0 flex-1 h-full"
    >
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 min-h-0 flex-1">
        <div className="flex flex-col border rounded-lg min-h-0">
          <div className="p-3 border-b space-y-2">
            <Label>Produits du magasin</Label>
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Rechercher un produit..."
                value={productSearchTerm}
                onChange={(e) => setProductSearchTerm(e.target.value)}
                className="pl-9"
              />
            </div>
          </div>
          <ScrollArea className="flex-1 min-h-0">
            {loadingProducts ? (
              <div className="flex items-center justify-center h-32 text-muted-foreground">
                <Loader2 className="h-5 w-5 animate-spin mr-2" />
                Chargement...
              </div>
            ) : filteredSourceProducts.length === 0 ? (
              <p className="p-4 text-sm text-muted-foreground text-center">
                {sourceProducts.length === 0
                  ? "Aucun produit dans ce magasin"
                  : "Aucun résultat"}
              </p>
            ) : (
              <div className="p-2 space-y-1">
                {filteredSourceProducts.map((product) => {
                  const variants: ProductVariant[] = Array.isArray(
                    product.variants,
                  )
                    ? product.variants
                    : [];
                  const hasVariants = variants.length > 0;

                  if (!hasVariants) {
                    const inCart = transferCart.some(
                      (item) =>
                        item.id === product.id && item.variantId == null,
                    );
                    const stock = Number(product.initial_quantity ?? 0);
                    const key = cartKey(product.id);
                    const qty = getQtyInput(key, stock);
                    return (
                      <div
                        key={product.id}
                        className="flex items-center justify-between gap-2 rounded-md border px-3 py-2 hover:bg-muted/50"
                      >
                        <div className="min-w-0 flex-1">
                          <p className="text-sm font-medium truncate">
                            {product.name}
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {product.reference} · Stock : {stock}
                          </p>
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          <Input
                            type="number"
                            min={1}
                            max={stock}
                            value={qty}
                            disabled={inCart || stock <= 0}
                            onChange={(e) =>
                              setQtyInput(
                                key,
                                Number(e.target.value),
                                stock,
                              )
                            }
                            className="w-16 h-8 text-center px-1"
                          />
                          <Button
                            type="button"
                            size="sm"
                            variant={inCart ? "secondary" : "outline"}
                            disabled={inCart || stock <= 0}
                            onClick={() => addToTransferCart(product)}
                          >
                            {inCart ? (
                              <>
                                <Check className="h-3.5 w-3.5 mr-1" />
                                Sélectionné
                              </>
                            ) : (
                              "Sélectionner"
                            )}
                          </Button>
                        </div>
                      </div>
                    );
                  }

                  const totalStock = variants.reduce(
                    (s, v) => s + Number(v.quantity || 0),
                    0,
                  );
                  const expanded = expandedProductIds.has(product.id);
                  const sortedVariants = [...variants].sort((a, b) => {
                    const ia = SIZE_ORDER.indexOf(
                      (a.size ?? "").toUpperCase(),
                    );
                    const ib = SIZE_ORDER.indexOf(
                      (b.size ?? "").toUpperCase(),
                    );
                    return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
                  });

                  return (
                    <div
                      key={product.id}
                      className="rounded-md border overflow-hidden"
                    >
                      <button
                        type="button"
                        onClick={() => toggleExpand(product.id)}
                        className="w-full flex items-center gap-2 px-3 py-2 hover:bg-muted/50 text-left"
                      >
                        {expanded ? (
                          <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground" />
                        ) : (
                          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
                        )}
                        <div className="min-w-0 flex-1">
                          <p className="text-sm font-medium truncate">
                            {product.name}
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {product.reference} · {variants.length}{" "}
                            variante(s) · Stock : {totalStock}
                          </p>
                        </div>
                      </button>
                      {expanded && (
                        <div className="border-t bg-muted/20 px-2 py-2 space-y-1">
                          {sortedVariants.map((variant) => {
                            const vLabel = formatVariantLabel(
                              variant.size,
                              variant.color,
                            );
                            const vStock = Number(variant.quantity ?? 0);
                            const inCart = transferCart.some(
                              (item) =>
                                item.id === product.id &&
                                item.variantId === variant.id,
                            );
                            const key = cartKey(product.id, variant.id);
                            const qty = getQtyInput(key, vStock);
                            return (
                              <div
                                key={variant.id}
                                className="flex items-center justify-between gap-2 rounded-md border bg-background px-2 py-1.5"
                              >
                                <div className="min-w-0 text-xs">
                                  <span className="font-semibold">
                                    {vLabel || "Standard"}
                                  </span>
                                  <span className="text-muted-foreground">
                                    {" "}
                                    · Stock : {vStock}
                                  </span>
                                </div>
                                <div className="flex items-center gap-1.5 shrink-0">
                                  <Input
                                    type="number"
                                    min={1}
                                    max={vStock}
                                    value={qty}
                                    disabled={inCart || vStock <= 0}
                                    onChange={(e) =>
                                      setQtyInput(
                                        key,
                                        Number(e.target.value),
                                        vStock,
                                      )
                                    }
                                    className="w-14 h-7 text-center px-1 text-xs"
                                  />
                                  <Button
                                    type="button"
                                    size="sm"
                                    variant={
                                      inCart ? "secondary" : "outline"
                                    }
                                    disabled={inCart || vStock <= 0}
                                    className="h-7 px-2"
                                    onClick={() =>
                                      addVariantToTransferCart(
                                        product,
                                        variant,
                                      )
                                    }
                                  >
                                    {inCart ? (
                                      <Check className="h-3.5 w-3.5" />
                                    ) : (
                                      <Plus className="h-3.5 w-3.5" />
                                    )}
                                  </Button>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </ScrollArea>
        </div>

        <div className="flex flex-col gap-4 min-h-0">
          <div className="flex flex-col border rounded-lg flex-1 min-h-0">
            <div className="p-3 border-b flex items-center justify-between">
              <div className="flex items-center gap-2">
                <ShoppingCart className="h-4 w-4" />
                <Label>Panier de transfert</Label>
              </div>
              <Badge variant="secondary">
                {transferCartTotalQty} unité(s)
              </Badge>
            </div>
            <ScrollArea className="flex-1 min-h-0">
              {transferCart.length === 0 ? (
                <p className="p-4 text-sm text-muted-foreground text-center">
                  Aucun produit sélectionné
                </p>
              ) : (
                <div className="p-2 space-y-1">
                  {transferCart.map((item) => (
                    <div
                      key={cartKey(item.id, item.variantId)}
                      className="flex items-center justify-between gap-2 rounded-md bg-muted/50 px-3 py-2"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-medium truncate">
                          {item.name}
                          {item.variantLabel && (
                            <span className="text-muted-foreground font-normal">
                              {" "}
                              — {item.variantLabel}
                            </span>
                          )}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {item.reference} · max {item.maxQuantity}
                        </p>
                      </div>
                      <div className="flex items-center gap-1 shrink-0">
                        <Input
                          type="number"
                          min={1}
                          max={item.maxQuantity}
                          value={item.quantity}
                          onChange={(e) =>
                            updateTransferCartQuantity(
                              item.id,
                              item.variantId,
                              Number(e.target.value),
                            )
                          }
                          className="w-16 h-8 text-center px-1"
                        />
                        <Button
                          type="button"
                          size="icon"
                          variant="ghost"
                          className="h-7 w-7 text-muted-foreground hover:text-destructive"
                          onClick={() =>
                            removeFromTransferCart(item.id, item.variantId)
                          }
                        >
                          <X className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </ScrollArea>
          </div>

          <div className="flex flex-col border rounded-lg">
            <div className="p-3 border-b space-y-2">
              <Label>Magasin de destination</Label>
              <div className="relative">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Rechercher un magasin..."
                  value={destinationSearchTerm}
                  onChange={(e) => setDestinationSearchTerm(e.target.value)}
                  className="pl-9"
                />
              </div>
              {selectedDestinationStore && (
                <div className="flex items-center gap-2 rounded-md border border-primary/30 bg-primary/5 px-3 py-2">
                  <Store className="h-4 w-4 text-primary shrink-0" />
                  <span className="text-sm font-medium">
                    {selectedDestinationStore.shop_name}
                  </span>
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-6 w-6 ml-auto shrink-0"
                    onClick={() => setDestinationStoreId("")}
                  >
                    <X className="h-3.5 w-3.5" />
                  </Button>
                </div>
              )}
            </div>
            <ScrollArea className="h-40">
              <div className="p-2 space-y-1">
                {destinationStores.length === 0 ? (
                  <p className="p-2 text-sm text-muted-foreground text-center">
                    Aucun magasin trouvé
                  </p>
                ) : (
                  destinationStores.map((store) => (
                    <button
                      key={store.magasin_id}
                      type="button"
                      onClick={() =>
                        setDestinationStoreId(store.magasin_id)
                      }
                      className={`w-full flex items-center gap-2 rounded-md px-3 py-2 text-left text-sm transition-colors hover:bg-muted/50 ${
                        destinationStoreId === store.magasin_id
                          ? "bg-primary/10 border border-primary/30 font-medium"
                          : "border border-transparent"
                      }`}
                    >
                      {store.shop_logo ? (
                        <img
                          src={store.shop_logo}
                          alt=""
                          className="h-5 w-5 rounded-full object-cover"
                        />
                      ) : (
                        <Store className="h-4 w-4 text-muted-foreground shrink-0" />
                      )}
                      {store.shop_name}
                      {destinationStoreId === store.magasin_id && (
                        <Check className="h-4 w-4 ml-auto text-primary shrink-0" />
                      )}
                    </button>
                  ))
                )}
              </div>
            </ScrollArea>
          </div>
        </div>
      </div>

      <Button
        type="submit"
        disabled={
          submittingTransfer ||
          transferCart.length === 0 ||
          !destinationStoreId
        }
        className="w-full"
      >
        {submittingTransfer ? (
          <>
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Transfert en cours...
          </>
        ) : (
          <>
            <ArrowLeftRight className="mr-2 h-4 w-4" />
            Transférer{" "}
            {transferCartTotalQty > 0 ? `${transferCartTotalQty} unité(s)` : ""}
          </>
        )}
      </Button>
    </form>
  );
}
