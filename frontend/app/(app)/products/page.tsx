"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { djangoClient } from "@/lib/django-client";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { useRealtimeRefresh } from "@/lib/hooks/useRealtimeRefresh";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Plus,
  Trash2,
  Pencil,
  Search,
  Package,
  RefreshCw,
  ArrowUpCircle,
  ArrowDownCircle,
  Tag,
} from "lucide-react";
import { toast } from "sonner";

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat("fr-MG").format(Math.round(Number(n || 0))) + " Ar";

export default function ProductsPage() {
  const { isGerant, loading: userLoading } = useCurrentUser();
  const [references, setReferences] = useState<any[]>([]);
  const [categories, setCategories] = useState<any[]>([]);
  const [types, setTypes] = useState<any[]>([]);
  const [brands, setBrands] = useState<any[]>([]);
  const [colors, setColors] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<string>("ALL");
  const [typeFilter, setTypeFilter] = useState<string>("ALL");
  const [brandFilter, setBrandFilter] = useState<string>("ALL");
  const [createOpen, setCreateOpen] = useState(false);
  const [manageBrandsOpen, setManageBrandsOpen] = useState(false);
  const [variantsOf, setVariantsOf] = useState<any | null>(null);
  const [editTarget, setEditTarget] = useState<any | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<any | null>(null);

  const fetchAll = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const [refs, cats, tps, brs, cols] = await Promise.all([
        djangoClient.catalog.references.list(),
        djangoClient.catalog.categories.list(),
        djangoClient.catalog.types.list(),
        djangoClient.catalog.brands.list(),
        djangoClient.catalog.colors.list(),
      ]);
      setReferences(refs);
      setCategories(cats);
      setTypes(tps);
      setBrands(brs);
      setColors(cols);
    } catch (err: any) {
      toast.error(err.message || "Erreur de chargement du catalogue");
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useRealtimeRefresh(["product_variant", "stock_movement"], () =>
    fetchAll(true),
  );
  useEffect(() => {
    if (!userLoading) fetchAll();
  }, [userLoading, fetchAll]);

  // Types du catalogue exposent leur `category` (id) — pas de champ `category`
  // direct sur la référence (seulement `category_name` en lecture), donc on
  // reconstruit le lien type -> catégorie côté client pour filtrer.
  const typeToCategory = useMemo(() => {
    const map: Record<string, string> = {};
    for (const t of types) map[String(t.id)] = String(t.category);
    return map;
  }, [types]);

  const typesForCategoryFilter = useMemo(
    () =>
      categoryFilter === "ALL"
        ? types
        : types.filter((t) => String(t.category) === categoryFilter),
    [types, categoryFilter],
  );

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return references.filter((r) => {
      if (
        categoryFilter !== "ALL" &&
        typeToCategory[String(r.type)] !== categoryFilter
      )
        return false;
      if (typeFilter !== "ALL" && String(r.type) !== typeFilter) return false;
      if (brandFilter !== "ALL" && String(r.brand) !== brandFilter)
        return false;
      if (!q) return true;
      return (
        r.reference_name.toLowerCase().includes(q) ||
        (r.brand_name || "").toLowerCase().includes(q) ||
        (r.category_name || "").toLowerCase().includes(q)
      );
    });
  }, [
    references,
    search,
    categoryFilter,
    typeFilter,
    brandFilter,
    typeToCategory,
  ]);

  const stockInfo = (ref: any) => {
    const variants = ref.variants || [];
    const total = variants.reduce((s: number, v: any) => s + v.stock_actuel, 0);
    const rupture = variants.some((v: any) => v.is_rupture);
    const bas = variants.some((v: any) => v.is_stock_bas);
    if (rupture) return { label: "Rupture", class: "bg-red-100 text-red-800" };
    if (bas)
      return { label: "Stock bas", class: "bg-orange-100 text-orange-800" };
    return { label: "OK", class: "bg-green-100 text-green-800" };
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      await djangoClient.catalog.references.delete(deleteTarget.id);
      toast.success("Référence supprimée");
      setDeleteTarget(null);
      fetchAll();
    } catch (err: any) {
      toast.error(err.message || "Suppression impossible");
    }
  };

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Package className="h-6 w-6" /> Catalogue produits
          </h1>
          <p className="text-sm text-muted-foreground">
            Catégorie → Sous-type → Marque → Référence → Couleur (§8 du cahier
            des charges).
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="icon" onClick={() => fetchAll()}>
            <RefreshCw className="h-4 w-4" />
          </Button>
          {isGerant && (
            <Button variant="outline" onClick={() => setManageBrandsOpen(true)}>
              <Tag className="h-4 w-4 mr-2" /> Marques
            </Button>
          )}
          {isGerant && (
            <Button onClick={() => setCreateOpen(true)}>
              <Plus className="h-4 w-4 mr-2" /> Nouvelle référence
            </Button>
          )}
        </div>
      </div>

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Marque, référence..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select
          value={categoryFilter}
          onValueChange={(v) => {
            setCategoryFilter(v);
            setTypeFilter("ALL");
          }}
        >
          <SelectTrigger className="w-full sm:w-56">
            <SelectValue placeholder="Toutes les catégories" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">Toutes les catégories</SelectItem>
            {categories.map((c) => (
              <SelectItem key={c.id} value={String(c.id)}>
                {c.nom}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={typeFilter} onValueChange={setTypeFilter}>
          <SelectTrigger className="w-full sm:w-56">
            <SelectValue placeholder="Tous les sous-types" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">Tous les sous-types</SelectItem>
            {typesForCategoryFilter.map((t) => (
              <SelectItem key={t.id} value={String(t.id)}>
                {t.nom}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={brandFilter} onValueChange={setBrandFilter}>
          <SelectTrigger className="w-full sm:w-56">
            <SelectValue placeholder="Toutes les marques" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">Toutes les marques</SelectItem>
            {brands.map((b) => (
              <SelectItem key={b.id} value={String(b.id)}>
                {b.nom}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <div className="p-6">
              <Skeleton className="h-64 w-full" />
            </div>
          ) : filtered.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">
              Aucune référence.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Sous-type</TableHead>
                    <TableHead>Marque</TableHead>
                    <TableHead>Référence</TableHead>
                    <TableHead>Prix vente</TableHead>
                    <TableHead>Variantes</TableHead>
                    <TableHead>Stock total</TableHead>
                    <TableHead>Statut</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map((ref) => {
                    const info = stockInfo(ref);
                    const total = (ref.variants || []).reduce(
                      (s: number, v: any) => s + v.stock_actuel,
                      0,
                    );
                    return (
                      <TableRow
                        key={ref.id}
                        className="cursor-pointer"
                        onClick={() => setVariantsOf(ref)}
                      >
                        <TableCell>{ref.type_name}</TableCell>
                        <TableCell className="font-medium">
                          {ref.brand_name}
                        </TableCell>
                        <TableCell>{ref.reference_name}</TableCell>
                        <TableCell>{fmt(ref.prix_vente)}</TableCell>
                        <TableCell>{(ref.variants || []).length}</TableCell>
                        <TableCell>{total}</TableCell>
                        <TableCell>
                          <Badge className={info.class}>{info.label}</Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          {isGerant && (
                            <>
                              <Button
                                size="icon"
                                variant="ghost"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setEditTarget(ref);
                                }}
                              >
                                <Pencil className="h-4 w-4" />
                              </Button>
                              <Button
                                size="icon"
                                variant="ghost"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setDeleteTarget(ref);
                                }}
                              >
                                <Trash2 className="h-4 w-4 text-red-500" />
                              </Button>
                            </>
                          )}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      <VariantsDialog
        reference={variantsOf}
        onOpenChange={(o) => !o && setVariantsOf(null)}
        onChanged={() => fetchAll(true)}
        canEdit={isGerant}
      />

      {isGerant && (
        <CreateReferenceDialog
          open={createOpen}
          onOpenChange={setCreateOpen}
          categories={categories}
          types={types}
          brands={brands}
          colors={colors}
          onCreated={() => {
            setCreateOpen(false);
            fetchAll();
          }}
          onCatalogChanged={() => fetchAll(true)}
        />
      )}

      <EditReferenceDialog
        reference={editTarget}
        types={types}
        brands={brands}
        onOpenChange={(o) => !o && setEditTarget(null)}
        onSaved={() => {
          setEditTarget(null);
          fetchAll();
        }}
      />

      <ManageBrandsDialog
        open={manageBrandsOpen}
        onOpenChange={setManageBrandsOpen}
        brands={brands}
        onChanged={() => fetchAll(true)}
      />

      <Dialog
        open={!!deleteTarget}
        onOpenChange={(o) => !o && setDeleteTarget(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Supprimer {deleteTarget?.brand_name}{" "}
              {deleteTarget?.reference_name} ?
            </DialogTitle>
            <DialogDescription>
              Cette référence et toutes ses variantes seront supprimées
              définitivement.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              Annuler
            </Button>
            <Button variant="destructive" onClick={handleDelete}>
              Supprimer
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function VariantsDialog({
  reference,
  onOpenChange,
  onChanged,
  canEdit,
}: {
  reference: any | null;
  onOpenChange: (o: boolean) => void;
  onChanged: () => void;
  canEdit: boolean;
}) {
  const [adjusting, setAdjusting] = useState<any | null>(null);
  const [newColor, setNewColor] = useState("");
  const [newStock, setNewStock] = useState(0);
  const [newSeuil, setNewSeuil] = useState(1);
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    setNewColor("");
    setNewStock(0);
    setNewSeuil(1);
    setAdding(false);
  }, [reference]);

  if (!reference) return null;

  const addVariant = async () => {
    if (!newColor.trim()) {
      toast.error("Couleur requise");
      return;
    }
    try {
      await djangoClient.catalog.variants.create({
        product_reference: reference.id,
        couleur: newColor.trim(),
        stock_actuel: newStock,
        seuil_alerte: newSeuil,
      });
      toast.success("Variante ajoutée");
      setAdding(false);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  return (
    <Dialog open={!!reference} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>
            {reference.brand_name} {reference.reference_name}
          </DialogTitle>
          <DialogDescription>
            {reference.type_name} — {fmt(reference.prix_vente)}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          {(reference.variants || []).map((v: any) => (
            <div
              key={v.id}
              className="flex items-center justify-between border rounded-md px-3 py-2"
            >
              <div>
                <p className="font-medium text-sm">{v.couleur}</p>
                <p className="text-xs text-muted-foreground">
                  Stock: {v.stock_actuel} · Seuil: {v.seuil_alerte}
                </p>
              </div>
              {canEdit && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => setAdjusting(v)}
                >
                  Ajuster
                </Button>
              )}
            </div>
          ))}
        </div>

        {canEdit &&
          (adding ? (
            <div className="border rounded-md p-3 space-y-2">
              <div className="grid grid-cols-3 gap-2">
                <Input
                  placeholder="Couleur"
                  value={newColor}
                  onChange={(e) => setNewColor(e.target.value)}
                  className="col-span-3"
                />
                <Input
                  type="number"
                  placeholder="Stock"
                  value={newStock}
                  onChange={(e) => setNewStock(Number(e.target.value))}
                />
                <Input
                  type="number"
                  placeholder="Seuil alerte"
                  value={newSeuil}
                  onChange={(e) => setNewSeuil(Number(e.target.value))}
                />
              </div>
              <div className="flex gap-2">
                <Button size="sm" onClick={addVariant}>
                  Ajouter
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => setAdding(false)}
                >
                  Annuler
                </Button>
              </div>
            </div>
          ) : (
            <Button variant="outline" size="sm" onClick={() => setAdding(true)}>
              <Plus className="h-4 w-4 mr-2" /> Ajouter une couleur
            </Button>
          ))}

        <AdjustStockDialog
          variant={adjusting}
          onOpenChange={(o) => !o && setAdjusting(null)}
          onAdjusted={() => {
            setAdjusting(null);
            onChanged();
          }}
        />
      </DialogContent>
    </Dialog>
  );
}

function AdjustStockDialog({
  variant,
  onOpenChange,
  onAdjusted,
}: {
  variant: any | null;
  onOpenChange: (o: boolean) => void;
  onAdjusted: () => void;
}) {
  const [type, setType] = useState<"ENTREE" | "SORTIE">("ENTREE");
  const [quantite, setQuantite] = useState(1);
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    setType("ENTREE");
    setQuantite(1);
    setNote("");
  }, [variant]);

  if (!variant) return null;

  const submit = async () => {
    setSubmitting(true);
    try {
      await djangoClient.catalog.variants.adjust(variant.id, {
        type,
        quantite,
        note,
      });
      toast.success("Stock ajusté");
      onAdjusted();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={!!variant} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Ajuster le stock — {variant.couleur}</DialogTitle>
          <DialogDescription>
            Entrée/sortie manuelle réservée au gérant (§7.4 du cahier des
            charges).
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="flex gap-2">
            <Button
              variant={type === "ENTREE" ? "default" : "outline"}
              className="flex-1"
              onClick={() => setType("ENTREE")}
            >
              <ArrowUpCircle className="h-4 w-4 mr-2" /> Entrée
            </Button>
            <Button
              variant={type === "SORTIE" ? "default" : "outline"}
              className="flex-1"
              onClick={() => setType("SORTIE")}
            >
              <ArrowDownCircle className="h-4 w-4 mr-2" /> Sortie
            </Button>
          </div>
          <div className="space-y-1">
            <Label>Quantité</Label>
            <Input
              type="number"
              min={1}
              value={quantite}
              onChange={(e) => setQuantite(Math.max(1, Number(e.target.value)))}
            />
          </div>
          <div className="space-y-1">
            <Label>Note (optionnel)</Label>
            <Input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Ex: correction inventaire"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Enregistrement…" : "Confirmer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function CreateReferenceDialog({
  open,
  onOpenChange,
  categories,
  types,
  brands,
  colors,
  onCreated,
  onCatalogChanged,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  categories: any[];
  types: any[];
  brands: any[];
  colors: any[];
  onCreated: () => void;
  onCatalogChanged: () => void;
}) {
  const [categoryId, setCategoryId] = useState<string>("");
  const [typeId, setTypeId] = useState<string>("");
  const [brandId, setBrandId] = useState<string>("");
  const [referenceName, setReferenceName] = useState("");
  const [prixAchat, setPrixAchat] = useState("");
  const [prixVente, setPrixVente] = useState("");
  const [variants, setVariants] = useState<
    { couleur: string; stock: number; seuil: number }[]
  >([]);
  const [variantCouleurId, setVariantCouleurId] = useState("");
  const [variantStock, setVariantStock] = useState(0);
  const [variantSeuil, setVariantSeuil] = useState(1);
  const [submitting, setSubmitting] = useState(false);
  const [newTypeName, setNewTypeName] = useState("");
  const [newBrandName, setNewBrandName] = useState("");
  const [newColorName, setNewColorName] = useState("");

  useEffect(() => {
    if (!open) return;
    setCategoryId("");
    setTypeId("");
    setBrandId("");
    setReferenceName("");
    setPrixAchat("");
    setPrixVente("");
    setVariants([]);
    setVariantCouleurId("");
    setVariantStock(0);
    setVariantSeuil(1);
    setNewTypeName("");
    setNewBrandName("");
    setNewColorName("");
  }, [open]);

  const margin =
    prixAchat && prixVente ? Number(prixVente) - Number(prixAchat) : null;

  const createColor = async () => {
    if (!newColorName.trim()) return;
    try {
      const created = await djangoClient.catalog.colors.create({
        nom: newColorName.trim(),
      });
      toast.success("Couleur créée");
      setNewColorName("");
      onCatalogChanged();
      setVariantCouleurId(String(created.id));
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const addVariant = () => {
    const color = colors.find((c) => String(c.id) === variantCouleurId);
    if (!color || variantStock < 0) return;
    if (variants.some((v) => v.couleur === color.nom)) {
      toast.error("Cette couleur est déjà dans la liste");
      return;
    }
    setVariants((prev) => [
      ...prev,
      { couleur: color.nom, stock: variantStock, seuil: variantSeuil },
    ]);
    setVariantCouleurId("");
    setVariantStock(0);
    setVariantSeuil(1);
  };

  const removeVariant = (couleur: string) => {
    setVariants((prev) => prev.filter((v) => v.couleur !== couleur));
  };

  const typesForCategory = types.filter(
    (t) => String(t.category) === categoryId,
  );

  const createType = async () => {
    if (!categoryId || !newTypeName.trim()) return;
    try {
      const created = await djangoClient.catalog.types.create({
        category: Number(categoryId),
        nom: newTypeName.trim(),
      });
      toast.success("Sous-type créé");
      setNewTypeName("");
      onCatalogChanged();
      setTypeId(String(created.id));
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const createBrand = async () => {
    if (!newBrandName.trim()) return;
    try {
      const created = await djangoClient.catalog.brands.create({
        nom: newBrandName.trim(),
      });
      toast.success("Marque créée");
      setNewBrandName("");
      onCatalogChanged();
      setBrandId(String(created.id));
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const submit = async () => {
    if (!typeId || !brandId || !referenceName.trim() || !prixVente) {
      toast.error("Tous les champs sont requis");
      return;
    }
    setSubmitting(true);
    try {
      const ref = await djangoClient.catalog.references.create({
        type: Number(typeId),
        brand: Number(brandId),
        reference_name: referenceName.trim(),
        prix_achat: prixAchat || 0,
        prix_vente: prixVente,
      });
      for (const v of variants) {
        await djangoClient.catalog.variants.create({
          product_reference: ref.id,
          couleur: v.couleur,
          stock_actuel: v.stock,
          seuil_alerte: v.seuil,
        });
      }
      toast.success("Référence créée");
      onCreated();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la création");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Nouvelle référence produit</DialogTitle>
          <DialogDescription>
            Catégorie → Sous-type → Marque → Référence (§8 du cahier des
            charges).
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1">
            <Label>Catégorie</Label>
            <Select
              value={categoryId}
              onValueChange={(v) => {
                setCategoryId(v);
                setTypeId("");
              }}
            >
              <SelectTrigger>
                <SelectValue placeholder="Choisir une catégorie" />
              </SelectTrigger>
              <SelectContent>
                {categories.map((c) => (
                  <SelectItem key={c.id} value={String(c.id)}>
                    {c.nom}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {categoryId && (
            <div className="space-y-1">
              <Label>Sous-type</Label>
              <div className="flex gap-2">
                <Select value={typeId} onValueChange={setTypeId}>
                  <SelectTrigger className="flex-1">
                    <SelectValue placeholder="Choisir un sous-type" />
                  </SelectTrigger>
                  <SelectContent>
                    {typesForCategory.map((t) => (
                      <SelectItem key={t.id} value={String(t.id)}>
                        {t.nom}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex gap-2 mt-1">
                <Input
                  placeholder="Nouveau sous-type (ex: MAGSAFE)"
                  value={newTypeName}
                  onChange={(e) => setNewTypeName(e.target.value)}
                  className="flex-1 h-8 text-xs"
                />
                <Button
                  size="sm"
                  variant="outline"
                  className="h-8"
                  onClick={createType}
                >
                  Créer
                </Button>
              </div>
            </div>
          )}

          <div className="space-y-1">
            <Label>Marque</Label>
            <Select value={brandId} onValueChange={setBrandId}>
              <SelectTrigger>
                <SelectValue placeholder="Choisir une marque" />
              </SelectTrigger>
              <SelectContent>
                {brands.map((b) => (
                  <SelectItem key={b.id} value={String(b.id)}>
                    {b.nom}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="flex gap-2 mt-1">
              <Input
                placeholder="Nouvelle marque"
                value={newBrandName}
                onChange={(e) => setNewBrandName(e.target.value)}
                className="flex-1 h-8 text-xs"
              />
              <Button
                size="sm"
                variant="outline"
                className="h-8"
                onClick={createBrand}
              >
                Créer
              </Button>
            </div>
          </div>

          <div className="space-y-1">
            <Label>Référence (modèle)</Label>
            <Input
              placeholder="Ex: A16, S25 Ultra"
              value={referenceName}
              onChange={(e) => setReferenceName(e.target.value)}
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Prix d&apos;achat (Ar)</Label>
              <Input
                type="number"
                placeholder="0"
                value={prixAchat}
                onChange={(e) => setPrixAchat(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label>Prix de vente (Ar)</Label>
              <Input
                type="number"
                value={prixVente}
                onChange={(e) => setPrixVente(e.target.value)}
              />
            </div>
          </div>
          {margin !== null && (
            <p
              className={`text-xs -mt-2 ${margin >= 0 ? "text-green-600" : "text-red-600"}`}
            >
              Marge estimée : {fmt(margin)} / unité
            </p>
          )}

          <div className="border-t pt-3 space-y-2">
            <div className="flex items-center justify-between">
              <p className="text-sm font-medium">Variantes (couleurs)</p>
              {variants.length > 0 && (
                <span className="text-xs text-muted-foreground">
                  {variants.length} couleur(s) ·{" "}
                  {variants.reduce((s, v) => s + v.stock, 0)} unité(s)
                </span>
              )}
            </div>

            <div className="flex flex-wrap gap-2 items-end">
              <div className="space-y-1 flex-[2] min-w-[130px]">
                <Label className="text-xs">Couleur</Label>
                <Select value={variantCouleurId} onValueChange={setVariantCouleurId}>
                  <SelectTrigger>
                    <SelectValue placeholder="Choisir" />
                  </SelectTrigger>
                  <SelectContent>
                    {colors.map((c) => (
                      <SelectItem key={c.id} value={String(c.id)}>
                        {c.nom}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1 min-w-[80px]">
                <Label className="text-xs">Nombre</Label>
                <Input
                  type="number"
                  min={0}
                  value={variantStock}
                  onChange={(e) => setVariantStock(Number(e.target.value))}
                />
              </div>
              <div className="space-y-1 min-w-[80px]">
                <Label className="text-xs">Seuil d&apos;alerte</Label>
                <Input
                  type="number"
                  min={0}
                  value={variantSeuil}
                  onChange={(e) => setVariantSeuil(Number(e.target.value))}
                />
              </div>
              <Button
                type="button"
                size="sm"
                variant="secondary"
                onClick={addVariant}
                disabled={!variantCouleurId}
                className="shrink-0"
              >
                <Plus className="h-4 w-4 mr-1" /> Ajouter
              </Button>
            </div>
            <div className="flex gap-2">
              <Input
                placeholder="Nouvelle couleur (ex: Bleu)"
                value={newColorName}
                onChange={(e) => setNewColorName(e.target.value)}
                className="flex-1 h-8 text-xs"
              />
              <Button
                size="sm"
                variant="outline"
                className="h-8"
                onClick={createColor}
              >
                Créer
              </Button>
            </div>

            {variants.length > 0 && (
              <div className="flex flex-wrap gap-2 pt-1">
                {variants.map((v) => (
                  <span
                    key={v.couleur}
                    className="inline-flex items-center gap-1.5 rounded-full border border-slate-300 bg-slate-100 dark:bg-slate-800 dark:border-slate-600 px-2 py-1 text-xs font-medium text-slate-700 dark:text-slate-200"
                  >
                    {v.couleur} · {v.stock} (seuil {v.seuil})
                    <button
                      type="button"
                      onClick={() => removeVariant(v.couleur)}
                      className="text-slate-400 hover:text-red-500"
                    >
                      ×
                    </button>
                  </span>
                ))}
              </div>
            )}
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Création…" : "Créer la référence"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function EditReferenceDialog({
  reference,
  types,
  brands,
  onOpenChange,
  onSaved,
}: {
  reference: any | null;
  types: any[];
  brands: any[];
  onOpenChange: (o: boolean) => void;
  onSaved: () => void;
}) {
  const [typeId, setTypeId] = useState("");
  const [brandId, setBrandId] = useState("");
  const [referenceName, setReferenceName] = useState("");
  const [prixAchat, setPrixAchat] = useState("");
  const [prixVente, setPrixVente] = useState("");
  const [actif, setActif] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!reference) return;
    setTypeId(String(reference.type));
    setBrandId(String(reference.brand));
    setReferenceName(reference.reference_name);
    setPrixAchat(String(reference.prix_achat ?? "0"));
    setPrixVente(String(reference.prix_vente));
    setActif(reference.actif !== false);
  }, [reference]);

  if (!reference) return null;

  const margin =
    prixAchat && prixVente ? Number(prixVente) - Number(prixAchat) : null;

  const submit = async () => {
    if (!referenceName.trim() || !prixVente) {
      toast.error("Champs requis manquants");
      return;
    }
    setSubmitting(true);
    try {
      await djangoClient.catalog.references.update(reference.id, {
        type: Number(typeId),
        brand: Number(brandId),
        reference_name: referenceName.trim(),
        prix_achat: prixAchat || 0,
        prix_vente: prixVente,
        actif,
      });
      toast.success("Référence mise à jour");
      onSaved();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la mise à jour");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={!!reference} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Modifier la référence</DialogTitle>
          <DialogDescription>
            {reference.category_name} → {reference.type_name}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1">
            <Label>Sous-type</Label>
            <Select value={typeId} onValueChange={setTypeId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {types.map((t) => (
                  <SelectItem key={t.id} value={String(t.id)}>
                    {t.nom}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Marque</Label>
            <Select value={brandId} onValueChange={setBrandId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {brands.map((b) => (
                  <SelectItem key={b.id} value={String(b.id)}>
                    {b.nom}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Référence (modèle)</Label>
            <Input
              value={referenceName}
              onChange={(e) => setReferenceName(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Prix d&apos;achat (Ar)</Label>
              <Input
                type="number"
                value={prixAchat}
                onChange={(e) => setPrixAchat(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label>Prix de vente (Ar)</Label>
              <Input
                type="number"
                value={prixVente}
                onChange={(e) => setPrixVente(e.target.value)}
              />
            </div>
          </div>
          {margin !== null && (
            <p
              className={`text-xs -mt-2 ${margin >= 0 ? "text-green-600" : "text-red-600"}`}
            >
              Marge estimée : {fmt(margin)} / unité
            </p>
          )}
          <div className="flex items-center gap-2">
            <Button
              type="button"
              size="sm"
              variant={actif ? "default" : "outline"}
              onClick={() => setActif(!actif)}
            >
              {actif ? "Active" : "Inactive"}
            </Button>
            <span className="text-xs text-muted-foreground">
              Une référence inactive n'apparaît plus dans la recherche de
              commande.
            </span>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Enregistrement…" : "Enregistrer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ManageBrandsDialog({
  open,
  onOpenChange,
  brands,
  onChanged,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  brands: any[];
  onChanged: () => void;
}) {
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingName, setEditingName] = useState("");
  const [newName, setNewName] = useState("");

  const startEdit = (b: any) => {
    setEditingId(b.id);
    setEditingName(b.nom);
  };

  const saveEdit = async () => {
    if (!editingId || !editingName.trim()) return;
    try {
      await djangoClient.catalog.brands.update(editingId, {
        nom: editingName.trim(),
      });
      toast.success("Marque renommée");
      setEditingId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const removeBrand = async (b: any) => {
    try {
      await djangoClient.catalog.brands.delete(b.id);
      toast.success("Marque supprimée");
      onChanged();
    } catch (err: any) {
      toast.error(
        err.message ||
          "Suppression impossible (marque utilisée par des références)",
      );
    }
  };

  const addBrand = async () => {
    if (!newName.trim()) return;
    try {
      await djangoClient.catalog.brands.create({ nom: newName.trim() });
      toast.success("Marque ajoutée");
      setNewName("");
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Gérer les marques</DialogTitle>
          <DialogDescription>
            Renommer ou supprimer une marque (impossible si elle a des
            références).
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2 max-h-72 overflow-y-auto">
          {brands.map((b) => (
            <div
              key={b.id}
              className="flex items-center gap-2 border rounded-md px-3 py-2"
            >
              {editingId === b.id ? (
                <>
                  <Input
                    value={editingName}
                    onChange={(e) => setEditingName(e.target.value)}
                    className="h-8 flex-1"
                    autoFocus
                  />
                  <Button size="sm" onClick={saveEdit}>
                    OK
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setEditingId(null)}
                  >
                    Annuler
                  </Button>
                </>
              ) : (
                <>
                  <span className="flex-1 text-sm">{b.nom}</span>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => startEdit(b)}
                  >
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => removeBrand(b)}
                  >
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </>
              )}
            </div>
          ))}
          {brands.length === 0 && (
            <p className="text-sm text-muted-foreground text-center py-4">
              Aucune marque.
            </p>
          )}
        </div>
        <div className="flex gap-2 border-t pt-3">
          <Input
            placeholder="Nouvelle marque"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
          />
          <Button onClick={addBrand}>
            <Plus className="h-4 w-4 mr-2" /> Ajouter
          </Button>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Fermer
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
