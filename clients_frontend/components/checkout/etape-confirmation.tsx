"use client";

import { useState } from "react";
import { ArrowLeft, PhoneCall, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/panel";
import { formatAr } from "@/lib/utils";
import type { Coordonnees, Remise } from "@/lib/commande";

/**
 * Étape 4 — la confirmation ferme.
 *
 * Deux gestes délibérés sont demandés : cocher l'attestation, puis confirmer
 * dans la fenêtre. La commande ne peut plus être modifiée en ligne ensuite —
 * sans compte, rien ne permettrait d'authentifier celui qui le demanderait —
 * donc l'écran le dit avant, pas après.
 */
export function EtapeConfirmation({
  coordonnees,
  remise,
  total,
  envoi,
  erreur,
  onConfirmer,
  onRetour,
}: {
  coordonnees: Coordonnees;
  remise: Remise;
  total: number;
  envoi: boolean;
  erreur: string | null;
  onConfirmer: () => void;
  onRetour: () => void;
}) {
  const [atteste, setAtteste] = useState(false);
  const [fenetre, setFenetre] = useState(false);

  return (
    <>
      <div className="hairline rounded-xl bg-surface/50 p-5 sm:p-6">
        <h2 className="text-base font-medium tracking-tight">Dernière vérification</h2>

        <div className="mt-5 rounded-xl bg-foreground/[0.04] p-4">
          <p className="flex items-start gap-2.5 text-sm">
            <PhoneCall className="mt-0.5 size-4 shrink-0 text-accent" aria-hidden />
            <span>
              La boutique vous appellera au <strong className="tabular-nums">{coordonnees.telephone}</strong> pour
              confirmer cette commande avant de la préparer.
            </span>
          </p>
        </div>

        <dl className="mt-5 space-y-2">
          {[
            ["Nom", coordonnees.nom],
            ["Téléphone", coordonnees.telephone],
            ["Autre numéro", coordonnees.telephone2 || "—"],
            ["Remise", remise.mode === "EN_LIGNE" ? "Livraison à domicile" : "Retrait sur place"],
            ...(remise.mode === "EN_LIGNE" ? [["Adresse", remise.adresse] as const] : []),
          ].map(([libelle, valeur]) => (
            <div key={libelle} className="flex justify-between gap-4 border-b border-border/70 pb-2 last:border-0">
              <dt className="text-sm text-muted">{libelle}</dt>
              <dd className="text-right text-sm font-medium">{valeur}</dd>
            </div>
          ))}
          <div className="flex items-baseline justify-between gap-4 pt-1">
            <dt className="text-sm font-medium">Total à payer</dt>
            <dd className="text-lg font-semibold tracking-tight tabular-nums">{formatAr(total)}</dd>
          </div>
        </dl>

        <label className="mt-6 flex cursor-pointer items-start gap-3 rounded-lg border border-border p-4 text-sm">
          <input
            type="checkbox"
            checked={atteste}
            onChange={(e) => setAtteste(e.target.checked)}
            className="mt-0.5 size-4 shrink-0 rounded border-border accent-[var(--accent)]"
          />
          <span>
            Je confirme que mon nom, mes numéros et mon adresse sont exacts, et que la commande ne pourra plus être
            modifiée en ligne.
          </span>
        </label>

        {erreur ? (
          <p role="alert" className="mt-4 text-sm whitespace-pre-line text-rose-600 dark:text-rose-400">
            {erreur}
          </p>
        ) : null}

        <div className="mt-6 flex flex-col gap-2 sm:flex-row-reverse sm:justify-start">
          <Button
            type="button"
            variant="accent"
            size="lg"
            disabled={!atteste}
            onClick={() => setFenetre(true)}
          >
            <ShieldCheck aria-hidden />
            Confirmer ma commande
          </Button>
          <Button type="button" variant="contour" size="lg" onClick={onRetour} disabled={envoi}>
            <ArrowLeft aria-hidden />
            Revenir au détail
          </Button>
        </div>
      </div>

      <Modal
        ouvert={fenetre}
        onOuvertChange={(o) => (o ? undefined : setFenetre(false))}
        titre="Envoyer la commande ?"
        description={`Un total de ${formatAr(total)} sera annoncé à la boutique, qui vous rappellera au ${coordonnees.telephone} pour confirmer.`}
      >
        <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
          <Button variant="contour" onClick={() => setFenetre(false)} disabled={envoi}>
            Pas encore
          </Button>
          <Button variant="accent" onClick={onConfirmer} chargement={envoi}>
            Oui, envoyer
          </Button>
        </div>
      </Modal>
    </>
  );
}
