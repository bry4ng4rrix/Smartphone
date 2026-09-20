"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/field";
import { ApiError, messageErreur } from "@/lib/api";
import { useAuth } from "@/providers/auth-provider";
import { useToast } from "@/providers/toast-provider";

function useErreurs() {
  const [erreur, setErreur] = useState<ApiError | null>(null);
  return {
    erreur,
    setErreur,
    champ: (nom: string) => erreur?.pour(nom),
    // Les messages sans champ identifié (`detail`, non-champ) vont en haut du formulaire.
    globales: () => {
      if (!erreur) return [];
      const connus = new Set(["email", "password", "nom", "telephone", "adresse", "ancien_mot_de_passe", "nouveau_mot_de_passe"]);
      const restes = Object.entries(erreur.champs)
        .filter(([cle]) => !connus.has(cle))
        .flatMap(([, messages]) => messages);
      return restes.length ? restes : erreur.status === 0 ? [erreur.message] : [];
    },
  };
}

function Alerte({ messages }: { messages: string[] }) {
  if (!messages.length) return null;
  return (
    <p role="alert" className="rounded-lg bg-rose-500/10 px-4 py-3 text-sm whitespace-pre-line text-rose-700 dark:text-rose-300">
      {messages.join("\n")}
    </p>
  );
}

export function FormulaireConnexion() {
  const { connexion } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const toast = useToast();
  const { erreur, setErreur, champ, globales } = useErreurs();
  const [envoi, setEnvoi] = useState(false);

  const suite = params.get("suite") || "/compte";

  const soumettre = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    setEnvoi(true);
    setErreur(null);
    try {
      const client = await connexion(String(data.get("email") ?? ""), String(data.get("password") ?? ""));
      toast.succes("Bienvenue", client.nom);
      router.replace(suite);
    } catch (e) {
      if (e instanceof ApiError) setErreur(e);
      else toast.erreur("Connexion impossible", messageErreur(e));
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <form onSubmit={soumettre} className="space-y-4" noValidate>
      <Alerte messages={[...globales(), ...(erreur?.status === 401 ? [erreur.message] : [])]} />

      <Field label="Adresse e-mail" htmlFor="email" erreurs={champ("email")}>
        <Input id="email" name="email" type="email" autoComplete="email" required placeholder="vous@exemple.mg" />
      </Field>

      <Field label="Mot de passe" htmlFor="password" erreurs={champ("password")}>
        <Input id="password" name="password" type="password" autoComplete="current-password" required placeholder="••••••••" />
      </Field>

      <Button type="submit" variant="accent" size="lg" className="w-full" chargement={envoi}>
        Se connecter
      </Button>

      <p className="text-center text-sm text-muted">
        Pas encore de compte ?{" "}
        <Link href={`/inscription${suite !== "/compte" ? `?suite=${encodeURIComponent(suite)}` : ""}`} className="text-accent hover:underline">
          Créer un compte
        </Link>
      </p>
    </form>
  );
}

export function FormulaireInscription() {
  const { inscription } = useAuth();
  const router = useRouter();
  const params = useSearchParams();
  const toast = useToast();
  const { setErreur, champ, globales } = useErreurs();
  const [envoi, setEnvoi] = useState(false);

  const suite = params.get("suite") || "/compte";

  const soumettre = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    setEnvoi(true);
    setErreur(null);
    try {
      const client = await inscription({
        email: String(data.get("email") ?? ""),
        password: String(data.get("password") ?? ""),
        nom: String(data.get("nom") ?? ""),
        telephone: String(data.get("telephone") ?? ""),
        adresse: String(data.get("adresse") ?? ""),
      });
      toast.succes("Compte créé", `Bienvenue ${client.nom}`);
      router.replace(suite);
    } catch (e) {
      if (e instanceof ApiError) setErreur(e);
      else toast.erreur("Inscription impossible", messageErreur(e));
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <form onSubmit={soumettre} className="space-y-4" noValidate>
      <Alerte messages={globales()} />

      <Field label="Nom complet" htmlFor="nom" erreurs={champ("nom")}>
        <Input id="nom" name="nom" autoComplete="name" required placeholder="Rakoto Jean" />
      </Field>

      <Field label="Adresse e-mail" htmlFor="email" erreurs={champ("email")}>
        <Input id="email" name="email" type="email" autoComplete="email" required placeholder="vous@exemple.mg" />
      </Field>

      <Field
        label="Téléphone"
        htmlFor="telephone"
        aide="Format international : +261XXXXXXXXX"
        erreurs={champ("telephone")}
      >
        <Input id="telephone" name="telephone" type="tel" autoComplete="tel" required placeholder="+261341234567" />
      </Field>

      <Field label="Adresse (facultatif)" htmlFor="adresse" aide="Réutilisée par défaut à la livraison." erreurs={champ("adresse")}>
        <Input id="adresse" name="adresse" autoComplete="street-address" placeholder="Lot II A Antananarivo" />
      </Field>

      <Field label="Mot de passe" htmlFor="password" aide="8 caractères minimum." erreurs={champ("password")}>
        <Input id="password" name="password" type="password" autoComplete="new-password" required minLength={8} placeholder="••••••••" />
      </Field>

      <Button type="submit" variant="accent" size="lg" className="w-full" chargement={envoi}>
        Créer mon compte
      </Button>

      <p className="text-center text-sm text-muted">
        Déjà client ?{" "}
        <Link href={`/connexion${suite !== "/compte" ? `?suite=${encodeURIComponent(suite)}` : ""}`} className="text-accent hover:underline">
          Se connecter
        </Link>
      </p>
    </form>
  );
}
