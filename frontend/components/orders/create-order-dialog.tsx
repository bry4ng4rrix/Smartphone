"use client";

/**
 * Dialogue « Nouvelle commande » — source UNIQUE.
 *
 * Il était auparavant écrit deux fois : une fois dans la page Commandes, une
 * fois dans la page Produits. Les deux copies avaient déjà divergé (libellés,
 * champs). Elles sont désormais le même composant, donc toute évolution
 * profite aux deux points d'entrée sans risque d'écart.
 */

import React, { useEffect, useMemo, useState } from "react";
import { djangoClient } from "@/lib/django-client";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { useDeliveryZones } from "@/lib/hooks/useDeliveryZones";
import { DateTimeInput } from "@/components/ui/datetime-input";
import { appDatetimeLocalValue, appDatetimeLocalToIso } from "@/lib/timezone";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
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
import { Package, Plus, Trash2, Truck } from "lucide-react";
import { toast } from "sonner";

export const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat("fr-MG").format(Math.round(Number(n || 0))) + " Ar";

// Zones de livraison : configurables dans Paramètres (CRUD nom+prix — voir
// useDeliveryZones/DeliveryZoneOption), plus le littéral "RECUPERATION"
// toujours présent (retrait sur place, structurellement à part : pas de
// livreur, pas de frais).
export function buildZoneOptions(
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

export const MODE_PAIEMENT = [
  { value: "AVANT", label: "Payé" },
  { value: "LIVRAISON", label: "Paiement à la livraison" },
];

export interface CartItem {
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

export function OrderItemsEditor({
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

export function CreateOrderDialog({
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
  // Second numéro facultatif — le client donne souvent un numéro de secours,
  // ou celui de la personne qui réceptionne à sa place (§ demande).
  const [telephone2, setTelephone2] = useState("");
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
  // Campagne marketing d'origine (facultatif) — alimente le rapport Marketing.
  const [campagnes, setCampagnes] = useState<{ id: number; nom: string; plateforme_label: string }[]>([]);
  const [campagneId, setCampagneId] = useState("");

  useEffect(() => {
    if (!open) return;
    if (!isPreparateur) {
      djangoClient.orders
        .availableStaff("PREPARATEUR")
        .then(setPreparateurs)
        .catch(() => setPreparateurs([]));
      djangoClient.campaigns
        .list({ actif: true })
        .then(setCampagnes)
        .catch(() => setCampagnes([]));
    }
    setCampagneId("");
    setClientNom("");
    setTelephone("+261");
    setTelephone2("");
    setZone(isPreparateur ? "RECUPERATION" : "");
    setAdresseLivraison("");
    setModePaiement("LIVRAISON");
    setDateCommande(appDatetimeLocalValue(new Date()));
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
    // Le second numéro est facultatif, mais s'il est saisi il doit être au
    // même format — sinon le serveur le refuserait après coup.
    if (telephone2.trim() && !/^\+261\d{9}$/.test(telephone2.trim())) {
      toast.error("Autre téléphone au format +261XXXXXXXXX");
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
        telephone_2: telephone2.trim(),
        livraison_zone: zone as any,
        adresse_livraison: adresseLivraison.trim(),
        mode_paiement: modePaiement as any,
        ...(campagneId ? { campagne: Number(campagneId) } : {}),
        // Champ vidé par l'utilisateur -> pas envoyé -> le serveur prend "maintenant" (heure précise).
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
      <DialogContent className="max-w-2xl">
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
          <DateTimeInput value={dateCommande} onChange={setDateCommande} />
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

        {!isPreparateur && campagnes.length > 0 && (
          <div className="space-y-2">
            <Label>Campagne marketing (facultatif)</Label>
            <Select value={campagneId || "NONE"} onValueChange={(v) => setCampagneId(v === "NONE" ? "" : v)}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Aucune" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="NONE">Aucune</SelectItem>
                {campagnes.map((c) => (
                  <SelectItem key={c.id} value={String(c.id)}>
                    {c.nom} · {c.plateforme_label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
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
          <div className="space-y-2">
            <Label>Autre téléphone (optionnel)</Label>
            <Input
              value={telephone2}
              onChange={(e) => setTelephone2(e.target.value)}
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
