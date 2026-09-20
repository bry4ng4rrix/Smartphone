"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowLeft, ArrowRight, Check, CreditCard, MapPin, Receipt, ShoppingBag, Store, Truck } from "lucide-react";
import { Button, ButtonLink } from "@/components/ui/button";
import { ColorDot } from "@/components/ui/color-dot";
import { EmptyState } from "@/components/ui/empty-state";
import { Field, Input, Textarea } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import { ApiError, messageErreur } from "@/lib/api";
import { catalogue, commandes } from "@/lib/endpoints";
import { cn, formatAr, pluriel } from "@/lib/utils";
import { useAuth } from "@/providers/auth-provider";
import { useCart } from "@/providers/cart-provider";
import { useToast } from "@/providers/toast-provider";
import type { ModePaiement, Zone, ZonesReponse } from "@/lib/types";

const ETAPES = [
  { cle: "livraison", label: "Livraison", icone: MapPin },
  { cle: "paiement", label: "Paiement", icone: CreditCard },
  { cle: "resume", label: "Résumé", icone: Receipt },
] as const;

type Etape = (typeof ETAPES)[number]["cle"];

export function CheckoutVue() {
  const { lignes, nbArticles, sousTotal, vider } = useCart();
  const { client } = useAuth();
  const router = useRouter();
  const toast = useToast();

  const boutiqueId = lignes[0]?.boutiqueId ?? null;
  const boutiqueNom = lignes[0]?.boutiqueNom ?? "";

  const [etape, setEtape] = useState<Etape>("livraison");
  const [zones, setZones] = useState<ZonesReponse | null>(null);
  const [zonesErreur, setZonesErreur] = useState<string | null>(null);

  const [zone, setZone] = useState<string>("");
  // Le composant n'est rendu qu'une fois la session confirmée (AuthGuard) :
  // le profil est donc déjà disponible pour pré-remplir les coordonnées.
  const [adresse, setAdresse] = useState(client?.adresse ?? "");
  const [telephone, setTelephone] = useState(client?.telephone ?? "");
  const [telephone2, setTelephone2] = useState("");
  const [modePaiement, setModePaiement] = useState<ModePaiement>("LIVRAISON");
  const [note, setNote] = useState("");

  const [envoi, setEnvoi] = useState(false);
  const [erreur, setErreur] = useState<ApiError | null>(null);

  // Zones réellement proposées par la boutique du panier.
  useEffect(() => {
    if (boutiqueId === null) return;
    let annule = false;
    (async () => {
      try {
        const reponse = await catalogue.zones(boutiqueId);
        if (annule) return;
        setZones(reponse);
        setZone((actuelle) => actuelle || reponse.zones[0]?.code || reponse.recuperation.code);
      } catch (e) {
        if (!annule) setZonesErreur(messageErreur(e, "Impossible de charger les zones de livraison."));
      }
    })();
    return () => {
      annule = true;
    };
  }, [boutiqueId]);

  const zoneChoisie: Zone | null = useMemo(() => {
    if (!zones) return null;
    if (zone === zones.recuperation.code) return zones.recuperation;
    return zones.zones.find((z) => z.code === zone) ?? null;
  }, [zones, zone]);

  const retrait = zoneChoisie?.code === "RECUPERATION";
  const fraisEstimes = zoneChoisie?.prix ?? 0;

  const passerAPaiement = () => {
    if (!zoneChoisie) return;
    if (!retrait && !adresse.trim()) {
      toast.erreur("Adresse requise", "Indiquez où livrer la commande.");
      return;
    }
    setEtape("paiement");
  };

  const commander = async () => {
    if (boutiqueId === null || !zoneChoisie) return;
    setEnvoi(true);
    setErreur(null);
    try {
      const commande = await commandes.creer({
        boutique: boutiqueId,
        items: lignes.map((l) => ({ variante: l.varianteId, quantite: l.quantite, prix_attendu: l.prix })),
        livraison_zone: zoneChoisie.code,
        adresse_livraison: retrait ? "" : adresse.trim(),
        telephone: telephone.trim() || undefined,
        telephone_2: telephone2.trim(),
        mode_paiement: modePaiement,
        note: note.trim(),
      });
      vider();
      toast.succes("Commande envoyée", `${commande.numero} · en attente de validation`);
      router.replace(`/compte/commandes/${commande.id}?nouvelle=1`);
    } catch (e) {
      if (e instanceof ApiError) {
        setErreur(e);
        setEtape("resume");
      } else {
        toast.erreur("Commande impossible", messageErreur(e));
      }
    } finally {
      setEnvoi(false);
    }
  };

  if (lignes.length === 0) {
    return (
      <EmptyState
        icone={ShoppingBag}
        titre="Votre panier est vide"
        description="Ajoutez des articles avant de passer commande."
        className="hairline mt-8 bg-surface/40"
        action={<ButtonLink href="/catalogue" variant="primaire">Voir le catalogue</ButtonLink>}
      />
    );
  }

  const indexEtape = ETAPES.findIndex((e) => e.cle === etape);

  return (
    <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_360px] lg:items-start">
      <div>
        {/* Progression */}
        <ol className="mb-8 flex items-center gap-2 text-xs" aria-label="Étapes de la commande">
          <li className="flex items-center gap-2 text-muted">
            <span className="grid size-7 place-items-center rounded-full bg-foreground/[0.06]">
              <Check className="size-3.5" aria-hidden />
            </span>
            <Link href="/panier" className="hidden transition-colors hover:text-foreground sm:inline">
              Panier
            </Link>
          </li>
          {ETAPES.map((e, i) => {
            const actif = i === indexEtape;
            const passe = i < indexEtape;
            return (
              <li key={e.cle} className="flex items-center gap-2">
                <span className="h-px w-4 bg-border sm:w-8" aria-hidden />
                <span
                  className={cn(
                    "grid size-7 place-items-center rounded-full transition-colors",
                    actif ? "bg-accent text-accent-foreground" : passe ? "bg-foreground/[0.06] text-foreground" : "bg-foreground/[0.04] text-muted",
                  )}
                >
                  {passe ? <Check className="size-3.5" aria-hidden /> : <e.icone className="size-3.5" aria-hidden />}
                </span>
                <span className={cn("hidden sm:inline", actif ? "font-medium text-foreground" : "text-muted")} aria-current={actif ? "step" : undefined}>
                  {e.label}
                </span>
              </li>
            );
          })}
        </ol>

        {/* Étape 1 — livraison */}
        {etape === "livraison" ? (
          <section className="hairline rounded-xl bg-surface/50 p-5 sm:p-6" aria-labelledby="etape-livraison">
            <h2 id="etape-livraison" className="text-lg font-medium tracking-tight">
              Informations de livraison
            </h2>

            {zonesErreur ? (
              <p role="alert" className="mt-4 rounded-lg bg-rose-500/10 px-4 py-3 text-sm text-rose-700 dark:text-rose-300">
                {zonesErreur}
              </p>
            ) : null}

            {!zones && !zonesErreur ? (
              <div className="mt-5 space-y-3">
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-16 w-full" />
              </div>
            ) : null}

            {zones ? (
              <>
                <fieldset className="mt-5">
                  <legend className="text-[11px] font-medium tracking-[0.18em] text-muted uppercase">Mode de réception</legend>
                  <div className="mt-3 grid gap-2 sm:grid-cols-2">
                    {[zones.recuperation, ...zones.zones].map((z) => {
                      const choisie = zone === z.code;
                      const estRetrait = z.code === "RECUPERATION";
                      return (
                        <label
                          key={z.code}
                          className={cn(
                            "flex cursor-pointer items-start gap-3 rounded-lg p-4 transition-all duration-200",
                            choisie ? "glass-strong ring-1 ring-accent/50" : "hairline hover:border-foreground/25",
                          )}
                        >
                          <input
                            type="radio"
                            name="zone"
                            value={z.code}
                            checked={choisie}
                            onChange={() => setZone(z.code)}
                            className="mt-1 size-4 accent-[var(--accent)]"
                          />
                          <span className="min-w-0 flex-1">
                            <span className="flex items-center gap-2 text-sm font-medium">
                              {estRetrait ? <Store className="size-3.5 text-muted" aria-hidden /> : <Truck className="size-3.5 text-muted" aria-hidden />}
                              {z.nom}
                            </span>
                            <span className="mt-0.5 block text-xs text-muted tabular-nums">
                              {z.prix > 0 ? formatAr(z.prix) : "Sans frais"}
                            </span>
                          </span>
                        </label>
                      );
                    })}
                  </div>
                </fieldset>

                <div className="mt-5 grid gap-4 sm:grid-cols-2">
                  {!retrait ? (
                    <Field
                      label="Adresse de livraison"
                      htmlFor="adresse"
                      className="sm:col-span-2"
                      erreurs={erreur?.pour("adresse_livraison")}
                    >
                      <Input
                        id="adresse"
                        value={adresse}
                        onChange={(e) => setAdresse(e.target.value)}
                        autoComplete="street-address"
                        placeholder="Lot II A Ankadifotsy, Antananarivo"
                        required
                      />
                    </Field>
                  ) : (
                    <p className="rounded-lg bg-foreground/[0.04] px-4 py-3 text-xs text-muted sm:col-span-2">
                      Retrait sur place : aucune adresse n&apos;est nécessaire, la boutique vous préviendra quand la commande sera prête.
                    </p>
                  )}

                  <Field label="Téléphone" htmlFor="telephone" aide="+261XXXXXXXXX" erreurs={erreur?.pour("telephone")}>
                    <Input
                      id="telephone"
                      value={telephone}
                      onChange={(e) => setTelephone(e.target.value)}
                      type="tel"
                      autoComplete="tel"
                      placeholder="+261341234567"
                    />
                  </Field>

                  <Field label="Second téléphone (facultatif)" htmlFor="telephone2" erreurs={erreur?.pour("telephone_2")}>
                    <Input
                      id="telephone2"
                      value={telephone2}
                      onChange={(e) => setTelephone2(e.target.value)}
                      type="tel"
                      placeholder="+261331234567"
                    />
                  </Field>

                  <Field label="Note pour le livreur (facultatif)" htmlFor="note" className="sm:col-span-2" erreurs={erreur?.pour("note")}>
                    <Textarea
                      id="note"
                      value={note}
                      onChange={(e) => setNote(e.target.value)}
                      placeholder="Ex : appeler avant de venir, portail bleu…"
                    />
                  </Field>
                </div>

                <div className="mt-6 flex justify-end">
                  <Button variant="primaire" size="lg" onClick={passerAPaiement} disabled={!zoneChoisie}>
                    Continuer
                    <ArrowRight aria-hidden />
                  </Button>
                </div>
              </>
            ) : null}
          </section>
        ) : null}

        {/* Étape 2 — paiement */}
        {etape === "paiement" ? (
          <section className="hairline rounded-xl bg-surface/50 p-5 sm:p-6" aria-labelledby="etape-paiement">
            <h2 id="etape-paiement" className="text-lg font-medium tracking-tight">
              Mode de paiement
            </h2>
            <p className="mt-1 text-sm text-muted">Le règlement se fait directement avec la boutique.</p>

            <fieldset className="mt-5 grid gap-2 sm:grid-cols-2">
              <legend className="sr-only">Mode de paiement</legend>
              {(
                [
                  { valeur: "LIVRAISON" as const, titre: retrait ? "Paiement au retrait" : "Paiement à la livraison", detail: "Vous réglez en recevant la commande." },
                  { valeur: "AVANT" as const, titre: "Paiement avant", detail: "Vous réglez la commande auprès de la boutique avant l'envoi." },
                ] satisfies { valeur: ModePaiement; titre: string; detail: string }[]
              ).map((m) => (
                <label
                  key={m.valeur}
                  className={cn(
                    "flex cursor-pointer items-start gap-3 rounded-lg p-4 transition-all duration-200",
                    modePaiement === m.valeur ? "glass-strong ring-1 ring-accent/50" : "hairline hover:border-foreground/25",
                  )}
                >
                  <input
                    type="radio"
                    name="paiement"
                    value={m.valeur}
                    checked={modePaiement === m.valeur}
                    onChange={() => setModePaiement(m.valeur)}
                    className="mt-1 size-4 accent-[var(--accent)]"
                  />
                  <span>
                    <span className="block text-sm font-medium">{m.titre}</span>
                    <span className="mt-0.5 block text-xs text-muted">{m.detail}</span>
                  </span>
                </label>
              ))}
            </fieldset>

            <div className="mt-6 flex items-center justify-between">
              <Button variant="fantome" onClick={() => setEtape("livraison")}>
                <ArrowLeft aria-hidden />
                Retour
              </Button>
              <Button variant="primaire" size="lg" onClick={() => setEtape("resume")}>
                Voir le résumé
                <ArrowRight aria-hidden />
              </Button>
            </div>
          </section>
        ) : null}

        {/* Étape 3 — résumé */}
        {etape === "resume" ? (
          <section className="hairline rounded-xl bg-surface/50 p-5 sm:p-6" aria-labelledby="etape-resume">
            <h2 id="etape-resume" className="text-lg font-medium tracking-tight">
              Résumé de la commande
            </h2>

            {erreur ? (
              <div role="alert" className="mt-4 rounded-lg bg-rose-500/10 px-4 py-3 text-sm text-rose-700 dark:text-rose-300">
                <p className="font-medium">La boutique n&apos;a pas pu enregistrer la commande :</p>
                <p className="mt-1 whitespace-pre-line">{erreur.message}</p>
                {erreur.pour("items").length > 0 ? (
                  <Link href="/panier" className="mt-2 inline-block underline">
                    Revoir mon panier
                  </Link>
                ) : null}
              </div>
            ) : null}

            <dl className="mt-5 space-y-4 text-sm">
              <div>
                <dt className="text-[11px] tracking-[0.18em] text-muted uppercase">Boutique</dt>
                <dd className="mt-1 font-medium">{boutiqueNom}</dd>
              </div>
              <div>
                <dt className="text-[11px] tracking-[0.18em] text-muted uppercase">Réception</dt>
                <dd className="mt-1">
                  {zoneChoisie?.nom}
                  {!retrait && adresse ? ` · ${adresse}` : ""}
                </dd>
              </div>
              <div>
                <dt className="text-[11px] tracking-[0.18em] text-muted uppercase">Contact</dt>
                <dd className="mt-1">
                  {telephone || client?.telephone}
                  {telephone2 ? ` / ${telephone2}` : ""}
                </dd>
              </div>
              <div>
                <dt className="text-[11px] tracking-[0.18em] text-muted uppercase">Paiement</dt>
                <dd className="mt-1">{modePaiement === "AVANT" ? "Paiement avant l'envoi" : retrait ? "Paiement au retrait" : "Paiement à la livraison"}</dd>
              </div>
              {note ? (
                <div>
                  <dt className="text-[11px] tracking-[0.18em] text-muted uppercase">Note</dt>
                  <dd className="mt-1 whitespace-pre-line">{note}</dd>
                </div>
              ) : null}
            </dl>

            <div className="mt-6 flex items-center justify-between gap-3">
              <Button variant="fantome" onClick={() => setEtape("paiement")} disabled={envoi}>
                <ArrowLeft aria-hidden />
                Retour
              </Button>
              <Button variant="accent" size="lg" onClick={commander} chargement={envoi}>
                Confirmer la commande
              </Button>
            </div>

            <p className="mt-3 text-right text-[11px] text-muted">
              La boutique validera votre commande avant préparation. Vous pourrez la modifier ou l&apos;annuler jusque-là.
            </p>
          </section>
        ) : null}
      </div>

      {/* Récapitulatif */}
      <aside className="glass sticky top-24 rounded-xl p-5">
        <h2 className="text-sm font-medium tracking-tight">
          {nbArticles} {pluriel(nbArticles, "article")}
        </h2>

        <ul className="mt-4 space-y-3">
          {lignes.map((l) => (
            <li key={l.varianteId} className="flex items-start gap-3 text-sm">
              <span className="mt-0.5 grid size-9 shrink-0 place-items-center rounded-lg bg-foreground/[0.05] text-xs font-medium tabular-nums">
                ×{l.quantite}
              </span>
              <span className="min-w-0 flex-1">
                <span className="line-clamp-1 font-medium">{l.nomComplet}</span>
                <span className="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                  <ColorDot nom={l.couleur} />
                  {l.couleur}
                </span>
              </span>
              <span className="shrink-0 text-sm tabular-nums">{formatAr(l.prix * l.quantite)}</span>
            </li>
          ))}
        </ul>

        <dl className="mt-5 space-y-2 border-t border-[var(--glass-border)] pt-4 text-sm">
          <div className="flex items-baseline justify-between">
            <dt className="text-muted">Articles</dt>
            <dd className="tabular-nums">{formatAr(sousTotal)}</dd>
          </div>
          <div className="flex items-baseline justify-between">
            <dt className="text-muted">Livraison{zoneChoisie ? ` · ${zoneChoisie.nom}` : ""}</dt>
            <dd className="tabular-nums">{zoneChoisie ? (fraisEstimes > 0 ? formatAr(fraisEstimes) : "Sans frais") : "—"}</dd>
          </div>
          <div className="flex items-baseline justify-between border-t border-[var(--glass-border)] pt-3">
            <dt className="font-medium">Total estimé</dt>
            <dd className="text-lg font-semibold tracking-tight tabular-nums">{formatAr(sousTotal + fraisEstimes)}</dd>
          </div>
        </dl>

        <p className="mt-3 text-[11px] leading-relaxed text-muted">
          Estimation d&apos;après les prix affichés. Le montant qui fait foi est celui calculé par la boutique sur la commande.
        </p>
      </aside>
    </div>
  );
}
