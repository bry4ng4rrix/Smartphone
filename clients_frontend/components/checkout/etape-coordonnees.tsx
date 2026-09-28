"use client";

import { useId } from "react";
import { ArrowRight, Phone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/field";
import { TELEPHONE_AIDE, type Coordonnees, type Erreurs } from "@/lib/commande";

/**
 * Étape 1 — qui commande.
 *
 * Le téléphone est le seul moyen de vous joindre : la boutique n'a plus de
 * compte à consulter, elle rappelle sur ce numéro pour confirmer. Le libellé
 * le dit, pour que le client comprenne pourquoi on insiste.
 */
export function EtapeCoordonnees({
  valeurs,
  erreurs,
  onChange,
  onSuivant,
}: {
  valeurs: Coordonnees;
  erreurs: Erreurs;
  onChange: (maj: Partial<Coordonnees>) => void;
  onSuivant: () => void;
}) {
  const idNom = useId();
  const idTel = useId();
  const idTel2 = useId();

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSuivant();
      }}
      noValidate
      className="hairline rounded-xl bg-surface/50 p-5 sm:p-6"
    >
      <h2 className="text-base font-medium tracking-tight">Vos coordonnées</h2>
      <p className="mt-1.5 flex items-start gap-2 text-sm text-muted">
        <Phone className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>
          La boutique vous appelle pour confirmer la commande avant de la préparer. Vérifiez bien votre numéro.
        </span>
      </p>

      <div className="mt-6 grid gap-4 sm:grid-cols-2">
        <Field label="Nom complet" htmlFor={idNom} erreurs={erreurs.nom ? [erreurs.nom] : undefined} className="sm:col-span-2">
          <Input
            id={idNom}
            value={valeurs.nom}
            onChange={(e) => onChange({ nom: e.target.value })}
            autoComplete="name"
            placeholder="Rakoto Jean"
            required
          />
        </Field>

        <Field
          label="Téléphone"
          htmlFor={idTel}
          aide={TELEPHONE_AIDE}
          erreurs={erreurs.telephone ? [erreurs.telephone] : undefined}
        >
          <Input
            id={idTel}
            type="tel"
            inputMode="tel"
            value={valeurs.telephone}
            onChange={(e) => onChange({ telephone: e.target.value })}
            autoComplete="tel"
            placeholder="+261 34 00 000 00"
            required
          />
        </Field>

        <Field
          label="Autre numéro (facultatif)"
          htmlFor={idTel2}
          aide="Utilisé si le premier ne répond pas."
          erreurs={erreurs.telephone2 ? [erreurs.telephone2] : undefined}
        >
          <Input
            id={idTel2}
            type="tel"
            inputMode="tel"
            value={valeurs.telephone2}
            onChange={(e) => onChange({ telephone2: e.target.value })}
            autoComplete="tel"
            placeholder="+261 32 00 000 00"
          />
        </Field>
      </div>

      <div className="mt-6 flex justify-end">
        <Button type="submit" variant="primaire" size="lg">
          Continuer
          <ArrowRight aria-hidden />
        </Button>
      </div>
    </form>
  );
}
