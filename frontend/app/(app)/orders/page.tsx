"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { djangoClient } from "@/lib/django-client";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { useRealtimeRefresh } from "@/lib/hooks/useRealtimeRefresh";
import { useDeliveryZones } from "@/lib/hooks/useDeliveryZones";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
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
  Tooltip,
  TooltipTrigger,
  TooltipContent,
} from "@/components/ui/tooltip";
import {
  Plus,
  Trash2,
  Truck,
  Package,
  RefreshCw,
  Phone,
  ShoppingCart,
  Wrench,
  Boxes,
  CheckCircle2,
  Undo2,
  UserCheck,
  Pencil,
  UserRound,
  Ban,
  History,
  Camera,
} from "lucide-react";
import { toast } from "sonner";

function IconAction({
  label,
  onClick,
  icon: Icon,
  variant = "default",
  className = "",
  disabled = false,
  showLabel = false,
}: {
  label: string;
  onClick: (e: React.MouseEvent) => void;
  icon: any;
  variant?: "default" | "outline" | "ghost" | "destructive";
  className?: string;
  disabled?: boolean;
  showLabel?: boolean;
}) {
  const content = (
    <>
      <Icon className="h-4 w-4" />
      {showLabel && <span className="text-xs font-medium">{label}</span>}
    </>
  );

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          size={showLabel ? "sm" : "icon"}
          variant={variant}
          className={showLabel ? `gap-1.5 ${className}` : className}
          onClick={onClick}
          disabled={disabled}
        >
          {content}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  );
}

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat("fr-MG").format(Math.round(Number(n || 0))) + " Ar";

const fmtDT = (iso?: string | null) =>
  iso
    ? new Date(iso).toLocaleString("fr-FR", {
        day: "2-digit",
        month: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
      })
    : null;

const historyAt = (order: any, statut: string) =>
  (order.status_history || []).find((h: any) => h.nouveau_statut === statut)
    ?.timestamp;

const STATUTS = [
  {
    value: "NOUVELLE",
    label: "Nouvelle",
    color: "bg-slate-100 text-slate-800",
  },
  {
    value: "EN_PREPARATION",
    label: "En préparation",
    color: "bg-amber-100 text-amber-800",
  },
  { value: "PRETE", label: "Prête", color: "bg-blue-100 text-blue-800" },
  {
    value: "EN_LIVRAISON",
    label: "En livraison",
    color: "bg-purple-100 text-purple-800",
  },
  { value: "LIVRE", label: "Livré", color: "bg-green-100 text-green-800" },
  { value: "RETOUR", label: "Retour", color: "bg-red-100 text-red-800" },
  { value: "ANNULEE", label: "Annulée", color: "bg-zinc-200 text-zinc-800" },
];
const statutInfo = (s: string) =>
  STATUTS.find((x) => x.value === s) || STATUTS[0];

// "Jour J" = jour du champ date_commande (planning) — le préparateur/livreur
// voit toutes ses commandes à venir mais ne peut agir dessus qu'à partir de
// ce jour (le serveur applique la même règle, voir orders/services.py).
const isJourJ = (dateStr?: string | null) => {
  if (!dateStr) return true;
  const d = new Date(dateStr);
  const today = new Date();
  d.setHours(0, 0, 0, 0);
  today.setHours(0, 0, 0, 0);
  return d.getTime() <= today.getTime();
};

// Zones de livraison : configurables dans Paramètres (§ demande, CRUD
// nom+prix — voir useDeliveryZones/DeliveryZoneOption), plus le littéral
// "RECUPERATION" toujours présent (retrait sur place, structurellement à
// part : pas de livreur, pas de frais). `buildZoneOptions` retrouve la même
// forme {value,label,frais} que l'ancienne liste figée, pour que tous les
// .find()/.filter() existants restent inchangés.
function buildZoneOptions(
  zones: { code: string; nom: string; prix: number }[],
) {
  return [
    ...zones.map((z) => ({
      value: z.code,
      label: `${z.nom} (${fmt(z.prix)})`,
      frais: Number(z.prix),
    })),
    { value: "RECUPERATION", label: "Récupération (0 Ar)", frais: 0 },
  ];
}

const MODE_PAIEMENT = [
  { value: "AVANT", label: "Paye" },
  { value: "LIVRAISON", label: "Paiement à la livraison" },
];

interface CartItem {
  key: string;
  type_id: number;
  type_name: string;
  reference_id: number;
  reference_label: string;
  prix_vente: number;
  variant_id: number;
  couleur: string;
  stock_actuel: number;
  quantite: number;
}

