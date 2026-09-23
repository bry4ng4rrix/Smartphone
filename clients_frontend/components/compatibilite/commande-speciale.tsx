"use client";

import { useId, useState } from "react";
import { ArrowLeft, CheckCircle2, Info } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input, Textarea } from "@/components/ui/field";
import { AcompteResume } from "@/components/compatibilite/acompte-resume";
import { ApiError, messageErreur } from "@/lib/api";
import { commandesSpeciales } from "@/lib/endpoints";
import { ENVOI_COMMANDE_SPECIALE_ACTIF } from "@/lib/compatibilite";
import { useAuth } from "@/providers/auth-provider";
import { useToast } from "@/providers/toast-provider";
import type { Categorie, Marque } from "@/lib/types";

type Champs = Record<string, string[]>;

/**
 * Étape 3 : la demande elle-même.
 *
 * Téléphone, marque et type de produit sont déjà connus du parcours : ils
 * sont rappelés, pas redemandés. Nom et contact viennent du compte quand le
 * client est connecté — on ne fait pas ressaisir ce que l'on sait déjà.
 */
export function CommandeSpeciale({
  categorie,
  marque,
  modele,
  boutiqueId,
  prixIndicatif,
  onRetour,
}: {
  categorie: Categorie;
  marque: Marque;
  modele: string;
  boutiqueId: number | null;
  prixIndicatif: number | null;
  onRetour: () => void;
}) {
  const { client } = useAuth();
  const toast = useToast();

  const idNom = useId();
  const idContact = useId();
  const idProduit = useId();
  const idQuantite = useId();
  const idPrecision = useId();

  // Préremplissage depuis le compte, sans effet : tant que le client n'a
  // rien saisi (`null`), le champ affiche ce que l'on sait déjà de lui. Le
  // profil arrive de façon asynchrone (vérification du jeton), la valeur
  // suit donc toute seule dès qu'il est connu.
  const [nomSaisi, setNomSaisi] = useState<string | null>(null);
  const [contactSaisi, setContactSaisi] = useState<string | null>(null);
  const nom = nomSaisi ?? client?.nom ?? "";
  const contact = contactSaisi ?? client?.telephone ?? "";

  const [produitSouhaite, setProduitSouhaite] = useState("");
  const [quantite, setQuantite] = useState(1);
  const [precision, setPrecision] = useState("");
  const [envoi, setEnvoi] = useState(false);
  const [erreurs, setErreurs] = useState<Champs>({});
  const [erreurGlobale, setErreurGlobale] = useState<string | null>(null);
  const [envoyee, setEnvoyee] = useState(false);

  const telephone = `${marque.nom} ${modele}`.trim();

  const valider = (): boolean => {
    const trouvees: Champs = {};
    if (!nom.trim()) trouvees.contact_nom = ["Indiquez le nom à contacter."];
    if (!contact.trim()) trouvees.contact_telephone = ["Indiquez un numéro pour vous joindre."];
    if (!produitSouhaite.trim()) trouvees.produit_souhaite = ["Décrivez le produit souhaité."];
    if (!Number.isInteger(quantite) || quantite < 1) trouvees.quantite = ["La quantité doit être d'au moins 1."];
    setErreurs(trouvees);
    return Object.keys(trouvees).length === 0;
  };

  const envoyer = async () => {
    if (!valider()) return;
    setErreurGlobale(null);

    // Pas d'endpoint côté serveur : on s'arrête au récapitulatif plutôt que
    // de faire croire à un enregistrement. Voir lib/compatibilite.ts.
    if (!ENVOI_COMMANDE_SPECIALE_ACTIF || boutiqueId === null) {
      setEnvoyee(true);
      return;
    }

    setEnvoi(true);
    try {
      await commandesSpeciales.creer({
        boutique: boutiqueId,
        categorie: categorie.id,
        telephone_marque: marque.nom,
        telephone_modele: modele.trim(),
        produit_souhaite: produitSouhaite.trim(),
        quantite,
        contact_nom: nom.trim(),
        contact_telephone: contact.trim(),
        precision: precision.trim() || undefined,
      });
      toast.succes("Demande envoyée", "La boutique vous recontacte pour l'acompte.");
      setEnvoyee(true);
    } catch (e) {
      if (e instanceof ApiError) setErreurs(e.champs);
      setErreurGlobale(messageErreur(e, "Impossible d'envoyer la demande."));
    } finally {
      setEnvoi(false);
    }
  };

  if (envoyee) {
    return (
      <div className="hairline rounded-xl bg-surface/60 px-6 py-12 text-center sm:px-10">
        <span className="glass mx-auto mb-5 flex size-14 items-center justify-center rounded-full text-emerald-600 dark:text-emerald-400">
          <CheckCircle2 className="size-6" aria-hidden />
        </span>
        <h2 className="text-lg font-medium tracking-tight">Demande enregistrée</h2>

        <dl className="mx-auto mt-6 max-w-sm space-y-2 text-left">
          {[
            ["Téléphone", telephone],
            ["Type de produit", categorie.nom],
            ["Produit souhaité", produitSouhaite.trim()],
            ["Quantité", String(quantite)],
            ["Contact", `${nom.trim()} · ${contact.trim()}`],
          ].map(([libelle, valeur]) => (
            <div key={libelle} className="flex justify-between gap-4 border-b border-border/70 pb-2 last:border-0">
              <dt className="text-sm text-muted">{libelle}</dt>
              <dd className="text-right text-sm font-medium">{valeur}</dd>
            </div>
          ))}
        </dl>

        {ENVOI_COMMANDE_SPECIALE_ACTIF ? (
          <p className="mx-auto mt-6 max-w-md text-sm text-muted">
            La boutique confirme le montant puis vous indique comment régler l&apos;acompte. Votre demande passe ensuite
            en validation.
          </p>
        ) : (
          <p className="mx-auto mt-6 flex max-w-md gap-2 text-left text-sm text-muted">
            <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
            <span>
              L&apos;envoi en ligne des commandes spéciales n&apos;est pas encore ouvert. Conservez ce récapitulatif et
              communiquez-le à la boutique pour lancer la demande.
            </span>
          </p>
        )}

        <div className="mt-7">
          <Button variant="contour" onClick={onRetour}>
            <ArrowLeft aria-hidden />
            Revenir à la recherche
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void envoyer();
        }}
        className="hairline rounded-xl bg-surface/60 p-5 sm:p-7"
        noValidate
      >
        <h2 className="text-lg font-medium tracking-tight sm:text-xl">Commande spéciale</h2>
        <p className="mt-1.5 text-sm text-muted">
          Nous commandons le produit pour vous. Vérifiez vos coordonnées et précisez votre besoin.
        </p>

        <dl className="mt-5 grid gap-3 sm:grid-cols-2">
          <div className="hairline rounded-lg bg-surface/60 px-4 py-3">
            <dt className="text-[11px] tracking-wide text-muted uppercase">Téléphone</dt>
            <dd className="mt-1 text-sm font-medium">{telephone}</dd>
          </div>
          <div className="hairline rounded-lg bg-surface/60 px-4 py-3">
            <dt className="text-[11px] tracking-wide text-muted uppercase">Type de produit</dt>
            <dd className="mt-1 text-sm font-medium">{categorie.nom}</dd>
          </div>
        </dl>

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <Field label="Nom" htmlFor={idNom} erreurs={erreurs.contact_nom}>
            <Input id={idNom} value={nom} onChange={(e) => setNomSaisi(e.target.value)} autoComplete="name" required />
          </Field>

          <Field
            label="Téléphone / contact"
            htmlFor={idContact}
            erreurs={erreurs.contact_telephone}
            aide="Numéro sur lequel la boutique vous joindra."
          >
            <Input
              id={idContact}
              type="tel"
              value={contact}
              onChange={(e) => setContactSaisi(e.target.value)}
              autoComplete="tel"
              placeholder="+261XXXXXXXXX"
              required
            />
          </Field>

          <Field
            label="Produit souhaité"
            htmlFor={idProduit}
            erreurs={erreurs.produit_souhaite}
            className="sm:col-span-2"
          >
            <Input
              id={idProduit}
              value={produitSouhaite}
              onChange={(e) => setProduitSouhaite(e.target.value)}
              placeholder={`${categorie.nom} silicone noire, antichoc transparente…`}
              required
            />
          </Field>

          <Field label="Quantité" htmlFor={idQuantite} erreurs={erreurs.quantite}>
            <Input
              id={idQuantite}
              type="number"
              inputMode="numeric"
              min={1}
              value={quantite}
              onChange={(e) => setQuantite(Number(e.target.value))}
              required
            />
          </Field>

          <Field
            label="Description / précision"
            htmlFor={idPrecision}
            aide="Couleur, matière, motif… (facultatif)"
            className="sm:col-span-2"
            erreurs={erreurs.precision}
          >
            <Textarea id={idPrecision} value={precision} onChange={(e) => setPrecision(e.target.value)} rows={3} />
          </Field>
        </div>

        {erreurGlobale ? (
          <p role="alert" className="mt-4 text-sm text-rose-600 dark:text-rose-400">
            {erreurGlobale}
          </p>
        ) : null}

        <div className="mt-6 flex flex-col gap-2 sm:flex-row-reverse">
          <Button type="submit" variant="accent" size="lg" chargement={envoi}>
            Envoyer ma demande
          </Button>
          <Button type="button" variant="contour" size="lg" onClick={onRetour}>
            <ArrowLeft aria-hidden />
            Retour
          </Button>
        </div>
      </form>

      <AcompteResume prixUnitaire={prixIndicatif} quantite={quantite} />
    </div>
  );
}
