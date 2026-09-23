"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useMemo, useState } from "react";
import { SlidersHorizontal, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ColorDot } from "@/components/ui/color-dot";
import { Panel } from "@/components/ui/panel";
import { Field, Select } from "@/components/ui/field";
import { cn } from "@/lib/utils";
import type { Categorie, Couleur, Marque, SousType } from "@/lib/types";

export type Referentiels = {
  categories: Categorie[];
  sousTypes: SousType[];
  marques: Marque[];
  couleurs: Couleur[];
};

/** Paramètres réellement acceptés par `GET /api/produit/`. */
const CLES = ["search", "category", "sous_type", "brand", "couleur", "available"] as const;
type Cle = (typeof CLES)[number];

function useFiltres() {
  const router = useRouter();
  const params = useSearchParams();

  const valeurs = useMemo(() => {
    const v: Partial<Record<Cle, string>> = {};
    for (const cle of CLES) {
      const valeur = params.get(cle);
      if (valeur) v[cle] = valeur;
    }
    return v;
  }, [params]);

  const appliquer = useCallback(
    (modifs: Partial<Record<Cle, string | null>>) => {
      const suivant = new URLSearchParams(params.toString());
      for (const [cle, valeur] of Object.entries(modifs)) {
        if (valeur) suivant.set(cle, valeur);
        else suivant.delete(cle);
      }
      // Un changement de filtre repart de la première page.
      suivant.delete("page");
      // Le sous-type appartient à une catégorie : changer de catégorie l'invalide.
      if ("category" in modifs) suivant.delete("sous_type");
      router.push(`/catalogue${suivant.size ? `?${suivant}` : ""}`, { scroll: false });
    },
    [params, router],
  );

  const reinitialiser = useCallback(() => router.push("/catalogue", { scroll: false }), [router]);

  return { valeurs, appliquer, reinitialiser, nbActifs: Object.keys(valeurs).length };
}

function Groupe({ titre, children }: { titre: string; children: React.ReactNode }) {
  return (
    <fieldset className="border-t border-border/70 py-5 first:border-t-0 first:pt-0">
      <legend className="mb-3 text-[11px] font-medium tracking-[0.18em] text-muted uppercase">{titre}</legend>
      {children}
    </fieldset>
  );
}

function Puce({ actif, children, ...props }: React.ComponentProps<"button"> & { actif?: boolean }) {
  return (
    <button
      type="button"
      aria-pressed={actif}
      className={cn(
        "rounded-full px-3 py-1.5 text-[13px] transition-all duration-200",
        actif ? "bg-foreground text-background" : "hairline text-muted hover:text-foreground",
      )}
      {...props}
    >
      {children}
    </button>
  );
}

export function FiltresContenu({ referentiels }: { referentiels: Referentiels }) {
  const { valeurs, appliquer, reinitialiser, nbActifs } = useFiltres();
  const { categories, sousTypes, marques, couleurs } = referentiels;

  const categorieActive = valeurs.category ? Number(valeurs.category) : null;
  const sousTypesVisibles = categorieActive ? sousTypes.filter((s) => s.categorie === categorieActive) : sousTypes;

  return (
    <div>
      {nbActifs > 0 ? (
        <div className="mb-4 flex items-center justify-between gap-2">
          <p className="text-xs text-muted">
            {nbActifs} filtre{nbActifs > 1 ? "s" : ""} actif{nbActifs > 1 ? "s" : ""}
          </p>
          <button type="button" onClick={reinitialiser} className="inline-flex items-center gap-1 text-xs text-accent hover:underline">
            <X className="size-3" aria-hidden /> Tout effacer
          </button>
        </div>
      ) : null}

      <Groupe titre="Catégorie">
        <div className="flex flex-wrap gap-1.5">
          <Puce actif={!valeurs.category} onClick={() => appliquer({ category: null })}>
            Toutes
          </Puce>
          {categories.map((c) => (
            <Puce key={c.id} actif={valeurs.category === String(c.id)} onClick={() => appliquer({ category: String(c.id) })}>
              {c.nom}
            </Puce>
          ))}
        </div>
      </Groupe>

      {sousTypesVisibles.length > 0 ? (
        <Groupe titre="Sous-type">
          <div className="flex flex-wrap gap-1.5">
            <Puce actif={!valeurs.sous_type} onClick={() => appliquer({ sous_type: null })}>
              Tous
            </Puce>
            {sousTypesVisibles.map((s) => (
              <Puce key={s.id} actif={valeurs.sous_type === String(s.id)} onClick={() => appliquer({ sous_type: String(s.id) })}>
                {s.nom}
              </Puce>
            ))}
          </div>
        </Groupe>
      ) : null}

      {marques.length > 0 ? (
        <Groupe titre="Marque">
          <Field label="Marque" htmlFor="filtre-marque" className="[&>label]:sr-only">
            <Select
              id="filtre-marque"
              value={valeurs.brand ?? ""}
              onChange={(e) => appliquer({ brand: e.target.value || null })}
            >
              <option value="">Toutes les marques</option>
              {marques.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.nom}
                </option>
              ))}
            </Select>
          </Field>
        </Groupe>
      ) : null}

      {couleurs.length > 0 ? (
        <Groupe titre="Couleur">
          <div className="flex flex-wrap gap-1.5">
            <Puce actif={!valeurs.couleur} onClick={() => appliquer({ couleur: null })}>
              Toutes
            </Puce>
            {couleurs.map((c) => (
              <Puce
                key={c.id}
                actif={valeurs.couleur === c.nom}
                onClick={() => appliquer({ couleur: valeurs.couleur === c.nom ? null : c.nom })}
                className={cn(
                  "inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[13px] transition-all duration-200",
                  valeurs.couleur === c.nom ? "bg-foreground text-background" : "hairline text-muted hover:text-foreground",
                )}
              >
                <ColorDot nom={c.nom} className="size-2.5" />
                {c.nom}
              </Puce>
            ))}
          </div>
        </Groupe>
      ) : null}

      <Groupe titre="Disponibilité">
        <label className="flex cursor-pointer items-center gap-2.5 text-sm">
          <input
            type="checkbox"
            checked={valeurs.available === "1"}
            onChange={(e) => appliquer({ available: e.target.checked ? "1" : null })}
            className="size-4 rounded border-border accent-[var(--accent)]"
          />
          Uniquement les produits disponibles
        </label>
      </Groupe>
    </div>
  );
}

/** Bouton + feuille de filtres sur mobile (pas de sidebar sous 1024px). */
export function FiltresMobile({ referentiels, nbResultats }: { referentiels: Referentiels; nbResultats: number }) {
  const [ouvert, setOuvert] = useState(false);
  const { nbActifs } = useFiltres();

  return (
    <>
      <Button variant="verre" size="sm" onClick={() => setOuvert(true)} className="lg:hidden">
        <SlidersHorizontal aria-hidden />
        Filtres
        {nbActifs > 0 ? (
          <span className="ml-0.5 grid size-5 place-items-center rounded-full bg-accent text-[10px] font-semibold text-accent-foreground">
            {nbActifs}
          </span>
        ) : null}
      </Button>

      <Panel
        ouvert={ouvert}
        onOuvertChange={setOuvert}
        titre="Filtres"
        description={`${nbResultats} produit${nbResultats > 1 ? "s" : ""}`}
        cote="bas"
        pied={
          <Button variant="primaire" className="w-full" onClick={() => setOuvert(false)}>
            Voir les résultats
          </Button>
        }
      >
        <FiltresContenu referentiels={referentiels} />
      </Panel>
    </>
  );
}
