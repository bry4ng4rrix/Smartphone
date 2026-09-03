"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { djangoClient } from "@/lib/django-client";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { toast } from "sonner";
import {
  Building2,
  RefreshCw,
  Zap,
  MoreVertical,
  Pencil,
  Download,
  Trash2,
  Smartphone,
  Plus,
  Store,
  Users,
  Package,
  Shield,
} from "lucide-react";

const STATUS_OPTIONS: { value: string; label: string }[] = [
  { value: "active", label: "Activer" },
  { value: "disabled", label: "Désactiver" },
  { value: "pending", label: "Mettre en attente" },
  { value: "trial", label: "Démarrer essai 1 mois" },
  { value: "demo", label: "Mode démo" },
];

const STATUS_LABEL: Record<string, string> = {
  active: "Actif",
  disabled: "Désactivé",
  pending: "En attente",
  trial: "Essai",
  demo: "Démo",
};

const getStatusBadgeClass = (status: string) => {
  switch (status) {
    case "active":
      return "bg-green-50 text-green-700";
    case "trial":
      return "bg-blue-50 text-blue-700";
    case "demo":
      return "bg-purple-50 text-purple-700";
    case "pending":
      return "bg-orange-50 text-orange-700";
    case "disabled":
      return "bg-red-50 text-red-700";
    default:
      return "bg-muted text-muted-foreground";
  }
};

