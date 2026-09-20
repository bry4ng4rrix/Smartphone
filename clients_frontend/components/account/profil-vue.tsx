"use client";

import { useState } from "react";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/field";
import { ApiError, messageErreur } from "@/lib/api";
import { compte } from "@/lib/endpoints";
import { formatDate } from "@/lib/utils";
import { useAuth } from "@/providers/auth-provider";
import { useToast } from "@/providers/toast-provider";

export function ProfilVue() {
  const { client, appliquerProfil, deconnexion } = useAuth();
  const toast = useToast();
  const [profilEnvoi, setProfilEnvoi] = useState(false);
  const [profilErreur, setProfilErreur] = useState<ApiError | null>(null);
  const [mdpEnvoi, setMdpEnvoi] = useState(false);
  const [mdpErreur, setMdpErreur] = useState<ApiError | null>(null);

  if (!client) return null;

  const enregistrerProfil = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    setProfilEnvoi(true);
    setProfilErreur(null);
    try {
      const maj = await compte.majProfil({
        nom: String(data.get("nom") ?? ""),
        telephone: String(data.get("telephone") ?? ""),
        adresse: String(data.get("adresse") ?? ""),
      });
      appliquerProfil(maj);
      toast.succes("Profil enregistré");
    } catch (e) {
      if (e instanceof ApiError) setProfilErreur(e);
      else toast.erreur("Enregistrement impossible", messageErreur(e));
    } finally {
      setProfilEnvoi(false);
    }
  };

  const changerMotDePasse = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formulaire = e.currentTarget;
    const data = new FormData(formulaire);
    setMdpEnvoi(true);
    setMdpErreur(null);
    try {
      await compte.changerMotDePasse({
        ancien_mot_de_passe: String(data.get("ancien") ?? ""),
        nouveau_mot_de_passe: String(data.get("nouveau") ?? ""),
      });
      formulaire.reset();
      toast.succes("Mot de passe modifié");
    } catch (e) {
      if (e instanceof ApiError) setMdpErreur(e);
      else toast.erreur("Modification impossible", messageErreur(e));
    } finally {
      setMdpEnvoi(false);
    }
  };

  return (
    <div className="space-y-6">
      <section className="hairline rounded-xl bg-surface/50 p-5 sm:p-6" aria-labelledby="profil">
        <h2 id="profil" className="text-lg font-medium tracking-tight">
          Mes informations
        </h2>
        <p className="mt-1 text-sm text-muted">Client depuis le {formatDate(client.created_at)}</p>

        <form onSubmit={enregistrerProfil} className="mt-5 grid gap-4 sm:grid-cols-2" noValidate>
          {profilErreur ? (
            <p role="alert" className="rounded-lg bg-rose-500/10 px-4 py-3 text-sm whitespace-pre-line text-rose-700 sm:col-span-2 dark:text-rose-300">
              {profilErreur.message}
            </p>
          ) : null}

          <Field label="Nom complet" htmlFor="nom" erreurs={profilErreur?.pour("nom")}>
            <Input id="nom" name="nom" defaultValue={client.nom} autoComplete="name" required />
          </Field>

          <Field label="Téléphone" htmlFor="telephone" aide="+261XXXXXXXXX" erreurs={profilErreur?.pour("telephone")}>
            <Input id="telephone" name="telephone" defaultValue={client.telephone} type="tel" autoComplete="tel" required />
          </Field>

          <Field label="Adresse" htmlFor="adresse" className="sm:col-span-2" erreurs={profilErreur?.pour("adresse")}>
            <Input id="adresse" name="adresse" defaultValue={client.adresse} autoComplete="street-address" />
          </Field>

          <Field label="Adresse e-mail" htmlFor="email" aide="L'e-mail de connexion n'est pas modifiable." className="sm:col-span-2">
            <Input id="email" value={client.email} readOnly disabled />
          </Field>

          <div className="sm:col-span-2">
            <Button type="submit" variant="accent" chargement={profilEnvoi}>
              Enregistrer
            </Button>
          </div>
        </form>
      </section>

      <section className="hairline rounded-xl bg-surface/50 p-5 sm:p-6" aria-labelledby="motdepasse">
        <h2 id="motdepasse" className="text-lg font-medium tracking-tight">
          Mot de passe
        </h2>

        <form onSubmit={changerMotDePasse} className="mt-5 grid gap-4 sm:grid-cols-2" noValidate>
          {mdpErreur ? (
            <p role="alert" className="rounded-lg bg-rose-500/10 px-4 py-3 text-sm whitespace-pre-line text-rose-700 sm:col-span-2 dark:text-rose-300">
              {mdpErreur.message}
            </p>
          ) : null}

          <Field label="Mot de passe actuel" htmlFor="ancien" erreurs={mdpErreur?.pour("ancien_mot_de_passe")}>
            <Input id="ancien" name="ancien" type="password" autoComplete="current-password" required />
          </Field>

          <Field label="Nouveau mot de passe" htmlFor="nouveau" aide="8 caractères minimum." erreurs={mdpErreur?.pour("nouveau_mot_de_passe")}>
            <Input id="nouveau" name="nouveau" type="password" autoComplete="new-password" minLength={8} required />
          </Field>

          <div className="sm:col-span-2">
            <Button type="submit" variant="contour" chargement={mdpEnvoi}>
              Modifier le mot de passe
            </Button>
          </div>
        </form>
      </section>

      <Button variant="fantome" onClick={deconnexion}>
        <LogOut aria-hidden />
        Se déconnecter
      </Button>
    </div>
  );
}
