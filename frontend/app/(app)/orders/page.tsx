"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { djangoClient } from "@/lib/django-client";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { useRealtimeRefresh } from "@/lib/hooks/useRealtimeRefresh";
import { useDeliveryZones } from "@/lib/hooks/useDeliveryZones";
import { DateTimeInput } from "@/components/ui/datetime-input";
import {
  CreateOrderDialog,
  OrderItemsEditor,
  buildZoneOptions,
  fmt,
  MODE_PAIEMENT,
  type CartItem,
} from "@/components/orders/create-order-dialog";
import {
  APP_TIME_ZONE,
  appDayKey,
  appToday,
  appDatetimeLocalValue,
  appDatetimeLocalToIso,
  actionOuverte,
  affichageOuvert,
  fmtOuverture,
  dernierJourOuvert,
  type RoleCommande,
  fmtAppDate,
  fmtAppDateTime,
} from "@/lib/timezone";
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
  MessageCircle,
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
  CalendarClock,
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

// Tous les horodatages sont affichés à l'heure d'Antananarivo (fuseau du
// magasin), quel que soit le réglage de l'appareil — cohérent avec la règle
// du jour J et avec le serveur.
const fmtDT = (iso?: string | null) =>
  iso
    ? new Date(iso).toLocaleString("fr-FR", {
        timeZone: APP_TIME_ZONE,
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

/**
 * Mot à retaper avant de confirmer une transition (§ demande).
 *
 * « Livré » et « Retour » ferment la commande : elles sont irréversibles
 * dans le workflow normal — seul le gérant peut ensuite les corriger — et le
 * bouton se touche vite par accident sur un téléphone en tournée. Retaper le
 * mot rend le geste délibéré. Sans accent, pour rester tapable au clavier
 * comme au pavé tactile.
 */
const MOTS_CONFIRMATION: Record<string, string> = {
  LIVRE: "LIVRE",
  RETOUR: "RETOUR",
};

// Filtres de statut de la page Livreur (§ demande) : le livreur ne filtre
// que sur les deux états qui le concernent — celles qu'il doit aller
// chercher, et celles qu'il a livrées. "À récupérer" = commande prête au
// dépôt (statut PRETE), libellé métier du livreur, plus parlant que "Prête".
// Les autres états (en préparation, en livraison, retour) restent visibles
// dans la liste via "Tous les statuts" : on retire l'option de filtre, pas
// les commandes.
const LIVREUR_STATUT_ACTIF = [
  { value: "ALL", label: "Tous les statuts" },
  { value: "PRETE", label: "À récupérer" },
  { value: "LIVRE", label: "Livrées" },
];

// Historique personnel (préparateur/livreur) : tous les statuts déjà
// traversés par SES commandes, y compris les états terminaux.
const HISTORIQUE_STATUT_FILTERS = [
  { value: "ALL", label: "Tous les statuts" },
  { value: "LIVRE", label: "Livrées" },
  { value: "RETOUR", label: "Retours" },
  { value: "ANNULEE", label: "Annulées" },
  { value: "EN_LIVRAISON", label: "En livraison" },
  { value: "PRETE", label: "À récupérer" },
  { value: "EN_PREPARATION", label: "En préparation" },
  { value: "NOUVELLE", label: "Nouvelles" },
];

// Zones de livraison : configurables dans Paramètres (§ demande, CRUD
// nom+prix — voir useDeliveryZones/DeliveryZoneOption), plus le littéral
// "RECUPERATION" toujours présent (retrait sur place, structurellement à
// part : pas de livreur, pas de frais). `buildZoneOptions` retrouve la même
// forme {value,label,frais} que l'ancienne liste figée, pour que tous les
// .find()/.filter() existants restent inchangés.

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
  // Le préparateur et le livreur voient toutes leurs commandes à venir
  // (planning) mais ne peuvent agir dessus qu'à partir de leur OUVERTURE :
  // 19h00 la veille pour le préparateur, minuit le jour J pour le livreur
  // (§ demande). Le calcul vit dans lib/timezone.ts et reprend celui du
  // serveur (orders/services.py::ouverture_actions), qui reste seul juge :
  // ici on ne fait qu'anticiper l'affichage.
  const roleCommande: RoleCommande = isPreparateur ? "PREPARATEUR" : "LIVREUR";
  const isJourJ = useCallback(
    (dateStr?: string | null) => actionOuverte(dateStr, roleCommande),
    [roleCommande],
  );

  const [statutFilter, setStatutFilter] = useState<string>("ALL");
  const [detail, setDetail] = useState<any | null>(null);
  // Confirmation "Commande prête" jouée DANS le modal de détail : au lieu de
  // le refermer pour ouvrir la boîte de confirmation, on remplace le bas de
  // la fiche par le formulaire note + photo (§ demande).
  const [sharingChat, setSharingChat] = useState<"livreur" | "general" | null>(
    null,
  );
  const [detailInline, setDetailInline] = useState<{
    target: string;
    label: string;
    showPhoto: boolean;
  } | null>(null);
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
  // Mot à retaper avant d'annuler — vidé à chaque ouverture de la boîte.
  const [cancelWord, setCancelWord] = useState("");
  // Correction d'un état final saisi par erreur (§ demande).
  const [correction, setCorrection] = useState<{
    order: any;
    cible: string;
    label: string;
  } | null>(null);
  const [cancelling, setCancelling] = useState(false);
  // Le préparateur suit séparément sa file "à préparer" (livraison) et ses
  // commandes "Récupération sur place" (qu'il peut créer lui-même).
  const [preparateurTab, setPreparateurTab] = useState<
    "A_PREPARER" | "RECUPERATIONS"
  >("A_PREPARER");
  // Onglet "Historique" (préparateur/livreur) — journal de leurs commandes
  // déjà traitées, tous statuts, filtrable par date/heure.
  const [viewMode, setViewMode] = useState<"ACTIF" | "HISTORIQUE">("ACTIF");
  // Tous les filtres de date s'ouvrent sur le JOUR J — la date du jour à
  // Antananarivo (§ demande). C'est la journée de travail en cours : gérant,
  // préparateur et livreur arrivent donc sur ce qu'ils ont à traiter
  // aujourd'hui, sans avoir à filtrer eux-mêmes. Ils restent libres de
  // changer la date, et "Réinitialiser" les ramène au jour J.
  const [historiqueFrom, setHistoriqueFrom] = useState(
    () => `${appToday()}T00:00`,
  );
  const [historiqueTo, setHistoriqueTo] = useState(() => `${appToday()}T23:59`);
  const [historiqueStatut, setHistoriqueStatut] = useState("ALL");
  // Filtres gérant : date (un seul jour, pas de plage Du/Au) + préparateur assigné.
  const [gerantDate, setGerantDate] = useState(() => appToday());
  const [preparateurFilterId, setPreparateurFilterId] = useState("");
  const [preparateurFilterList, setPreparateurFilterList] = useState<
    { id: number; full_name: string }[]
  >([]);
  // Filtres livreur (vue "Ma tournée") : statut + date (un seul jour).
  const [livreurStatutFilter, setLivreurStatutFilter] = useState("ALL");
  // Le livreur voit TOUTES ses commandes, y compris celles des jours
  // suivants (planning) — § demande : seules les ACTIONS sont bloquées hors
  // jour J, pas l'affichage. Son filtre de date part donc vide.
  const [livreurDate, setLivreurDate] = useState("");
  // Filtre préparateur (vue "À préparer"/"Récupérations") : date (un seul jour).
  const [preparateurDate, setPreparateurDate] = useState(() => appToday());

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
            filters.date_from = appDatetimeLocalToIso(historiqueFrom);
          if (historiqueTo)
            filters.date_to = appDatetimeLocalToIso(historiqueTo);
          if (historiqueStatut !== "ALL") filters.statut = historiqueStatut;
        }
        // Préparateur/livreur : sur le jour par défaut, la fenêtre va
        // jusqu'au dernier jour déjà ouvert — après 19h00 elle inclut donc
        // les commandes du lendemain, qui viennent d'être débloquées. Dès
        // que l'utilisateur choisit une autre date, on filtre ce seul jour.
        if (isPreparateur && viewMode === "ACTIF" && preparateurDate) {
          filters.date_debut = preparateurDate;
          filters.date_fin =
            preparateurDate === appToday()
              ? dernierJourOuvert("PREPARATEUR")
              : preparateurDate;
        }
        if (isLivreur && viewMode === "ACTIF") {
          if (livreurStatutFilter !== "ALL") {
            filters.statut = livreurStatutFilter;
          }
          // Filtre facultatif : sans date choisie, le serveur renvoie tout
          // le planning du livreur.
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
      historiqueStatut,
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

  // Actions proposées au gérant : uniquement les transitions réellement
  // possibles depuis le statut courant — le workflow ne revient jamais en
  // arrière (§ demande : une commande Prête ne peut pas repasser par
  // "Assigner un préparateur"), et une commande terminée (Livrée / Retour /
  // Annulée) n'en propose aucune. Mêmes règles que orders/services.py::
  // TRANSITIONS, qui refuserait de toute façon un saut ou un retour arrière.
  const gerantActionOptions = (
    order: any,
  ): {
    value: string;
    label: string;
    target: string;
    kind: "status" | "assign";
    role?: "PREPARATEUR" | "LIVREUR";
    icon?: any;
  }[] => {
    const isRecuperation = order?.livraison_zone === "RECUPERATION";

    switch (order?.statut_courant) {
      case "NOUVELLE":
        return [
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
        ];
      case "EN_PREPARATION":
        return [
          {
            value: "commande-prete",
            label: "Commande prête",
            target: "PRETE",
            kind: "status",
            icon: Package,
          },
        ];
      case "PRETE":
        // Retrait sur place : pas de livreur, le gérant clôture directement
        // au comptoir (voir services.py::change_order_status).
        return isRecuperation
          ? [
              {
                value: "livre",
                label: "Récupérée par le client",
                target: "LIVRE",
                kind: "status",
                icon: Package,
              },
            ]
          : [
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
            ];
      case "EN_LIVRAISON":
        return [
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
        ];
      default:
        return [];
    }
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
      return true;
    } catch (err: any) {
      toast.error(err.message || "Action impossible");
      return false;
    }
  };

  /**
   * Recharge la commande affichée dans le modal, sans le fermer.
   *
   * Le détail doit suivre le workflow : après « Commande prête », la fiche
   * montre le statut Prête, la chronologie complétée et le bouton suivant
   * (§ demande). Si le rechargement échoue — ou si le rôle courant n'a plus
   * le droit de voir la commande à son nouveau statut — on referme, faute de
   * quoi la fiche resterait figée sur un état périmé.
   */
  const refreshDetail = async (orderId: number) => {
    try {
      const fresh = await djangoClient.orders.getById(orderId);
      setDetail(fresh);
    } catch {
      setDetail(null);
    }
  };

  /**
   * Partage la commande dans la messagerie (§ demande) : résumé + photo de
   * préparation, envoyés au livreur assigné ou au salon Général. Tout est
   * composé côté serveur — la photo y est déjà, inutile de la faire
   * redescendre puis remonter.
   */
  const shareOrderToChat = async (order: any, cible: "livreur" | "general") => {
    setSharingChat(cible);
    try {
      await djangoClient.orders.shareToChat(order.id, cible);
      toast.success(
        cible === "livreur"
          ? `Commande envoyée à ${order.livreur_name}`
          : "Commande envoyée au chat général",
      );
    } catch (err: any) {
      toast.error(err.message || "Partage impossible");
    } finally {
      setSharingChat(null);
    }
  };

  /**
   * Corrige un état final saisi par erreur — un « Retour » touché par
   * accident alors que la livraison était faite, et l'inverse. Le serveur
   * rétablit le stock : les articles ressortent (ou rentrent) selon le sens.
   */
  const doCorrigerStatut = async (note: string) => {
    if (!correction) return;
    try {
      await djangoClient.orders.corrigerStatut(
        correction.order.id,
        correction.cible,
        note,
      );
      toast.success(
        `Commande ${correction.order.numero} corrigée → ${correction.label}`,
      );
      fetchOrders(true);
      if (detail?.id === correction.order.id) await refreshDetail(detail.id);
      setCorrection(null);
    } catch (err: any) {
      toast.error(err.message || "Correction impossible");
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
      setCancelWord("");
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
        order.date_commande ? fmtAppDate(order.date_commande) : "",
        order.date_commande ? fmtAppDateTime(order.date_commande) : "",
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return searchableString.includes(q);
    });
  }, [visibleOrders, searchQuery]);

  /**
   * Liste finalement affichée, pour les TROIS rôles : la commande la plus
   * récemment CRÉÉE en haut (§ demande).
   *
   * Le livreur garde en plus son regroupement : les commandes du jour J
   * passent avant le planning à venir. Ce regroupement suit l'AFFICHAGE, pas
   * l'action : une commande du lendemain remonte dès 19h00 la veille (5 h
   * d'avance), alors que son bouton, lui, ne se débloque qu'à minuit
   * (§ demande). À l'intérieur de chaque groupe, la plus récente d'abord.
   */
  const displayedOrders = useMemo(() => {
    const creeLe = (o: any) =>
      o.created_at ? new Date(o.created_at).getTime() : 0;
    const rang = (o: any) =>
      isLivreur && !affichageOuvert(o.date_commande) ? 1 : 0;
    return [...searchableOrders].sort(
      (a, b) => rang(a) - rang(b) || creeLe(b) - creeLe(a),
    );
  }, [searchableOrders, isLivreur]);

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
        <div className="flex flex-wrap items-end gap-2">
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
              <History className=" w-4 mr-2" /> Historique
            </Button>
            {viewMode === "ACTIF" && (
              <Select
                value={livreurStatutFilter}
                onValueChange={setLivreurStatutFilter}
              >
                <SelectTrigger className="mr-2">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {LIVREUR_STATUT_ACTIF.map((o) => (
                    <SelectItem key={o.value} value={o.value}>
                      {o.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
          </div>
        </div>
      )}

      {isLivreur && viewMode === "ACTIF" && (
        <div className="flex flex-wrap items-end gap-2">
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
          {(preparateurDate !== appToday() || searchQuery) && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setPreparateurDate(appToday());
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
            <DateTimeInput
              value={historiqueFrom}
              onChange={setHistoriqueFrom}
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Au</Label>
            <DateTimeInput value={historiqueTo} onChange={setHistoriqueTo} />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Statut</Label>
            <Select
              value={historiqueStatut}
              onValueChange={setHistoriqueStatut}
            >
              <SelectTrigger className="w-45">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {HISTORIQUE_STATUT_FILTERS.map((o) => (
                  <SelectItem key={o.value} value={o.value}>
                    {o.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {(historiqueFrom !== `${appToday()}T00:00` ||
            historiqueTo !== `${appToday()}T23:59` ||
            historiqueStatut !== "ALL") && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setHistoriqueFrom(`${appToday()}T00:00`);
                setHistoriqueTo(`${appToday()}T23:59`);
                setHistoriqueStatut("ALL");
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
          {(gerantDate !== appToday() ||
            preparateurFilterId ||
            statutFilter !== "ALL" ||
            searchQuery) && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setGerantDate(appToday());
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
          ) : displayedOrders.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">
              Aucune commande trouvée pour cette recherche.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Statut</TableHead>

                    {/* Type, Sous-type et Date ne sont plus des colonnes :
                        ils allongeaient le tableau au point de le faire
                        défiler horizontalement. Ils restent consultables
                        dans le détail, au clic sur la ligne (§ demande). */}
                    <TableHead>Produit</TableHead>
                    <TableHead>Client</TableHead>
                    {isLivreur && <TableHead>Adresse</TableHead>}
                    {isLivreur && <TableHead>Téléphone</TableHead>}
                    <TableHead>{isLivreur ? "Zone" : "Adresse"}</TableHead>
                    {!isPreparateur && <TableHead>Total</TableHead>}
                    {isGerant && <TableHead>Assigné à</TableHead>}
                    <TableHead className="text-right">Action</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {displayedOrders.map((order) => {
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
                    const notYetDue =
                      (isPreparateur || isLivreur) &&
                      !isJourJ(order.date_commande);
                    // Ce que le bouton doit annoncer, c'est le moment où il
                    // se débloquera — pas la date de livraison.
                    const dueDateLabel = order.date_commande
                      ? fmtOuverture(order.date_commande, roleCommande)
                      : "";
                    return (
                      <TableRow
                        key={order.id}
                        className="cursor-pointer"
                        onClick={() => setDetail(order)}
                      >
                        <TableCell className="align-top">
                          <Badge
                            className={statutInfo(order.statut_courant).color}
                          >
                            {statutInfo(order.statut_courant).label}
                          </Badge>
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

                        {!isPreparateur && (
                          <TableCell className="align-top">
                            {/* Rien à encaisser : le client a déjà payé
                                d'avance, on masque le montant au livreur
                                pour éviter toute confusion (§ demande). */}
                            {isLivreur && order.mode_paiement === "AVANT" ? (
                              <span className="text-xs text-emerald-600 dark:text-emerald-400 font-medium">
                                Déjà payé
                              </span>
                            ) : (
                              fmt(order.total_a_payer)
                            )}
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
                            {isGerant &&
                              gerantActionOptions(order).length > 0 && (
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
                                    {gerantActionOptions(order).map(
                                      (option) => (
                                        <SelectItem
                                          key={option.value}
                                          value={option.value}
                                        >
                                          {option.label}
                                        </SelectItem>
                                      ),
                                    )}
                                  </SelectContent>
                                </Select>
                              )}
                            {!isGerant &&
                              action &&
                              !(isLivreur && notYetDue) && (
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
                              !isGerant &&
                              !(isLivreur && notYetDue) && (
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
                            {/* Commande close : le gérant peut corriger un
                                état saisi par erreur — le livreur touche
                                vite « Retour » alors que la livraison est
                                faite (§ demande). Directement accessible
                                depuis la ligne, sans ouvrir le détail. */}
                            {isGerant &&
                              ["LIVRE", "RETOUR"].includes(
                                order.statut_courant,
                              ) &&
                              (() => {
                                const cible =
                                  order.statut_courant === "RETOUR"
                                    ? "LIVRE"
                                    : "RETOUR";
                                const label = statutInfo(cible).label;
                                return (
                                  <IconAction
                                    label={`Corriger → ${label}`}
                                    icon={Undo2}
                                    variant="outline"
                                    showLabel
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      setCorrection({ order, cible, label });
                                    }}
                                  />
                                );
                              })()}
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
      <Dialog
        open={!!detail}
        onOpenChange={(o) => {
          if (!o) {
            setDetail(null);
            setDetailInline(null);
          }
        }}
      >
        <DialogContent className="max-w-lg lg:max-w-2xl">
          {detail && (
            <>
              <DialogHeader>
                <div className="flex items-center justify-between gap-2 pr-6">
                  <DialogTitle>Commande {detail.numero}</DialogTitle>
                  {/* "Modifier" reste proposé tant que la commande n'est pas
                      terminée (§ demande) : au-delà de "En préparation" le
                      formulaire se limite au mode de paiement, un client
                      pouvant régler d'avance une commande déjà en tournée.
                      Les transitions de statut, elles, sont les boutons EN BAS
                      de la fiche : ils se remplacent au fil du workflow et ne
                      ferment pas la fenêtre. */}
                  {isGerant &&
                    !["LIVRE", "RETOUR", "ANNULEE"].includes(
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
                          {[
                            it.category_name && ` ${it.category_name}`,
                            it.type_name && ` ${it.type_name}`,
                            it.brand_name && ` ${it.brand_name}`,
                            it.quantite && `Quantité : ${it.quantite}`,
                          ]
                            .filter(Boolean)
                            .join(" • ") || "Sans métadonnées"}
                        </div>
                      </div>
                    ))}
                  </div>
                )}

                <div className="grid gap-2">
                  {/* Reprend la colonne « Date » retiree du tableau. */}
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">
                      {detail.statut_courant === "LIVRE"
                        ? "Livrée le"
                        : "Livraison prévue le"}
                    </span>
                    <span className="text-right">
                      {fmtAppDateTime(
                        detail.statut_courant === "LIVRE"
                          ? historyAt(detail, "LIVRE") || detail.date_commande
                          : detail.date_commande,
                      )}
                    </span>
                  </div>
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
                  {/* Rien ne reste à encaisser quand le client a déjà payé
                      d'avance : afficher un "Total à payer" ferait croire au
                      livreur qu'il doit encore réclamer la somme (§ demande). */}
                  {detail.mode_paiement !== "AVANT" && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">
                        Total à payer
                      </span>
                      <span className="font-semibold">
                        {detail.total_a_payer != null
                          ? fmt(detail.total_a_payer)
                          : "-"}
                      </span>
                    </div>
                  )}
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
                </div>

                {/* Actions du détail, jouées SANS quitter le modal (§ demande) :
                    le bouton laisse place, dans la même fenêtre, au
                    formulaire de confirmation (note, et photo de preuve pour
                    le passage "Prête"). Seule l'assignation part dans sa
                    propre boîte, qui doit charger la liste du personnel. */}
                {(() => {
                  // Confirmation en cours : elle remplace les boutons.
                  if (detailInline) {
                    return (
                      <div className="space-y-3 rounded-md border bg-muted/10 p-3">
                        <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">
                          Confirmer : {detailInline.label}
                        </p>
                        {detailInline.showPhoto && (
                          <p className="text-sm text-muted-foreground">
                            Ajoutez si besoin une note et une photo prouvant que
                            la préparation est faite — le livreur les verra.
                          </p>
                        )}
                        <NoteForm
                          showPhoto={detailInline.showPhoto}
                          confirmWord={MOTS_CONFIRMATION[detailInline.target]}
                          onCancel={() => setDetailInline(null)}
                          onSubmit={async (note, photo) => {
                            const ok = await doChangeStatus(
                              detail,
                              detailInline.target,
                              note,
                              undefined,
                              photo,
                            );
                            // En cas d'échec on reste sur le formulaire : la
                            // note et la photo saisies ne sont pas perdues.
                            if (!ok) return;
                            setDetailInline(null);
                            // On NE ferme PAS : on recharge la commande pour
                            // que la fiche affiche le nouveau statut, la
                            // chronologie à jour et l'action suivante.
                            await refreshDetail(detail.id);
                          }}
                        />
                      </div>
                    );
                  }

                  const dueLabel = `Disponible le ${fmtOuverture(detail.date_commande, roleCommande)}`;

                  // Ouvre la confirmation intégrée pour une transition.
                  const ouvrir = (target: string, label: string) =>
                    setDetailInline({
                      target,
                      label,
                      // La photo ne sert de preuve qu'au passage "Prête".
                      showPhoto: target === "PRETE",
                    });

                  // Commande close : plus de transition possible, mais le
                  // gérant peut CORRIGER un état saisi par erreur — le
                  // livreur touche vite « Retour » alors que la livraison
                  // est faite (§ demande).
                  if (
                    isGerant &&
                    ["LIVRE", "RETOUR"].includes(detail.statut_courant)
                  ) {
                    const cible =
                      detail.statut_courant === "RETOUR" ? "LIVRE" : "RETOUR";
                    const label = statutInfo(cible).label;
                    return (
                      <Button
                        variant="outline"
                        className="w-full"
                        onClick={() =>
                          setCorrection({ order: detail, cible, label })
                        }
                      >
                        <Undo2 className="h-4 w-4 mr-2" />
                        Corriger l&apos;état → {label}
                      </Button>
                    );
                  }

                  // GÉRANT : toutes les actions du statut courant, en
                  // boutons. Elles se remplacent au fil du workflow, la
                  // fenêtre restant ouverte jusqu'au statut terminal.
                  if (isGerant) {
                    const options = gerantActionOptions(detail);
                    if (options.length === 0) return null;
                    return (
                      <div className="flex flex-col sm:flex-row gap-2">
                        {options.map((option) => (
                          <Button
                            key={option.value}
                            className="flex-1"
                            variant={
                              option.kind === "assign" ||
                              option.target === "RETOUR"
                                ? "outline"
                                : "default"
                            }
                            onClick={() => {
                              if (option.kind === "assign") {
                                // Choisir une personne demande de charger la
                                // liste du personnel : seule action qui garde
                                // sa propre boîte.
                                const order = detail;
                                setDetail(null);
                                setAssignTarget({
                                  order,
                                  role: option.role || "PREPARATEUR",
                                });
                                return;
                              }
                              ouvrir(option.target, option.label);
                            }}
                          >
                            {option.icon && (
                              <option.icon className="h-4 w-4 mr-2" />
                            )}
                            {option.label}
                          </Button>
                        ))}
                      </div>
                    );
                  }

                  // LIVREUR en cours de livraison : "Livré" et "Retour" sont
                  // deux issues possibles, pas une succession.
                  if (
                    isLivreur &&
                    detail.statut_courant === "EN_LIVRAISON" &&
                    isJourJ(detail.date_commande)
                  ) {
                    return (
                      <div className="flex flex-col sm:flex-row gap-2">
                        <Button
                          className="flex-1"
                          onClick={() => ouvrir("LIVRE", "Livré")}
                        >
                          <Truck className="h-4 w-4 mr-2" /> Livré
                        </Button>
                        <Button
                          variant="outline"
                          className="flex-1 text-red-600"
                          onClick={() => ouvrir("RETOUR", "Retour")}
                        >
                          <Undo2 className="h-4 w-4 mr-2" /> Retour
                        </Button>
                      </div>
                    );
                  }

                  // Préparateur et livreur : leur action du moment, jouée
                  // elle aussi sans quitter la fenêtre.
                  const action = nextAction(detail);
                  if (!action) return null;
                  const bloque = !isJourJ(detail.date_commande);
                  // Livreur hors jour J : aucun bouton, pas même grisé.
                  if (isLivreur && bloque) return null;
                  return (
                    <Button
                      className="w-full"
                      disabled={bloque}
                      onClick={() => ouvrir(action.target, action.label)}
                    >
                      <action.icon className="h-4 w-4 mr-2" />
                      {bloque ? dueLabel : action.label}
                    </Button>
                  );
                })()}

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

                {/* Partage dans la messagerie — proposé dès qu'une photo de
                    préparation existe, au gérant comme au préparateur, pour
                    prévenir le livreur avec la preuve du colis (§ demande). */}
                {(isGerant || isPreparateur) &&
                  (detail.status_history || []).some((h: any) => h.photo) && (
                    <div className="border-t pt-3 space-y-2">
                      <p className="text-muted-foreground">
                        Envoyer au chat (avec la photo)
                      </p>
                      {/* Une seule destination : le salon Général a été
                          retiré de la messagerie (§ demande), l'y envoyer
                          n'aurait plus de lecteur. */}
                      <Button
                        variant="outline"
                        className="w-full"
                        disabled={!detail.livreur || sharingChat !== null}
                        onClick={() => shareOrderToChat(detail, "livreur")}
                      >
                        <MessageCircle className="h-4 w-4 mr-2" />
                        {sharingChat === "livreur"
                          ? "Envoi…"
                          : detail.livreur_name
                            ? `Au livreur (${detail.livreur_name})`
                            : "Aucun livreur assigné"}
                      </Button>
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
                            {fmtAppDateTime(h.timestamp)}
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
              {/* Commande déjà réglée : le livreur n'a rien à encaisser,
                  on masque tous les montants et on l'annonce clairement
                  (§ demande). */}
              {isLivreur && actionNote.order.mode_paiement === "AVANT" ? (
                <div className="border-t pt-1.5 flex justify-between font-medium text-emerald-600 dark:text-emerald-400">
                  <span>À encaisser</span>
                  <span>Rien — déjà payé</span>
                </div>
              ) : (
                actionNote.order.total_a_payer != null && (
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
                )
              )}
            </div>
          )}
          <NoteForm
            showPhoto={actionNote?.target === "PRETE"}
            confirmWord={
              actionNote ? MOTS_CONFIRMATION[actionNote.target] : undefined
            }
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

      {/* Correction d'un état final saisi par erreur (gérant) */}
      <Dialog
        open={!!correction}
        onOpenChange={(o) => !o && setCorrection(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Corriger la commande {correction?.order?.numero}
            </DialogTitle>
            <DialogDescription>
              Son état passera de{" "}
              <span className="font-semibold text-foreground">
                {correction &&
                  statutInfo(correction.order.statut_courant).label}
              </span>{" "}
              à{" "}
              <span className="font-semibold text-foreground">
                {correction?.label}
              </span>
              . Le stock est rétabli en conséquence :{" "}
              {correction?.cible === "LIVRE"
                ? "les articles ressortent du stock, puisqu'ils n'ont jamais été rapportés."
                : "les articles rentrent en stock, puisque le colis est revenu."}
            </DialogDescription>
          </DialogHeader>
          <NoteForm
            confirmWord={correction?.cible === "RETOUR" ? "RETOUR" : "LIVRE"}
            onCancel={() => setCorrection(null)}
            onSubmit={(note) => doCorrigerStatut(note)}
          />
        </DialogContent>
      </Dialog>

      {/* Annulation commande (gérant) — restitue le stock si déjà déduit */}
      <Dialog
        open={!!cancelTarget}
        onOpenChange={(o) => {
          if (!o) {
            setCancelTarget(null);
            setCancelWord("");
          }
        }}
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
          {/* Annuler est irréversible : on fait retaper le mot pour rendre
              le geste délibéré (§ demande). */}
          <div className="space-y-2">
            <Label className="text-sm">
              Pour confirmer, tapez{" "}
              <span className="font-semibold text-foreground">ANNULER</span>
            </Label>
            <Input
              value={cancelWord}
              onChange={(e) => setCancelWord(e.target.value)}
              placeholder="ANNULER"
              autoComplete="off"
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCancelTarget(null)}>
              Retour
            </Button>
            <Button
              variant="destructive"
              onClick={handleCancelOrder}
              disabled={
                cancelling ||
                cancelWord.trim().toLocaleLowerCase("fr") !== "annuler"
              }
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
    // La création vient de created_at (horodatage automatique), pas de
    // date_commande qui porte désormais la livraison prévue — sinon une
    // livraison planifiée pour demain s'affichait "avant" la préparation.
    {
      icon: ShoppingCart,
      label: "Commande crée le",
      date: order.created_at,
      reached: !!order.created_at,
    },
    {
      icon: CalendarClock,
      label: "Livraison prévue le",
      date: order.date_commande,
      reached: !!order.date_commande,
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
          <span className="font-semibold">{fmtAppDateTime(r.date)}</span>
        </li>
      ))}
    </ul>
  );
}

function NoteForm({
  onSubmit,
  onCancel,
  showPhoto = false,
  confirmWord,
}: {
  onSubmit: (note: string, photo?: File) => void;
  onCancel?: () => void;
  // Preuve que la préparation est faite — proposé uniquement au passage
  // "Prête" (préparateur/gérant), voir OrderStatusHistory.photo.
  showPhoto?: boolean;
  /**
   * Mot à retaper pour débloquer la confirmation (§ demande). Réservé aux
   * actions sans retour en arrière — Retour, Annulation : un livreur peut
   * effleurer le bouton par accident, retaper le mot rend le geste
   * délibéré. Volontairement PAS un mot de passe : on veut éviter une
   * fausse manœuvre, pas ré-authentifier.
   */
  confirmWord?: string;
}) {
  const [note, setNote] = useState("");
  const [photo, setPhoto] = useState<File | undefined>(undefined);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const [saisie, setSaisie] = useState("");

  // Comparaison tolérante : casse et espaces autour ne doivent pas bloquer.
  const motValide =
    !confirmWord ||
    saisie.trim().toLocaleLowerCase("fr") ===
      confirmWord.trim().toLocaleLowerCase("fr");

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
      {confirmWord && (
        <div className="space-y-2">
          <Label className="text-sm">
            Pour confirmer, tapez{" "}
            <span className="font-semibold text-foreground">{confirmWord}</span>
          </Label>
          <Input
            value={saisie}
            onChange={(e) => setSaisie(e.target.value)}
            placeholder={confirmWord}
            autoComplete="off"
          />
        </div>
      )}
      <DialogFooter>
        {onCancel && (
          <Button variant="outline" onClick={onCancel}>
            Annuler
          </Button>
        )}
        <Button disabled={!motValide} onClick={() => onSubmit(note, photo)}>
          Confirmer
        </Button>
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
    setAssignedAt(appDatetimeLocalValue(new Date()));
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
              <DateTimeInput value={assignedAt} onChange={setAssignedAt} />
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

  // Au-delà de "En préparation" la commande est trop engagée : seul le mode
  // de paiement reste modifiable (le client peut régler d'avance une
  // commande déjà en tournée). Même règle que le serveur —
  // orders/services.py::update_order, qui refuserait le reste de toute façon.
  const paiementSeul =
    !!order && !["NOUVELLE", "EN_PREPARATION"].includes(order.statut_courant);

  useEffect(() => {
    if (!order) return;
    setClientNom(order.client_nom || "");
    setTelephone(order.telephone || "");
    setZone(order.livraison_zone || "");
    setAdresseLivraison(order.adresse_livraison || "");
    setModePaiement(order.mode_paiement || "LIVRAISON");
    setDateCommande(
      order.date_commande
        ? appDatetimeLocalValue(new Date(order.date_commande))
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
    // En régime restreint on ne valide rien d'autre : seul le paiement part.
    if (!paiementSeul && !clientNom.trim()) {
      toast.error("Nom du client requis");
      return;
    }
    if (!paiementSeul && !/^\+261\d{9}$/.test(telephone)) {
      toast.error("Téléphone au format +261XXXXXXXXX");
      return;
    }
    if (!paiementSeul && items.length === 0) {
      toast.error("Ajoutez au moins un article");
      return;
    }
    setSubmitting(true);
    try {
      if (paiementSeul) {
        await djangoClient.orders.update(order.id, {
          mode_paiement: modePaiement as any,
        });
        toast.success(`Commande ${order.numero} — paiement mis à jour`);
        onSaved();
        return;
      }
      await djangoClient.orders.update(order.id, {
        client_nom: clientNom.trim(),
        telephone,
        livraison_zone: zone as any,
        adresse_livraison:
          zone === "RECUPERATION" ? "" : adresseLivraison.trim(),
        mode_paiement: modePaiement as any,
        ...(dateCommande
          ? { date_commande: appDatetimeLocalToIso(dateCommande) }
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
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Modifier la commande {order?.numero}</DialogTitle>
          <DialogDescription>
            {paiementSeul
              ? "Commande déjà engagée : seul le mode de paiement reste modifiable."
              : 'Possible tant que la commande n\'est pas encore "Prête".'}
          </DialogDescription>
        </DialogHeader>

        {/* Régime restreint : au-delà de "En préparation" seul le
            mode de paiement reste modifiable (§ demande). Tout le
            reste du formulaire est masqué — le serveur le refuserait
            de toute façon (orders/services.py::update_order). */}
        {!paiementSeul && (
          <>
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

            <div className="space-y-2">
              <Label>Date et heure de livraison</Label>
              <DateTimeInput value={dateCommande} onChange={setDateCommande} />
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
          </>
        )}

        {(paiementSeul || zone !== "RECUPERATION") && (
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

        {!paiementSeul && (
          <>
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
          </>
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

// Sélecteur d'articles (recherche catalogue + panier) — partagé entre
// CreateOrderDialog et EditOrderDialog (le gérant peut aussi modifier les
// articles d'une commande "Nouvelle", voir orders/views.py::partial_update).