const emptyForm = {
  company_name: "",
  full_name: "",
  email: "",
  password: "",
  phone: "",
  status: "pending",
};

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export default function LabelDashboardPage() {
  const [companies, setCompanies] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [updating, setUpdating] = useState<number | null>(null);
  const [activatingAll, setActivatingAll] = useState(false);
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [search, setSearch] = useState("");

  // Create/Edit dialog
  const [formOpen, setFormOpen] = useState(false);
  const [formMode, setFormMode] = useState<"create" | "edit">("create");
  const [formTarget, setFormTarget] = useState<any | null>(null);
  const [formData, setFormData] = useState(emptyForm);
  const [saving, setSaving] = useState(false);

  // Delete dialog
  const [deleteTarget, setDeleteTarget] = useState<any | null>(null);
  const [deleteConfirmText, setDeleteConfirmText] = useState("");
  const [deleting, setDeleting] = useState(false);

  // Devices dialog
  const [devicesTarget, setDevicesTarget] = useState<any | null>(null);
  const [devices, setDevices] = useState<any[]>([]);
  const [deviceLimit, setDeviceLimit] = useState<{ count: number; limit: number } | null>(null);
  const [devicesLoading, setDevicesLoading] = useState(false);
  const [deletingDeviceId, setDeletingDeviceId] = useState<number | null>(null);

  // Offers catalog (for assignment dropdown)
  const [offers, setOffers] = useState<any[]>([]);

  // Backup in progress
  const [backingUp, setBackingUp] = useState<number | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const data = await djangoClient.platformAdmin.listCompanies();
      setCompanies(data);
    } catch (err) {
      console.error(err);
      toast.error("Erreur lors du chargement des sociétés");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
    djangoClient.platformAdmin.listOffers().then(setOffers).catch(() => {});
  }, [fetchData]);

  const filtered = useMemo(() => {
    const term = search.toLowerCase();
    return companies.filter((c) => {
      const matchesStatus = statusFilter === "all" || c.status === statusFilter;
      const matchesTerm =
        !term ||
        (c.company_name || "").toLowerCase().includes(term) ||
        (c.admin_email || "").toLowerCase().includes(term) ||
        (c.admin_full_name || "").toLowerCase().includes(term);
      return matchesStatus && matchesTerm;
    });
  }, [companies, statusFilter, search]);

  const expiringSoon = useMemo(
    () => companies.filter((c) => c.status === "trial" && c.days_left_in_trial !== null && c.days_left_in_trial <= 3),
    [companies]
  );

  const handleStatusChange = async (adminProfileId: number, status: string) => {
    setUpdating(adminProfileId);
    try {
      const updated = await djangoClient.platformAdmin.updateStatus(
        adminProfileId,
        status,
      );
      setCompanies((prev) =>
        prev.map((c) => (c.id === adminProfileId ? updated : c)),
      );
      toast.success("Statut mis à jour");
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la mise à jour");
    } finally {
      setUpdating(null);
    }
  };

  const handleActivateAll = async () => {
    if (!confirm("Activer tous les abonnements de toutes les sociétés ?"))
      return;
    setActivatingAll(true);
    try {
      await djangoClient.platformAdmin.activateAll();
      toast.success("Tous les abonnements ont été activés");
      fetchData();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'activation globale");
    } finally {
      setActivatingAll(false);
    }
  };

  const openCreate = () => {
    setFormMode("create");
    setFormTarget(null);
    setFormData(emptyForm);
    setFormOpen(true);
  };

  const openEdit = (c: any) => {
    setFormMode("edit");
    setFormTarget(c);
    setFormData({
      company_name: c.company_name || "",
      full_name: c.admin_full_name || "",
      email: c.admin_email || "",
      password: "",
      phone: c.admin_phone || "",
      status: c.status || "pending",
    });
    setFormOpen(true);
  };

  const handleSaveForm = async () => {
    setSaving(true);
    try {
      if (formMode === "create") {
        await djangoClient.platformAdmin.createCompany({
          company_name: formData.company_name,
          full_name: formData.full_name,
          email: formData.email,
          password: formData.password,
          phone: formData.phone,
          status: formData.status,
        });
        toast.success("Société créée");
      } else if (formTarget) {
        await djangoClient.platformAdmin.updateCompany(formTarget.id, {
          company_name: formData.company_name,
          admin_full_name: formData.full_name,
          admin_phone: formData.phone,
        });
        toast.success("Société mise à jour");
      }
      setFormOpen(false);
      fetchData();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'enregistrement");
    } finally {
      setSaving(false);
    }
  };

  const handleBackup = async (c: any) => {
    setBackingUp(c.id);
    try {
      const { blob, filename } = await djangoClient.platformAdmin.backupCompany(
        c.id,
      );
      downloadBlob(blob, filename);
      toast.success("Sauvegarde téléchargée");
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la sauvegarde");
    } finally {
      setBackingUp(null);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget || deleteConfirmText !== deleteTarget.company_name)
      return;
    setDeleting(true);
    try {
      const { blob, filename } = await djangoClient.platformAdmin.deleteCompany(
        deleteTarget.id,
      );
      downloadBlob(blob, filename);
      toast.success(
        "Société supprimée (sauvegarde téléchargée automatiquement)",
      );
      setDeleteTarget(null);
      setDeleteConfirmText("");
      fetchData();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la suppression");
    } finally {
      setDeleting(false);
    }
  };

  const openDevices = async (c: any) => {
    setDevicesTarget(c);
    setDevicesLoading(true);
    try {
      const data = await djangoClient.platformAdmin.getDevices(c.id);
      setDevices(data.devices);
      setDeviceLimit({ count: data.count, limit: data.limit });
    } catch (err) {
      console.error(err);
      toast.error("Erreur lors du chargement des appareils");
    } finally {
      setDevicesLoading(false);
    }
  };

  const handleDeleteDevice = async (deviceId: number) => {
    if (!devicesTarget) return;
    setDeletingDeviceId(deviceId);
    try {
      await djangoClient.platformAdmin.deleteDevice(devicesTarget.id, deviceId);
      toast.success("Appareil supprimé");
      openDevices(devicesTarget);
      fetchData();
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de la suppression");
    } finally {
      setDeletingDeviceId(null);
    }
  };

  const handleAssignOffer = async (adminProfileId: number, offerId: string) => {
    setUpdating(adminProfileId);
    try {
      const updated = await djangoClient.platformAdmin.assignOffer(
        adminProfileId,
        offerId === "none" ? null : Number(offerId),
      );
      setCompanies((prev) => prev.map((c) => (c.id === adminProfileId ? updated : c)));
      toast.success("Offre assignée");
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'assignation");
    } finally {
      setUpdating(null);
    }
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight flex items-center gap-2">
            <Building2 className="h-7 w-7 text-blue-600" />
            Label Technology
          </h1>
          <p className="text-muted-foreground mt-1 text-sm sm:text-base">
            Supervision des sociétés et gestion des abonnements
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={fetchData}
            disabled={loading}
          >
            <RefreshCw
              className={`h-4 w-4 mr-2 ${loading ? "animate-spin" : ""}`}
            />
            Actualiser
          </Button>
          <Button variant="outline" size="sm" onClick={openCreate}>
            <Plus className="h-4 w-4 mr-2" />
            Nouvelle société
          </Button>
          <Button
            size="sm"
            onClick={handleActivateAll}
            disabled={activatingAll || loading}
          >
            <Zap className="h-4 w-4 mr-2" />
            Activer tous les abonnements
          </Button>
        </div>
      </div>

      {expiringSoon.length > 0 && (
        <Card className="border-orange-200 bg-orange-50/50">
          <CardContent className="py-4">
            <p className="text-sm font-medium text-orange-800">
              {expiringSoon.length} société{expiringSoon.length > 1 ? "s" : ""} en essai expire
              {expiringSoon.length > 1 ? "nt" : ""} bientôt :
            </p>
            <div className="flex flex-wrap gap-2 mt-2">
              {expiringSoon.map((c) => (
                <Badge key={c.id} variant="outline" className="bg-white text-orange-700 border-orange-300">
                  {c.company_name} — {c.days_left_in_trial} j
                </Badge>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-5 gap-4">
        {(["active", "trial", "demo", "pending", "disabled"] as const).map(
          (status) => (
            <Card key={status}>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium">
                  {STATUS_LABEL[status]}
                </CardTitle>
              </CardHeader>
              <CardContent>
                {loading ? (
                  <Skeleton className="h-7 w-10" />
                ) : (
                  <div className="text-2xl font-bold">
                    {companies.filter((c) => c.status === status).length}
                  </div>
                )}
              </CardContent>
            </Card>
          ),
        )}
      </div>

      <div className="flex flex-col sm:flex-row flex-wrap gap-3">
        <Input
          placeholder="Rechercher société, email admin..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full sm:max-w-xs"
        />
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-full sm:w-48">
            <SelectValue placeholder="Statut" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tous les statuts</SelectItem>
            {Object.entries(STATUS_LABEL).map(([value, label]) => (
              <SelectItem key={value} value={value}>
                {label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-56 w-full" />
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">
            Aucune société trouvée
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((c) => (
            <Card key={c.id} className="flex flex-col">
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center shrink-0 overflow-hidden">
                      {c.logo ? (
                        <img
                          src={c.logo}
                          alt={c.company_name}
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        <Building2 className="h-5 w-5 text-blue-600" />
                      )}
                    </div>
                    <div className="min-w-0">
                      <CardTitle className="text-base truncate">
                        {c.company_name}
                      </CardTitle>
                      <CardDescription className="truncate">
                        {c.admin_email}
                      </CardDescription>
                    </div>
                  </div>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 shrink-0"
                      >
                        <MoreVertical className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onClick={() => openEdit(c)}>
                        <Pencil className="h-4 w-4 mr-2" />
                        Modifier
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => openDevices(c)}>
                        <Smartphone className="h-4 w-4 mr-2" />
                        Appareils connectés
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        onClick={() => handleBackup(c)}
                        disabled={backingUp === c.id}
                      >
                        <Download className="h-4 w-4 mr-2" />
                        {backingUp === c.id
                          ? "Génération..."
                          : "Sauvegarder (ZIP)"}
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem
                        className="text-red-600 focus:text-red-600"
                        onClick={() => {
                          setDeleteTarget(c);
                          setDeleteConfirmText("");
                        }}
                      >
                        <Trash2 className="h-4 w-4 mr-2" />
                        Supprimer
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </CardHeader>
              <CardContent className="flex-1 flex flex-col gap-3">
                <div className="flex flex-wrap gap-2">
                  <Badge
                    variant="outline"
                    className={getStatusBadgeClass(c.status)}
                  >
                    {STATUS_LABEL[c.status] || c.status}
                  </Badge>
                  {c.status === "trial" && c.days_left_in_trial !== null && (
                    <Badge variant="outline" className="font-normal">
                      {c.days_left_in_trial} j restant(s)
                    </Badge>
                  )}
                  <Badge
                    variant="outline"
                    className="font-normal flex items-center gap-1"
                  >
                    <Shield className="h-3 w-3" />
                    {c.admin_count} admin{c.admin_count > 1 ? "s" : ""}
                  </Badge>
                  <Badge
                    variant="outline"
                    className={`font-normal flex items-center gap-1 ${
                      c.device_count >= c.max_devices ? "bg-red-50 text-red-700" : ""
                    }`}
                  >
                    <Smartphone className="h-3 w-3" />
                    {c.device_count} / {c.max_devices} appareils
                  </Badge>
                  {c.offer_name && (
                    <Badge variant="outline" className="font-normal bg-indigo-50 text-indigo-700">
                      {c.offer_name}
                    </Badge>
                  )}
                </div>

                <div className="grid grid-cols-3 gap-2 text-center text-sm">
                  <div className="rounded-md border p-2">
                    <Store className="h-4 w-4 mx-auto mb-1 text-blue-500" />
                    <div className="font-semibold">{c.store_count}</div>
                    <div className="text-xs text-muted-foreground">
                      Boutiques
                    </div>
                  </div>
                  <div className="rounded-md border p-2">
                    <Users className="h-4 w-4 mx-auto mb-1 text-green-500" />
                    <div className="font-semibold">{c.user_count}</div>
                    <div className="text-xs text-muted-foreground">
                      Utilisateurs
                    </div>
                  </div>
                  <div className="rounded-md border p-2">
                    <Package className="h-4 w-4 mx-auto mb-1 text-orange-500" />
                    <div className="font-semibold">{c.total_stock}</div>
                    <div className="text-xs text-muted-foreground">Stock</div>
                  </div>
                </div>

                <div className="mt-auto pt-2 space-y-2">
                  <Select
                    value=""
                    onValueChange={(v) => handleStatusChange(c.id, v)}
                    disabled={updating === c.id}
                  >
                    <SelectTrigger className="w-full h-8 text-xs">
                      <SelectValue placeholder="Changer le statut" />
                    </SelectTrigger>
                    <SelectContent>
                      {STATUS_OPTIONS.map((opt) => (
                        <SelectItem key={opt.value} value={opt.value}>
                          {opt.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Select
                    value={c.offer_id ? String(c.offer_id) : "none"}
                    onValueChange={(v) => handleAssignOffer(c.id, v)}
                    disabled={updating === c.id}
                  >
                    <SelectTrigger className="w-full h-8 text-xs">
                      <SelectValue placeholder="Offre d'abonnement" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">Aucune offre (limite par défaut)</SelectItem>
                      {offers.map((o) => (
                        <SelectItem key={o.id} value={String(o.id)}>
                          {o.name} — {o.max_devices} appareils · {o.duration_months} mois
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Create/Edit dialog */}
      <Dialog open={formOpen} onOpenChange={setFormOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {formMode === "create"
                ? "Nouvelle société"
                : "Modifier la société"}
            </DialogTitle>
            <DialogDescription>
              {formMode === "create"
                ? "Crée un compte admin et une société sur la plateforme."
                : "Modifie le nom de la société et les informations de contact de l'admin."}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label>Nom de la société</Label>
              <Input
                value={formData.company_name}
                onChange={(e) =>
                  setFormData((f) => ({ ...f, company_name: e.target.value }))
                }
              />
            </div>
            <div className="space-y-1.5">
              <Label>Nom de l'admin</Label>
              <Input
                value={formData.full_name}
                onChange={(e) =>
                  setFormData((f) => ({ ...f, full_name: e.target.value }))
                }
              />
            </div>
            {formMode === "create" && (
              <div className="space-y-1.5">
                <Label>Email de l'admin</Label>
                <Input
                  type="email"
                  value={formData.email}
                  onChange={(e) =>
                    setFormData((f) => ({ ...f, email: e.target.value }))
                  }
                />
              </div>
            )}
            <div className="space-y-1.5">
              <Label>Téléphone</Label>
              <Input
                value={formData.phone}
                onChange={(e) =>
                  setFormData((f) => ({ ...f, phone: e.target.value }))
                }
              />
            </div>
            {formMode === "create" && (
              <>
                <div className="space-y-1.5">
                  <Label>Mot de passe temporaire</Label>
                  <Input
                    type="text"
                    value={formData.password}
                    onChange={(e) =>
                      setFormData((f) => ({ ...f, password: e.target.value }))
                    }
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Statut initial</Label>
                  <Select
                    value={formData.status}
                    onValueChange={(v) =>
                      setFormData((f) => ({ ...f, status: v }))
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {Object.entries(STATUS_LABEL).map(([value, label]) => (
                        <SelectItem key={value} value={value}>
                          {label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setFormOpen(false)}>
              Annuler
            </Button>
            <Button onClick={handleSaveForm} disabled={saving}>
              {saving ? "Enregistrement..." : "Enregistrer"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation dialog */}
      <Dialog
        open={!!deleteTarget}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="text-red-600">
              Supprimer "{deleteTarget?.company_name}" ?
            </DialogTitle>
            <DialogDescription>
              Cette action est irréversible : toutes les boutiques, produits,
              ventes et utilisateurs de cette société seront définitivement
              supprimés. Une sauvegarde ZIP sera automatiquement téléchargée
              avant suppression. Tapez le nom exact de la société pour
              confirmer.
            </DialogDescription>
          </DialogHeader>
          <Input
            value={deleteConfirmText}
            onChange={(e) => setDeleteConfirmText(e.target.value)}
            placeholder={deleteTarget?.company_name}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              Annuler
            </Button>
            <Button
              variant="destructive"
              disabled={
                deleting || deleteConfirmText !== deleteTarget?.company_name
              }
              onClick={handleDelete}
            >
              {deleting ? "Suppression..." : "Supprimer définitivement"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Devices dialog */}
      <Dialog
        open={!!devicesTarget}
        onOpenChange={(open) => !open && setDevicesTarget(null)}
      >
        <DialogContent className="sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle className="flex items-center justify-between gap-2 pr-6">
              <span>Appareils connectés — {devicesTarget?.company_name}</span>
              {deviceLimit && (
                <Badge
                  variant="outline"
                  className={deviceLimit.count >= deviceLimit.limit ? "bg-red-50 text-red-700" : "bg-blue-50 text-blue-700"}
                >
                  {deviceLimit.count} / {deviceLimit.limit}
                </Badge>
              )}
            </DialogTitle>
            <DialogDescription>
              Appareils enregistrés pour les utilisateurs de cette société
            </DialogDescription>
          </DialogHeader>
          {devicesLoading ? (
            <div className="space-y-2">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="h-10 w-full" />
              ))}
            </div>
          ) : devices.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">
              Aucun appareil enregistré
            </p>
          ) : (
            <div className="max-h-96 overflow-y-auto space-y-2">
              {devices.map((d) => (
                <div
                  key={d.id}
                  className="flex items-center justify-between border rounded-md p-2 text-sm"
                >
                  <div>
                    <p className="font-medium">
                      {d.user_name}{" "}
                      <span className="text-xs text-muted-foreground">
                        ({d.user_role})
                      </span>
                    </p>
                    <p className="text-xs text-muted-foreground truncate max-w-xs">
                      {d.label || d.user_agent}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="text-right">
                      <p className="font-mono text-xs">{d.ip_address || "-"}</p>
                      <p className="text-xs text-muted-foreground">
                        {new Date(d.last_seen).toLocaleString("fr-FR")}
                      </p>
                    </div>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-7 w-7 text-red-600 hover:text-red-700"
                      disabled={deletingDeviceId === d.id}
                      onClick={() => handleDeleteDevice(d.id)}
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
