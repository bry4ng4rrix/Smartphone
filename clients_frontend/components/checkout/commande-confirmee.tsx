"use client";

import Link from "next/link";
import { CheckCircle2, PhoneCall, Printer } from "lucide-react";
import { Button, ButtonLink } from "@/components/ui/button";
import { formatAr } from "@/lib/utils";
import type { Commande } from "@/lib/types";

/**
 * Écran final : la seule et unique fois où le client verra ces informations.
 *
 * Il n'y a pas de page de suivi — sans compte, aucune façon d'authentifier
 * qui demande à relire une commande. D'où le numéro mis en avant et le bouton
 * d'impression : c'est la trace que le client emporte.
 */
export function CommandeConfirmee({ commande }: { commande: Commande }) {
  const retrait = commande.livraison_zone === "RECUPERATION";

  return (
    <div className="hairline rounded-xl bg-surface/50 px-6 py-10 sm:px-10">
      <div className="text-center">
        <span className="glass mx-auto mb-5 flex size-14 items-center justify-center rounded-full text-emerald-600 dark:text-emerald-400">
          <CheckCircle2 className="size-6" aria-hidden />
        </span>
        <h2 className="text-xl font-medium tracking-tight">Commande envoyée</h2>
        <p className="mx-auto mt-2 max-w-md text-sm text-muted">
          Conservez ce numéro : c&apos;est votre référence auprès de la boutique.
        </p>
        <p className="mt-4 inline-block rounded-lg bg-foreground/[0.06] px-4 py-2 text-lg font-semibold tracking-tight tabular-nums">
          {commande.numero}
        </p>
      </div>

      <div className="mx-auto mt-7 max-w-md rounded-xl bg-accent/[0.07] p-4">
        <p className="flex items-start gap-2.5 text-sm">
          <PhoneCall className="mt-0.5 size-4 shrink-0 text-accent" aria-hidden />
          <span>
            La boutique vous appelle au <strong className="tabular-nums">{commande.telephone}</strong> pour confirmer.
            La préparation démarre après cet appel.
          </span>
        </p>
      </div>

      <dl className="mx-auto mt-7 max-w-md">
        {commande.items.map((item) => (
          <div key={item.id} className="flex justify-between gap-4 border-b border-border/70 py-2">
            <dt className="min-w-0 text-sm">
              <span className="block truncate">{item.produit.nom_complet}</span>
              <span className="text-xs text-muted">
                {item.couleur} · ×{item.quantite}
              </span>
            </dt>
            <dd className="text-right text-sm font-medium tabular-nums">{formatAr(item.total)}</dd>
          </div>
        ))}

        <div className="flex justify-between gap-4 border-b border-border/70 py-2">
          <dt className="text-sm text-muted">{retrait ? "Retrait sur place" : "Frais de livraison"}</dt>
          <dd className="text-right text-sm tabular-nums">{formatAr(commande.frais_livraison)}</dd>
        </div>

        <div className="flex items-baseline justify-between gap-4 pt-3">
          <dt className="text-sm font-medium">Total à payer</dt>
          <dd className="text-lg font-semibold tracking-tight tabular-nums">{formatAr(commande.total_a_payer)}</dd>
        </div>
      </dl>

      <dl className="mx-auto mt-6 max-w-md space-y-2">
        {[
          ["Nom", commande.client_nom],
          ["Téléphone", commande.telephone],
          ...(commande.telephone_2 ? [["Autre numéro", commande.telephone_2] as const] : []),
          ...(retrait ? [] : [["Adresse", commande.adresse_livraison ?? "—"] as const]),
        ].map(([libelle, valeur]) => (
          <div key={libelle} className="flex justify-between gap-4">
            <dt className="text-sm text-muted">{libelle}</dt>
            <dd className="text-right text-sm">{valeur}</dd>
          </div>
        ))}
      </dl>

      <div className="mt-8 flex flex-col gap-2 sm:flex-row sm:justify-center">
        <Button variant="contour" onClick={() => window.print()} className="print:hidden">
          <Printer aria-hidden />
          Imprimer
        </Button>
        <ButtonLink href="/catalogue" variant="primaire" className="print:hidden">
          Continuer mes achats
        </ButtonLink>
      </div>

      <p className="mt-6 text-center text-xs text-muted print:hidden">
        Une erreur dans vos informations ?{" "}
        <Link href="/catalogue" className="text-accent hover:underline">
          Signalez-la lors de l&apos;appel
        </Link>
        .
      </p>
    </div>
  );
}