export default function OrdersPage() {
  const {
    user,
    isGerant,
    isPreparateur,
    isLivreur,
    loading: userLoading,
  } = useCurrentUser();
  const { zones } = useDeliveryZones();
  const zoneOptions = useMemo(() => buildZoneOptions(zones), [zones]);
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [statutFilter, setStatutFilter] = useState<string>("ALL");
  const [detail, setDetail] = useState<any | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [actionNote, setActionNote] = useState<{
    order: any;
    target: string;
    label: string;
  } | null>(null);
  const [assignTarget, setAssignTarget] = useState<{
    order: any;
    role: "PREPARATEUR" | "LIVREUR";
  } | null>(null);
  const [editTarget, setEditTarget] = useState<any | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<any | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [cancelTarget, setCancelTarget] = useState<any | null>(null);
  const [cancelling, setCancelling] = useState(false);
  // Le préparateur suit séparément sa file "à préparer" (livraison) et ses
  // commandes "Récupération sur place" (qu'il peut créer lui-même).
  const [preparateurTab, setPreparateurTab] = useState<
    "A_PREPARER" | "RECUPERATIONS"
  >("A_PREPARER");
  // Onglet "Historique" (préparateur/livreur) — journal de leurs commandes
  // déjà traitées, tous statuts, filtrable par date/heure.
  const [viewMode, setViewMode] = useState<"ACTIF" | "HISTORIQUE">("ACTIF");
  const [historiqueFrom, setHistoriqueFrom] = useState("");
  const [historiqueTo, setHistoriqueTo] = useState("");
  // Filtres gérant : date (un seul jour, pas de plage Du/Au) + préparateur assigné.
  const [gerantDate, setGerantDate] = useState("");
  const [preparateurFilterId, setPreparateurFilterId] = useState("");
  const [preparateurFilterList, setPreparateurFilterList] = useState<
    { id: number; full_name: string }[]
  >([]);
  // Filtres livreur (vue "Ma tournée") : statut + date (un seul jour).
  const [livreurStatutFilter, setLivreurStatutFilter] = useState("ALL");
  const [livreurDate, setLivreurDate] = useState("");
  // Filtre préparateur (vue "À préparer"/"Récupérations") : date (un seul jour).
  const [preparateurDate, setPreparateurDate] = useState("");

  useEffect(() => {
    if (!isGerant) return;
    djangoClient.orders
      .availableStaff("PREPARATEUR")
      .then(setPreparateurFilterList)
      .catch(() => {});
  }, [isGerant]);

  const fetchOrders = useCallback(
    async (silent = false) => {
      if (!silent) setLoading(true);
      try {
        const filters: any = {};
        if (isGerant) {
          if (statutFilter !== "ALL" && statutFilter !== "NON_LIVREE")
            filters.statut = statutFilter;
          if (gerantDate) {
            filters.date_debut = gerantDate;
            filters.date_fin = gerantDate;
          }
          if (preparateurFilterId)
            filters.preparateur_id = Number(preparateurFilterId);
        }
        if ((isPreparateur || isLivreur) && viewMode === "HISTORIQUE") {
          filters.historique = true;
          if (historiqueFrom)
            filters.date_from = new Date(historiqueFrom).toISOString();
          if (historiqueTo)
            filters.date_to = new Date(historiqueTo).toISOString();
        }
        if (isPreparateur && viewMode === "ACTIF" && preparateurDate) {
          filters.date_debut = preparateurDate;
          filters.date_fin = preparateurDate;
        }
        if (isLivreur && viewMode === "ACTIF") {
          if (livreurStatutFilter !== "ALL")
            filters.statut = livreurStatutFilter;
          if (livreurDate) {
            filters.date_debut = livreurDate;
            filters.date_fin = livreurDate;
          }
        }
        const data = await djangoClient.orders.list(filters);
        setOrders(data);
      } catch (err: any) {
        toast.error(err.message || "Erreur de chargement des commandes");
      } finally {
        if (!silent) setLoading(false);
      }
    },
    [
      isGerant,
      statutFilter,
      gerantDate,
      preparateurFilterId,
      isPreparateur,
      isLivreur,
      viewMode,
      historiqueFrom,
      historiqueTo,
      preparateurDate,
      livreurStatutFilter,
      livreurDate,
    ],
  );

  useRealtimeRefresh(["order", "order_status_history"], () =>
    fetchOrders(true),
  );
  useEffect(() => {
    if (!userLoading) fetchOrders();
  }, [userLoading, fetchOrders]);

  const title =
    viewMode === "HISTORIQUE"
      ? "Historique"
      : isPreparateur
        ? "Dépôt — Commandes à préparer"
        : isLivreur
          ? "Ma tournée"
          : "Commandes";
  const description =
    viewMode === "HISTORIQUE"
      ? "Vos commandes déjà traitées, tous statuts — filtrables par date et heure."
      : isPreparateur
        ? 'Commandes reçues à préparer, puis à marquer "Prête" pour le livreur.'
        : isLivreur
          ? 'Commandes prêtes à récupérer, puis "Livré" ou "Retour" une fois la tournée faite.'
          : "Suivi complet des commandes clients.";

  const gerantActionOptions = (order: any) => {
    const options: {
      value: string;
      label: string;
      target: string;
      kind: "status" | "assign";
      role?: "PREPARATEUR" | "LIVREUR";
      icon?: any;
    }[] = [
      {
        value: "assign-preparateur",
        label: "Assigner un préparateur",
        target: "EN_PREPARATION",
        kind: "assign",
        role: "PREPARATEUR",
        icon: UserCheck,
      },
      {
        value: "commencer-preparation",
        label: "Commencer la préparation",
        target: "EN_PREPARATION",
        kind: "status",
        icon: Package,
      },
      {
        value: "commande-prete",
        label: "Commande prête",
        target: "PRETE",
        kind: "status",
        icon: Package,
      },
      {
        value: "assign-livreur",
        label: "Assigner un livreur",
        target: "EN_LIVRAISON",
        kind: "assign",
        role: "LIVREUR",
        icon: UserCheck,
      },
      {
        value: "rendre-en-livraison",
        label: "Récupérer / En livraison",
        target: "EN_LIVRAISON",
        kind: "status",
        icon: Truck,
      },
      {
        value: "livre",
        label: "Livrée",
        target: "LIVRE",
        kind: "status",
        icon: Truck,
      },
      {
        value: "retour",
        label: "Retour",
        target: "RETOUR",
        kind: "status",
        icon: Undo2,
      },
      {
        value: "retour-apres-livraison",
        label: "Retour après livraison",
        target: "RETOUR",
        kind: "status",
        icon: Undo2,
      },
    ];

    if (order?.livraison_zone === "RECUPERATION") {
      return options.filter(
        (option) =>
          !["assign-livreur", "rendre-en-livraison", "livre"].includes(
            option.value,
          ),
      );
    }

    return options;
  };

  const nextAction = (
    order: any,
  ): { label: string; target: string; icon: any; assign?: boolean } | null => {
    if (isPreparateur) {
      if (order.statut_courant === "NOUVELLE")
        return {
          label: "Commencer la préparation",
          target: "EN_PREPARATION",
          icon: Package,
        };
      if (order.statut_courant === "EN_PREPARATION")
        return { label: "Commande prête", target: "PRETE", icon: Package };
      return null;
    }
    if (isLivreur) {
      if (order.statut_courant === "PRETE")
        return {
          label: "Récupérer (en livraison)",
          target: "EN_LIVRAISON",
          icon: Truck,
        };
      if (order.statut_courant === "EN_LIVRAISON")
        return { label: "Livré", target: "LIVRE", icon: Truck };
      return null;
    }
    if (isGerant) {
      const actions = gerantActionOptions(order);
      if (actions.length === 0) return null;
      const first = actions[0];
      return {
        label: first.label,
        target: first.target,
        icon: first.icon || Package,
        assign: first.kind === "assign",
      };
    }
    return null;
  };

  const doChangeStatus = async (
    order: any,
    target: string,
    note?: string,
    assignee?: {
      preparateur_id?: number;
      livreur_id?: number;
      assigned_at?: string;
    },
    photo?: File,
  ) => {
    try {
      await djangoClient.orders.changeStatus(
        order.id,
        target,
        note,
        assignee,
        photo,
      );
      toast.success(`Commande ${order.numero} → ${statutInfo(target).label}`);
      fetchOrders(true);
      setActionNote(null);
      setAssignTarget(null);
    } catch (err: any) {
      toast.error(err.message || "Action impossible");
    }
  };

  const handleDeleteOrder = async () => {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await djangoClient.orders.delete(deleteTarget.id);
      toast.success(`Commande ${deleteTarget.numero} supprimée`);
      setDeleteTarget(null);
      fetchOrders(true);
    } catch (err: any) {
      toast.error(err.message || "Suppression impossible");
    } finally {
      setDeleting(false);
    }
  };

  const handleCancelOrder = async () => {
    if (!cancelTarget) return;
    setCancelling(true);
    try {
      await djangoClient.orders.cancel(cancelTarget.id);
      toast.success(`Commande ${cancelTarget.numero} annulée`);
      setCancelTarget(null);
      fetchOrders(true);
    } catch (err: any) {
      toast.error(err.message || "Annulation impossible");
    } finally {
      setCancelling(false);
    }
  };

  const visibleOrders =
    viewMode === "HISTORIQUE"
      ? orders
      : isPreparateur
        ? orders.filter((o) =>
            preparateurTab === "RECUPERATIONS"
              ? o.livraison_zone === "RECUPERATION"
              : o.livraison_zone !== "RECUPERATION",
          )
        : isGerant && statutFilter === "NON_LIVREE"
          ? orders.filter((o) => o.statut_courant !== "LIVRE")
          : orders;

  const searchableOrders = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return visibleOrders;

    return visibleOrders.filter((order: any) => {
      const productText = (order.items || [])
        .map((item: any) =>
          [
            item.reference_name,
            item.product_name,
            item.couleur,
            item.variant_name,
          ]
            .filter(Boolean)
            .join(" "),
        )
        .join(" ");

      const searchableString = [
        order.numero,
        order.client_nom,
        order.adresse_livraison,
        order.telephone,
        order.livraison_zone,
        order.preparateur_name,
        order.livreur_name,
        order.statut_courant,
        productText,
        order.date_commande
          ? new Date(order.date_commande).toLocaleDateString("fr-FR")
          : "",
        order.date_commande
          ? new Date(order.date_commande).toLocaleString("fr-FR")
          : "",
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return searchableString.includes(q);
    });
  }, [visibleOrders, searchQuery]);

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">{title}</h1>
          <p className="text-sm text-muted-foreground">{description}</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="icon" onClick={() => fetchOrders()}>
            <RefreshCw className="h-4 w-4" />
          </Button>
          {(isGerant || isPreparateur) && (
            <Button onClick={() => setCreateOpen(true)}>
              <Plus className="h-4 w-4 mr-2" />{" "}
              {isGerant ? "Nouvelle commande" : "Nouvelle récupération"}
            </Button>
          )}
        </div>
      </div>

      {isPreparateur && (
        <div className="flex flex-wrap gap-2">
          <Button
            variant={
              viewMode === "ACTIF" && preparateurTab === "A_PREPARER"
                ? "default"
                : "outline"
            }
            size="sm"
            onClick={() => {
              setViewMode("ACTIF");
              setPreparateurTab("A_PREPARER");
            }}
          >
            <Truck className="h-4 w-4 mr-2" /> À préparer
          </Button>
          <Button
            variant={
              viewMode === "ACTIF" && preparateurTab === "RECUPERATIONS"
                ? "default"
                : "outline"
            }
            size="sm"
            onClick={() => {
              setViewMode("ACTIF");
              setPreparateurTab("RECUPERATIONS");
            }}
          >
            <Package className="h-4 w-4 mr-2" /> Récupérations
          </Button>
          <Button
            variant={viewMode === "HISTORIQUE" ? "default" : "outline"}
            size="sm"
            onClick={() => setViewMode("HISTORIQUE")}
          >
            <History className="h-4 w-4 mr-2" /> Historique
          </Button>
        </div>
      )}

      {isLivreur && (
        <div className="flex flex-wrap gap-2">
          <Button
            variant={viewMode === "ACTIF" ? "default" : "outline"}
            size="sm"
            onClick={() => setViewMode("ACTIF")}
          >
            <Truck className="h-4 w-4 mr-2" /> Ma tournée
          </Button>
          <Button
            variant={viewMode === "HISTORIQUE" ? "default" : "outline"}
            size="sm"
            onClick={() => setViewMode("HISTORIQUE")}
          >
            <History className="h-4 w-4 mr-2" /> Historique
          </Button>
        </div>
      )}

      {isLivreur && viewMode === "ACTIF" && (
        <div className="flex flex-wrap items-end gap-2">
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Statut</Label>
            <Select
              value={livreurStatutFilter}
              onValueChange={setLivreurStatutFilter}
            >
              <SelectTrigger className="w-45">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">Tous</SelectItem>
                <SelectItem value="EN_PREPARATION">En préparation</SelectItem>
                <SelectItem value="PRETE">Prête</SelectItem>
                <SelectItem value="EN_LIVRAISON">En livraison</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Date</Label>
            <Input
              type="date"
              value={livreurDate}
              onChange={(e) => setLivreurDate(e.target.value)}
              className="w-auto"
            />
          </div>
          <div className="space-y-1 min-w-[220px] flex-1 max-w-[360px]">
            <Label className="text-xs text-muted-foreground">Recherche</Label>
            <Input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Code, client, produit, adresse, livreur, préparateur, date..."
              className="w-full"
            />
          </div>
          {(livreurStatutFilter !== "ALL" || livreurDate || searchQuery) && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setLivreurStatutFilter("ALL");
                setLivreurDate("");
                setSearchQuery("");
              }}
            >
              Réinitialiser
            </Button>
          )}
        </div>
      )}

      {isPreparateur && viewMode === "ACTIF" && (
        <div className="flex flex-wrap items-end gap-2">
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Date</Label>
            <Input
              type="date"
              value={preparateurDate}
              onChange={(e) => setPreparateurDate(e.target.value)}
              className="w-auto"
            />
          </div>
          <div className="space-y-1 min-w-[220px] flex-1 max-w-[360px]">
            <Label className="text-xs text-muted-foreground">Recherche</Label>
            <Input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Code, client, produit, adresse, date..."
              className="w-full"
            />
          </div>
          {(preparateurDate || searchQuery) && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setPreparateurDate("");
                setSearchQuery("");
              }}
            >
              Réinitialiser
            </Button>
          )}
        </div>
      )}

      {(isPreparateur || isLivreur) && viewMode === "HISTORIQUE" && (
        <div className="flex flex-wrap items-end gap-2">
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Du</Label>
            <Input
              type="datetime-local"
              value={historiqueFrom}
              onChange={(e) => setHistoriqueFrom(e.target.value)}
              className="w-auto"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Au</Label>
            <Input
              type="datetime-local"
              value={historiqueTo}
              onChange={(e) => setHistoriqueTo(e.target.value)}
              className="w-auto"
            />
          </div>
          {(historiqueFrom || historiqueTo) && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setHistoriqueFrom("");
                setHistoriqueTo("");
              }}
            >
              Réinitialiser
            </Button>
          )}
        </div>
      )}

      {isGerant && (
        <div className="flex flex-wrap gap-2">
          <Button
            variant={statutFilter === "ALL" ? "default" : "outline"}
            size="sm"
            onClick={() => setStatutFilter("ALL")}
          >
            Toutes
          </Button>
          <Button
            variant={statutFilter === "NON_LIVREE" ? "default" : "outline"}
            size="sm"
            onClick={() => setStatutFilter("NON_LIVREE")}
          >
            Pas encore livrée
          </Button>
          {STATUTS.map((s) => (
            <Button
              key={s.value}
              variant={statutFilter === s.value ? "default" : "outline"}
              size="sm"
              onClick={() => setStatutFilter(s.value)}
            >
              {s.label}
            </Button>
          ))}
        </div>
      )}

      {isGerant && (
        <div className="flex flex-wrap items-end gap-2">
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Date</Label>
            <Input
              type="date"
              value={gerantDate}
              onChange={(e) => setGerantDate(e.target.value)}
              className="w-auto"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Statut</Label>
            <Select value={statutFilter} onValueChange={setStatutFilter}>
              <SelectTrigger className="w-45">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">Tous</SelectItem>
                <SelectItem value="NON_LIVREE">Pas encore livrée</SelectItem>
                {STATUTS.map((s) => (
                  <SelectItem key={s.value} value={s.value}>
                    {s.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Préparateur</Label>
            <Select
              value={preparateurFilterId}
              onValueChange={setPreparateurFilterId}
            >
              <SelectTrigger className="w-45">
                <SelectValue placeholder="Tous" />
              </SelectTrigger>
              <SelectContent>
                {preparateurFilterList.map((p) => (
                  <SelectItem key={p.id} value={String(p.id)}>
                    {p.full_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1 min-w-[220px] flex-1 max-w-[360px]">
            <Label className="text-xs text-muted-foreground">Recherche</Label>
            <Input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Code, client, produit, adresse, livreur, préparateur, date..."
              className="w-full"
            />
          </div>
          {(gerantDate ||
            preparateurFilterId ||
            statutFilter !== "ALL" ||
            searchQuery) && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setGerantDate("");
                setPreparateurFilterId("");
                setStatutFilter("ALL");
                setSearchQuery("");
              }}
            >
              Réinitialiser
            </Button>
          )}
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <div className="p-6">
              <Skeleton className="h-64 w-full" />
            </div>
          ) : searchableOrders.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">
              Aucune commande trouvée pour cette recherche.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>N° commande</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Sous-type</TableHead>
                    <TableHead>Produit</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Client</TableHead>
                    {isLivreur && <TableHead>Adresse</TableHead>}
                    {isLivreur && <TableHead>Téléphone</TableHead>}
                    <TableHead>{isLivreur ? "Zone" : "Adresse"}</TableHead>
                    <TableHead>Statut</TableHead>
                    {!isPreparateur && <TableHead>Total</TableHead>}
                    {isGerant && <TableHead>Assigné à</TableHead>}
                    <TableHead className="text-right">Action</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {searchableOrders.map((order) => {
                    const action = nextAction(order);
                    const preparedAt = historyAt(order, "EN_PREPARATION");
                    // Tant que la commande n'est pas Livrée, on affiche la date de
                    // livraison prévue (date_commande) — une fois Livrée, l'heure
                    // réellement atteinte (§ demande).
                    const livreurAt =
                      order.statut_courant === "LIVRE"
                        ? historyAt(order, "LIVRE")
                        : order.date_commande;
                    // Une commande assignée à un préparateur dès sa création
                    // part directement en "En préparation" — restreindre la
                    // modification à "Nouvelle" ne laissait presque aucune
                    // fenêtre pour la corriger (§ demande). La suppression,
                    // elle, reste réservée à "Nouvelle" (rien d'engagé).
                    const canEdit =
                      isGerant &&
                      ["NOUVELLE", "EN_PREPARATION"].includes(
                        order.statut_courant,
                      );
                    const canDelete =
                      isGerant && order.statut_courant === "NOUVELLE";
                    const canCancel =
                      isGerant &&
                      !["LIVRE", "RETOUR", "ANNULEE"].includes(
                        order.statut_courant,
                      );
                    const firstItem = (order.items || [])[0];
                    const notYetDue =
                      (isPreparateur || isLivreur) &&
                      !isJourJ(order.date_commande);
                    const dueDateLabel = order.date_commande
                      ? new Date(order.date_commande).toLocaleDateString(
                          "fr-FR",
                          { day: "2-digit", month: "2-digit", year: "numeric" },
                        )
                      : "";
                    return (
                      <TableRow
                        key={order.id}
                        className="cursor-pointer"
                        onClick={() => setDetail(order)}
                      >
                        <TableCell className="align-top font-medium">
                          {order.numero}
                        </TableCell>
                        <TableCell className="align-top">
                          {firstItem?.category_name || "-"}
                        </TableCell>
                        <TableCell className="align-top">
                          {firstItem?.type_name || "-"}
                        </TableCell>
                        <TableCell className="align-top max-w-[280px]">
                          <div className="space-y-1.5">
                            {(order.items || []).map((it: any) => (
                              <div key={it.id} className="leading-tight">
                                <div className="flex items-center justify-between gap-2">
                                  <div className="font-medium text-foreground text-sm leading-tight">
                                    {it.reference_name || "Article"}
                                  </div>
                                  {it.quantite ? (
                                    <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                                      x{it.quantite}
                                    </span>
                                  ) : null}
                                </div>
                                <div className="flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground">
                                  {it.brand_name && (
                                    <span>Marque: {it.brand_name}</span>
                                  )}
                                  {it.couleur && (
                                    <span className="inline-flex items-center rounded-full border border-border bg-background px-1.5 py-0.5 text-[10px] text-foreground">
                                      {it.couleur}
                                    </span>
                                  )}
                                </div>
                              </div>
                            ))}
                          </div>
                        </TableCell>
                        <TableCell className="align-top whitespace-nowrap text-xs text-muted-foreground">
                          {order.date_commande
                            ? new Date(order.date_commande).toLocaleString(
                                "fr-FR",
                                {
                                  day: "2-digit",
                                  month: "2-digit",
                                  hour: "2-digit",
                                  minute: "2-digit",
                                },
                              )
                            : "-"}
                        </TableCell>
                        <TableCell className="align-top">
                          {order.client_nom}
                        </TableCell>
                        {isLivreur && (
                          <TableCell className="align-top max-w-[180px] truncate">
                            {order.adresse_livraison || "-"}
                          </TableCell>
                        )}
                        {isLivreur && (
                          <TableCell className="align-top">
                            <a
                              href={`tel:${order.telephone}`}
                              onClick={(e) => e.stopPropagation()}
                              className="flex items-center gap-1 text-blue-600 hover:underline"
                            >
                              <Phone className="h-3 w-3" /> {order.telephone}
                            </a>
                          </TableCell>
                        )}
                        <TableCell
                          className={
                            isLivreur
                              ? "align-top"
                              : "align-top max-w-[180px] truncate"
                          }
                        >
                          {isLivreur
                            ? zoneOptions
                                .find((z) => z.value === order.livraison_zone)
                                ?.label.split(" (")[0] || order.livraison_zone
                            : order.adresse_livraison ||
                              zoneOptions
                                .find((z) => z.value === order.livraison_zone)
                                ?.label.split(" (")[0] ||
                              order.livraison_zone}
                        </TableCell>
                        <TableCell className="align-top">
                          <Badge
                            className={statutInfo(order.statut_courant).color}
                          >
                            {statutInfo(order.statut_courant).label}
                          </Badge>
                        </TableCell>
                        {!isPreparateur && (
                          <TableCell className="align-top">
                            {fmt(order.total_a_payer)}
                          </TableCell>
                        )}
                        {isGerant && (
                          <TableCell className="align-top text-xs">
                            {!order.preparateur_name && !order.livreur_name ? (
                              <span className="text-muted-foreground">-</span>
                            ) : (
                              <div className="space-y-1.5">
                                {order.preparateur_name && (
                                  <div className="flex items-center gap-1.5 text-muted-foreground">
                                    <UserRound className="h-3.5 w-3.5 shrink-0" />
                                    <div>
                                      <div className="text-foreground">
                                        {order.preparateur_name}
                                      </div>
                                      {fmtDT(preparedAt) && (
                                        <div>{fmtDT(preparedAt)}</div>
                                      )}
                                    </div>
                                  </div>
                                )}
                                {order.livreur_name && (
                                  <div className="flex items-center gap-1.5 text-muted-foreground">
                                    <Truck className="h-3.5 w-3.5 shrink-0" />
                                    <div>
                                      <div className="text-foreground">
                                        {order.livreur_name}
                                      </div>
                                      {fmtDT(livreurAt) && (
                                        <div>
                                          {order.statut_courant === "LIVRE"
                                            ? "Livré le "
                                            : "Prévu le "}
                                          {fmtDT(livreurAt)}
                                        </div>
                                      )}
                                    </div>
                                  </div>
                                )}
                              </div>
                            )}
                          </TableCell>
                        )}
                        <TableCell className="align-top text-right">
                          <div className="flex items-center justify-end gap-1">
                            {isGerant && (
                              <Select
                                onValueChange={(value) => {
                                  const option = gerantActionOptions(
                                    order,
                                  ).find((item) => item.value === value);
                                  if (!option) return;

                                  if (option.kind === "assign") {
                                    setAssignTarget({
                                      order,
                                      role: option.role || "PREPARATEUR",
                                    });
                                    return;
                                  }

                                  setActionNote({
                                    order,
                                    target: option.target,
                                    label: option.label,
                                  });
                                }}
                              >
                                <SelectTrigger className="h-8 w-[170px] text-xs">
                                  <SelectValue placeholder="Action" />
                                </SelectTrigger>
                                <SelectContent>
                                  {gerantActionOptions(order).map((option) => (
                                    <SelectItem
                                      key={option.value}
                                      value={option.value}
                                    >
                                      {option.label}
                                    </SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            )}
                            {!isGerant && action && (
                              <IconAction
                                label={
                                  notYetDue
                                    ? `Disponible le ${dueDateLabel}`
                                    : action.label
                                }
                                icon={action.icon}
                                disabled={notYetDue}
                                showLabel
                                onClick={(e) => {
                                  e.stopPropagation();
                                  if (isGerant && action.assign) {
                                    setAssignTarget({
                                      order,
                                      role:
                                        action.target === "EN_PREPARATION"
                                          ? "PREPARATEUR"
                                          : "LIVREUR",
                                    });
                                  } else {
                                    setActionNote({
                                      order,
                                      target: action.target,
                                      label: action.label,
                                    });
                                  }
                                }}
                              />
                            )}
                            {(isLivreur || isGerant) &&
                              order.statut_courant === "EN_LIVRAISON" &&
                              !isGerant && (
                                <IconAction
                                  label={
                                    notYetDue
                                      ? `Disponible le ${dueDateLabel}`
                                      : "Retour"
                                  }
                                  icon={Undo2}
                                  variant="outline"
                                  className="text-red-600"
                                  disabled={notYetDue}
                                  showLabel
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setActionNote({
                                      order,
                                      target: "RETOUR",
                                      label: "Retour",
                                    });
                                  }}
                                />
                              )}
                            {canEdit && (
                              <IconAction
                                label="Modifier"
                                icon={Pencil}
                                variant="outline"
                                showLabel
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setEditTarget(order);
                                }}
                              />
                            )}
                            {canCancel && (
                              <IconAction
                                label="Annuler la commande"
                                icon={Ban}
                                variant="outline"
                                className="text-red-600"
                                showLabel
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setCancelTarget(order);
                                }}
                              />
                            )}
                            {canDelete && (
                              <IconAction
                                label="Supprimer"
                                icon={Trash2}
                                variant="outline"
                                className="text-red-600"
                                showLabel
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setDeleteTarget(order);
                                }}
                              />
                            )}
                          </div>
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

      {/* Détail commande */}
      <Dialog open={!!detail} onOpenChange={(o) => !o && setDetail(null)}>
        <DialogContent className="max-w-lg">
          {detail && (
            <>
              <DialogHeader>
                <div className="flex items-center justify-between gap-2 pr-6">
                  <DialogTitle>Commande {detail.numero}</DialogTitle>
                  {isGerant &&
                    ["NOUVELLE", "EN_PREPARATION"].includes(
                      detail.statut_courant,
                    ) && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => {
                          setEditTarget(detail);
                          setDetail(null);
                        }}
                      >
                        <Pencil className="h-4 w-4 mr-2" /> Modifier
                      </Button>
                    )}
                </div>
              </DialogHeader>
              <div className="space-y-3 text-sm">
                <div className="mb-2">
                  <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">
                    Information
                  </p>
                </div>

                {detail.items && detail.items.length > 0 && (
                  <div className="space-y-2 rounded-md border bg-muted/10 p-3">
                    <p className="text-muted-foreground text-xs uppercase tracking-[0.2em]">
                      Articles
                    </p>
                    {(detail.items || []).map((it: any) => (
                      <div key={it.id} className="space-y-1">
                        <div className="font-medium text-foreground">
                          {it.reference_name || "Article"}
                          {it.couleur ? ` (${it.couleur})` : ""}
                        </div>
                        <div className="text-xs text-muted-foreground">
                          {[it.type_name, it.category_name, it.brand_name]
                            .filter(Boolean)
                            .join(" • ") || "Sans métadonnées"}
                        </div>
                      </div>
                    ))}
                  </div>
                )}

                <div className="grid gap-2">
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Nom client</span>
                    <span className="text-right">
                      {detail.client_nom || "-"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Numéro client</span>
                    <span className="text-right">
                      {detail.telephone || "-"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">
                      Adresse client
                    </span>
                    <span className="text-right max-w-[55%] break-words">
                      {detail.adresse_livraison || "-"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">
                      Mode de payment
                    </span>
                    <span>
                      {MODE_PAIEMENT.find(
                        (m) => m.value === detail.mode_paiement,
                      )?.label ||
                        detail.mode_paiement ||
                        "-"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Total à payer</span>
                    <span className="font-semibold">
                      {detail.total_a_payer != null
                        ? fmt(detail.total_a_payer)
                        : "-"}
                    </span>
                  </div>
                  {detail.preparateur_name && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Préparateur</span>
                      <span>{detail.preparateur_name}</span>
                    </div>
                  )}
                  {detail.livreur_name && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Livreur</span>
                      <span>{detail.livreur_name}</span>
                    </div>
                  )}
                  {detail.created_at && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">
                        Commande créée le
                      </span>
                      <span>
                        {new Date(detail.created_at).toLocaleString("fr-FR")}
                      </span>
                    </div>
                  )}
                  {detail.date_commande && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">
                        Livraison prévue le
                      </span>
                      <span>
                        {new Date(detail.date_commande).toLocaleString("fr-FR")}
                      </span>
                    </div>
                  )}
                  {detail.status_history && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Livrée le</span>
                      <span>
                        {historyAt(detail, "LIVRE")
                          ? new Date(historyAt(detail, "LIVRE")).toLocaleString(
                              "fr-FR",
                            )
                          : historyAt(detail, "EN_LIVRAISON")
                            ? new Date(
                                historyAt(detail, "EN_LIVRAISON"),
                              ).toLocaleString("fr-FR")
                            : "-"}
                      </span>
                    </div>
                  )}
                </div>

                {detail.note_preparateur && (
                  <div>
                    <span className="text-muted-foreground">
                      Note pour le préparateur
                    </span>
                    <p>{detail.note_preparateur}</p>
                  </div>
                )}
                {detail.note_livreur && (
                  <div>
                    <span className="text-muted-foreground">
                      Note pour le livreur
                    </span>
                    <p>{detail.note_livreur}</p>
                  </div>
                )}

                {detail.status_history && (
                  <>
                    <div className="border-t pt-3">
                      <p className="text-muted-foreground mb-2">Chronologie</p>
                      <OrderTimeline order={detail} />
                    </div>
                    <div>
                      <p className="text-muted-foreground mb-1">
                        Historique détaillé
                      </p>
                      <ul className="space-y-1">
                        {detail.status_history.map((h: any) => (
                          <li
                            key={h.id}
                            className="text-xs text-muted-foreground"
                          >
                            {statutInfo(h.nouveau_statut).label} —{" "}
                            {h.changed_by_name || "Système"} —{" "}
                            {new Date(h.timestamp).toLocaleString("fr-FR")}
                            {h.note && ` (${h.note})`}
                            {h.photo && (
                              <a
                                href={h.photo}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="flex items-center gap-2 mt-1"
                              >
                                <img
                                  src={h.photo}
                                  alt="Photo de préparation"
                                  className="h-16 w-16 object-cover rounded border"
                                />
                                <span className="text-blue-600 underline">
                                  Voir / télécharger la photo
                                </span>
                              </a>
                            )}
                          </li>
                        ))}
                      </ul>
                    </div>
                  </>
                )}
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Confirmation avant toute action de statut (préparateur/livreur) */}
      <Dialog
        open={!!actionNote}
        onOpenChange={(o) => !o && setActionNote(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirmer : {actionNote?.label}</DialogTitle>
            <DialogDescription>
              Commande {actionNote?.order?.numero} — vérifiez le résumé avant de
              confirmer.
            </DialogDescription>
          </DialogHeader>
          {actionNote?.order && (
            <div className="rounded-md border bg-muted/30 p-3 space-y-1.5 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Client</span>
                <span className="font-medium">
                  {actionNote.order.client_nom}
                </span>
              </div>
              {actionNote.order.telephone && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Téléphone</span>
                  <span>{actionNote.order.telephone}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-muted-foreground">Zone</span>
                <span>
                  {zoneOptions
                    .find((z) => z.value === actionNote.order.livraison_zone)
                    ?.label.split(" (")[0] || actionNote.order.livraison_zone}
                </span>
              </div>
              {actionNote.order.adresse_livraison && (
                <div className="flex justify-between gap-4">
                  <span className="text-muted-foreground shrink-0">
                    Adresse
                  </span>
                  <span className="text-right">
                    {actionNote.order.adresse_livraison}
                  </span>
                </div>
              )}
              {actionNote.order.livraison_zone !== "RECUPERATION" && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Paiement</span>
                  <span>
                    {MODE_PAIEMENT.find(
                      (m) => m.value === actionNote.order.mode_paiement,
                    )?.label || actionNote.order.mode_paiement}
                  </span>
                </div>
              )}
              <div className="border-t pt-1.5">
                <span className="text-muted-foreground">Articles</span>
                <ul className="mt-1 space-y-0.5">
                  {(actionNote.order.items || []).map((it: any, i: number) => (
                    <li key={i} className="flex justify-between">
                      <span>
                        {it.reference_name} ({it.couleur})
                      </span>
                      <span>x{it.quantite}</span>
                    </li>
                  ))}
                </ul>
              </div>
              {actionNote.order.total_a_payer != null && (
                <div className="border-t pt-1.5 space-y-0.5">
                  {actionNote.order.livraison_zone !== "RECUPERATION" &&
                    actionNote.order.frais_livraison != null && (
                      <>
                        <div className="flex justify-between">
                          <span className="text-muted-foreground">
                            Prix de vente
                          </span>
                          <span>
                            {fmt(
                              Number(actionNote.order.total_a_payer) -
                                Number(actionNote.order.frais_livraison),
                            )}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-muted-foreground">
                            Frais de livraison
                          </span>
                          <span>{fmt(actionNote.order.frais_livraison)}</span>
                        </div>
                      </>
                    )}
                  <div className="flex justify-between font-medium">
                    <span>Total</span>
                    <span>{fmt(actionNote.order.total_a_payer)}</span>
                  </div>
                </div>
              )}
            </div>
          )}
          <NoteForm
            showPhoto={actionNote?.target === "PRETE"}
            onCancel={() => setActionNote(null)}
            onSubmit={(note, photo) =>
              actionNote &&
              doChangeStatus(
                actionNote.order,
                actionNote.target,
                note,
                undefined,
                photo,
              )
            }
          />
        </DialogContent>
      </Dialog>

      {/* Annulation commande (gérant) — restitue le stock si déjà déduit */}
      <Dialog
        open={!!cancelTarget}
        onOpenChange={(o) => !o && setCancelTarget(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Annuler la commande {cancelTarget?.numero} ?
            </DialogTitle>
            <DialogDescription>
              La commande de {cancelTarget?.client_nom} sera annulée.
              {cancelTarget &&
                ["EN_PREPARATION", "PRETE", "EN_LIVRAISON"].includes(
                  cancelTarget.statut_courant,
                ) && (
                  <>
                    {" "}
                    Le stock déjà déduit pour cette commande sera
                    automatiquement restitué.
                  </>
                )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCancelTarget(null)}>
              Retour
            </Button>
            <Button
              variant="destructive"
              onClick={handleCancelOrder}
              disabled={cancelling}
            >
              {cancelling ? "Annulation..." : "Annuler la commande"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {(isGerant || isPreparateur) && (
        <CreateOrderDialog
          open={createOpen}
          onOpenChange={setCreateOpen}
          onCreated={() => {
            setCreateOpen(false);
            fetchOrders();
          }}
        />
      )}

      {isGerant && (
        <AssignStaffDialog
          target={assignTarget}
          onOpenChange={(o) => !o && setAssignTarget(null)}
          onAssign={(userId, assignedAt) =>
            assignTarget &&
            doChangeStatus(
              assignTarget.order,
              assignTarget.role === "PREPARATEUR"
                ? "EN_PREPARATION"
                : "EN_LIVRAISON",
              undefined,
              {
                ...(assignTarget.role === "PREPARATEUR"
                  ? { preparateur_id: userId }
                  : { livreur_id: userId }),
                assigned_at: assignedAt,
              },
            )
          }
        />
      )}

      {isGerant && (
        <EditOrderDialog
          order={editTarget}
          onOpenChange={(o) => !o && setEditTarget(null)}
          onSaved={() => {
            setEditTarget(null);
            fetchOrders(true);
          }}
        />
      )}

      <Dialog
        open={!!deleteTarget}
        onOpenChange={(o) => !o && setDeleteTarget(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Supprimer la commande {deleteTarget?.numero} ?
            </DialogTitle>
            <DialogDescription>
              Cette action est définitive — la commande de{" "}
              {deleteTarget?.client_nom} sera supprimée.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              Annuler
            </Button>
            <Button
              variant="destructive"
              onClick={handleDeleteOrder}
              disabled={deleting}
            >
              {deleting ? "Suppression..." : "Supprimer"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

// Résumé "Prête le / En livraison depuis le / Livrée le" — une ligne par
// statut effectivement atteint, dérivée de l'historique complet, pour une
// lecture immédiate sans avoir à parcourir la liste détaillée en dessous.
const TIMELINE_MILESTONES: { status: string; icon: any; label: string }[] = [
  { status: "EN_PREPARATION", icon: Wrench, label: "Préparation commencée le" },
  { status: "PRETE", icon: Boxes, label: "Prête le" },
  { status: "EN_LIVRAISON", icon: Truck, label: "En livraison depuis le" },
  { status: "LIVRE", icon: CheckCircle2, label: "Livrée le" },
  { status: "RETOUR", icon: Undo2, label: "Retour le" },
];

function OrderTimeline({ order }: { order: any }) {
  const timestamps = new Map<string, string>();
  for (const h of order.status_history || []) {
    if (!timestamps.has(h.nouveau_statut))
      timestamps.set(h.nouveau_statut, h.timestamp);
  }

  const rows = [
    {
      icon: ShoppingCart,
      label: "Commande créée le",
      date: order.date_commande,
      reached: true,
    },
    ...TIMELINE_MILESTONES.map((m) => ({
      icon: m.icon,
      label: m.label,
      date: timestamps.get(m.status),
      reached: timestamps.has(m.status),
    })),
  ].filter((r) => r.reached);

  return (
    <ul className="space-y-2">
      {rows.map((r) => (
        <li key={r.label} className="flex items-center gap-2 text-sm">
          <r.icon className="h-4 w-4 text-primary shrink-0" />
          <span className="text-muted-foreground">{r.label}</span>
          <span className="font-semibold">
            {r.date ? new Date(r.date).toLocaleString("fr-FR") : "—"}
          </span>
        </li>
      ))}
    </ul>
  );
}

function NoteForm({
  onSubmit,
  onCancel,
  showPhoto = false,
}: {
  onSubmit: (note: string, photo?: File) => void;
  onCancel?: () => void;
  // Preuve que la préparation est faite — proposé uniquement au passage
  // "Prête" (préparateur/gérant), voir OrderStatusHistory.photo.
  showPhoto?: boolean;
}) {
  const [note, setNote] = useState("");
  const [photo, setPhoto] = useState<File | undefined>(undefined);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);

  return (
    <div className="space-y-4">
      <Textarea
        placeholder="Note (optionnel)"
        value={note}
        onChange={(e) => setNote(e.target.value)}
      />
      {showPhoto && (
        <div className="space-y-2">
          <Label className="flex items-center gap-1.5 text-sm">
            <Camera className="h-4 w-4" /> Photo de la préparation (optionnel)
          </Label>
          <Input
            type="file"
            accept="image/*"
            onChange={(e) => {
              const file = e.target.files?.[0];
              setPhoto(file);
              setPhotoPreview(file ? URL.createObjectURL(file) : null);
            }}
          />
          {photoPreview && (
            <img
              src={photoPreview}
              alt="Aperçu"
              className="h-20 w-20 object-cover rounded border"
            />
          )}
        </div>
      )}
      <DialogFooter>
        {onCancel && (
          <Button variant="outline" onClick={onCancel}>
            Annuler
          </Button>
        )}
        <Button onClick={() => onSubmit(note, photo)}>Confirmer</Button>
      </DialogFooter>
    </div>
  );
}

// Le gérant désigne un préparateur/livreur — seuls ceux libres (pas déjà en
// charge d'une autre commande) sont sélectionnables.
function AssignStaffDialog({
  target,
  onOpenChange,
  onAssign,
}: {
  target: { order: any; role: "PREPARATEUR" | "LIVREUR" } | null;
  onOpenChange: (o: boolean) => void;
  onAssign: (userId: number, assignedAt?: string) => void;
}) {
  const [staff, setStaff] = useState<
    { id: number; full_name: string; available: boolean }[]
  >([]);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<string>("");
  const [assignedAt, setAssignedAt] = useState("");

  useEffect(() => {
    if (!target) return;
    setSelected("");
    setAssignedAt(toDatetimeLocalValue(new Date()));
    setLoading(true);
    djangoClient.orders
      .availableStaff(target.role, target.order.magasin)
      .then(setStaff)
      .catch(() => setStaff([]))
      .finally(() => setLoading(false));
  }, [target]);

  const roleLabel = target?.role === "PREPARATEUR" ? "préparateur" : "livreur";

  return (
    <Dialog open={!!target} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Assigner un {roleLabel}</DialogTitle>
          <DialogDescription>
            Commande {target?.order?.numero} — choisissez manuellement qui prend
            cette commande en charge.
          </DialogDescription>
        </DialogHeader>
        {loading ? (
          <Skeleton className="h-10 w-full" />
        ) : staff.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-6">
            Aucun {roleLabel} enregistré pour ce magasin.
          </p>
        ) : (
          <div className="space-y-3">
            <Select value={selected} onValueChange={setSelected}>
              <SelectTrigger>
                <SelectValue placeholder={`Choisir un ${roleLabel}`} />
              </SelectTrigger>
              <SelectContent>
                {staff.map((s) => (
                  <SelectItem key={s.id} value={String(s.id)}>
                    {s.full_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="space-y-1">
              <Label>Date et heure</Label>
              <Input
                type="datetime-local"
                value={assignedAt}
                onChange={(e) => setAssignedAt(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Vide = maintenant.
              </p>
            </div>
          </div>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annuler
          </Button>
          <Button
            disabled={!selected}
            onClick={() =>
              onAssign(
                Number(selected),
                assignedAt ? new Date(assignedAt).toISOString() : undefined,
              )
            }
          >
            Assigner
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// Modification d'une commande "Nouvelle" (client, téléphone, date, zone,
// adresse, paiement, note, articles) — réservée au gérant (voir
// orders/views.py::partial_update) : rien n'est encore préparé/déduit du
// stock à ce stade, donc les articles restent librement modifiables.
function EditOrderDialog({
  order,
  onOpenChange,
  onSaved,
}: {
  order: any | null;
  onOpenChange: (o: boolean) => void;
  onSaved: () => void;
}) {
  const { zones } = useDeliveryZones();
  const zoneOptions = useMemo(() => buildZoneOptions(zones), [zones]);
  const [clientNom, setClientNom] = useState("");
  const [telephone, setTelephone] = useState("");
  const [zone, setZone] = useState("");
  const [adresseLivraison, setAdresseLivraison] = useState("");
  const [modePaiement, setModePaiement] = useState("LIVRAISON");
  const [dateCommande, setDateCommande] = useState("");
  const [notePreparateur, setNotePreparateur] = useState("");
  const [noteLivreur, setNoteLivreur] = useState("");
  const [items, setItems] = useState<CartItem[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [preparateurId, setPreparateurId] = useState("");
  const [preparateurs, setPreparateurs] = useState<
    { id: number; full_name: string; available: boolean }[]
  >([]);
  const [livreurId, setLivreurId] = useState("");
  const [livreurs, setLivreurs] = useState<
    { id: number; full_name: string; available: boolean }[]
  >([]);

  useEffect(() => {
    if (!order) return;
    setClientNom(order.client_nom || "");
    setTelephone(order.telephone || "");
    setZone(order.livraison_zone || "");
    setAdresseLivraison(order.adresse_livraison || "");
    setModePaiement(order.mode_paiement || "LIVRAISON");
    setDateCommande(
      order.date_commande
        ? toDatetimeLocalValue(new Date(order.date_commande))
        : "",
    );
    setNotePreparateur(order.note_preparateur || "");
    setNoteLivreur(order.note_livreur || "");
    setPreparateurId(order.preparateur ? String(order.preparateur) : "");
    djangoClient.orders
      .availableStaff("PREPARATEUR", order.magasin)
      .then(setPreparateurs)
      .catch(() => setPreparateurs([]));
    setLivreurId(order.livreur ? String(order.livreur) : "");
    djangoClient.orders
      .availableStaff(
        "LIVREUR",
        order.magasin,
        order.date_commande || undefined,
      )
      .then(setLivreurs)
      .catch(() => setLivreurs([]));
    setItems(
      (order.items || []).map((it: any) => ({
        key: `existing-${it.id}`,
        type_id: 0,
        type_name: "",
        reference_id: 0,
        reference_label: it.reference_name,
        prix_vente: Number(it.prix_unitaire),
        variant_id: it.product_variant,
        couleur: it.couleur,
        stock_actuel: Infinity,
        quantite: it.quantite,
      })),
    );
  }, [order]);

  const submit = async () => {
    if (!order) return;
    if (!clientNom.trim()) {
      toast.error("Nom du client requis");
      return;
    }
    if (!/^\+261\d{9}$/.test(telephone)) {
      toast.error("Téléphone au format +261XXXXXXXXX");
      return;
    }
    if (items.length === 0) {
      toast.error("Ajoutez au moins un article");
      return;
    }
    setSubmitting(true);
    try {
      await djangoClient.orders.update(order.id, {
        client_nom: clientNom.trim(),
        telephone,
        livraison_zone: zone as any,
        adresse_livraison:
          zone === "RECUPERATION" ? "" : adresseLivraison.trim(),
        mode_paiement: modePaiement as any,
        ...(dateCommande
          ? { date_commande: new Date(dateCommande).toISOString() }
          : {}),
        note_preparateur: notePreparateur,
        note_livreur: zone === "RECUPERATION" ? "" : noteLivreur,
        items: items.map((it) => ({
          product_variant: it.variant_id,
          quantite: it.quantite,
        })),
      });
      // Pré-assignation du préparateur/livreur — endpoints indépendants du
      // statut, comme à la création (voir orders/services.py::
      // assign_preparateur_early/assign_livreur_early). Rien à envoyer si
      // rien n'a changé.
      if (preparateurId && Number(preparateurId) !== order.preparateur) {
        try {
          await djangoClient.orders.assignPreparateur(
            order.id,
            Number(preparateurId),
          );
        } catch (assignErr: any) {
          toast.error(
            `Commande mise à jour, mais l'assignation du préparateur a échoué : ${assignErr.message || "erreur inconnue"}`,
          );
        }
      }
      if (
        zone !== "RECUPERATION" &&
        livreurId &&
        Number(livreurId) !== order.livreur
      ) {
        try {
          await djangoClient.orders.assignLivreur(order.id, Number(livreurId));
        } catch (assignErr: any) {
          toast.error(
            `Commande mise à jour, mais l'assignation du livreur a échoué : ${assignErr.message || "erreur inconnue"}`,
          );
        }
      }
      toast.success("Commande mise à jour");
      onSaved();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la modification");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={!!order} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Modifier la commande {order?.numero}</DialogTitle>
          <DialogDescription>
            Possible tant que la commande n'est pas encore "Prête".
          </DialogDescription>
        </DialogHeader>

        <OrderItemsEditor items={items} setItems={setItems} showPrices />

        <div className="space-y-2">
          <Label>Type de commande</Label>
          <div className="flex gap-2">
            <Button
              type="button"
              variant={zone !== "RECUPERATION" ? "default" : "outline"}
              className="flex-1"
              onClick={() =>
                setZone(
                  zoneOptions.find((z) => z.value !== "RECUPERATION")?.value ||
                    "",
                )
              }
            >
              <Truck className="h-4 w-4 mr-2" /> À livrer
            </Button>
            <Button
              type="button"
              variant={zone === "RECUPERATION" ? "default" : "outline"}
              className="flex-1"
              onClick={() => setZone("RECUPERATION")}
            >
              <Package className="h-4 w-4 mr-2" /> Récupération sur place
            </Button>
          </div>
        </div>

        <div className="space-y-2">
          <Label>Date et heure de livraison</Label>
          <Input
            type="datetime-local"
            value={dateCommande}
            onChange={(e) => setDateCommande(e.target.value)}
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label>Nom client</Label>
            <Input
              value={clientNom}
              onChange={(e) => setClientNom(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Téléphone</Label>
            <Input
              value={telephone}
              onChange={(e) => setTelephone(e.target.value)}
            />
          </div>
        </div>

        {zone !== "RECUPERATION" && (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Zone de livraison</Label>
              <Select value={zone} onValueChange={setZone}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {zoneOptions
                    .filter((z) => z.value !== "RECUPERATION")
                    .map((z) => (
                      <SelectItem key={z.value} value={z.value}>
                        {z.label}
                      </SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Adresse de livraison</Label>
              <Input
                value={adresseLivraison}
                onChange={(e) => setAdresseLivraison(e.target.value)}
              />
            </div>
          </div>
        )}

        {zone !== "RECUPERATION" && (
          <div className="space-y-2">
            <Label>Paiement</Label>
            <Select value={modePaiement} onValueChange={setModePaiement}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {MODE_PAIEMENT.map((m) => (
                  <SelectItem key={m.value} value={m.value}>
                    {m.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="space-y-2">
            <Label>Préparateur</Label>
            <Select value={preparateurId} onValueChange={setPreparateurId}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Non assigné" />
              </SelectTrigger>
              <SelectContent>
                {preparateurs.map((p) => (
                  <SelectItem key={p.id} value={String(p.id)}>
                    {p.full_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {zone !== "RECUPERATION" && (
            <div className="space-y-2">
              <Label>Livreur</Label>
              <Select value={livreurId} onValueChange={setLivreurId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Non assigné" />
                </SelectTrigger>
                <SelectContent>
                  {livreurs.map((l) => (
                    <SelectItem key={l.id} value={String(l.id)}>
                      {l.full_name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>

        <div className="space-y-2">
          <Label>Note pour le préparateur (optionnel)</Label>
          <Textarea
            value={notePreparateur}
            onChange={(e) => setNotePreparateur(e.target.value)}
          />
        </div>

        {zone !== "RECUPERATION" && (
          <div className="space-y-2">
            <Label>Note pour le livreur (optionnel)</Label>
            <Textarea
              value={noteLivreur}
              onChange={(e) => setNoteLivreur(e.target.value)}
            />
          </div>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Enregistrement..." : "Enregistrer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// Format un Date en valeur locale pour <input type="datetime-local"> (pas d'UTC).
function toDatetimeLocalValue(d: Date) {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// Sélecteur d'articles (recherche catalogue + panier) — partagé entre
// CreateOrderDialog et EditOrderDialog (le gérant peut aussi modifier les
// articles d'une commande "Nouvelle", voir orders/views.py::partial_update).
function OrderItemsEditor({
  items,
  setItems,
  showPrices,
}: {
  items: CartItem[];
  setItems: React.Dispatch<React.SetStateAction<CartItem[]>>;
  showPrices: boolean;
}) {
  // Filtres Catégorie → Sous-type + Marque, combinés à la recherche texte
  // (§6 du cahier des charges : "Type produit" filtre "Marque", recherche
  // autocomplete dans le catalogue).
  const [categories, setCategories] = useState<any[]>([]);
  const [types, setTypes] = useState<any[]>([]);
  const [brands, setBrands] = useState<any[]>([]);
  const [categoryId, setCategoryId] = useState<number | null>(null);
  const [typeId, setTypeId] = useState<number | null>(null);
  const [brandId, setBrandId] = useState<number | null>(null);
  const [query, setQuery] = useState("");
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);
  const [selectedRef, setSelectedRef] = useState<any | null>(null);
  const [variantId, setVariantId] = useState<number | null>(null);
  const [quantite, setQuantite] = useState("");

  useEffect(() => {
    djangoClient.catalog.categories
      .list()
      .then(setCategories)
      .catch(() => {});
    djangoClient.catalog.types
      .list()
      .then(setTypes)
      .catch(() => {});
    djangoClient.catalog.brands
      .list()
      .then(setBrands)
      .catch(() => {});
  }, []);

  const typesForCategory = categoryId
    ? types.filter((t) => t.category === categoryId)
    : types;

  // La recherche se déclenche dès qu'un filtre est choisi (même sans texte),
  // pour afficher directement les éléments correspondant à la sélection.
  useEffect(() => {
    if (!query && !typeId && !brandId && !categoryId) {
      setSuggestions([]);
      return;
    }
    setSearching(true);
    const t = setTimeout(() => {
      djangoClient.catalog.references
        .autocomplete(query, {
          type: typeId ?? undefined,
          brand: brandId ?? undefined,
          category: categoryId ?? undefined,
        })
        .then(setSuggestions)
        .catch(() => setSuggestions([]))
        .finally(() => setSearching(false));
    }, 250);
    return () => clearTimeout(t);
  }, [query, typeId, brandId, categoryId]);

  const addItem = () => {
    if (!selectedRef || !variantId) {
      toast.error("Sélectionnez une référence et une couleur");
      return;
    }
    const variant = selectedRef.couleurs.find(
      (c: any) => c.variant_id === variantId,
    );
    if (!variant) return;
    const qty = Number(quantite);
    if (!qty || qty < 1) {
      toast.error("Quantité invalide");
      return;
    }
    if (qty > variant.stock_actuel) {
      toast.error(`Stock insuffisant (disponible: ${variant.stock_actuel})`);
      return;
    }
    setItems((prev) => [
      ...prev,
      {
        key: `${variantId}-${Date.now()}`,
        type_id: selectedRef.type,
        type_name: selectedRef.type_name,
        reference_id: selectedRef.id,
        reference_label: `${selectedRef.brand_name} ${selectedRef.reference_name}`,
        prix_vente: Number(selectedRef.prix_vente),
        variant_id: variantId,
        couleur: variant.couleur,
        stock_actuel: variant.stock_actuel,
        quantite: qty,
      },
    ]);
    setQuery("");
    setSuggestions([]);
    setSelectedRef(null);
    setVariantId(null);
    setQuantite("");
  };

  return (
    <div className="space-y-3">
      <div className="border rounded-lg p-4 space-y-3 bg-muted/30">
        <p className="text-sm font-medium">Ajouter un article</p>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <Select
            value={categoryId ? String(categoryId) : ""}
            onValueChange={(v) => {
              setCategoryId(Number(v));
              setTypeId(null);
            }}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Catégorie" />
            </SelectTrigger>
            <SelectContent>
              {categories.map((c) => (
                <SelectItem key={c.id} value={String(c.id)}>
                  {c.nom}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select
            value={typeId ? String(typeId) : ""}
            onValueChange={(v) => setTypeId(Number(v))}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Sous-type" />
            </SelectTrigger>
            <SelectContent>
              {typesForCategory.map((t) => (
                <SelectItem key={t.id} value={String(t.id)}>
                  {t.nom}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select
            value={brandId ? String(brandId) : ""}
            onValueChange={(v) => setBrandId(Number(v))}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Marque" />
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

        {(categoryId || typeId || brandId) && (
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-xs text-muted-foreground">Filtres :</span>
            {categoryId && (
              <Badge variant="secondary" className="gap-1">
                {categories.find((c) => c.id === categoryId)?.nom}
                <button
                  type="button"
                  onClick={() => {
                    setCategoryId(null);
                    setTypeId(null);
                  }}
                >
                  ×
                </button>
              </Badge>
            )}
            {typeId && (
              <Badge variant="secondary" className="gap-1">
                {types.find((t) => t.id === typeId)?.nom}
                <button type="button" onClick={() => setTypeId(null)}>
                  ×
                </button>
              </Badge>
            )}
            {brandId && (
              <Badge variant="secondary" className="gap-1">
                {brands.find((b) => b.id === brandId)?.nom}
                <button type="button" onClick={() => setBrandId(null)}>
                  ×
                </button>
              </Badge>
            )}
          </div>
        )}

        <div className="relative">
          <Input
            placeholder="Rechercher une référence (ex: A15)"
            value={
              selectedRef
                ? `${selectedRef.brand_name} ${selectedRef.reference_name}`
                : query
            }
            onChange={(e) => {
              setQuery(e.target.value);
              setSelectedRef(null);
              setVariantId(null);
            }}
          />
          {!selectedRef && (query || typeId || brandId || categoryId) && (
            <div className="absolute z-10 mt-1 w-full bg-background border rounded-md shadow-md max-h-56 overflow-y-auto">
              {searching ? (
                <p className="px-3 py-2 text-sm text-muted-foreground">
                  Recherche…
                </p>
              ) : suggestions.length === 0 ? (
                <p className="px-3 py-2 text-sm text-muted-foreground">
                  Aucun résultat pour cette sélection.
                </p>
              ) : (
                suggestions.map((s) => (
                  <button
                    type="button"
                    key={s.id}
                    className="w-full text-left px-3 py-2 text-sm hover:bg-muted flex justify-between"
                    onClick={() => {
                      setSelectedRef(s);
                      setQuery("");
                      setSuggestions([]);
                    }}
                  >
                    <span>
                      {s.brand_name} {s.reference_name}{" "}
                      <span className="text-muted-foreground">
                        ({s.type_name})
                      </span>
                    </span>
                    {showPrices && <span>{fmt(s.prix_vente)}</span>}
                  </button>
                ))
              )}
            </div>
          )}
        </div>

        {selectedRef && (
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 items-end">
            <div className="space-y-1">
              <Label>Couleur</Label>
              <Select
                value={variantId ? String(variantId) : ""}
                onValueChange={(v) => setVariantId(Number(v))}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Couleur" />
                </SelectTrigger>
                <SelectContent>
                  {selectedRef.couleurs.map((c: any) => (
                    <SelectItem
                      key={c.variant_id}
                      value={String(c.variant_id)}
                      disabled={c.stock_actuel <= 0}
                    >
                      {c.couleur} (stock: {c.stock_actuel})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Quantité</Label>
              <Input
                type="number"
                min={1}
                placeholder="Ex: 1"
                value={quantite}
                onChange={(e) => setQuantite(e.target.value)}
              />
            </div>
            {showPrices && (
              <div className="space-y-1">
                <Label>Prix (Ar)</Label>
                <Input value={fmt(selectedRef.prix_vente)} readOnly disabled />
              </div>
            )}
            <Button
              type="button"
              className="sm:col-span-3"
              variant="secondary"
              onClick={addItem}
            >
              <Plus className="h-4 w-4 mr-2" /> Ajouter à la commande
            </Button>
          </div>
        )}
      </div>

      {items.length > 0 && (
        <div className="space-y-2">
          {items.map((it, idx) => (
            <div
              key={it.key}
              className="flex items-center justify-between text-sm border rounded-md px-3 py-2"
            >
              <span>
                {it.reference_label} ({it.couleur}) x{it.quantite}
              </span>
              <div className="flex items-center gap-3">
                {showPrices && <span>{fmt(it.prix_vente * it.quantite)}</span>}
                <Button
                  size="icon"
                  variant="ghost"
                  onClick={() =>
                    setItems((prev) => prev.filter((_, i) => i !== idx))
                  }
                >
                  <Trash2 className="h-4 w-4 text-red-500" />
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function CreateOrderDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  onCreated: () => void;
}) {
  const { isPreparateur } = useCurrentUser();
  const { zones } = useDeliveryZones();
  const zoneOptions = useMemo(() => buildZoneOptions(zones), [zones]);
  // Le préparateur ne crée que des retraits sur place, et ne voit aucune
  // donnée financière (§4/§7.2 du cahier des charges — même règle que pour
  // la consultation des commandes).
  const showPrices = !isPreparateur;
  const [clientNom, setClientNom] = useState("");
  const [telephone, setTelephone] = useState("+261");
  const [zone, setZone] = useState("");
  const [adresseLivraison, setAdresseLivraison] = useState("");
  const [modePaiement, setModePaiement] = useState("LIVRAISON");
  const [dateCommande, setDateCommande] = useState("");
  const [notePreparateur, setNotePreparateur] = useState("");
  const [noteLivreur, setNoteLivreur] = useState("");
  const [items, setItems] = useState<CartItem[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [preparateurId, setPreparateurId] = useState("");
  const [livreurId, setLivreurId] = useState("");
  const [preparateurs, setPreparateurs] = useState<
    { id: number; full_name: string; available: boolean }[]
  >([]);
  const [livreurs, setLivreurs] = useState<
    { id: number; full_name: string; available: boolean }[]
  >([]);

  useEffect(() => {
    if (!open) return;
    if (!isPreparateur) {
      djangoClient.orders
        .availableStaff("PREPARATEUR")
        .then(setPreparateurs)
        .catch(() => setPreparateurs([]));
    }
    setClientNom("");
    setTelephone("+261");
    setZone(isPreparateur ? "RECUPERATION" : "");
    setAdresseLivraison("");
    setModePaiement("LIVRAISON");
    setDateCommande(toDatetimeLocalValue(new Date()));
    setNotePreparateur("");
    setNoteLivreur("");
    setItems([]);
    setPreparateurId("");
    setLivreurId("");
  }, [open, isPreparateur]);

  // Sélectionne la première zone payante disponible dès qu'elle est chargée
  // (les zones sont fetchées de façon async — voir useDeliveryZones) ; sans
  // effet pour le préparateur, dont la zone reste toujours "RECUPERATION".
  useEffect(() => {
    if (!open || isPreparateur || zone) return;
    const first = zoneOptions.find((z) => z.value !== "RECUPERATION");
    if (first) setZone(first.value);
  }, [open, isPreparateur, zone, zoneOptions]);

  // Reinterrogé à chaque changement de date/heure : le livreur peut être
  // pré-assigné dès la création (voir submit()), donc "disponible" reflète
  // aussi un éventuel conflit d'horaire avec une autre commande déjà
  // (pré-)assignée à ce livreur le même jour/heure — purement indicatif,
  // n'empêche pas la sélection (voir orders/views.py::available_staff).
  useEffect(() => {
    if (!open || isPreparateur) return;
    const iso = dateCommande ? new Date(dateCommande).toISOString() : undefined;
    djangoClient.orders
      .availableStaff("LIVREUR", undefined, iso)
      .then(setLivreurs)
      .catch(() => setLivreurs([]));
  }, [open, isPreparateur, dateCommande]);

  const zoneInfo = zoneOptions.find((z) => z.value === zone) ?? { frais: 0 };
  const itemsTotal = items.reduce(
    (s, it) => s + it.prix_vente * it.quantite,
    0,
  );
  const total = itemsTotal + zoneInfo.frais;

  const submit = async () => {
    if (!clientNom.trim()) {
      toast.error("Nom du client requis");
      return;
    }
    if (!/^\+261\d{9}$/.test(telephone)) {
      toast.error("Téléphone au format +261XXXXXXXXX");
      return;
    }
    if (items.length === 0) {
      toast.error("Ajoutez au moins un article");
      return;
    }
    setSubmitting(true);
    try {
      const order = await djangoClient.orders.create({
        client_nom: clientNom.trim(),
        telephone,
        livraison_zone: zone as any,
        adresse_livraison: adresseLivraison.trim(),
        mode_paiement: modePaiement as any,
        // Champ vidé par l'utilisateur -> pas envoyé -> le serveur prend "maintenant" (heure précise).
        ...(dateCommande
          ? { date_commande: new Date(dateCommande).toISOString() }
          : {}),
        note_preparateur: notePreparateur,
        note_livreur: zone === "RECUPERATION" ? "" : noteLivreur,
        items: items.map((it) => ({
          product_variant: it.variant_id,
          quantite: it.quantite,
        })),
      });
      let assignmentFailed = false;
      // Pré-assignation du préparateur — indépendante du statut : la
      // commande reste "Nouvelle" (en attente) jusqu'à ce que ce
      // préparateur clique lui-même "Commencer la préparation" (§ demande —
      // voir orders/services.py::assign_preparateur_early).
      if (preparateurId) {
        try {
          await djangoClient.orders.assignPreparateur(
            order.id,
            Number(preparateurId),
          );
        } catch (assignErr: any) {
          assignmentFailed = true;
          toast.error(
            `Commande créée, mais l'assignation du préparateur a échoué : ${assignErr.message || "erreur inconnue"} ` +
              "(à assigner depuis le tableau).",
          );
        }
      }
      // Pré-assignation du livreur — indépendante du statut, réutilisée
      // automatiquement au passage "En livraison" une fois la commande
      // Prête (voir orders/services.py::assign_livreur_early).
      if (livreurId) {
        try {
          await djangoClient.orders.assignLivreur(order.id, Number(livreurId));
        } catch (assignErr: any) {
          assignmentFailed = true;
          toast.error(
            `Commande créée, mais l'assignation du livreur a échoué : ${assignErr.message || "erreur inconnue"} ` +
              "(à assigner depuis le tableau).",
          );
        }
      }
      if (!assignmentFailed) {
        toast.success(
          preparateurId || livreurId
            ? "Commande créée et assignée"
            : "Commande créée",
        );
      }
      onCreated();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la création");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Nouvelle commande</DialogTitle>
          <DialogDescription>
            Vente Facebook ou sur place — §6 du cahier des charges.
          </DialogDescription>
        </DialogHeader>

        <OrderItemsEditor
          items={items}
          setItems={setItems}
          showPrices={showPrices}
        />

        {isPreparateur ? (
          <p className="text-xs text-muted-foreground -mt-2">
            Retrait sur place uniquement — la commande apparaîtra dans
            "Récupérations" une fois prête, à valider comme livrée au comptoir
            par le gérant.
          </p>
        ) : (
          <div className="space-y-2">
            <Label>Type de commande</Label>
            <div className="flex gap-2">
              <Button
                type="button"
                variant={zone !== "RECUPERATION" ? "default" : "outline"}
                className="flex-1"
                onClick={() =>
                  setZone(
                    zoneOptions.find((z) => z.value !== "RECUPERATION")
                      ?.value || "",
                  )
                }
              >
                <Truck className="h-4 w-4 mr-2" /> À livrer
              </Button>
              <Button
                type="button"
                variant={zone === "RECUPERATION" ? "default" : "outline"}
                className="flex-1"
                onClick={() => setZone("RECUPERATION")}
              >
                <Package className="h-4 w-4 mr-2" /> Récupération sur place
              </Button>
            </div>
          </div>
        )}
        <div className="space-y-2">
          <Label>Date et heure de livraison</Label>
          <Input
            type="datetime-local"
            value={dateCommande}
            onChange={(e) => setDateCommande(e.target.value)}
          />
          <p className="text-xs text-muted-foreground">Vide = maintenant.</p>
        </div>
        {!isPreparateur && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Préparateur</Label>
              <Select value={preparateurId} onValueChange={setPreparateurId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Assigner plus tard" />
                </SelectTrigger>
                <SelectContent>
                  {preparateurs.map((p) => (
                    <SelectItem key={p.id} value={String(p.id)}>
                      {p.full_name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Livreur</Label>
              <Select value={livreurId} onValueChange={setLivreurId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Assigner plus tard" />
                </SelectTrigger>
                <SelectContent>
                  {livreurs.map((p) => (
                    <SelectItem key={p.id} value={String(p.id)}>
                      {p.full_name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
        )}
        {zone !== "RECUPERATION" && (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Zone de livraison</Label>
              <Select value={zone} onValueChange={setZone}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {zoneOptions
                    .filter((z) => z.value !== "RECUPERATION")
                    .map((z) => (
                      <SelectItem key={z.value} value={z.value}>
                        {z.label}
                      </SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Adresse de livraison</Label>
              <Input
                value={adresseLivraison}
                onChange={(e) => setAdresseLivraison(e.target.value)}
                placeholder="Ex: Lot II M 45 Antanimena, Antananarivo"
              />
            </div>
          </div>
        )}

        {zone !== "RECUPERATION" && (
          <div className="space-y-2">
            <Label>Paiement</Label>
            <Select value={modePaiement} onValueChange={setModePaiement}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {MODE_PAIEMENT.map((m) => (
                  <SelectItem key={m.value} value={m.value}>
                    {m.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label>Nom client</Label>
            <Input
              value={clientNom}
              onChange={(e) => setClientNom(e.target.value)}
              placeholder="Rakoto Jean"
            />
          </div>
          <div className="space-y-2">
            <Label>Téléphone</Label>
            <Input
              value={telephone}
              onChange={(e) => setTelephone(e.target.value)}
              placeholder="+261340000000"
            />
          </div>
        </div>

        {/* informations du client  */}

        <div className="space-y-2">
          <Label>
            {isPreparateur
              ? "Note (optionnel)"
              : "Note pour le préparateur (optionnel)"}
          </Label>
          <Textarea
            value={notePreparateur}
            onChange={(e) => setNotePreparateur(e.target.value)}
          />
        </div>
        {!isPreparateur && zone !== "RECUPERATION" && (
          <div className="space-y-2">
            <Label>Note pour le livreur (optionnel)</Label>
            <Textarea
              value={noteLivreur}
              onChange={(e) => setNoteLivreur(e.target.value)}
            />
          </div>
        )}
        {showPrices && (
          <>
            <div className="flex justify-between items-center border-t pt-3 text-sm">
              <span>Frais de livraison</span>
              <span>{fmt(zoneInfo.frais)}</span>
            </div>
            <div className="flex justify-between items-center font-semibold">
              <span>Total à payer</span>
              <span>{fmt(total)}</span>
            </div>
          </>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Création…" : "Créer la commande"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
