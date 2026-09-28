"use client";

import { useEffect, useState } from "react";
import { ShoppingBag } from "lucide-react";
import { ButtonLink } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Etapes } from "@/components/checkout/etapes";
import { EtapeCoordonnees } from "@/components/checkout/etape-coordonnees";
import { EtapeLivraison } from "@/components/checkout/etape-livraison";
import { EtapeVerification } from "@/components/checkout/etape-verification";
import { EtapeConfirmation } from "@/components/checkout/etape-confirmation";
import { CommandeConfirmee } from "@/components/checkout/commande-confirmee";
import { messageErreur } from "@/lib/api";
import { catalogue, commandes } from "@/lib/endpoints";
import {
  COORDONNEES_VIDES,
  REMISE_VIDE,
  aucuneErreur,
  indexEtape,
  normaliserTelephone,
  validerCoordonnees,
  validerRemise,
  type Coordonnees,
  type Erreurs,
  type Etape,
  type Remise,
} from "@/lib/commande";
import { useCart } from "@/providers/cart-provider";
import { useToast } from "@/providers/toast-provider";
import type { Commande } from "@/lib/types";

/**
 * Tunnel de commande, sans compte.
 *
 * Quatre étapes, quatre validations : coordonnées, livraison, vérification
 * complète (tout y est modifiable), puis confirmation ferme — attestation
 * cochée et fenêtre de confirmation. La commande part ensuite « en attente
 * d'approbation » et le gérant rappelle.
 *
 * Les montants affichés sont indicatifs : le serveur recalcule les frais et
 * le total à partir du catalogue et de la zone. Le navigateur n'envoie jamais
 * de montant.
 */
export function CheckoutVue() {
  const { lignes, nbArticles, sousTotal, definirQuantite, retirer, vider } = useCart();
  const toast = useToast();

  const [etape, setEtape] = useState<Etape>("coordonnees");
  const [atteinte, setAtteinte] = useState<Etape>("coordonnees");
  const [coordonnees, setCoordonnees] = useState<Coordonnees>(COORDONNEES_VIDES);
  const [remise, setRemise] = useState<Remise>(REMISE_VIDE);
  const [erreurs, setErreurs] = useState<Erreurs>({});
  const [envoi, setEnvoi] = useState(false);
  const [erreurEnvoi, setErreurEnvoi] = useState<string | null>(null);
  const [confirmee, setConfirmee] = useState<Commande | null>(null);

  // Tarif de livraison : il vient du serveur, jamais d'une constante d'ici.
  const [prixLivraison, setPrixLivraison] = useState<number | null>(null);
  const boutiqueId = lignes[0]?.boutiqueId ?? null;

  useEffect(() => {
    if (boutiqueId === null) return;
    let annule = false;
    (async () => {
      try {
        const reponse = await catalogue.zones(boutiqueId);
        if (!annule) setPrixLivraison(reponse.zones[0]?.prix ?? null);
      } catch {
        // Sans tarif, l'étape livraison affiche « — » plutôt qu'un chiffre
        // inventé ; le serveur appliquera le bon montant de toute façon.
        if (!annule) setPrixLivraison(null);
      }
    })();
    return () => {
      annule = true;
    };
  }, [boutiqueId]);

  const aller = (cible: Etape) => {
    setEtape(cible);
    if (indexEtape(cible) > indexEtape(atteinte)) setAtteinte(cible);
    setErreurs({});
  };

  const validerEtapeCoordonnees = () => {
    const trouvees = validerCoordonnees(coordonnees);
    setErreurs(trouvees);
    if (!aucuneErreur(trouvees)) return;
    // On fige la forme canonique dès la validation : ce que le client relira
    // ensuite est exactement ce qui partira au serveur.
    setCoordonnees((c) => ({
      ...c,
      nom: c.nom.trim(),
      telephone: normaliserTelephone(c.telephone),
      telephone2: normaliserTelephone(c.telephone2),
    }));
    aller("livraison");
  };

  const validerEtapeLivraison = () => {
    const trouvees = validerRemise(remise);
    setErreurs(trouvees);
    if (!aucuneErreur(trouvees)) return;
    setRemise((r) => ({ ...r, adresse: r.adresse.trim(), note: r.note.trim() }));
    aller("verification");
  };

  const envoyer = async () => {
    if (boutiqueId === null || lignes.length === 0) return;
    setEnvoi(true);
    setErreurEnvoi(null);
    try {
      const commande = await commandes.creer({
        boutique: boutiqueId,
        items: lignes.map((l) => ({
          variante: l.varianteId,
          quantite: l.quantite,
          // Prix vu au moment de l'ajout : le serveur refuse la commande s'il
          // a changé entre-temps, plutôt que de facturer autre chose.
          prix_attendu: l.prix,
        })),
        livraison_zone: remise.mode,
        client_nom: coordonnees.nom,
        telephone: coordonnees.telephone,
        telephone_2: coordonnees.telephone2 || undefined,
        adresse_livraison: remise.mode === "EN_LIGNE" ? remise.adresse : undefined,
        note: remise.note || undefined,
      });
      setConfirmee(commande);
      vider();
      toast.succes("Commande envoyée", `La boutique vous rappelle au ${commande.telephone}.`);
    } catch (e) {
      setErreurEnvoi(messageErreur(e, "Impossible d'envoyer la commande."));
    } finally {
      setEnvoi(false);
    }
  };

  if (confirmee) return <CommandeConfirmee commande={confirmee} />;

  if (lignes.length === 0) {
    return (
      <EmptyState
        icone={ShoppingBag}
        titre="Votre panier est vide."
        description="Ajoutez des articles avant de passer commande."
        action={
          <ButtonLink href="/catalogue" variant="primaire">
            Voir le catalogue
          </ButtonLink>
        }
        className="hairline bg-surface/40"
      />
    );
  }

  const frais = remise.mode === "RECUPERATION" ? 0 : (prixLivraison ?? 0);

  return (
    <div>
      <Etapes courante={etape} atteinte={atteinte} onAller={aller} />

      {etape === "coordonnees" ? (
        <EtapeCoordonnees
          valeurs={coordonnees}
          erreurs={erreurs}
          onChange={(maj) => setCoordonnees((c) => ({ ...c, ...maj }))}
          onSuivant={validerEtapeCoordonnees}
        />
      ) : etape === "livraison" ? (
        <EtapeLivraison
          valeurs={remise}
          erreurs={erreurs}
          prixLivraison={prixLivraison}
          onChange={(maj) => setRemise((r) => ({ ...r, ...maj }))}
          onSuivant={validerEtapeLivraison}
          onRetour={() => aller("coordonnees")}
        />
      ) : etape === "verification" ? (
        <EtapeVerification
          lignes={lignes}
          coordonnees={coordonnees}
          remise={remise}
          sousTotal={sousTotal}
          fraisLivraison={frais}
          onQuantite={definirQuantite}
          onRetirer={retirer}
          onModifierCoordonnees={() => setEtape("coordonnees")}
          onModifierLivraison={() => setEtape("livraison")}
          onSuivant={() => aller("confirmation")}
          onRetour={() => setEtape("livraison")}
        />
      ) : (
        <EtapeConfirmation
          coordonnees={coordonnees}
          remise={remise}
          total={sousTotal + frais}
          envoi={envoi}
          erreur={erreurEnvoi}
          onConfirmer={envoyer}
          onRetour={() => setEtape("verification")}
        />
      )}

      <p className="mt-6 text-center text-xs text-muted">
        {nbArticles} {nbArticles > 1 ? "articles" : "article"} · aucun paiement en ligne, vous réglez à la remise.
      </p>
    </div>
  );
}
