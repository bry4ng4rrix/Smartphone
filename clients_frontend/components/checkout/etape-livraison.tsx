"use client";

import { useId } from "react";
import { ArrowLeft, ArrowRight, Store, Truck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input, Textarea } from "@/components/ui/field";
import { formatAr, cn } from "@/lib/utils";
import type { Erreurs, ModeRemise, Remise } from "@/lib/commande";

function Choix({
  actif,
  icone: Icone,
  titre,
  detail,
  prix,
  onClick,
}: {
  actif: boolean;
  icone: typeof Truck;
  titre: string;
  detail: string;
  prix: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={actif}
      className={cn(
        "flex w-full items-start gap-3 rounded-xl border p-4 text-left transition-colors",
        actif ? "border-accent/60 bg-accent/[0.06]" : "border-border hover:border-foreground/25 hover:bg-foreground/[0.03]",
      )}
    >
      <span
        className={cn(
          "mt-0.5 grid size-9 shrink-0 place-items-center rounded-full",
          actif ? "bg-accent text-accent-foreground" : "bg-foreground/[0.06] text-muted",
        )}
      >
        <Icone className="size-4" aria-hidden />
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex flex-wrap items-baseline justify-between gap-2">
          <span className="text-sm font-medium">{titre}</span>
          <span className="text-sm font-semibold tabular-nums">{prix}</span>
        </span>
        <span className="mt-0.5 block text-xs text-muted">{detail}</span>
      </span>
    </button>
  );
}

/**
 * Étape 2 — où et comment recevoir.
 *
 * `prixLivraison` vient de l'API (`GET /api/boutiques/{id}/zones/`), jamais
 * d'une constante du front : c'est le serveur qui fixe le tarif, et c'est lui
 * qui l'appliquera à la commande.
 */
export function EtapeLivraison({
  valeurs,
  erreurs,
  prixLivraison,
  onChange,
  onSuivant,
  onRetour,
}: {
  valeurs: Remise;
  erreurs: Erreurs;
  prixLivraison: number | null;
  onChange: (maj: Partial<Remise>) => void;
  onSuivant: () => void;
  onRetour: () => void;
}) {
  const idAdresse = useId();
  const idNote = useId();

  const choisir = (mode: ModeRemise) => onChange({ mode });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSuivant();
      }}
      noValidate
      className="hairline rounded-xl bg-surface/50 p-5 sm:p-6"
    >
      <h2 className="text-base font-medium tracking-tight">Livraison</h2>
      <p className="mt-1.5 text-sm text-muted">Comment souhaitez-vous recevoir votre commande ?</p>

      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <Choix
          actif={valeurs.mode === "EN_LIGNE"}
          icone={Truck}
          titre="Livraison"
          detail="Livrée à l'adresse que vous indiquez."
          prix={prixLivraison === null ? "—" : formatAr(prixLivraison)}
          onClick={() => choisir("EN_LIGNE")}
        />
        <Choix
          actif={valeurs.mode === "RECUPERATION"}
          icone={Store}
          titre="Retrait sur place"
          detail="À récupérer directement en boutique."
          prix="Gratuit"
          onClick={() => choisir("RECUPERATION")}
        />
      </div>

      {valeurs.mode === "EN_LIGNE" ? (
        <div className="mt-5">
          <Field
            label="Adresse de livraison"
            htmlFor={idAdresse}
            aide="Quartier, lot, point de repère — le plus précis possible."
            erreurs={erreurs.adresse ? [erreurs.adresse] : undefined}
          >
            <Input
              id={idAdresse}
              value={valeurs.adresse}
              onChange={(e) => onChange({ adresse: e.target.value })}
              autoComplete="street-address"
              placeholder="Lot II A 15 Ambohipo, près de l'école"
              required
            />
          </Field>
        </div>
      ) : null}

      <div className="mt-5">
        <Field label="Précision pour la boutique (facultatif)" htmlFor={idNote}>
          <Textarea
            id={idNote}
            value={valeurs.note}
            onChange={(e) => onChange({ note: e.target.value })}
            rows={3}
            placeholder="Heure à laquelle vous joindre, indication d'accès…"
          />
        </Field>
      </div>

      <div className="mt-6 flex flex-col gap-2 sm:flex-row-reverse sm:justify-start">
        <Button type="submit" variant="primaire" size="lg">
          Continuer
          <ArrowRight aria-hidden />
        </Button>
        <Button type="button" variant="contour" size="lg" onClick={onRetour}>
          <ArrowLeft aria-hidden />
          Retour
        </Button>
      </div>
    </form>
  );
}
