"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { ArrowLeft, CalendarClock, CheckCircle2, Hourglass, MapPin, Pencil, Store, X } from "lucide-react";
import { Button, ButtonLink } from "@/components/ui/button";
import { ColorDot } from "@/components/ui/color-dot";
import { EmptyState } from "@/components/ui/empty-state";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { Modal } from "@/components/ui/panel";
import { Skeleton } from "@/components/ui/skeleton";
import { StatutBadge, Timeline } from "@/components/orders/status";
import { ApiError, messageErreur } from "@/lib/api";
import { catalogue, commandes as apiCommandes } from "@/lib/endpoints";
import { aujourdhuiIso, depuisIso, libelleSouhait, versIso } from "@/lib/livraison";
import { DESCRIPTION_STATUT } from "@/lib/statuts";
import { cn, formatAr, formatDateTime, pluriel } from "@/lib/utils";
import { useToast } from "@/providers/toast-provider";
import type { Commande, ModePaiement, ZonesReponse } from "@/lib/types";

export function CommandeDetail({ id }: { id: string }) {
  const toast = useToast();
  const params = useSearchParams();
  const nouvelle = params.get("nouvelle") === "1";

  const [commande, setCommande] = useState<Commande | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [zones, setZones] = useState<ZonesReponse | null>(null);
  const [modifier, setModifier] = useState(false);
  const [annuler, setAnnuler] = useState(false);

  useEffect(() => {
    let annule = false;
    (async () => {
      try {
        const donnees = await apiCommandes.detail(id);
        if (annule) return;
        setCommande(donnees);
        // Nom de la zone fixée par la boutique : l'API client n'en renvoie
        // que le code.
        try {
          const liste = await catalogue.zones(donnees.boutique.id);
          if (!annule) setZones(liste);
        } catch {
          /* le code de zone restera affiché tel quel */
        }
      } catch (e) {
        if (!annule) setErreur(messageErreur(e, "Commande introuvable."));
      }
    })();
    return () => {
      annule = true;
    };
  }, [id]);

  if (erreur) {
    return (
      <EmptyState
        icone={X}
        titre="Commande introuvable"
        description={erreur}
        className="hairline bg-surface/40"
        action={<ButtonLink href="/compte/commandes" variant="primaire">Mes commandes</ButtonLink>}
      />
    );
  }

  if (!commande) {
    return (
      <div className="space-y-4" aria-busy="true">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-48 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  const articles = commande.items.reduce((n, i) => n + i.quantite, 0);
  const retrait = commande.livraison_zone === "RECUPERATION";
  // Avant l'approbation, la zone de livraison (et ses frais) reste provisoire.
  const enAttente = commande.statut === "EN_ATTENTE_APPROBATION";
  const nomZone = zones?.zones.find((z) => z.code === commande.livraison_zone)?.nom ?? null;
  // Créneau de livraison : champ dédié de l'API, ajusté par la boutique.
  const souhait = libelleSouhait(commande.date_livraison_souhaitee);
  const remarque = commande.note ?? "";

  return (
    <div>
      <Link href="/compte/commandes" className="mb-6 inline-flex items-center gap-2 text-sm text-muted transition-colors hover:text-foreground">
        <ArrowLeft className="size-4" aria-hidden />
        Mes commandes
      </Link>

      {nouvelle ? (
        <div className="glass mb-6 flex items-start gap-3 rounded-xl p-4">
          <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-emerald-600 dark:text-emerald-400" aria-hidden />
          <div>
            <p className="text-sm font-medium">Commande envoyée à {commande.boutique.nom}</p>
            <p className="mt-0.5 text-xs text-muted">
              Elle sera validée par la boutique. Vous pouvez encore la modifier ou l&apos;annuler depuis cette page.
            </p>
          </div>
        </div>
      ) : null}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">{commande.numero}</h1>
          <p className="mt-1 text-sm text-muted">
            Passée le {formatDateTime(commande.date_commande)} · {commande.boutique.nom}
          </p>
        </div>
        <StatutBadge statut={commande.statut} label={commande.statut_label} className="px-3.5 py-1.5 text-[13px]" />
      </div>

      <p className="mt-3 text-sm text-muted">{DESCRIPTION_STATUT[commande.statut]}</p>

      {/* Actions — pilotées par les droits renvoyés par l'API, jamais déduits du statut. */}
      {commande.peut_modifier || commande.peut_annuler ? (
        <div className="mt-5 flex flex-wrap gap-2">
          {commande.peut_modifier ? (
            <Button variant="contour" size="sm" onClick={() => setModifier(true)}>
              <Pencil aria-hidden />
              Modifier la livraison
            </Button>
          ) : null}
          {commande.peut_annuler ? (
            <Button variant="fantome" size="sm" onClick={() => setAnnuler(true)}>
              <X aria-hidden />
              Annuler la commande
            </Button>
          ) : null}
        </div>
      ) : (
        <p className="mt-5 rounded-lg bg-foreground/[0.04] px-4 py-3 text-xs text-muted">
          Cette commande n&apos;est plus modifiable depuis l&apos;espace client. Contactez la boutique pour toute question.
        </p>
      )}

      <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_340px] lg:items-start">
        <div className="space-y-6">
          <section aria-labelledby="suivi">
            <h2 id="suivi" className="mb-3 text-sm font-medium tracking-tight">
              Suivi
            </h2>
            <Timeline commande={commande} />
          </section>

          <section aria-labelledby="articles">
            <h2 id="articles" className="mb-3 text-sm font-medium tracking-tight">
              {articles} {pluriel(articles, "article")}
            </h2>
            <ul className="hairline divide-y divide-border/70 rounded-xl bg-surface/50">
              {commande.items.map((i) => (
                <li key={i.id} className={cn("flex items-start gap-3 p-4", i.retourne && "opacity-60")}>
                  <span className="grid size-10 shrink-0 place-items-center rounded-lg bg-foreground/[0.05] text-xs font-medium tabular-nums">
                    ×{i.quantite}
                  </span>
                  <div className="min-w-0 flex-1">
                    <Link href={`/produit/${i.produit.id}`} className="text-sm font-medium hover:text-accent">
                      {i.produit.nom_complet}
                    </Link>
                    <p className="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                      <ColorDot nom={i.variante.couleur} />
                      {i.variante.couleur}
                      {i.retourne ? <span className="ml-1 text-rose-600 dark:text-rose-400">· non livré</span> : null}
                    </p>
                    <p className="mt-0.5 text-xs text-muted tabular-nums">{formatAr(i.prix_unitaire)} / unité</p>
                  </div>
                  <span className={cn("text-sm font-medium tabular-nums", i.retourne && "line-through")}>{formatAr(i.total)}</span>
                </li>
              ))}
            </ul>
          </section>
        </div>

        <aside className="space-y-4">
          <div className="glass rounded-xl p-5">
            <h2 className="text-sm font-medium tracking-tight">Montant</h2>
            <dl className="mt-4 space-y-2 text-sm">
              <div className="flex items-baseline justify-between">
                <dt className="text-muted">Articles</dt>
                <dd className="tabular-nums">{formatAr(commande.total_a_payer - commande.frais_livraison)}</dd>
              </div>
              <div className="flex items-baseline justify-between gap-4">
                <dt className="text-muted">Livraison</dt>
                <dd className={cn("tabular-nums", enAttente && "text-right text-xs text-muted")}>
                  {enAttente
                    ? retrait
                      ? "Retrait sur place — sans frais"
                      : "Fixée par la boutique"
                    : commande.frais_livraison > 0
                      ? formatAr(commande.frais_livraison)
                      : "Sans frais"}
                </dd>
              </div>
              {/* Tant que la boutique n'a pas validé, les frais — donc le total —
                  ne sont pas arrêtés : on n'affiche pas de montant provisoire. */}
              <div className="flex items-start justify-between gap-4 border-t border-[var(--glass-border)] pt-3">
                <dt className="font-medium">Total à payer</dt>
                {enAttente ? (
                  <dd className="flex items-center gap-1.5 text-right text-[13px] font-medium text-amber-600 dark:text-amber-400">
                    <Hourglass className="size-3.5 shrink-0" aria-hidden />
                    En attente de confirmation du gérant
                  </dd>
                ) : (
                  <dd className="text-xl font-semibold tracking-tight tabular-nums">{formatAr(commande.total_a_payer)}</dd>
                )}
              </div>
            </dl>
            <p className="mt-3 text-[11px] text-muted">
              {commande.mode_paiement === "AVANT" ? "Paiement avant l'envoi." : retrait ? "Paiement au retrait." : "Paiement à la livraison."}
            </p>
          </div>

          <div className="hairline rounded-xl bg-surface/50 p-5 text-sm">
            <h2 className="text-sm font-medium tracking-tight">Réception</h2>
            <p className="mt-3 flex items-start gap-2 text-muted">
              {retrait ? <Store className="mt-0.5 size-4 shrink-0" aria-hidden /> : <MapPin className="mt-0.5 size-4 shrink-0" aria-hidden />}
              <span>
                {retrait ? "Retrait sur place" : commande.adresse_livraison || "Adresse non précisée"}
                {!retrait ? (
                  <span className="mt-0.5 block text-xs">
                    Zone : {enAttente ? "à confirmer par la boutique" : nomZone ?? commande.livraison_zone}
                  </span>
                ) : null}
              </span>
            </p>
            <p className="mt-3 text-muted">
              {commande.telephone}
              {commande.telephone_2 ? ` / ${commande.telephone_2}` : ""}
            </p>
            {souhait ? (
              <p className="mt-3 flex items-center gap-2 border-t border-border/70 pt-3 text-sm">
                <CalendarClock className="size-4 shrink-0 text-muted" aria-hidden />
                {enAttente ? "Livraison souhaitée le " : "Livraison prévue le "}
                {souhait}
              </p>
            ) : null}
            {remarque ? (
              <p className="mt-3 border-t border-border/70 pt-3 text-xs whitespace-pre-line text-muted">« {remarque} »</p>
            ) : null}
          </div>
        </aside>
      </div>

      <ModifierCommande
        commande={commande}
        ouvert={modifier}
        onOuvertChange={setModifier}
        onMaj={(c) => {
          setCommande(c);
          toast.succes("Commande mise à jour", c.numero);
        }}
      />

      <AnnulerCommande
        commande={commande}
        ouvert={annuler}
        onOuvertChange={setAnnuler}
        onMaj={(c) => {
          setCommande(c);
          toast.info("Commande annulée", c.numero);
        }}
      />
    </div>
  );
}

/** Seuls les champs acceptés par `PATCH /api/client/orders/{id}/`. */
function ModifierCommande({
  commande,
  ouvert,
  onOuvertChange,
  onMaj,
}: {
  commande: Commande;
  ouvert: boolean;
  onOuvertChange: (o: boolean) => void;
  onMaj: (c: Commande) => void;
}) {
  const toast = useToast();
  const retrait = commande.livraison_zone === "RECUPERATION";
  const [adresse, setAdresse] = useState(commande.adresse_livraison ?? "");
  const [telephone, setTelephone] = useState(commande.telephone);
  const [telephone2, setTelephone2] = useState(commande.telephone_2);
  const [modePaiement, setModePaiement] = useState<ModePaiement>(commande.mode_paiement);
  const creneau = depuisIso(commande.date_livraison_souhaitee);
  const [dateSouhaitee, setDateSouhaitee] = useState(creneau.date);
  const [heureSouhaitee, setHeureSouhaitee] = useState(creneau.heure);
  const [note, setNote] = useState(commande.note ?? "");
  const [envoi, setEnvoi] = useState(false);
  const [erreur, setErreur] = useState<ApiError | null>(null);

  const enregistrer = async () => {
    setEnvoi(true);
    setErreur(null);
    try {
      const maj = await apiCommandes.modifier(commande.id, {
        // La zone de livraison n'est pas modifiable ici : la boutique la fixe
        // (et avec elle les frais) au moment de valider la commande.
        adresse_livraison: retrait ? "" : adresse.trim(),
        telephone: telephone.trim(),
        telephone_2: telephone2.trim(),
        mode_paiement: modePaiement,
        note: note.trim(),
        date_livraison_souhaitee: retrait ? undefined : versIso(dateSouhaitee, heureSouhaitee),
      });
      onMaj(maj);
      onOuvertChange(false);
    } catch (e) {
      if (e instanceof ApiError) setErreur(e);
      else toast.erreur("Modification impossible", messageErreur(e));
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <Modal
      ouvert={ouvert}
      onOuvertChange={onOuvertChange}
      titre="Modifier mes informations"
      description="Adresse, téléphones, paiement et remarque. Les articles et les frais de livraison ne sont pas modifiables ici : pour changer le panier, annulez et repassez commande."
    >
      <div className="space-y-4">
        {erreur ? (
          <p role="alert" className="rounded-lg bg-rose-500/10 px-4 py-3 text-sm whitespace-pre-line text-rose-700 dark:text-rose-300">
            {erreur.message}
          </p>
        ) : null}

        {!retrait ? (
          <>
            <Field label="Adresse de livraison" htmlFor="maj-adresse" erreurs={erreur?.pour("adresse_livraison")}>
              <Input id="maj-adresse" value={adresse} onChange={(e) => setAdresse(e.target.value)} />
            </Field>

            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Date de livraison souhaitée" htmlFor="maj-date">
                <Input
                  id="maj-date"
                  type="date"
                  min={aujourdhuiIso()}
                  value={dateSouhaitee}
                  onChange={(e) => setDateSouhaitee(e.target.value)}
                />
              </Field>
              <Field label="Heure souhaitée" htmlFor="maj-heure">
                <Input id="maj-heure" type="time" value={heureSouhaitee} onChange={(e) => setHeureSouhaitee(e.target.value)} />
              </Field>
            </div>
          </>
        ) : (
          <p className="rounded-lg bg-foreground/[0.04] px-4 py-3 text-xs text-muted">
            Retrait sur place : aucune adresse n&apos;est nécessaire.
          </p>
        )}

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Téléphone" htmlFor="maj-tel" aide="+261XXXXXXXXX" erreurs={erreur?.pour("telephone")}>
            <Input id="maj-tel" value={telephone} onChange={(e) => setTelephone(e.target.value)} type="tel" />
          </Field>
          <Field label="Second téléphone" htmlFor="maj-tel2" erreurs={erreur?.pour("telephone_2")}>
            <Input id="maj-tel2" value={telephone2} onChange={(e) => setTelephone2(e.target.value)} type="tel" />
          </Field>
        </div>

        <Field label="Mode de paiement" htmlFor="maj-paiement" erreurs={erreur?.pour("mode_paiement")}>
          <Select id="maj-paiement" value={modePaiement} onChange={(e) => setModePaiement(e.target.value as ModePaiement)}>
            <option value="LIVRAISON">Paiement à la réception</option>
            <option value="AVANT">Paiement avant l&apos;envoi</option>
          </Select>
        </Field>

        <Field label="Remarque" htmlFor="maj-note" erreurs={erreur?.pour("note")}>
          <Textarea id="maj-note" value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>

        <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
          <Button variant="contour" onClick={() => onOuvertChange(false)} disabled={envoi}>
            Annuler
          </Button>
          <Button variant="accent" onClick={enregistrer} chargement={envoi}>
            Enregistrer
          </Button>
        </div>
      </div>
    </Modal>
  );
}

function AnnulerCommande({
  commande,
  ouvert,
  onOuvertChange,
  onMaj,
}: {
  commande: Commande;
  ouvert: boolean;
  onOuvertChange: (o: boolean) => void;
  onMaj: (c: Commande) => void;
}) {
  const toast = useToast();
  const [note, setNote] = useState("");
  const [envoi, setEnvoi] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  const confirmer = async () => {
    setEnvoi(true);
    setErreur(null);
    try {
      const maj = await apiCommandes.annuler(commande.id, note.trim());
      onMaj(maj);
      onOuvertChange(false);
    } catch (e) {
      setErreur(messageErreur(e, "Annulation impossible."));
      toast.erreur("Annulation impossible");
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <Modal
      ouvert={ouvert}
      onOuvertChange={onOuvertChange}
      titre={`Annuler ${commande.numero} ?`}
      description="L'annulation est définitive. Vous pourrez repasser commande à tout moment."
    >
      <div className="space-y-4">
        {erreur ? (
          <p role="alert" className="rounded-lg bg-rose-500/10 px-4 py-3 text-sm whitespace-pre-line text-rose-700 dark:text-rose-300">
            {erreur}
          </p>
        ) : null}

        <Field label="Motif (facultatif)" htmlFor="annul-note" aide="Transmis à la boutique.">
          <Textarea id="annul-note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Ex : erreur de coloris" />
        </Field>

        <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
          <Button variant="contour" onClick={() => onOuvertChange(false)} disabled={envoi}>
            Garder ma commande
          </Button>
          <Button variant="danger" onClick={confirmer} chargement={envoi}>
            Annuler la commande
          </Button>
        </div>
      </div>
    </Modal>
  );
}
