"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { djangoClient } from "@/lib/django-client";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import {
  HoverCard,
  HoverCardContent,
  HoverCardTrigger,
} from "@/components/ui/hover-card";
import { Skeleton } from "@/components/ui/skeleton";
import { Calendar } from "@/components/ui/calendar";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  ArrowDown,
  TrendingUp,
  Package,
  RefreshCw,
  Download,
  CalendarIcon,
  X,
} from "lucide-react";
import * as XLSX from "xlsx";
import { toast } from "sonner";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { useRealtimeRefresh } from "@/lib/hooks/useRealtimeRefresh";
import { useDebouncedValue } from "@/lib/hooks/useDebouncedValue";

const fmt = (n: number) =>
  new Intl.NumberFormat("fr-MG", { minimumFractionDigits: 0 }).format(
    Math.round(n),
  );

// YYYY-MM-DD en heure locale (pas UTC) — même format que <input type="date">.
const toDateInputValue = (d: Date) => {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

const getMovementTypeBadgeClass = (type: string) => {
  switch (type) {
    case "Entrée":
      return "bg-green-50 text-green-700";
    case "Sortie":
      return "bg-red-50 text-red-700";
    case "Transfert":
      return "bg-blue-50 text-blue-700";
    default:
      return "bg-orange-50 text-orange-700";
  }
};

const parseVariantEntries = (
  label: string | null | undefined,
  fallbackChange: number,
) =>
  (label || "")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean)
    .map((part) => {
      const match = part.match(/^(.*)\s+x(\d+)$/i);
      if (match) {
        const qty = parseInt(match[2], 10);
        return { name: match[1].trim(), qty: fallbackChange < 0 ? -qty : qty };
      }
      return { name: part, qty: fallbackChange };
    });

const getChangeBadgeClass = (change: number, movementType: string) => {
  if (movementType === "Transfert") return "bg-blue-50 text-blue-700";
  if (change > 0) return "bg-green-50 text-green-700";
  if (change < 0) return "bg-red-50 text-red-700";
  return "bg-orange-50 text-orange-700";
};

