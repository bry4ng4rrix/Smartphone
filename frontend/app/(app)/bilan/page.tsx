"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { djangoClient } from "@/lib/django-client";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { useRealtimeRefresh } from "@/lib/hooks/useRealtimeRefresh";
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
  ShieldAlert,
  RefreshCw,
  Receipt,
  Undo2,
  PackageCheck,
  Users,
  ChevronRight,
  ArrowLeft,
  Wallet,
  Plus,
  Check,
  X,
} from "lucide-react";
import { toast } from "sonner";
import {
  APP_TIME_ZONE,
  appDayBounds,
  appToday,
  fmtAppDate,
} from "@/lib/timezone";

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat("fr-MG").format(Math.round(Number(n || 0))) + " Ar";

// Prix produit seul = total à payer moins les frais de livraison — dérivé
// sans avoir besoin du prix par article (jamais exposé au livreur, voir
// orders/serializers.py::OrderItemPublicSerializer).
const prixProduit = (order: any) =>
  Number(order.total_a_payer || 0) - Number(order.frais_livraison || 0);

// Le client a-t-il réglé AVANT la livraison ? (Order.mode_paiement, cf.
// orders/models.py::MODE_PAIEMENT_CHOICES).
const estPrepayee = (order: any) => order.mode_paiement === "AVANT";

/**
 * Argent réellement encaissé par le livreur sur cette commande (§ demande).
 *
 * Une commande déjà payée d'avance ne fait RIEN encaisser au livreur : elle
 * vaut 0 Ar dans le bilan, même si son total est non nul. Sans ça le bilan
 * réclamerait au livreur de l'argent qu'il n'a jamais reçu — et le total du
 * gérant serait faux d'autant.
 */
const argentEncaisse = (order: any) =>
  estPrepayee(order) ? 0 : Number(order.total_a_payer || 0);

function sumTotals(orders: any[]) {
  return {
    count: orders.length,
    prix: orders.reduce((s, o) => s + prixProduit(o), 0),
    frais: orders.reduce((s, o) => s + Number(o.frais_livraison || 0), 0),
    // Somme des montants réellement remis par le livreur.
    argent: orders.reduce((s, o) => s + argentEncaisse(o), 0),
    // Montant des commandes prépayées — existe, mais n'est pas encaissé par
    // le livreur : affiché à part pour que l'écart soit explicable.
    prepaye: orders
      .filter(estPrepayee)
      .reduce((s, o) => s + Number(o.total_a_payer || 0), 0),
    prepayeCount: orders.filter(estPrepayee).length,
  };
}

type Totals = ReturnType<typeof sumTotals>;

