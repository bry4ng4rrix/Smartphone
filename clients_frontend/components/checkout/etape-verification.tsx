"use client";

import { ArrowLeft, ArrowRight, Minus, Pencil, Plus, Trash2 } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { formatAr, pluriel } from "@/lib/utils";
import type { Coordonnees, Remise } from "@/lib/commande";
import type { LignePanier } from "@/providers/cart-provider";

function Bloc({
  titre,
  onModifier,
  children,
}: {
  titre: string;
  onModifier?: () => void;
  children: React.ReactNode;
}) {
  return (
    <section className="border-t border-border/70 py-5 first:border-t-0 first:pt-0">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h3 className="text-[11px] font-medium tracking-[0.18em] text-muted uppercase">{titre}</h3>
        {onModifier ? (
          <button
            type="button"
            onClick={onModifier}
            className="inline-flex items-center gap-1.5 text-xs text-accent transition-opacity hover:underline"
          >
            <Pencil className="size-3" aria-hidden />
            Modifier
          </button>
        ) : null}
      </div>
      {children}
    </section>
  );
}

function Ligne({ libelle, valeur }: { libelle: string; valeur: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-1">
      <dt className="text-sm text-muted">{libelle}</dt>
      <dd className="text-right text-sm font-medium">{valeur || "—"}</dd>
    </div>
  );
}

/**
 * Étape 3 — tout relire, tout corriger.
 *
 * Rien n'est figé : les quantités se changent ici même, et chaque bloc
 * renvoie à l'étape qui l'a saisi. C'est le dernier écran où l'on modifie ;
 * la suite ne fait plus que confirmer.
 */
export function EtapeVerification({
  lignes,
  coordonnees,
  remise,
  sousTotal,
  fraisLivraison,
  onQuantite,
  onRetirer,
  onModifierCoordonnees,
  onModifierLivraison,
  onSuivant,
  onRetour,
}: {
  lignes: LignePanier[];
  coordonnees: Coordonnees;
  remise: Remise;
  sousTotal: number;
  fraisLivraison: number;
  onQuantite: (varianteId: number, quantite: number) => void;
  onRetirer: (varianteId: number) => void;
  onModifierCoordonnees: () => void;
  onModifierLivraison: () => void;
  onSuivant: () => void;
  onRetour: () => void;
}) {
  const total = sousTotal + fraisLivraison;

  return (
    <div className="hairline rounded-xl bg-surface/50 p-5 sm:p-6">
      <h2 className="text-base font-medium tracking-tight">Vérifiez votre commande</h2>
      <p className="mt-1.5 text-sm text-muted">
        Relisez chaque ligne. Tout reste modifiable à cette étape.
      </p>

      <div className="mt-6">
        <Bloc titre="Articles">
          {lignes.length === 0 ? (
            <p className="text-sm text-muted">
              Votre panier est vide.{" "}
              <Link href="/catalogue" className="text-accent hover:underline">
                Retourner au catalogue
              </Link>
              .
            </p>
          ) : (
            <ul className="divide-y divide-border/70">
              {lignes.map((l) => (
                <li key={l.varianteId} className="flex flex-wrap items-center gap-3 py-3 first:pt-0">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{l.nomComplet}</p>
                    <p className="text-xs text-muted">
                      {l.couleur} · {formatAr(l.prix)} l&apos;unité
                    </p>
                  </div>

                  <div className="flex items-center gap-1">
                    <Button
                      type="button"
                      variant="contour"
                      size="icone_sm"
                      onClick={() => onQuantite(l.varianteId, l.quantite - 1)}
                      disabled={l.quantite <= 1}
                      aria-label={`Retirer un ${l.nomComplet}`}
                    >
                      <Minus aria-hidden />
                    </Button>
                    <span className="w-8 text-center text-sm font-medium tabular-nums" aria-live="polite">
                      {l.quantite}
                    </span>
                    <Button
                      type="button"
                      variant="contour"
                      size="icone_sm"
                      onClick={() => onQuantite(l.varianteId, l.quantite + 1)}
                      aria-label={`Ajouter un ${l.nomComplet}`}
                    >
                      <Plus aria-hidden />
                    </Button>
                  </div>

                  <p className="w-24 text-right text-sm font-semibold tabular-nums">
                    {formatAr(l.prix * l.quantite)}
                  </p>

                  <Button
                    type="button"
                    variant="fantome"
                    size="icone_sm"
                    onClick={() => onRetirer(l.varianteId)}
                    aria-label={`Retirer ${l.nomComplet} du panier`}
                  >
                    <Trash2 aria-hidden />
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </Bloc>

        <Bloc titre="Vos coordonnées" onModifier={onModifierCoordonnees}>
          <dl>
            <Ligne libelle="Nom" valeur={coordonnees.nom} />
            <Ligne libelle="Téléphone" valeur={coordonnees.telephone} />
            <Ligne libelle="Autre numéro" valeur={coordonnees.telephone2} />
          </dl>
        </Bloc>

        <Bloc titre="Livraison" onModifier={onModifierLivraison}>
          <dl>
            <Ligne
              libelle="Mode"
              valeur={remise.mode === "EN_LIGNE" ? "Livraison à domicile" : "Retrait sur place"}
            />
            {remise.mode === "EN_LIGNE" ? <Ligne libelle="Adresse" valeur={remise.adresse} /> : null}
            {remise.note ? <Ligne libelle="Précision" valeur={remise.note} /> : null}
          </dl>
        </Bloc>

        <Bloc titre="Montant">
          <dl>
            <Ligne
              libelle={`Sous-total (${lignes.reduce((n, l) => n + l.quantite, 0)} ${pluriel(
                lignes.reduce((n, l) => n + l.quantite, 0),
                "article",
              )})`}
              valeur={formatAr(sousTotal)}
            />
            <Ligne
              libelle="Frais de livraison"
              valeur={remise.mode === "RECUPERATION" ? "Gratuit" : formatAr(fraisLivraison)}
            />
            <div className="mt-2 flex items-baseline justify-between gap-4 border-t border-border/70 pt-3">
              <dt className="text-sm font-medium">Total à payer</dt>
              <dd className="text-lg font-semibold tracking-tight tabular-nums">{formatAr(total)}</dd>
            </div>
          </dl>
          <p className="mt-2 text-xs text-muted">
            Le montant définitif est confirmé par la boutique lors de son appel.
          </p>
        </Bloc>
      </div>

      <div className="mt-6 flex flex-col gap-2 sm:flex-row-reverse sm:justify-start">
        <Button
          type="button"
          variant="primaire"
          size="lg"
          onClick={onSuivant}
          disabled={lignes.length === 0}
        >
          Tout est correct
          <ArrowRight aria-hidden />
        </Button>
        <Button type="button" variant="contour" size="lg" onClick={onRetour}>
          <ArrowLeft aria-hidden />
          Retour
        </Button>
      </div>
    </div>
  );
}
