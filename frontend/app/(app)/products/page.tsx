"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { djangoClient } from "@/lib/django-client";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { useRealtimeRefresh } from "@/lib/hooks/useRealtimeRefresh";
import { useDebouncedValue } from "@/lib/hooks/useDebouncedValue";
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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
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
  DollarSign,
  Download,
  Upload,
  Settings,
  Check,
  FolderPlus,
  Palette,
} from "lucide-react";
import { toast } from "sonner";

// Indicateur de couleur par variante (badge "Variantes") — seuils fixes,
// affichés en légende dans l'entête du tableau (§ demande) : rouge = plus
// aucun stock, bleu = 2 pièces ou moins, vert = 3 pièces ou plus.
const variantStockBadgeClass = (stock: number) => {
  if (stock <= 0)
    return "font-normal border-red-200 text-red-700 dark:text-red-500 bg-red-50/50 dark:bg-red-900/20";
  if (stock <= 2)
    return "font-normal border-blue-200 text-blue-700 dark:text-blue-500 bg-blue-50/50 dark:bg-blue-900/20";
  return "font-normal border-green-200 text-green-700 dark:text-green-500  bg-green-50/50 dark:bg-green-900/20";
};

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
  const [catalogSettingsOpen, setCatalogSettingsOpen] = useState(false);
  const [bulkPriceOpen, setBulkPriceOpen] = useState(false);
  const [variantsOf, setVariantsOf] = useState<any | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<any | null>(null);
  const [exporting, setExporting] = useState(false);
  const [importing, setImporting] = useState(false);
  const importInputRef = useRef<HTMLInputElement | null>(null);

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

  const debouncedSearch = useDebouncedValue(search);

  const filtered = useMemo(() => {
    const q = debouncedSearch.trim().toLowerCase();
    const tokens = q.split(/\s+/).filter(Boolean);
    return references.filter((r) => {
      if (
        categoryFilter !== "ALL" &&
        typeToCategory[String(r.type)] !== categoryFilter
      )
        return false;
      if (typeFilter !== "ALL" && String(r.type) !== typeFilter) return false;
      if (brandFilter !== "ALL" && String(r.brand) !== brandFilter)
        return false;
      if (tokens.length === 0) return true;
      // Chaque mot doit se retrouver quelque part (nom, marque, catégorie,
      // sous-type OU une couleur de variante) — permet "samsung bleu",
      // "pixel 6 pro vert", peu importe l'ordre des mots.
      const haystack = [
        r.reference_name,
        r.brand_name,
        r.category_name,
        r.type_name,
        ...(r.variants || []).map((v: any) => v.couleur),
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return tokens.every((t) => haystack.includes(t));
    });
  }, [
    references,
    debouncedSearch,
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
    if (rupture)
      return {
        label: "Rupture",
        class: "bg-red-100 text-red-800  dark:bg-red-900/20 dark:text-red-500",
      };
    if (bas)
      return {
        label: "Stock bas",
        class:
          "bg-orange-100  dark:bg-orange-900/20 dark:text-orange-500 text-orange-800",
      };
    return {
      label: "OK",
      class:
        "bg-green-100 text-green-800  dark:bg-green-900/20 dark:text-green-500",
    };
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

  const handleExportExcel = async () => {
    setExporting(true);
    try {
      const { blob, filename } =
        await djangoClient.catalog.references.exportExcel();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename || "catalogue.xlsx";
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'export");
    } finally {
      setExporting(false);
    }
  };

  const handleImportExcel = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setImporting(true);
    try {
      const res = await djangoClient.catalog.references.importExcel(file);

      // Le fichier renvoyé porte une colonne Statut + Date sur chaque ligne
      // traitée — le retélécharger permet de reprendre plus tard sans
      // revenir au début (les lignes déjà marquées seront sautées).
      const url = URL.createObjectURL(res.blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = res.filename || "catalogue_import.xlsx";
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);

      toast.success(
        `${res.created_references} référence(s) créée(s), ${res.updated_references} mise(s) à jour, ` +
          `${res.created_variants} couleur(s) créée(s), ${res.updated_variants} mise(s) à jour` +
          (res.skipped_count > 0 ? `, ${res.skipped_count} ligne(s) déjà traitée(s) ignorée(s)` : "") +
          `. Fichier annoté téléchargé (${res.filename}).`,
      );
      if (res.errors_count > 0) {
        toast.error(
          `${res.errors_count} ligne(s) en erreur — voir la colonne "Statut" du fichier téléchargé.`,
          { duration: 10000 },
        );
      }
      fetchAll();

      // Revue optionnelle par IA locale (Ollama) des références nouvellement
      // créées, pour repérer un quasi-doublon qu'une simple comparaison de
      // texte ne peut pas voir (ex: faute de frappe) — best-effort, ne
      // bloque jamais l'import (déjà fait au-dessus) si Ollama ne répond pas.
      if (res.new_reference_names.length > 0) {
        const existingNames = references.map(
          (r: any) => `${r.brand_name} ${r.reference_name}`,
        );
        fetch("/api/ai/check-duplicates", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            newNames: res.new_reference_names,
            existingNames,
          }),
        })
          .then((r) => r.json())
          .then((data) => {
            if (data.warnings?.length > 0) {
              toast.warning(
                `Vérification IA : ${data.warnings.length} nouvelle(s) référence(s) ressemble(nt) à une existante — ` +
                  data.warnings
                    .slice(0, 3)
                    .map((w: any) => `"${w.nouvelle}" ≈ "${w.ressemble_a}"`)
                    .join(" · "),
                { duration: 15000 },
              );
            }
          })
          .catch(() => {
            // Ollama indisponible/hors service — l'import reste valide, on
            // ignore silencieusement cette vérification supplémentaire.
          });
      }
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'import");
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="p-4 sm:p-6 space-y-5">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Package className="h-6 w-6" /> Catalogue produits
          </h1>
          <p className="text-sm text-muted-foreground">
            Catégorie → Sous-type → Marque → Référence → Couleur (§8 du cahier
            des charges).
          </p>
        </div>

        <div className="flex flex-wrap items-center justify-end gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => fetchAll()}
            className="h-10 w-10 rounded-md p-0"
          >
            <RefreshCw className="h-4 w-4" />
          </Button>

          {isGerant && (
            <Button
              variant="secondary"
              size="sm"
              onClick={handleExportExcel}
              disabled={exporting}
              className="h-10"
            >
              <Download className="h-4 w-4 mr-2" />
              {exporting ? "Export..." : "Exporter Excel"}
            </Button>
          )}

          {isGerant && (
            <>
              <input
                ref={importInputRef}
                type="file"
                accept=".xlsx,.xls"
                className="hidden"
                onChange={handleImportExcel}
              />
              <Button
                variant="secondary"
                size="sm"
                onClick={() => importInputRef.current?.click()}
                disabled={importing}
                className="h-10"
              >
                <Upload className="h-4 w-4 mr-2" />
                {importing ? "Import..." : "Importer Excel"}
              </Button>
            </>
          )}

          {isGerant && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setCatalogSettingsOpen(true)}
              className="h-10"
            >
              <Settings className="h-4 w-4 mr-2" /> Paramètres
            </Button>
          )}

          {isGerant && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setBulkPriceOpen(true)}
              className="h-10"
            >
              <DollarSign className="h-4 w-4 mr-2" /> Modifier prix par
              sous-type
            </Button>
          )}

          {isGerant && (
            <Button
              size="sm"
              onClick={() => setCreateOpen(true)}
              className="h-10 px-4 font-medium"
            >
              <Plus className="h-4 w-4 mr-2" /> Nouvelle référence
            </Button>
          )}
        </div>
      </div>

      <div className="flex flex-col gap-3 xl:flex-row xl:items-center">
        <div className="relative flex-1 xl:max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Marque, référence..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10 h-11"
          />
        </div>

        <div className="grid gap-3 md:grid-cols-3 xl:flex-1">
          <Select
            value={categoryFilter}
            onValueChange={(v) => {
              setCategoryFilter(v);
              setTypeFilter("ALL");
            }}
          >
            <SelectTrigger className="h-11 w-full">
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
            <SelectTrigger className="h-11 w-full">
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
            <SelectTrigger className="h-11 w-full">
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
                    <TableHead className="w-12"></TableHead>
                    <TableHead>Sous-type</TableHead>
                    <TableHead>Marque</TableHead>
                    <TableHead>Référence</TableHead>
                    {isGerant && <TableHead>Prix actuel</TableHead>}
                    <TableHead>Prix de vente</TableHead>
                    {isGerant && <TableHead>Marge</TableHead>}
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
                        <TableCell>
                          {ref.photo ? (
                            <img
                              src={ref.photo}
                              alt={ref.reference_name}
                              className="h-8 w-8 rounded object-cover border"
                            />
                          ) : (
                            <div className="h-8 w-8 rounded border bg-muted flex items-center justify-center">
                              <Package className="h-4 w-4 text-muted-foreground" />
                            </div>
                          )}
                        </TableCell>
                        <TableCell>{ref.type_name}</TableCell>
                        <TableCell className="font-medium">
                          {ref.brand_name}
                        </TableCell>
                        <TableCell>{ref.reference_name}</TableCell>
                        {isGerant && (
                          <TableCell>{fmt(ref.prix_achat)}</TableCell>
                        )}
                        <TableCell>{fmt(ref.prix_vente)}</TableCell>
                        {isGerant && (
                          <TableCell
                            className={
                              Number(ref.prix_vente) -
                                Number(ref.prix_achat || 0) >=
                              0
                                ? "text-green-600"
                                : "text-red-600"
                            }
                          >
                            {fmt(
                              Number(ref.prix_vente) -
                                Number(ref.prix_achat || 0),
                            )}
                          </TableCell>
                        )}
                        <TableCell className="max-w-60">
                          {(ref.variants || []).length === 0 ? (
                            <span className="text-xs text-muted-foreground">
                              Aucune
                            </span>
                          ) : (
                            <div className="flex flex-wrap gap-1">
                              {(ref.variants || []).map((v: any) => (
                                <Badge
                                  key={v.id}
                                  variant="outline"
                                  className={`${variantStockBadgeClass(v.stock_actuel)}`}
                                >
                                  {v.couleur} · {v.stock_actuel}
                                </Badge>
                              ))}
                            </div>
                          )}
                        </TableCell>
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
                                  setVariantsOf(ref);
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

      <ProductDetailDialog
        reference={variantsOf}
        categories={categories}
        types={types}
        brands={brands}
        colors={colors}
        onOpenChange={(o) => !o && setVariantsOf(null)}
        onChanged={() => fetchAll(true)}
        onCatalogChanged={() => fetchAll(true)}
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

      <CatalogSettingsDialog
        open={catalogSettingsOpen}
        onOpenChange={setCatalogSettingsOpen}
        brands={brands}
        categories={categories}
        types={types}
        colors={colors}
        onChanged={() => fetchAll(true)}
      />

      <BulkPriceDialog
        open={bulkPriceOpen}
        onOpenChange={setBulkPriceOpen}
        types={types}
        references={references}
        defaultTypeId={typeFilter !== "ALL" ? typeFilter : ""}
        onDone={() => {
          setBulkPriceOpen(false);
          fetchAll(true);
        }}
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