function OrdersTable({ rows }: { rows: any[] }) {
  return (
    <div className="overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Type</TableHead>
            <TableHead>Sous-type</TableHead>
            <TableHead>Produit</TableHead>
            <TableHead>Date</TableHead>
            <TableHead>Client</TableHead>
            <TableHead>Adresse</TableHead>
            <TableHead className="text-right">Prix</TableHead>
            <TableHead className="text-right">Frais</TableHead>
            <TableHead className="text-right">Argent</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((order) => {
            const firstItem = (order.items || [])[0];
            const prepayee = estPrepayee(order);
            return (
              <TableRow key={order.id}>
                <TableCell className="align-top">
                  {firstItem?.category_name || "-"}
                </TableCell>
                <TableCell className="align-top">
                  {firstItem?.type_name || "-"}
                </TableCell>
                <TableCell className="align-top max-w-[220px]">
                  {(order.items || [])
                    .map(
                      (it: any) =>
                        `${it.reference_name}${it.couleur ? ` (${it.couleur})` : ""} x${it.quantite}`,
                    )
                    .join(", ")}
                </TableCell>
                <TableCell className="align-top whitespace-nowrap text-xs text-muted-foreground">
                  {order.date_commande
                    ? new Date(order.date_commande).toLocaleString("fr-FR", {
                        timeZone: APP_TIME_ZONE,
                        day: "2-digit",
                        month: "2-digit",
                        hour: "2-digit",
                        minute: "2-digit",
                      })
                    : "-"}
                </TableCell>
                <TableCell className="align-top">{order.client_nom}</TableCell>
                <TableCell className="align-top max-w-[180px] truncate">
                  {order.adresse_livraison || "-"}
                </TableCell>
                <TableCell className="align-top text-right">
                  {fmt(prixProduit(order))}
                </TableCell>
                <TableCell className="align-top text-right">
                  {fmt(order.frais_livraison)}
                </TableCell>
                {/* Payée d'avance -> 0 Ar : le livreur n'a rien encaissé. */}
                <TableCell className="align-top text-right font-medium">
                  {fmt(argentEncaisse(order))}
                  {prepayee && (
                    <span className="block text-[11px] font-normal text-emerald-600 dark:text-emerald-400">
                      déjà payé
                    </span>
                  )}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}

function TicketBloc({
  titre,
  totals,
  variant,
}: {
  titre: string;
  totals: Totals;
  variant: "livrees" | "retours";
}) {
  return (
    <div
      className={
        variant === "retours"
          ? "space-y-1.5 border-t border-dashed pt-3"
          : "space-y-1.5"
      }
    >
      <p className="text-xs font-semibold text-muted-foreground">{titre}</p>
      <div className="flex justify-between">
        <span>Nombre</span>
        <span>{totals.count}</span>
      </div>

      {totals.prepayeCount > 0 && (
        <div className="flex justify-between text-emerald-600 dark:text-emerald-400">
          <span>Dont payé d&apos;avance ({totals.prepayeCount})</span>
          <span>-{fmt(totals.prepaye)}</span>
        </div>
      )}
      <div
        className={`border-t border-dashed pt-1.5 flex justify-between font-bold ${
          variant === "retours" ? "text-red-600" : ""
        }`}
      >
        <span>
          {variant === "retours" ? "TOTAL NON ENCAISSÉ" : "TOTAL ARGENT"}
        </span>
        <span>{fmt(totals.argent)}</span>
      </div>
    </div>
  );
}

const STATUT_DEPENSE: Record<string, { label: string; classe: string }> = {
  EN_ATTENTE: {
    label: "En attente",
    classe: "text-amber-600 dark:text-amber-400",
  },
  ACCEPTE: {
    label: "Acceptée",
    classe: "text-emerald-600 dark:text-emerald-400",
  },
  REJETE: { label: "Rejetée", classe: "text-red-600" },
};

/**
 * Dépenses de la journée (§ demande).
 *
 * Le LIVREUR en déclare (repas, carburant, enveloppes…) depuis les types
 * configurés dans Paramètres, ou en saisie libre. Elles partent en attente :
 * le gérant est notifié et tranche. Le GÉRANT, lui, voit ici les dépenses du
 * livreur consulté et les accepte ou les rejette. Seules les acceptées
 * viennent diminuer l'argent à remettre.
 */
function DepensesDuJour({
  depenses,
  jour,
  peutDeclarer,
  peutTrancher,
  onChanged,
}: {
  depenses: any[];
  jour: string;
  peutDeclarer: boolean;
  peutTrancher: boolean;
  onChanged: () => void;
}) {
  const [types, setTypes] = useState<any[]>([]);
  const [typeId, setTypeId] = useState<string>("LIBRE");
  const [libelle, setLibelle] = useState("");
  const [montant, setMontant] = useState("");
  const [quantite, setQuantite] = useState("1");
  const [motif, setMotif] = useState("");
  const [envoi, setEnvoi] = useState(false);

  useEffect(() => {
    if (!peutDeclarer) return;
    djangoClient.expenseTypes
      .list()
      .then((l) => setTypes(l.filter((t: any) => t.actif)))
      .catch(() => setTypes([]));
  }, [peutDeclarer]);

  // Choisir un type pré-remplit le libellé et le montant, qui restent
  // modifiables : le prix du catalogue n'est qu'une valeur par défaut.
  const choisirType = (value: string) => {
    setTypeId(value);
    const t = types.find((x) => String(x.id) === value);
    if (t) {
      setLibelle(t.nom);
      setMontant(String(t.prix_unitaire));
      setQuantite("1");
    }
  };

  const typeChoisi = types.find((x) => String(x.id) === typeId);
  const total = (Number(montant) || 0) * (Number(quantite) || 1);

  const declarer = async () => {
    if (!libelle.trim()) {
      toast.error("Indiquez la nature de la dépense.");
      return;
    }
    if (!(Number(montant) > 0)) {
      toast.error("Le montant doit être supérieur à 0.");
      return;
    }
    setEnvoi(true);
    try {
      await djangoClient.expenses.create({
        type_depense: typeChoisi ? typeChoisi.id : null,
        libelle: libelle.trim(),
        prix_unitaire: Number(montant),
        quantite: Number(quantite) || 1,
        motif: motif.trim(),
        date: jour,
      });
      toast.success("Dépense envoyée au gérant pour validation");
      setTypeId("LIBRE");
      setLibelle("");
      setMontant("");
      setQuantite("1");
      setMotif("");
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Envoi impossible");
    } finally {
      setEnvoi(false);
    }
  };

  const trancher = async (d: any, statut: "ACCEPTE" | "REJETE") => {
    try {
      await djangoClient.expenses.resoudre(d.id, statut);
      toast.success(
        statut === "ACCEPTE" ? "Dépense acceptée" : "Dépense rejetée",
      );
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Action impossible");
    }
  };

  const supprimer = async (d: any) => {
    try {
      await djangoClient.expenses.delete(d.id);
      toast.success("Dépense retirée");
      onChanged();
    } catch (err: any) {
      toast.error(err.message || "Suppression impossible");
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Wallet className="h-4 w-4" /> Dépenses ({depenses.length})
        </CardTitle>
        <CardDescription>
          {peutDeclarer
            ? "Déclarez vos frais de tournée : ils seront déduits de l'argent à remettre une fois validés par le gérant."
            : "Frais déclarés par le livreur. Seuls ceux que vous acceptez sont déduits de son bilan."}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {depenses.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-4">
            Aucune dépense ce jour-là.
          </p>
        ) : (
          <div className="space-y-2">
            {depenses.map((d) => {
              const st = STATUT_DEPENSE[d.statut] || STATUT_DEPENSE.EN_ATTENTE;
              return (
                <div key={d.id} className="border rounded-md px-3 py-2 text-sm">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium truncate">
                      {d.libelle}
                      {d.quantite > 1 ? ` x${d.quantite}` : ""}
                    </span>
                    <span className="font-semibold whitespace-nowrap">
                      {fmt(d.montant)}
                    </span>
                  </div>
                  <div className="flex items-center justify-between gap-2 mt-1">
                    <span className="text-xs text-muted-foreground truncate">
                      {d.motif || "Sans motif"}
                    </span>
                    <span className={`text-xs font-medium ${st.classe}`}>
                      {st.label}
                    </span>
                  </div>
                  {d.statut === "EN_ATTENTE" && (
                    <div className="flex gap-2 mt-2">
                      {peutTrancher && (
                        <>
                          <Button
                            size="sm"
                            className="flex-1"
                            onClick={() => trancher(d, "ACCEPTE")}
                          >
                            <Check className="h-4 w-4 mr-1" /> Accepter
                          </Button>
                          <Button
                            size="sm"
                            variant="outline"
                            className="flex-1 text-red-600"
                            onClick={() => trancher(d, "REJETE")}
                          >
                            <X className="h-4 w-4 mr-1" /> Rejeter
                          </Button>
                        </>
                      )}
                      {peutDeclarer && (
                        <Button
                          size="sm"
                          variant="ghost"
                          className="text-red-600"
                          onClick={() => supprimer(d)}
                        >
                          Retirer
                        </Button>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {peutDeclarer && (
          <div className="space-y-2 border-t pt-3">
            <Label className="text-xs text-muted-foreground">
              Nouvelle dépense
            </Label>
            <div className="flex flex-wrap gap-2">
              <select
                value={typeId}
                onChange={(e) => choisirType(e.target.value)}
                className="h-9 rounded-md border bg-background px-2 text-sm flex-1 min-w-[140px]"
              >
                <option value="LIBRE">Autre (saisie libre)</option>
                {types.map((t) => (
                  <option key={t.id} value={String(t.id)}>
                    {t.nom} — {fmt(t.prix_unitaire)}
                    {t.par_unite ? " /u" : ""}
                  </option>
                ))}
              </select>
              <Input
                placeholder="Nature (ex: Repas)"
                value={libelle}
                onChange={(e) => setLibelle(e.target.value)}
                className="flex-1 min-w-[140px]"
              />
            </div>
            <div className="flex flex-wrap gap-2">
              <Input
                type="number"
                min={0}
                placeholder="Montant (Ar)"
                value={montant}
                onChange={(e) => setMontant(e.target.value)}
                className="w-32"
              />
              {(typeChoisi?.par_unite || typeId === "LIBRE") && (
                <Input
                  type="number"
                  min={1}
                  placeholder="Quantité"
                  value={quantite}
                  onChange={(e) => setQuantite(e.target.value)}
                  className="w-28"
                />
              )}
              <span className="flex items-center text-sm text-muted-foreground">
                = {fmt(total)}
              </span>
            </div>
            <Input
              placeholder="Motif (pourquoi cette dépense ?)"
              value={motif}
              onChange={(e) => setMotif(e.target.value)}
            />
            <Button className="w-full" disabled={envoi} onClick={declarer}>
              <Plus className="h-4 w-4 mr-2" />
              {envoi ? "Envoi…" : "Envoyer au gérant"}
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

/** Bilan d'un jour pour un périmètre donné (un livreur, ou tous). */
function BilanJour({
  orders,
  loading,
  jour,
  titreTicket,
  depenses = [],
}: {
  orders: any[];
  loading: boolean;
  jour: string;
  titreTicket: string;
  /** Dépenses du livreur pour ce jour, tous statuts confondus. */
  depenses?: any[];
}) {
  // Seules les dépenses ACCEPTÉES par le gérant viennent diminuer l'argent
  // remis (§ demande) : une dépense en attente ou refusée ne doit pas
  // fausser le compte.
  const depensesAcceptees = useMemo(
    () => depenses.filter((d) => d.statut === "ACCEPTE"),
    [depenses],
  );
  const totalDepenses = useMemo(
    () => depensesAcceptees.reduce((s, d) => s + Number(d.montant || 0), 0),
    [depensesAcceptees],
  );
  // Les retours ne sont volontairement pas additionnés aux livrées (§ demande)
  // — un colis retourné n'a rien fait encaisser au livreur.
  const livrees = useMemo(
    () => orders.filter((o) => o.statut_courant === "LIVRE"),
    [orders],
  );
  const retours = useMemo(
    () => orders.filter((o) => o.statut_courant === "RETOUR"),
    [orders],
  );
  const totalLivrees = useMemo(() => sumTotals(livrees), [livrees]);
  const totalRetours = useMemo(() => sumTotals(retours), [retours]);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-[1fr_300px] gap-6">
      <div className="lg:sticky lg:top-6 self-start">
        <Card className="font-mono">
          <CardHeader className="text-center border-b border-dashed">
            <Receipt className="h-5 w-5 mx-auto mb-1 text-muted-foreground" />
            <CardTitle className="text-base tracking-wide">
              BILAN DU JOUR
            </CardTitle>
            <CardDescription className="space-y-0.5">
              {/* Offset explicite : sans lui la chaîne est lue dans le
                  fuseau de l'appareil puis reconvertie, ce qui peut
                  décaler l'affichage d'un jour. */}
              <span className="block">
                {fmtAppDate(`${jour}T12:00:00+03:00`)}
              </span>
              <span className="block font-semibold">{titreTicket}</span>
            </CardDescription>
          </CardHeader>
          <CardContent className="text-sm space-y-4 pt-4">
            <TicketBloc
              titre="LIVRAISONS EFFECTUÉES"
              totals={totalLivrees}
              variant="livrees"
            />
            {depensesAcceptees.length > 0 && (
              <div className="space-y-1.5 border-t border-dashed pt-3">
                <p className="text-xs font-semibold text-muted-foreground">
                  DÉPENSES VALIDÉES
                </p>
                {depensesAcceptees.map((d) => (
                  <div key={d.id} className="flex justify-between">
                    <span className="truncate pr-2">
                      {d.libelle}
                      {d.quantite > 1 ? ` x${d.quantite}` : ""}
                    </span>
                    <span>-{fmt(d.montant)}</span>
                  </div>
                ))}
                <div className="border-t border-dashed pt-1.5 flex justify-between font-bold">
                  <span>NET À REMETTRE</span>
                  <span>{fmt(totalLivrees.argent - totalDepenses)}</span>
                </div>
              </div>
            )}
            <TicketBloc
              titre="RETOURS (hors total ci-dessus)"
              totals={totalRetours}
              variant="retours"
            />
          </CardContent>
        </Card>
      </div>
      <div className="space-y-6 min-w-0">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <PackageCheck className="h-4 w-4" /> Livraisons effectuées (
              {livrees.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            {loading ? (
              <div className="p-6">
                <Skeleton className="h-32 w-full" />
              </div>
            ) : livrees.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-10">
                Aucune livraison effectuée ce jour-là.
              </p>
            ) : (
              <OrdersTable rows={livrees} />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Undo2 className="h-4 w-4 text-red-600" /> Retours (
              {retours.length})
            </CardTitle>
            <CardDescription>
              Colis rapportés — rien n&apos;a été encaissé, ces montants ne sont
              pas comptés dans le total du ticket.
            </CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            {loading ? (
              <div className="p-6">
                <Skeleton className="h-24 w-full" />
              </div>
            ) : retours.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-10">
                Aucun retour ce jour-là.
              </p>
            ) : (
              <OrdersTable rows={retours} />
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
/** Une ligne de la vue d'ensemble du gérant : un livreur et ses totaux du jour. */
type LigneLivreur = {
  key: string;
  nom: string;
  livrees: Totals;
  retours: Totals;
};

export default function BilanPage() {
  const { user, isLivreur, isGerant, loading: userLoading } = useCurrentUser();
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  // Le gérant choisit le jour ; le livreur reste sur aujourd'hui.
  const [jour, setJour] = useState(() => appToday());
  const [livreurs, setLivreurs] = useState<{ id: number; full_name: string }[]>(
    [],
  );
  // Gérant : null = vue d'ensemble (liste des livreurs) ; sinon le livreur
  // dont on regarde le détail. Le détail ne s'ouvre qu'au clic (§ demande).
  const [detailLivreur, setDetailLivreur] = useState<string | null>(null);

  useEffect(() => {
    if (!isGerant) return;
    djangoClient.orders
      .availableStaff("LIVREUR")
      .then(setLivreurs)
      .catch(() => setLivreurs([]));
  }, [isGerant]);

  // Changer de jour renvoie à la vue d'ensemble : le détail affiché ne
  // correspondrait plus à ce que montre la liste.
  useEffect(() => {
    setDetailLivreur(null);
  }, [jour]);

  const fetchOrders = useCallback(
    async (silent = false) => {
      if (!silent) setLoading(true);
      try {
        // Le livreur passe par son historique personnel (déjà scopé à lui
        // côté serveur) ; le gérant interroge toutes les commandes du jour.
        const filters = isGerant
          ? { date_debut: jour, date_fin: jour }
          : (() => {
              const { start, end } = appDayBounds(jour);
              return { historique: true, date_from: start, date_to: end };
            })();
        const data = await djangoClient.orders.list(filters as any);
        setOrders(data);
      } catch {
        setOrders([]);
      } finally {
        if (!silent) setLoading(false);
      }
    },
    [isGerant, jour],
  );

  // Dépenses du jour — le livreur ne reçoit que les siennes, le gérant
  // celles de tous ses magasins (filtrage côté serveur).
  const [depenses, setDepenses] = useState<any[]>([]);

  const fetchDepenses = useCallback(async () => {
    try {
      const data = await djangoClient.expenses.list({
        date_debut: jour,
        date_fin: jour,
      });
      setDepenses(data);
    } catch {
      setDepenses([]);
    }
  }, [jour]);

  useRealtimeRefresh(["order", "order_status_history"], () =>
    fetchOrders(true),
  );
  useEffect(() => {
    if (!userLoading && (isLivreur || isGerant)) {
      fetchOrders();
      fetchDepenses();
    }
  }, [userLoading, isLivreur, isGerant, fetchOrders, fetchDepenses]);

  // Seules les commandes terminées entrent dans un bilan.
  const traitees = useMemo(
    () =>
      orders.filter(
        (o) => o.statut_courant === "LIVRE" || o.statut_courant === "RETOUR",
      ),
    [orders],
  );

  const nomLivreur = useCallback(
    (key: string) => {
      if (key === "SANS") return "Retrait au comptoir (sans livreur)";
      return (
        livreurs.find((l) => String(l.id) === key)?.full_name ||
        traitees.find((o) => String(o.livreur) === key)?.livreur_name ||
        `Livreur #${key}`
      );
    },
    [livreurs, traitees],
  );

  /** Une ligne par livreur ayant travaillé ce jour-là, la plus grosse recette d'abord. */
  const lignes = useMemo<LigneLivreur[]>(() => {
    const groupes = new Map<string, any[]>();
    for (const o of traitees) {
      const key = o.livreur == null ? "SANS" : String(o.livreur);
      const rows = groupes.get(key);
      if (rows) rows.push(o);
      else groupes.set(key, [o]);
    }
    return [...groupes.entries()]
      .map(([key, rows]) => ({
        key,
        nom: nomLivreur(key),
        livrees: sumTotals(rows.filter((o) => o.statut_courant === "LIVRE")),
        retours: sumTotals(rows.filter((o) => o.statut_courant === "RETOUR")),
      }))
      .sort((a, b) => b.livrees.argent - a.livrees.argent);
  }, [traitees, nomLivreur]);

  const totalJour = useMemo(
    () => ({
      livrees: sumTotals(traitees.filter((o) => o.statut_courant === "LIVRE")),
      retours: sumTotals(traitees.filter((o) => o.statut_courant === "RETOUR")),
    }),
    [traitees],
  );

  const depensesDuDetail = useMemo(
    () =>
      detailLivreur
        ? depenses.filter((d) => String(d.livreur) === detailLivreur)
        : [],
    [depenses, detailLivreur],
  );

  const ordersDuDetail = useMemo(
    () =>
      detailLivreur
        ? traitees.filter(
            (o) =>
              (o.livreur == null ? "SANS" : String(o.livreur)) ===
              detailLivreur,
          )
        : [],
    [traitees, detailLivreur],
  );

  if (!userLoading && !isLivreur && !isGerant) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-20 text-center">
            <ShieldAlert className="h-12 w-12 text-red-500 mb-4" />
            <h2 className="text-xl font-bold">Accès refusé</h2>
            <p className="text-muted-foreground mt-2">
              Cette page est réservée au livreur et au gérant.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Bilan du jour</h1>
          <p className="text-sm text-muted-foreground">
            {isGerant
              ? "Montant encaissé par chaque livreur. Cliquez sur un livreur pour voir le détail de ses commandes."
              : "Livraisons effectuées et retours d'aujourd'hui — voir le ticket récapitulatif."}
          </p>
        </div>
        <div className="flex items-end gap-2">
          {isGerant && (
            <div className="space-y-1">
              <Label className="text-xs text-muted-foreground">Jour</Label>
              <Input
                type="date"
                value={jour}
                onChange={(e) => setJour(e.target.value || appToday())}
                className="w-auto"
              />
            </div>
          )}
          <Button
            variant="outline"
            size="icon"
            onClick={() => {
              fetchOrders();
              fetchDepenses();
            }}
          >
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Livreur : son propre bilan, directement. */}
      {!isGerant && (
        <div className="space-y-6">
          <BilanJour
            orders={traitees}
            loading={loading}
            jour={jour}
            titreTicket={user?.full_name || "Mon bilan"}
            depenses={depenses}
          />
          <DepensesDuJour
            depenses={depenses}
            jour={jour}
            peutDeclarer
            peutTrancher={false}
            onChanged={fetchDepenses}
          />
        </div>
      )}

      {/* Gérant, vue d'ensemble : uniquement la liste des livreurs et leurs totaux. */}
      {isGerant && !detailLivreur && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <Card>
              <CardHeader className="pb-2">
                <CardDescription>Livraisons effectuées</CardDescription>
                <CardTitle className="text-2xl">
                  {totalJour.livrees.count}
                </CardTitle>
              </CardHeader>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardDescription>Total encaissé</CardDescription>
                <CardTitle className="text-2xl">
                  {fmt(totalJour.livrees.argent)}
                </CardTitle>
              </CardHeader>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardDescription>Retours</CardDescription>
                <CardTitle className="text-2xl text-red-600">
                  {totalJour.retours.count}
                </CardTitle>
              </CardHeader>
            </Card>
          </div>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Users className="h-4 w-4" /> Livreurs du{" "}
                {fmtAppDate(`${jour}T12:00:00+03:00`)}
              </CardTitle>
              <CardDescription>
                Cliquez sur une ligne pour ouvrir le détail : toutes les
                commandes, tous les produits et tous les totaux.
              </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6">
                  <Skeleton className="h-32 w-full" />
                </div>
              ) : lignes.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-10">
                  Aucune livraison ni retour ce jour-là.
                </p>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Livreur</TableHead>
                        <TableHead className="text-right">Livraisons</TableHead>
                        <TableHead className="text-right">Retours</TableHead>
                        <TableHead className="text-right">
                          Total produits
                        </TableHead>
                        <TableHead className="text-right">
                          Total frais
                        </TableHead>
                        <TableHead className="text-right">Dépenses</TableHead>
                        <TableHead className="text-right">
                          Total encaissé
                        </TableHead>
                        <TableHead className="w-10" />
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {lignes.map((l) => (
                        <TableRow
                          key={l.key}
                          className="cursor-pointer"
                          onClick={() => setDetailLivreur(l.key)}
                        >
                          <TableCell className="font-medium">{l.nom}</TableCell>
                          <TableCell className="text-right">
                            {l.livrees.count}
                          </TableCell>
                          <TableCell className="text-right text-red-600">
                            {l.retours.count || "-"}
                          </TableCell>
                          <TableCell className="text-right">
                            {fmt(l.livrees.prix)}
                          </TableCell>
                          <TableCell className="text-right">
                            {fmt(l.livrees.frais)}
                          </TableCell>
                          <TableCell className="text-right">
                            {(() => {
                              const sien = depenses.filter(
                                (d) => String(d.livreur) === l.key,
                              );
                              const attente = sien.filter(
                                (d) => d.statut === "EN_ATTENTE",
                              ).length;
                              const valide = sien
                                .filter((d) => d.statut === "ACCEPTE")
                                .reduce(
                                  (s, d) => s + Number(d.montant || 0),
                                  0,
                                );
                              if (!sien.length)
                                return (
                                  <span className="text-muted-foreground">
                                    -
                                  </span>
                                );
                              return (
                                <>
                                  {valide > 0 && <span>-{fmt(valide)}</span>}
                                  {attente > 0 && (
                                    <span className="block text-[11px] font-medium text-amber-600 dark:text-amber-400">
                                      {attente} à valider
                                    </span>
                                  )}
                                </>
                              );
                            })()}
                          </TableCell>
                          <TableCell className="text-right font-semibold">
                            {fmt(l.livrees.argent)}
                            {l.livrees.prepayeCount > 0 && (
                              <span className="block text-[11px] font-normal text-emerald-600 dark:text-emerald-400">
                                dont {fmt(l.livrees.prepaye)} déjà payé
                              </span>
                            )}
                          </TableCell>
                          <TableCell className="text-muted-foreground">
                            <ChevronRight className="h-4 w-4" />
                          </TableCell>
                        </TableRow>
                      ))}
                      <TableRow className="bg-muted/40 font-semibold">
                        <TableCell>Total du jour</TableCell>
                        <TableCell className="text-right">
                          {totalJour.livrees.count}
                        </TableCell>
                        <TableCell className="text-right text-red-600">
                          {totalJour.retours.count || "-"}
                        </TableCell>
                        <TableCell className="text-right">
                          {fmt(totalJour.livrees.prix)}
                        </TableCell>
                        <TableCell className="text-right">
                          {fmt(totalJour.livrees.frais)}
                        </TableCell>
                        <TableCell className="text-right">
                          {(() => {
                            const valide = depenses
                              .filter((d) => d.statut === "ACCEPTE")
                              .reduce((s, d) => s + Number(d.montant || 0), 0);
                            return valide > 0 ? `-${fmt(valide)}` : "-";
                          })()}
                        </TableCell>
                        <TableCell className="text-right">
                          {fmt(totalJour.livrees.argent)}
                        </TableCell>
                        <TableCell />
                      </TableRow>
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {/* Gérant, détail d'un livreur : tout le contenu, comme le voit le livreur. */}
      {isGerant && detailLivreur && (
        <div className="space-y-4">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setDetailLivreur(null)}
          >
            <ArrowLeft className="h-4 w-4 mr-2" /> Tous les livreurs
          </Button>
          <h2 className="text-lg font-semibold">{nomLivreur(detailLivreur)}</h2>
          <BilanJour
            orders={ordersDuDetail}
            loading={loading}
            jour={jour}
            titreTicket={nomLivreur(detailLivreur)}
            depenses={depensesDuDetail}
          />
          <DepensesDuJour
            depenses={depensesDuDetail}
            jour={jour}
            peutDeclarer={false}
            peutTrancher
            onChanged={fetchDepenses}
          />
        </div>
      )}
    </div>
  );
}
