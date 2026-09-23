"use client";

import { Info } from "lucide-react";
import { formatAr, formatDate } from "@/lib/utils";
import {
  DELAI_COMMANDE_SPECIALE_JOURS,
  TAUX_ACOMPTE,
  dateEstimee,
  repartirAcompte,
} from "@/lib/compatibilite";

function Ligne({ libelle, valeur, fort = false }: { libelle: string; valeur: string; fort?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-2">
      <dt className="text-sm text-muted">{libelle}</dt>
      <dd className={fort ? "text-[15px] font-semibold tracking-tight tabular-nums" : "text-sm tabular-nums"}>{valeur}</dd>
    </div>
  );
}

/**
 * Récapitulatif financier d'une commande spéciale.
 *
 * `prixUnitaire` est un ORDRE DE GRANDEUR tiré du catalogue (prix du même
 * produit quand il était en stock) : le front ne décide jamais d'un montant
 * à payer. Sans prix connu, on l'annonce au lieu d'inventer un chiffre.
 */
export function AcompteResume({
  prixUnitaire,
  quantite,
}: {
  prixUnitaire: number | null;
  quantite: number;
}) {
  const total = prixUnitaire !== null ? prixUnitaire * Math.max(1, quantite) : null;
  const { acompte, solde } = total !== null ? repartirAcompte(total) : { acompte: null, solde: null };
  const pourcent = Math.round(TAUX_ACOMPTE * 100);

  return (
    <div className="hairline rounded-xl bg-surface/60 p-5">
      <h3 className="text-sm font-medium">Acompte et délai</h3>

      <dl className="mt-3 divide-y divide-border/70">
        {total !== null ? (
          <>
            <Ligne libelle="Prix total estimé" valeur={formatAr(total)} />
            <Ligne libelle={`Acompte (${pourcent} %)`} valeur={formatAr(acompte)} fort />
            <Ligne libelle="Solde à la livraison" valeur={formatAr(solde)} />
          </>
        ) : (
          <>
            <Ligne libelle="Prix total" valeur="Chiffré par la boutique" />
            <Ligne libelle="Acompte" valeur={`${pourcent} % du total`} fort />
          </>
        )}
        <Ligne libelle="Délai estimé" valeur={`${DELAI_COMMANDE_SPECIALE_JOURS} jours`} />
        <Ligne libelle="Disponibilité estimée" valeur={formatDate(dateEstimee().toISOString())} />
      </dl>

      <p className="mt-3 flex gap-2 text-xs text-muted">
        <Info className="mt-0.5 size-3.5 shrink-0" aria-hidden />
        <span>
          {total !== null
            ? "Montants indicatifs, calculés sur le dernier prix catalogue. La boutique confirme le montant exact avant tout paiement."
            : "La boutique chiffre le produit puis vous communique le montant de l'acompte."}{" "}
          Le délai court à partir de la validation de votre demande.
        </span>
      </p>
    </div>
  );
}
