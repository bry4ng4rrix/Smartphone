"use client";

import { useId } from "react";
import { Search, TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import type { ModeleTelephone } from "@/lib/compatibilite";
import type { Marque } from "@/lib/types";

/**
 * Étape 1 du parcours : « pour quel téléphone ? ».
 *
 * Le modèle se choisit dans une liste (`<datalist>`) tout en restant
 * saisissable : la boutique ne référence pas forcément tous les téléphones
 * du marché, et un client dont le modèle manque doit pouvoir aller jusqu'à
 * la commande spéciale plutôt que se heurter à un menu fermé.
 */
export function PhoneSelector({
  libelle,
  marques,
  marqueId,
  onMarqueChange,
  modele,
  onModeleChange,
  modeles,
  chargement,
  erreur,
  onReessayer,
  onRechercher,
}: {
  libelle: string;
  marques: Marque[];
  marqueId: number | null;
  onMarqueChange: (id: number | null) => void;
  modele: string;
  onModeleChange: (valeur: string) => void;
  modeles: ModeleTelephone[];
  chargement: boolean;
  erreur: string | null;
  onReessayer: () => void;
  onRechercher: () => void;
}) {
  const idMarque = useId();
  const idModele = useId();
  const idListe = useId();

  const pret = marqueId !== null && modele.trim().length > 0;

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (pret) onRechercher();
      }}
      className="hairline rounded-xl bg-surface/60 p-5 sm:p-7"
    >
      <h2 className="text-lg font-medium tracking-tight sm:text-xl">
        Trouvez le {libelle.toLowerCase()} adapté à votre téléphone
      </h2>
      <p className="mt-1.5 text-sm text-muted">
        Indiquez votre téléphone : nous n&apos;affichons que les produits réellement compatibles.
      </p>

      <div className="mt-6 grid gap-4 sm:grid-cols-2">
        <Field label="Marque du téléphone" htmlFor={idMarque}>
          <Select
            id={idMarque}
            value={marqueId ?? ""}
            onChange={(e) => onMarqueChange(e.target.value ? Number(e.target.value) : null)}
          >
            <option value="">Sélectionner une marque</option>
            {marques.map((m) => (
              <option key={m.id} value={m.id}>
                {m.nom}
              </option>
            ))}
          </Select>
        </Field>

        <Field
          label="Modèle / Référence"
          htmlFor={idModele}
          aide={
            marqueId === null
              ? "Choisissez d'abord une marque."
              : chargement
                ? "Chargement des modèles…"
                : modeles.length
                  ? `${modeles.length} modèle${modeles.length > 1 ? "s" : ""} référencé${modeles.length > 1 ? "s" : ""} — ou saisissez le vôtre.`
                  : "Aucun modèle référencé : saisissez le vôtre."
          }
        >
          {chargement ? (
            <Skeleton className="h-11 w-full" />
          ) : (
            <>
              <Input
                id={idModele}
                list={idListe}
                value={modele}
                onChange={(e) => onModeleChange(e.target.value)}
                disabled={marqueId === null}
                placeholder="Galaxy A15, iPhone 13, Redmi Note 13…"
                autoComplete="off"
              />
              <datalist id={idListe}>
                {modeles.map((m) => (
                  <option key={m.nom} value={m.nom} />
                ))}
              </datalist>
            </>
          )}
        </Field>
      </div>

      {erreur ? (
        <div role="alert" className="mt-4 flex flex-wrap items-center gap-3 text-sm text-rose-600 dark:text-rose-400">
          <TriangleAlert className="size-4 shrink-0" aria-hidden />
          <span className="min-w-0 flex-1">{erreur}</span>
          <Button type="button" variant="contour" size="sm" onClick={onReessayer}>
            Réessayer
          </Button>
        </div>
      ) : null}

      <div className="mt-6">
        <Button type="submit" variant="accent" size="lg" disabled={!pret} className="w-full sm:w-auto">
          <Search aria-hidden />
          Rechercher
        </Button>
      </div>
    </form>
  );
}