export default function MovementsPage() {
  const { user, isAdmin, isManager } = useCurrentUser();
  const [movements, setMovements] = useState<any[]>([]);
  const [products, setProducts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [statsStartDate, setStatsStartDate] = useState("");
  const [statsEndDate, setStatsEndDate] = useState("");

  const fetchData = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const [movementsData, productsData] = await Promise.all([
        djangoClient.movements.list(),
        djangoClient.products.list(),
      ]);
      setMovements(movementsData);
      setProducts(productsData);
    } catch (err) {
      console.error("Error fetching data:", err);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  const productsById = useMemo(() => {
    const map: Record<string, any> = {};
    products.forEach((p) => {
      map[p.id] = p;
    });
    return map;
  }, [products]);

  useRealtimeRefresh(["stock_movement", "product_variant", "order"], () => fetchData(true));

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const debouncedSearchTerm = useDebouncedValue(searchTerm);

  const filteredMovements = useMemo(
    () =>
      movements.filter((m) => {
        const term = debouncedSearchTerm.toLowerCase();
        const mDateStr = m.created_at ? m.created_at.split("T")[0] : "";
        const matchesTerm =
          !term ||
          (m.product_name || "").toLowerCase().includes(term) ||
          (m.product_reference || "").toLowerCase().includes(term) ||
          (m.changed_by_name || "").toLowerCase().includes(term) ||
          (m.changed_by_username || "").toLowerCase().includes(term) ||
          (m.magasin_name || "").toLowerCase().includes(term) ||
          (m.note || "").toLowerCase().includes(term);
        const matchesStart = !startDate || mDateStr >= startDate;
        const matchesEnd = !endDate || mDateStr <= endDate;
        return matchesTerm && matchesStart && matchesEnd;
      }),
    [movements, debouncedSearchTerm, startDate, endDate],
  );

  const statsFilteredMovements = useMemo(
    () =>
      movements.filter((m) => {
        const mDateStr = m.created_at ? m.created_at.split("T")[0] : "";
        const matchesStart = !statsStartDate || mDateStr >= statsStartDate;
        const matchesEnd = !statsEndDate || mDateStr <= statsEndDate;
        return matchesStart && matchesEnd;
      }),
    [movements, statsStartDate, statsEndDate],
  );

  const statsPeriodLabel = useMemo(() => {
    if (statsStartDate && statsEndDate)
      return `du ${statsStartDate} au ${statsEndDate}`;
    if (statsStartDate) return `depuis le ${statsStartDate}`;
    if (statsEndDate) return `jusqu'au ${statsEndDate}`;
    return "toute la période";
  }, [statsStartDate, statsEndDate]);

  const movementStats = useMemo(() => {
    const soldMap: Record<string, { name: string; qty: number }> = {};
    const movedProductNames = new Set<string>();

    statsFilteredMovements.forEach((m) => {
      const name = m.product_name || "Produit inconnu";
      movedProductNames.add(name);
      if (m.change < 0) {
        if (!soldMap[name]) soldMap[name] = { name, qty: 0 };
        soldMap[name].qty += Math.abs(m.change || 0);
      }
    });

    const fastest = Object.values(soldMap)
      .sort((a, b) => b.qty - a.qty)
      .slice(0, 5);

    const slowest = products
      .filter((p) => !movedProductNames.has(p.name))
      .slice(0, 5)
      .map((p) => ({ name: p.name, qty: 0 }));

    return { fastest, slowest };
  }, [statsFilteredMovements, products]);

  const totalEntries = useMemo(
    () =>
      filteredMovements.reduce(
        (sum, m) => sum + (m.change > 0 ? m.change : 0),
        0,
      ),
    [filteredMovements],
  );

  const totalExits = useMemo(
    () =>
      filteredMovements.reduce(
        (sum, m) => sum + (m.change < 0 ? Math.abs(m.change) : 0),
        0,
      ),
    [filteredMovements],
  );

  const totalMovements = useMemo(
    () => filteredMovements.length,
    [filteredMovements],
  );

  const formatDate = (d: string) =>
    new Date(d).toLocaleDateString("fr-FR", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });

  const handleExportExcel = () => {
    if (filteredMovements.length === 0) {
      toast.error("Aucun mouvement à exporter pour les filtres sélectionnés");
      return;
    }
    const rows = filteredMovements.map((m) => ({
      Date: formatDate(m.created_at),
      Produit: m.product_name || `Produit #${m.product}`,
      Référence: m.product_reference || "",
      Type: m.movement_type || "Mise à jour",
      Quantité: m.change,
      "Stock avant": m.previous_quantity,
      "Stock après": m.new_quantity,
      Note: m.note || "",
      Utilisateur: m.changed_by_name || "Système",
      Email: m.changed_by_username || "",
      Magasin: m.magasin_name || "",
    }));
    const ws = XLSX.utils.json_to_sheet(rows);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Mouvements");
    const dateSuffix = new Date().toISOString().split("T")[0];
    XLSX.writeFile(wb, `mouvements_${dateSuffix}.xlsx`);
    toast.success(`${filteredMovements.length} mouvement(s) exporté(s)`);
  };

  const groupedByDay = useMemo(() => {
    const today = new Date().toISOString().split("T")[0];
    const groups: Record<string, any[]> = {};
    filteredMovements.forEach((m) => {
      const day = new Date(m.created_at).toISOString().split("T")[0];
      if (!groups[day]) groups[day] = [];
      groups[day].push(m);
    });
    return { groups, today };
  }, [filteredMovements]);

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl sm:text-3xl font-bold tracking-tight">
              Mouvements de stock
            </h1>
            <p className="text-muted-foreground mt-1 text-sm sm:text-base">
              Historique complet des mouvements de stock
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => fetchData()}
              disabled={loading}
            >
              <RefreshCw
                className={`h-4 w-4 mr-2 ${loading ? "animate-spin" : ""}`}
              />
              Actualiser
            </Button>
            {isAdmin && (
              <Button
                variant="outline"
                size="sm"
                onClick={handleExportExcel}
                disabled={loading || filteredMovements.length === 0}
              >
                <Download className="h-4 w-4 mr-2" />
                Exporter XLSX
              </Button>
            )}
          </div>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <ArrowDown className="h-4 w-4 text-red-500" />
              Total sorties
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <Skeleton className="h-8 w-20" />
            ) : (
              <div className="text-2xl font-bold">{fmt(totalExits)} unités</div>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <TrendingUp className="h-4 w-4 text-green-500" />
              Total entrées
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <Skeleton className="h-8 w-28" />
            ) : (
              <div className="text-2xl font-bold">
                {fmt(totalEntries)} unités
              </div>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Package className="h-4 w-4 text-blue-500" />
              Nb mouvements
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <Skeleton className="h-8 w-12" />
            ) : (
              <div className="text-2xl font-bold">{totalMovements}</div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Stats */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">
            Filtre statistiques produits
          </CardTitle>
          <CardDescription>
            Période analysée : {statsPeriodLabel}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col sm:flex-row flex-wrap gap-3 items-end">
            <div className="space-y-1.5 w-full sm:w-auto">
              <Label
                htmlFor="stats-start-date"
                className="text-xs text-muted-foreground"
              >
                Date début
              </Label>
              <Input
                id="stats-start-date"
                type="date"
                value={statsStartDate}
                onChange={(e) => setStatsStartDate(e.target.value)}
                className="w-full sm:max-w-[180px]"
              />
            </div>
            <div className="space-y-1.5 w-full sm:w-auto">
              <Label
                htmlFor="stats-end-date"
                className="text-xs text-muted-foreground"
              >
                Date fin
              </Label>
              <Input
                id="stats-end-date"
                type="date"
                value={statsEndDate}
                min={statsStartDate || undefined}
                onChange={(e) => setStatsEndDate(e.target.value)}
                className="w-full sm:max-w-[180px]"
              />
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setStatsStartDate("");
                setStatsEndDate("");
              }}
              disabled={!statsStartDate && !statsEndDate}
            >
              Réinitialiser
            </Button>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center text-green-600 dark:text-green-400">
              <TrendingUp className="mr-2 h-5 w-5" />
              Produits les plus vendus
            </CardTitle>
            <CardDescription>
              Sorties de stock sur la période ({statsPeriodLabel})
            </CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? (
              <Skeleton className="h-24 w-full" />
            ) : (
              <div className="space-y-3">
                {movementStats.fastest.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    Aucune vente enregistrée sur cette période.
                  </p>
                ) : (
                  movementStats.fastest.map((p, i) => (
                    <div
                      key={i}
                      className="flex justify-between items-center border-b pb-2 last:border-0"
                    >
                      <span className="font-medium text-sm">{p.name}</span>
                      <Badge
                        variant="outline"
                        className="bg-green-500/10 text-green-700 dark:text-green-400 border-green-500/20"
                      >
                        {p.qty} unités
                      </Badge>
                    </div>
                  ))
                )}
              </div>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center text-orange-600 dark:text-orange-400">
              <ArrowDown className="mr-2 h-5 w-5" />
              Produits sans mouvement
            </CardTitle>
            <CardDescription>
              Aucun mouvement sur la période ({statsPeriodLabel})
            </CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? (
              <Skeleton className="h-24 w-full" />
            ) : (
              <div className="space-y-3">
                {movementStats.slowest.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    Tous les produits ont eu au moins un mouvement sur cette
                    période.
                  </p>
                ) : (
                  movementStats.slowest.map((p, i) => (
                    <div
                      key={i}
                      className="flex justify-between items-center border-b pb-2 last:border-0"
                    >
                      <span className="font-medium text-sm">{p.name}</span>
                      <Badge
                        variant="outline"
                        className="bg-orange-500/10 text-orange-700 dark:text-orange-400 border-orange-500/20"
                      >
                        0 mouvement
                      </Badge>
                    </div>
                  ))
                )}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
      <div className="text-sm text-muted-foreground text-2xl font-bold">
        Filtre mouvements par date
      </div>
      {/* History Table */}
      <div className="flex flex-col sm:flex-row flex-wrap gap-3">
        <div className="flex flex-col sm:flex-row gap-2 flex-1 min-w-[200px]">
          <Input
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            className="w-full sm:max-w-[160px]"
            title="Date début"
          />
          <Input
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            className="w-full sm:max-w-[160px]"
            title="Date fin"
          />
        </div>
        <Input
          placeholder="Rechercher produit, référence, vendeur..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full sm:max-w-xs"
        />
      </div>
      <Card>
        <CardHeader>
          <CardTitle>Historique des mouvements de stock</CardTitle>
          <CardDescription>
            {filteredMovements.length} mouvement(s) affiché(s)
          </CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="space-y-2">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Référence</TableHead>
                    <TableHead>Produit</TableHead>
                    <TableHead>Variante(s)</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead className="text-right">Quantité</TableHead>
                    <TableHead>Fait par</TableHead>
                    {isManager && <TableHead>Magasin</TableHead>}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredMovements.length === 0 ? (
                    <TableRow>
                      <TableCell
                        colSpan={isManager ? 8 : 7}
                        className="text-center text-muted-foreground py-8"
                      >
                        Aucun mouvement enregistré
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredMovements.map((m) => (
                      <TableRow key={m.id}>
                        <TableCell className="text-sm">
                          {formatDate(m.created_at)}
                        </TableCell>
                        <TableCell className="text-sm">
                          {m.product_reference || "-"}
                        </TableCell>
                        <TableCell>
                          <p className="font-medium text-sm">
                            {m.product_name || `Produit #${m.product}`}
                          </p>
                          {(() => {
                            const p = productsById[m.product];
                            const brand = p?.brand;
                            const category = p?.category;
                            if (!brand && !category) return null;
                            return (
                              <p className="text-xs text-muted-foreground">
                                {[brand, category].filter(Boolean).join(" · ")}
                              </p>
                            );
                          })()}
                        </TableCell>
                        <TableCell>
                          {(() => {
                            const variants = parseVariantEntries(
                              m.variant_label,
                              m.change,
                            );
                            if (variants.length === 0) {
                              return (
                                <span className="text-sm text-muted-foreground">
                                  -
                                </span>
                              );
                            }
                            if (variants.length === 1) {
                              const v = variants[0];
                              return (
                                <Badge
                                  variant="outline"
                                  className="font-normal border-purple-200 text-sky-700 bg-purple-50/50"
                                >
                                  {v.name} {v.qty > 0 ? "+" : ""}
                                  {v.qty}
                                </Badge>
                              );
                            }
                            return (
                              <HoverCard>
                                <HoverCardTrigger asChild>
                                  <Badge
                                    variant="outline"
                                    className="font-normal border-purple-200 text-purple-700 bg-purple-50/50 cursor-default"
                                  >
                                    {variants.length} variantes
                                  </Badge>
                                </HoverCardTrigger>
                                <HoverCardContent className="w-auto p-2">
                                  <div className="flex flex-col gap-1">
                                    {variants.map((v, i) => (
                                      <Badge
                                        key={i}
                                        variant="outline"
                                        className="font-normal border-purple-200 text-purple-700 bg-purple-50/50"
                                      >
                                        {v.name} {v.qty > 0 ? "+" : ""}
                                        {v.qty}
                                      </Badge>
                                    ))}
                                  </div>
                                </HoverCardContent>
                              </HoverCard>
                            );
                          })()}
                        </TableCell>

                        <TableCell>
                          <Badge
                            variant="outline"
                            className={getMovementTypeBadgeClass(
                              m.movement_type || "Mise à jour",
                            )}
                          >
                            {m.movement_type || "Mise à jour"}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right font-medium">
                          <Badge
                            variant="outline"
                            className={getChangeBadgeClass(
                              m.change,
                              m.movement_type || "",
                            )}
                          >
                            {m.change > 0 ? "+" : ""}
                            {m.change}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-sm">
                          <p className="font-medium">
                            {m.changed_by_name || "Système"}
                          </p>
                          {m.changed_by_username && (
                            <p className="text-xs text-muted-foreground">
                              {m.changed_by_username}
                            </p>
                          )}
                        </TableCell>
                        {isManager && (
                          <TableCell className="text-sm">
                            <Badge
                              variant="outline"
                              className="font-normal border-blue-200 text-blue-700 bg-blue-50/50"
                            >
                              {m.magasin_name || "-"}
                            </Badge>
                          </TableCell>
                        )}
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Grouped by day */}
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h2 className="text-xl font-bold tracking-tight">Mouvements par jour</h2>
        <div className="flex items-center gap-2">
          <Popover>
            <PopoverTrigger asChild>
              <Button variant="outline" size="sm">
                <CalendarIcon className="h-4 w-4 mr-2" />
                {startDate && startDate === endDate
                  ? new Date(startDate).toLocaleDateString("fr-FR", {
                      day: "numeric",
                      month: "long",
                      year: "numeric",
                    })
                  : "Filtrer par jour"}
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-auto p-0" align="end">
              <Calendar
                mode="single"
                captionLayout="dropdown"
                selected={startDate && startDate === endDate ? new Date(startDate + "T00:00:00") : undefined}
                onSelect={(d) => {
                  if (!d) return;
                  const value = toDateInputValue(d);
                  setStartDate(value);
                  setEndDate(value);
                }}
              />
            </PopoverContent>
          </Popover>
          {startDate && startDate === endDate && (
            <Button variant="ghost" size="icon" onClick={() => { setStartDate(""); setEndDate(""); }}>
              <X className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
      <DailyMovementsTable
        groups={groupedByDay.groups}
        today={groupedByDay.today}
        isManager={isManager}
        hideToday={!(startDate && startDate === endDate)}
      />
    </div>
  );
}

function DailyMovementsTable({
  groups,
  today,
  isManager,
  hideToday = true,
}: {
  groups: Record<string, any[]>;
  today: string;
  isManager: boolean;
  hideToday?: boolean;
}) {
  const sortedDates = Object.keys(groups)
    .filter((d) => !hideToday || d !== today)
    .sort((a, b) => b.localeCompare(a));

  const fmt = (n: number) =>
    new Intl.NumberFormat("fr-MG").format(Math.round(n));

  const label = (dateKey: string) => {
    const d = new Date(dateKey);
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const same = (a: Date, b: Date) =>
      a.getFullYear() === b.getFullYear() &&
      a.getMonth() === b.getMonth() &&
      a.getDate() === b.getDate();
    if (same(d, yesterday)) return "Hier";
    return d.toLocaleDateString("fr-FR", {
      weekday: "long",
      day: "numeric",
      month: "long",
    });
  };

  if (sortedDates.length === 0) {
    return (
      <p className="text-sm text-muted-foreground text-center py-8">
        Aucun mouvement pour cette période.
      </p>
    );
  }

  return (
    <div className="space-y-6">
      {sortedDates.map((dateKey) => (
        <Card key={dateKey}>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2 capitalize">
              {label(dateKey)}
              <Badge variant="outline">
                {groups[dateKey].length} mouvement(s)
              </Badge>
              <span className="text-sm font-normal text-muted-foreground ml-auto">
                {fmt(
                  groups[dateKey].reduce(
                    (s, x) => s + Math.abs(x.change || 0),
                    0,
                  ),
                )}{" "}
                unités
              </span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Heure</TableHead>
                    <TableHead>Produit</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead className="text-right">Qté</TableHead>
                    <TableHead>Note</TableHead>
                    <TableHead>Utilisateur</TableHead>
                    {isManager && <TableHead>Magasin</TableHead>}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {groups[dateKey].map((m) => (
                    <TableRow key={m.id}>
                      <TableCell className="text-sm">
                        {new Date(m.created_at).toLocaleTimeString("fr-FR", {
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </TableCell>
                      <TableCell className="font-medium text-sm">
                        {m.product_name || `Produit #${m.product}`}
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant="outline"
                          className={getMovementTypeBadgeClass(
                            m.movement_type || "Mise à jour",
                          )}
                        >
                          {m.movement_type || "Mise à jour"}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right font-medium">
                        <Badge
                          variant="outline"
                          className={getChangeBadgeClass(
                            m.change,
                            m.movement_type || "",
                          )}
                        >
                          {m.change > 0 ? "+" : ""}
                          {m.change}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-sm">{m.note || "-"}</TableCell>
                      <TableCell className="text-sm">
                        <p className="font-medium">
                          {m.changed_by_name || "Système"}
                        </p>
                        {m.changed_by_username && (
                          <p className="text-xs text-muted-foreground">
                            {m.changed_by_username}
                          </p>
                        )}
                      </TableCell>
                      {isManager && (
                        <TableCell className="text-sm">
                          <Badge
                            variant="outline"
                            className="font-normal border-blue-200 text-blue-700 bg-blue-50/50"
                          >
                            {m.magasin_name || "-"}
                          </Badge>
                        </TableCell>
                      )}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