/// Détail produit complet (§8 du cahier des charges) : identité (catégorie →
/// sous-type → marque → référence), prix/marge, photo, statut, ET gestion
/// des variantes (couleurs) — tout en un seul endroit plutôt que dispersé
/// entre un dialog "Modifier" et un dialog "Variantes" séparés.
function ProductDetailDialog({
  reference,
  categories,
  types,
  brands,
  colors,
  onOpenChange,
  onChanged,
  onCatalogChanged,
  canEdit,
}: {
  reference: any | null;
  categories: any[];
  types: any[];
  brands: any[];
  colors: any[];
  onOpenChange: (o: boolean) => void;
  onChanged: () => void;
  onCatalogChanged: () => void;
  canEdit: boolean;
}) {
  const [categoryId, setCategoryId] = useState("");
  const [typeId, setTypeId] = useState("");
  const [brandId, setBrandId] = useState("");
  const [referenceName, setReferenceName] = useState("");
  const [prixAchat, setPrixAchat] = useState("");
  const [prixVente, setPrixVente] = useState("");
  const [actif, setActif] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);

  const [adjusting, setAdjusting] = useState<any | null>(null);
  const [deletingVariant, setDeletingVariant] = useState<any | null>(null);
  const [variantColorId, setVariantColorId] = useState("");
  const [newStock, setNewStock] = useState("");
  const [newSeuil, setNewSeuil] = useState("");
  const [newColorName, setNewColorName] = useState("");

  useEffect(() => {
    if (!reference) return;
    setTypeId(String(reference.type));
    setBrandId(String(reference.brand));
    setReferenceName(reference.reference_name);
    setPrixAchat(String(reference.prix_achat ?? "0"));
    setPrixVente(String(reference.prix_vente));
    setActif(reference.actif !== false);
    setPhotoFile(null);
    setPhotoPreview(reference.photo || null);
    const currentType = types.find((t) => t.id === reference.type);
    setCategoryId(currentType ? String(currentType.category) : "");
    setVariantColorId("");
    setNewStock("");
    setNewSeuil("");
    setNewColorName("");
  }, [reference, types]);

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setPhotoFile(file);
      setPhotoPreview(URL.createObjectURL(file));
    }
  };

  if (!reference) return null;

  const typesForCategory = types.filter(
    (t) => String(t.category) === categoryId,
  );
  const usedColors = new Set(
    (reference.variants || []).map((v: any) => v.couleur),
  );
  const availableColors = colors.filter((c: any) => !usedColors.has(c.nom));
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
      if (photoFile) {
        const fd = new FormData();
        fd.append("photo", photoFile);
        await djangoClient.patchFormData(
          `/catalog/references/${reference.id}/`,
          fd,
        );
      }
      toast.success("Référence mise à jour");
      onChanged();
      onOpenChange(false);
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la mise à jour");
    } finally {
      setSubmitting(false);
    }
  };

  const createColor = async () => {
    if (!newColorName.trim()) return;
    try {
      const created = await djangoClient.catalog.colors.create({
        nom: newColorName.trim(),
      });
      toast.success("Couleur créée");
      setNewColorName("");
      onCatalogChanged();
      setVariantColorId(String(created.id));
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const addVariant = async () => {
    const color = colors.find((c: any) => String(c.id) === variantColorId);
    if (!color) {
      toast.error("Choisissez une couleur");
      return;
    }
    try {
      await djangoClient.catalog.variants.create({
        product_reference: reference.id,
        couleur: color.nom,
        stock_actuel: newStock ? Number(newStock) : 0,
        seuil_alerte: newSeuil ? Number(newSeuil) : 1,
      });
      toast.success("Variante ajoutée");
      setVariantColorId("");
      setNewStock("");
      setNewSeuil("");
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const removeVariant = async () => {
    if (!deletingVariant) return;
    try {
      await djangoClient.catalog.variants.delete(deletingVariant.id);
      toast.success("Variante supprimée");
      setDeletingVariant(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Suppression impossible");
    }
  };

  return (
    // dialog de modification de la référence et gestion des variantes (couleurs)

    <Dialog open={!!reference} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {reference.brand_name} {reference.reference_name}
          </DialogTitle>
          <DialogDescription>
            Catégorie → Sous-type → Marque → Référence, prix, photo et variantes
            (§8 du cahier des charges).
          </DialogDescription>
        </DialogHeader>

        <div className="grid md:grid-cols-2 gap-6">
          {/* Colonne gauche : identité, prix, photo, statut */}
          <div className="space-y-3">
            <div className="space-y-1">
              <Label>Catégorie</Label>
              <Select
                value={categoryId}
                onValueChange={(v) => {
                  setCategoryId(v);
                  setTypeId("");
                }}
                disabled={!canEdit}
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
            <div className="space-y-1">
              <Label>Sous-type</Label>
              <Select
                value={typeId}
                onValueChange={setTypeId}
                disabled={!canEdit}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Choisir un sous-type" />
                </SelectTrigger>
                <SelectContent>
                  {(categoryId ? typesForCategory : types).map((t) => (
                    <SelectItem key={t.id} value={String(t.id)}>
                      {t.nom}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Marque</Label>
              <Select
                value={brandId}
                onValueChange={setBrandId}
                disabled={!canEdit}
              >
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
                disabled={!canEdit}
              />
            </div>
            <div className={canEdit ? "grid grid-cols-2 gap-3" : "space-y-1"}>
              {canEdit && (
                <div className="space-y-1">
                  <Label>Prix actuel (Ar)</Label>
                  <Input
                    type="number"
                    value={prixAchat}
                    onChange={(e) => setPrixAchat(e.target.value)}
                    disabled={!canEdit}
                  />
                </div>
              )}
              <div className="space-y-1">
                <Label>Prix de vente (Ar)</Label>
                <Input
                  type="number"
                  value={prixVente}
                  onChange={(e) => setPrixVente(e.target.value)}
                  disabled={!canEdit}
                />
              </div>
            </div>
            {canEdit && margin !== null && (
              <p
                className={`text-xs -mt-2 ${margin >= 0 ? "text-green-600" : "text-red-600"}`}
              >
                Marge estimée : {fmt(margin)} / unité
              </p>
            )}
            <div className="space-y-1">
              <Label>Photo</Label>
              <div className="flex items-center gap-3">
                {photoPreview ? (
                  <img
                    src={photoPreview}
                    alt="Aperçu"
                    className="h-16 w-16 object-cover rounded-md border shrink-0"
                  />
                ) : (
                  <div className="h-16 w-16 rounded-md border bg-muted flex items-center justify-center shrink-0">
                    <Package className="h-6 w-6 text-muted-foreground" />
                  </div>
                )}
                {canEdit && (
                  <Input
                    type="file"
                    accept="image/*"
                    onChange={handlePhotoChange}
                  />
                )}
              </div>
            </div>
            {canEdit && (
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
                  Inactive = invisible dans la recherche de commande.
                </span>
              </div>
            )}
            {canEdit && (
              <Button onClick={submit} disabled={submitting} className="w-full">
                {submitting
                  ? "Enregistrement…"
                  : "Enregistrer les informations"}
              </Button>
            )}
          </div>

          {/* Colonne droite : variantes (couleurs) */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <Label className="text-sm font-semibold">
                Variantes ({(reference.variants || []).length})
              </Label>
              <span className="text-xs text-muted-foreground">
                Stock total :{" "}
                {(reference.variants || []).reduce(
                  (s: number, v: any) => s + v.stock_actuel,
                  0,
                )}
              </span>
            </div>
            <div className="space-y-2 max-h-64 overflow-y-auto">
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
                    <div className="flex items-center gap-1">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => setAdjusting(v)}
                      >
                        Ajuster
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        onClick={() => setDeletingVariant(v)}
                      >
                        <Trash2 className="h-4 w-4 text-red-500" />
                      </Button>
                    </div>
                  )}
                </div>
              ))}
              {(reference.variants || []).length === 0 && (
                <p className="text-sm text-muted-foreground text-center py-4">
                  Aucune couleur pour cette référence.
                </p>
              )}
            </div>

            {canEdit && (
              <div className="border rounded-md p-3 space-y-2">
                <p className="text-sm font-medium">Ajouter une couleur</p>
                <div className="grid grid-cols-3 gap-2">
                  <div className="col-span-3 space-y-1">
                    <Label className="text-xs text-muted-foreground">
                      Couleur
                    </Label>
                    <Select
                      value={variantColorId}
                      onValueChange={setVariantColorId}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Couleur" />
                      </SelectTrigger>
                      <SelectContent>
                        {availableColors.map((c: any) => (
                          <SelectItem key={c.id} value={String(c.id)}>
                            {c.nom}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground">
                      Stock initial
                    </Label>
                    <Input
                      type="number"
                      placeholder="0"
                      value={newStock}
                      onChange={(e) => setNewStock(e.target.value)}
                    />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground">
                      Seuil d'alerte
                    </Label>
                    <Input
                      type="number"
                      placeholder="1"
                      value={newSeuil}
                      onChange={(e) => setNewSeuil(e.target.value)}
                    />
                  </div>
                  <div className="flex items-end">
                    <Button
                      size="sm"
                      onClick={addVariant}
                      disabled={!variantColorId}
                      className="w-full"
                    >
                      <Plus className="h-4 w-4 mr-1" /> Ajouter
                    </Button>
                  </div>
                </div>
                <div className="flex gap-2 pt-1 border-t">
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
              </div>
            )}
          </div>
        </div>

        <AdjustStockDialog
          variant={adjusting}
          onOpenChange={(o) => !o && setAdjusting(null)}
          onAdjusted={() => {
            setAdjusting(null);
            onChanged();
          }}
        />

        <Dialog
          open={!!deletingVariant}
          onOpenChange={(o) => !o && setDeletingVariant(null)}
        >
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                Supprimer la couleur {deletingVariant?.couleur} ?
              </DialogTitle>
              <DialogDescription>
                Cette variante et son historique de stock seront supprimés.
              </DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <Button
                variant="outline"
                onClick={() => setDeletingVariant(null)}
              >
                Annuler
              </Button>
              <Button variant="destructive" onClick={removeVariant}>
                Supprimer
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
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
  const [quantite, setQuantite] = useState("");
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    setType("ENTREE");
    setQuantite("");
    setNote("");
  }, [variant]);

  if (!variant) return null;

  const submit = async () => {
    const qty = Number(quantite);
    if (!quantite || qty < 1) {
      toast.error("Quantité requise");
      return;
    }
    setSubmitting(true);
    try {
      await djangoClient.catalog.variants.adjust(variant.id, {
        type,
        quantite: qty,
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
          <DialogTitle>
            Ajuster le stock — {variant.brand_name} {variant.reference_name}
          </DialogTitle>
          <DialogDescription>
            Entrée/sortie manuelle réservée au gérant (§7.4 du cahier des
            charges).
          </DialogDescription>
        </DialogHeader>
        <div className="flex items-center gap-2 rounded-md border bg-muted/40 px-3 py-2 text-sm">
          <span className="text-muted-foreground">Couleur :</span>
          <Badge variant="secondary">{variant.couleur}</Badge>
          <span className="text-muted-foreground ml-auto">
            Stock actuel :{" "}
            <span className="font-medium text-foreground">
              {variant.stock_actuel}
            </span>
            {" · "}Seuil d&apos;alerte : {variant.seuil_alerte}
          </span>
        </div>
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
              placeholder={`Stock actuel : ${variant.stock_actuel}`}
              value={quantite}
              onChange={(e) => setQuantite(e.target.value)}
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
  const [variantStock, setVariantStock] = useState("");
  const [variantSeuil, setVariantSeuil] = useState("");
  const [simpleStock, setSimpleStock] = useState("");
  const [simpleSeuil, setSimpleSeuil] = useState("1");
  const [submitting, setSubmitting] = useState(false);
  const [newTypeName, setNewTypeName] = useState("");
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);

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
    setVariantStock("");
    setVariantSeuil("");
    setSimpleStock("");
    setSimpleSeuil("1");
    setNewTypeName("");
    setPhotoFile(null);
    setPhotoPreview(null);
  }, [open]);

  // Certaines catégories (chargeur, écouteur…) n'ont pas de déclinaison
  // couleur — la référence n'a alors qu'une seule variante "Standard" et le
  // formulaire saisit directement une quantité (voir Paramètres du
  // catalogue).
  const selectedCategory = categories.find((c) => String(c.id) === categoryId);
  const avecCouleurs = selectedCategory ? selectedCategory.avec_couleurs !== false : true;

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setPhotoFile(file);
      setPhotoPreview(URL.createObjectURL(file));
    }
  };

  const margin =
    prixAchat && prixVente ? Number(prixVente) - Number(prixAchat) : null;

  const addVariant = () => {
    const color = colors.find((c) => String(c.id) === variantCouleurId);
    if (!color) return;
    if (variants.some((v) => v.couleur === color.nom)) {
      toast.error("Cette couleur est déjà dans la liste");
      return;
    }
    setVariants((prev) => [
      ...prev,
      {
        couleur: color.nom,
        stock: variantStock ? Number(variantStock) : 0,
        seuil: variantSeuil ? Number(variantSeuil) : 1,
      },
    ]);
    setVariantCouleurId("");
    setVariantStock("");
    setVariantSeuil("");
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
      if (photoFile) {
        const fd = new FormData();
        fd.append("photo", photoFile);
        await djangoClient.patchFormData(`/catalog/references/${ref.id}/`, fd);
      }
      const variantsToCreate = avecCouleurs
        ? variants
        : [
            {
              couleur: "Standard",
              stock: simpleStock ? Number(simpleStock) : 0,
              seuil: simpleSeuil ? Number(simpleSeuil) : 1,
            },
          ];
      for (const v of variantsToCreate) {
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
      <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Nouvelle référence produit</DialogTitle>
          <DialogDescription>
            Catégorie → Sous-type → Marque → Référence (§8 du cahier des
            charges).
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="space-y-1">
              <Label>Catégorie</Label>
              <Select
                value={categoryId}
                onValueChange={(v) => {
                  setCategoryId(v);
                  setTypeId("");
                }}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Choisir" />
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

            <div className="space-y-1">
              <Label>Marque</Label>
              <Select value={brandId} onValueChange={setBrandId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Choisir" />
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
                placeholder="Ex: A16, S25 Ultra"
                value={referenceName}
                onChange={(e) => setReferenceName(e.target.value)}
              />
            </div>
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

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Prix actuel (Ar)</Label>
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

          <div className="space-y-1">
            <Label>Photo (optionnel)</Label>
            <Input type="file" accept="image/*" onChange={handlePhotoChange} />
            {photoPreview && (
              <div className="mt-2 flex justify-center">
                <img
                  src={photoPreview}
                  alt="Aperçu"
                  className="h-24 w-24 object-cover rounded-md border"
                />
              </div>
            )}
          </div>

          {avecCouleurs ? (
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

              <div className="space-y-2">
                <div className="space-y-1">
                  <Label className="text-xs">Couleur</Label>
                  <Select
                    value={variantCouleurId}
                    onValueChange={setVariantCouleurId}
                  >
                    <SelectTrigger className="w-full">
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
                <div className="grid grid-cols-2 gap-2">
                  <div className="space-y-1">
                    <Label className="text-xs">Nombre</Label>
                    <Input
                      type="number"
                      min={0}
                      placeholder="0"
                      value={variantStock}
                      onChange={(e) => setVariantStock(e.target.value)}
                    />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Seuil d&apos;alerte</Label>
                    <Input
                      type="number"
                      min={0}
                      placeholder="1"
                      value={variantSeuil}
                      onChange={(e) => setVariantSeuil(e.target.value)}
                    />
                  </div>
                </div>
                <Button
                  type="button"
                  size="sm"
                  variant="secondary"
                  onClick={addVariant}
                  disabled={!variantCouleurId}
                  className="w-full"
                >
                  <Plus className="h-4 w-4 mr-1" /> Ajouter
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
          ) : (
            <div className="border-t pt-3 space-y-2">
              <p className="text-sm font-medium">Stock</p>
              <p className="text-xs text-muted-foreground -mt-1">
                Catégorie sans couleurs — une seule quantité pour cette
                référence.
              </p>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label className="text-xs">Quantité en stock</Label>
                  <Input
                    type="number"
                    min={0}
                    placeholder="0"
                    value={simpleStock}
                    onChange={(e) => setSimpleStock(e.target.value)}
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Seuil d&apos;alerte</Label>
                  <Input
                    type="number"
                    min={0}
                    placeholder="1"
                    value={simpleSeuil}
                    onChange={(e) => setSimpleSeuil(e.target.value)}
                  />
                </div>
              </div>
            </div>
          )}
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

// Marques de téléphones courantes (§8.1 du cahier des charges) — proposées
// en un clic pour éviter de les retaper à chaque nouvelle référence produit.
const SUGGESTED_BRANDS = [
  "Samsung",
  "iPhone",
  "Huawei",
  "Redmi",
  "Xiaomi",
  "Tecno",
  "Infinix",
  "Itel",
  "Oppo",
  "Realme",
  "Google Pixel",
  "Poco",
  "Vivo",
  "Honor",
];

function CatalogSettingsDialog({
  open,
  onOpenChange,
  brands,
  categories,
  types,
  colors,
  onChanged,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  brands: any[];
  categories: any[];
  types: any[];
  colors: any[];
  onChanged: () => void;
}) {
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingName, setEditingName] = useState("");
  const [newName, setNewName] = useState("");
  const [addingBrand, setAddingBrand] = useState<string | null>(null);

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

  const addSuggestedBrand = async (nom: string) => {
    setAddingBrand(nom);
    try {
      await djangoClient.catalog.brands.create({ nom });
      toast.success("Marque ajoutée");
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    } finally {
      setAddingBrand(null);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Paramètres du catalogue</DialogTitle>
          <DialogDescription>
            Marques, catégories et couleurs utilisés dans le catalogue
            produits (§8 du cahier des charges).
          </DialogDescription>
        </DialogHeader>

        <Tabs defaultValue="marques">
          <TabsList className="grid grid-cols-3 w-full">
            <TabsTrigger value="marques">Marques</TabsTrigger>
            <TabsTrigger value="categories">Catégories</TabsTrigger>
            <TabsTrigger value="couleurs">Couleurs</TabsTrigger>
          </TabsList>

          <TabsContent value="marques" className="space-y-3 pt-3">
            <div className="flex flex-wrap gap-2">
              {SUGGESTED_BRANDS.map((nom) => {
                const already = brands.some(
                  (b) => b.nom.toLowerCase() === nom.toLowerCase(),
                );
                return (
                  <Button
                    key={nom}
                    type="button"
                    size="sm"
                    variant={already ? "secondary" : "outline"}
                    disabled={already || addingBrand === nom}
                    onClick={() => addSuggestedBrand(nom)}
                  >
                    {already ? (
                      <Check className="h-3.5 w-3.5 mr-1.5" />
                    ) : (
                      <Plus className="h-3.5 w-3.5 mr-1.5" />
                    )}
                    {nom}
                  </Button>
                );
              })}
            </div>
            <div className="space-y-2 max-h-64 overflow-y-auto">
              {brands.map((b) => (
                <CrudRow
                  key={b.id}
                  label={b.nom}
                  editing={editingId === b.id}
                  editingValue={editingName}
                  onEditingValueChange={setEditingName}
                  onStartEdit={() => startEdit(b)}
                  onSaveEdit={saveEdit}
                  onCancelEdit={() => setEditingId(null)}
                  onRemove={() => removeBrand(b)}
                />
              ))}
              {brands.length === 0 && (
                <p className="text-sm text-muted-foreground text-center py-4">
                  Aucune marque.
                </p>
              )}
            </div>
            <div className="flex gap-2">
              <Input
                placeholder="Nouvelle marque"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
              />
              <Button onClick={addBrand}>
                <Plus className="h-4 w-4 mr-2" /> Ajouter
              </Button>
            </div>
          </TabsContent>

          <TabsContent value="categories" className="pt-3">
            <p className="text-xs text-muted-foreground mb-3">
              Catégorie (ex. Housse, Cache écran, Chargeur) → sous-type (ex.
              Flip cover, Privacy, Écouteur). « Sans couleurs » pour les
              catégories sans déclinaison couleur (chargeur, écouteur…) — la
              référence n&apos;a alors qu&apos;une quantité, sans gestion de
              couleur.
            </p>
            <CategoriesTypesCrud
              categories={categories}
              types={types}
              onChanged={onChanged}
            />
          </TabsContent>

          <TabsContent value="couleurs" className="pt-3">
            <p className="text-xs text-muted-foreground mb-3">
              Liste des couleurs proposées dans le sélecteur de variante.
            </p>
            <ColorsCrudList colors={colors} onChanged={onChanged} />
          </TabsContent>
        </Tabs>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Fermer
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// Ligne de liste éditable (nom + renommer/supprimer) — patron partagé par
// les marques et les couleurs pour éviter de dupliquer le même bloc JSX.
function CrudRow({
  label,
  editing,
  editingValue,
  onEditingValueChange,
  onStartEdit,
  onSaveEdit,
  onCancelEdit,
  onRemove,
  trailing,
}: {
  label: string;
  editing: boolean;
  editingValue: string;
  onEditingValueChange: (v: string) => void;
  onStartEdit: () => void;
  onSaveEdit: () => void;
  onCancelEdit: () => void;
  onRemove: () => void;
  trailing?: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-2 border rounded-md px-3 py-2">
      {editing ? (
        <>
          <Input
            value={editingValue}
            onChange={(e) => onEditingValueChange(e.target.value)}
            className="h-8 flex-1"
            autoFocus
          />
          <Button size="sm" onClick={onSaveEdit}>
            OK
          </Button>
          <Button size="sm" variant="ghost" onClick={onCancelEdit}>
            Annuler
          </Button>
        </>
      ) : (
        <>
          <span className="flex-1 text-sm">{label}</span>
          {trailing}
          <Button size="icon" variant="ghost" onClick={onStartEdit}>
            <Pencil className="h-4 w-4" />
          </Button>
          <Button size="icon" variant="ghost" onClick={onRemove}>
            <Trash2 className="h-4 w-4 text-red-500" />
          </Button>
        </>
      )}
    </div>
  );
}

function ColorsCrudList({
  colors,
  onChanged,
}: {
  colors: any[];
  onChanged: () => void;
}) {
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingName, setEditingName] = useState("");
  const [newName, setNewName] = useState("");

  const startEdit = (c: any) => {
    setEditingId(c.id);
    setEditingName(c.nom);
  };

  const saveEdit = async () => {
    if (!editingId || !editingName.trim()) return;
    try {
      await djangoClient.catalog.colors.update(editingId, {
        nom: editingName.trim(),
      });
      toast.success("Couleur renommée");
      setEditingId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const removeColor = async (c: any) => {
    try {
      await djangoClient.catalog.colors.delete(c.id);
      toast.success("Couleur supprimée");
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la suppression");
    }
  };

  const addColor = async () => {
    if (!newName.trim()) return;
    try {
      await djangoClient.catalog.colors.create({ nom: newName.trim() });
      toast.success("Couleur ajoutée");
      setNewName("");
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  return (
    <div className="space-y-3">
      <div className="space-y-2 max-h-64 overflow-y-auto">
        {colors.map((c) => (
          <CrudRow
            key={c.id}
            label={c.nom}
            editing={editingId === c.id}
            editingValue={editingName}
            onEditingValueChange={setEditingName}
            onStartEdit={() => startEdit(c)}
            onSaveEdit={saveEdit}
            onCancelEdit={() => setEditingId(null)}
            onRemove={() => removeColor(c)}
          />
        ))}
        {colors.length === 0 && (
          <p className="text-sm text-muted-foreground text-center py-4">
            Aucune couleur.
          </p>
        )}
      </div>
      <div className="flex gap-2">
        <Input
          placeholder="Nouvelle couleur (ex: Bleu)"
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
        />
        <Button onClick={addColor}>
          <Plus className="h-4 w-4 mr-2" /> Ajouter
        </Button>
      </div>
    </div>
  );
}

function CategoriesTypesCrud({
  categories,
  types,
  onChanged,
}: {
  categories: any[];
  types: any[];
  onChanged: () => void;
}) {
  const [editingCatId, setEditingCatId] = useState<number | null>(null);
  const [editingCatName, setEditingCatName] = useState("");
  const [newCatName, setNewCatName] = useState("");
  const [newCatAvecCouleurs, setNewCatAvecCouleurs] = useState(true);

  const [editingTypeId, setEditingTypeId] = useState<number | null>(null);
  const [editingTypeName, setEditingTypeName] = useState("");
  const [newTypeNameByCategory, setNewTypeNameByCategory] = useState<
    Record<number, string>
  >({});

  const startEditCat = (c: any) => {
    setEditingCatId(c.id);
    setEditingCatName(c.nom);
  };
  const saveEditCat = async () => {
    if (!editingCatId || !editingCatName.trim()) return;
    try {
      await djangoClient.catalog.categories.update(editingCatId, {
        nom: editingCatName.trim(),
      });
      toast.success("Catégorie renommée");
      setEditingCatId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };
  const removeCategory = async (c: any) => {
    try {
      await djangoClient.catalog.categories.delete(c.id);
      toast.success("Catégorie supprimée");
      onChanged();
    } catch (err: any) {
      toast.error(
        err.message ||
          "Suppression impossible (des sous-types en dépendent encore)",
      );
    }
  };
  const addCategory = async () => {
    if (!newCatName.trim()) return;
    try {
      await djangoClient.catalog.categories.create({
        nom: newCatName.trim(),
        ordre: categories.length,
        avec_couleurs: newCatAvecCouleurs,
      });
      toast.success("Catégorie ajoutée");
      setNewCatName("");
      setNewCatAvecCouleurs(true);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const toggleAvecCouleurs = async (c: any) => {
    try {
      await djangoClient.catalog.categories.update(c.id, {
        avec_couleurs: !(c.avec_couleurs !== false),
      });
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  const startEditType = (t: any) => {
    setEditingTypeId(t.id);
    setEditingTypeName(t.nom);
  };
  const saveEditType = async () => {
    if (!editingTypeId || !editingTypeName.trim()) return;
    try {
      await djangoClient.catalog.types.update(editingTypeId, {
        nom: editingTypeName.trim(),
      });
      toast.success("Sous-type renommé");
      setEditingTypeId(null);
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };
  const removeType = async (t: any) => {
    try {
      await djangoClient.catalog.types.delete(t.id);
      toast.success("Sous-type supprimé");
      onChanged();
    } catch (err: any) {
      toast.error(
        err.message ||
          "Suppression impossible (des références en dépendent encore)",
      );
    }
  };
  const addType = async (categoryId: number) => {
    const nom = (newTypeNameByCategory[categoryId] || "").trim();
    if (!nom) return;
    try {
      await djangoClient.catalog.types.create({ category: categoryId, nom });
      toast.success("Sous-type ajouté");
      setNewTypeNameByCategory((prev) => ({ ...prev, [categoryId]: "" }));
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Erreur");
    }
  };

  return (
    <div className="space-y-4">
      <div className="space-y-2 rounded-md border bg-muted/20 p-3">
        <Label className="text-[11px] font-medium uppercase tracking-[0.08em] text-muted-foreground">
          Nouvelle catégorie
        </Label>
        <div className="flex gap-2">
          <Input
            placeholder="Ex. Accessoires"
            value={newCatName}
            onChange={(e) => setNewCatName(e.target.value)}
            className="h-9"
          />
          <Button onClick={addCategory} className="shrink-0">
            <FolderPlus className="h-4 w-4 mr-2" /> Ajouter
          </Button>
        </div>
        <div className="flex gap-2">
          <Button
            type="button"
            size="sm"
            variant={newCatAvecCouleurs ? "default" : "outline"}
            className="flex-1"
            onClick={() => setNewCatAvecCouleurs(true)}
          >
            <Palette className="h-3.5 w-3.5 mr-1.5" /> Avec couleurs
          </Button>
          <Button
            type="button"
            size="sm"
            variant={!newCatAvecCouleurs ? "default" : "outline"}
            className="flex-1"
            onClick={() => setNewCatAvecCouleurs(false)}
          >
            Sans couleurs
          </Button>
        </div>
        <p className="text-[11px] text-muted-foreground">
          « Avec couleurs » : housse, cache écran… « Sans couleurs » :
          chargeur, écouteur… — une seule quantité par référence.
        </p>
      </div>

      {categories.map((c) => {
        const typesForCat = types.filter((t) => t.category === c.id);
        return (
          <div key={c.id} className="border rounded-md p-3 bg-muted/10">
            <div className="flex items-center gap-2 mb-2">
              {editingCatId === c.id ? (
                <>
                  <Input
                    value={editingCatName}
                    onChange={(e) => setEditingCatName(e.target.value)}
                    className="h-8 flex-1 font-medium"
                    autoFocus
                  />
                  <Button size="sm" onClick={saveEditCat}>
                    OK
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setEditingCatId(null)}
                  >
                    Annuler
                  </Button>
                </>
              ) : (
                <>
                  <Tag className="h-4 w-4 text-muted-foreground" />
                  <span className="flex-1 text-sm font-semibold">{c.nom}</span>
                  <Badge
                    variant={c.avec_couleurs !== false ? "secondary" : "outline"}
                    className="cursor-pointer gap-1 font-normal"
                    onClick={() => toggleAvecCouleurs(c)}
                  >
                    {c.avec_couleurs !== false ? (
                      <>
                        <Palette className="h-3 w-3" /> Avec couleurs
                      </>
                    ) : (
                      "Sans couleurs"
                    )}
                  </Badge>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => startEditCat(c)}
                  >
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => removeCategory(c)}
                  >
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </>
              )}
            </div>
            <div className="space-y-1.5 pl-6">
              {typesForCat.map((t) => (
                <div
                  key={t.id}
                  className="flex items-center gap-2 rounded-sm px-2 py-1 hover:bg-muted/40"
                >
                  {editingTypeId === t.id ? (
                    <>
                      <Input
                        value={editingTypeName}
                        onChange={(e) => setEditingTypeName(e.target.value)}
                        className="h-8 flex-1"
                        autoFocus
                      />
                      <Button size="sm" onClick={saveEditType}>
                        OK
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setEditingTypeId(null)}
                      >
                        Annuler
                      </Button>
                    </>
                  ) : (
                    <>
                      <span className="flex-1 text-sm text-muted-foreground">
                        {t.nom}
                      </span>
                      <Button
                        size="icon"
                        variant="ghost"
                        onClick={() => startEditType(t)}
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        onClick={() => removeType(t)}
                      >
                        <Trash2 className="h-3.5 w-3.5 text-red-500" />
                      </Button>
                    </>
                  )}
                </div>
              ))}
              {typesForCat.length === 0 && (
                <p className="text-xs text-muted-foreground">
                  Aucun sous-type.
                </p>
              )}
              <div className="flex gap-2 pt-1">
                <Input
                  placeholder="Nouveau sous-type"
                  value={newTypeNameByCategory[c.id] || ""}
                  onChange={(e) =>
                    setNewTypeNameByCategory((prev) => ({
                      ...prev,
                      [c.id]: e.target.value,
                    }))
                  }
                  className="h-8"
                />
                <Button
                  size="sm"
                  onClick={() => addType(c.id)}
                  className="shrink-0"
                >
                  <Plus className="h-3.5 w-3.5 mr-1" /> Ajouter
                </Button>
              </div>
            </div>
          </div>
        );
      })}
      {categories.length === 0 && (
        <p className="text-sm text-muted-foreground text-center py-4">
          Aucune catégorie.
        </p>
      )}
    </div>
  );
}

/// Modification groupée du prix d'achat/vente pour toutes les références
/// d'un même sous-type (ex: toutes les "Flip cover", quelle que soit la
/// marque) — évite de rouvrir chaque référence une par une.
function BulkPriceDialog({
  open,
  onOpenChange,
  types,
  references,
  defaultTypeId,
  onDone,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  types: any[];
  references: any[];
  defaultTypeId: string;
  onDone: () => void;
}) {
  const [typeId, setTypeId] = useState("");
  const [prixAchat, setPrixAchat] = useState("");
  const [prixVente, setPrixVente] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (open) {
      setTypeId(defaultTypeId || "");
      setPrixAchat("");
      setPrixVente("");
    }
  }, [open, defaultTypeId]);

  const matchCount = useMemo(
    () => references.filter((r) => String(r.type) === typeId).length,
    [references, typeId],
  );

  const submit = async () => {
    if (!typeId) {
      toast.error("Choisissez un sous-type");
      return;
    }
    if (!prixAchat && !prixVente) {
      toast.error("Indiquez au moins un prix à modifier");
      return;
    }
    setSubmitting(true);
    try {
      const res = await djangoClient.catalog.references.bulkUpdatePrice({
        type_id: Number(typeId),
        ...(prixAchat ? { prix_achat: prixAchat } : {}),
        ...(prixVente ? { prix_vente: prixVente } : {}),
      });
      toast.success(`${res.updated} référence(s) mise(s) à jour`);
      onDone();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la mise à jour groupée");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Modifier le prix par sous-type</DialogTitle>
          <DialogDescription>
            Change le prix d'achat et/ou de vente de TOUTES les références d'un
            sous-type en une seule fois (ex : toutes les "Flip cover", quelle
            que soit la marque).
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Sous-type</Label>
            <Select value={typeId} onValueChange={setTypeId}>
              <SelectTrigger>
                <SelectValue placeholder="Choisir un sous-type" />
              </SelectTrigger>
              <SelectContent>
                {types.map((t) => (
                  <SelectItem key={t.id} value={String(t.id)}>
                    {t.nom}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {typeId && (
              <p className="text-xs text-muted-foreground">
                {matchCount} référence{matchCount > 1 ? "s" : ""} concernée
                {matchCount > 1 ? "s" : ""}.
              </p>
            )}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Nouveau prix actuel</Label>
              <Input
                type="number"
                min={0}
                placeholder="Laisser vide = inchangé"
                value={prixAchat}
                onChange={(e) => setPrixAchat(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Nouveau prix de vente</Label>
              <Input
                type="number"
                min={0}
                placeholder="Laisser vide = inchangé"
                value={prixVente}
                onChange={(e) => setPrixVente(e.target.value)}
              />
            </div>
          </div>
          {typeId && matchCount > 0 && (prixAchat || prixVente) && (
            <p className="text-xs text-orange-600 bg-orange-50 border border-orange-200 rounded-md p-2">
              Cette action est irréversible et modifiera directement{" "}
              {matchCount} référence{matchCount > 1 ? "s" : ""}.
            </p>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annuler
          </Button>
          <Button
            onClick={submit}
            disabled={submitting || !typeId || matchCount === 0}
          >
            {submitting ? "Mise à jour..." : "Appliquer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
