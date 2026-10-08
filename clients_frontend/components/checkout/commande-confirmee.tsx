"use client";

import Link from "next/link";
import { CheckCircle2, PhoneCall, Printer } from "lucide-react";
import { Button, ButtonLink } from "@/components/ui/button";
import { PointRetrait } from "@/components/checkout/point-retrait";
import { formatAr } from "@/lib/utils";
import type { Commande } from "@/lib/types";

/**
 * Écran final : la seule et unique fois où le client verra ces informations.
 *
 * Il n'y a pas de page de suivi — sans compte, aucune façon d'authentifier
 * qui demande à relire une commande. D'où les numéros mis en avant et le
 * bouton d'impression : c'est la trace que le client emporte.
 *
 * Un panier mêlant plusieurs boutiques donne plusieurs commandes — une par
 * boutique, chacune avec son numéro, ses montants et son point de retrait.
 * Elles sont donc toutes affichées, et toutes imprimées.
 */
export function CommandeConfirmee({ commandes }: { commandes: Commande[] }) {
  const premiere = commandes[0];
  if (!premiere) return null;
  const plusieurs = commandes.length > 1;

  return (
    <div className="hairline rounded-xl bg-surface/50 px-6 py-10 sm:px-10">
      <div className="text-center">
        <span className="glass mx-auto mb-5 flex size-14 items-center justify-center rounded-full text-emerald-600 dark:text-emerald-400">
          <CheckCircle2 className="size-6" aria-hidden />
        </span>
        <h2 className="text-xl font-medium tracking-tight">
          {plusieurs ? `${commandes.length} commandes envoyées` : "Commande envoyée"}
        </h2>
        <p className="mx-auto mt-2 max-w-md text-sm text-muted">
          {plusieurs
            ? `Vos articles venaient de ${commandes.length} boutiques : chacune a reçu la sienne. Conservez ces numéros, ce sont vos références.`
            : "Conservez ce numéro : c'est votre référence auprès de la boutique."}
        </p>
      </div>

      <div className="mx-auto mt-7 max-w-md rounded-xl bg-accent/[0.07] p-4">
        <p className="flex items-start gap-2.5 text-sm">
          <PhoneCall className="mt-0.5 size-4 shrink-0 text-accent" aria-hidden />
          <span>
            {plusieurs ? "Chaque boutique vous appelle" : "La boutique vous appelle"} au{" "}
            <strong className="tabular-nums">{premiere.telephone}</strong> pour confirmer. La
            préparation démarre après cet appel.
          </span>
        </p>
      </div>

      {commandes.map((commande) => (
        <BlocCommande key={commande.id} commande={commande} avecBoutique={plusieurs} />
      ))}

      <dl className="mx-auto mt-6 max-w-md space-y-2">
        {[
          ["Nom", premiere.client_nom],
          ["Téléphone", premiere.telephone],
          ...(premiere.telephone_2 ? [["Autre numéro", premiere.telephone_2] as const] : []),
          ...(premiere.livraison_zone === "RECUPERATION"
            ? []
            : [["Adresse", premiere.adresse_livraison ?? "—"] as const]),
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

/** Le détail d'UNE commande : son numéro, ses articles, ses montants. */
function BlocCommande({ commande, avecBoutique }: { commande: Commande; avecBoutique: boolean }) {
  const retrait = commande.livraison_zone === "RECUPERATION";

  return (
    <div className="mx-auto mt-7 max-w-md border-t border-border/70 pt-6 first-of-type:border-0 first-of-type:pt-0">
      <div className="text-center">
        {avecBoutique ? (
          <p className="text-sm font-medium">{commande.boutique.nom}</p>
        ) : null}
        <p className="mt-1 inline-block rounded-lg bg-foreground/[0.06] px-4 py-2 text-lg font-semibold tracking-tight tabular-nums">
          {commande.numero}
        </p>
      </div>

      {/* Retrait sur place : cet écran est la seule occasion de donner
          l'adresse et le numéro du magasin: il n'existe pas de page de suivi
          à rouvrir. Imprimé avec le reste. */}
      {retrait ? (
        <PointRetrait
          nom={commande.boutique.nom}
          coordonnees={commande.boutique}
          className="mt-4"
        />
      ) : null}

      <dl className="mt-7">
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
    </div>
  );
}
