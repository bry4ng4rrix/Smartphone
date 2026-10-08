"use client";

import { useEffect, useMemo, useState } from "react";
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
  grouperParBoutique,
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
import type { Commande, ZonesReponse } from "@/lib/types";

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
  const [confirmees, setConfirmees] = useState<Commande[] | null>(null);

  // Le panier peut mêler plusieurs boutiques : chacune a son tarif de
  // livraison et son point de retrait, et donnera sa propre commande. Les
  // deux viennent du serveur, jamais d'une constante d'ici.
  const [zonesParBoutique, setZonesParBoutique] = useState<Record<number, ZonesReponse>>({});

  const boutiques = useMemo(() => grouperParBoutique(lignes), [lignes]);
  // Clé stable : l'effet ne se relance que si l'ENSEMBLE des boutiques change,
  // pas à chaque changement de quantité.
  const cleBoutiques = boutiques.map((b) => b.id).join(",");

  useEffect(() => {
    const ids = cleBoutiques ? cleBoutiques.split(",").map(Number) : [];
    if (ids.length === 0) return;
    let annule = false;
    (async () => {
      const reponses = await Promise.all(
        // Sans tarif, l'étape livraison affiche « — » plutôt qu'un chiffre
        // inventé ; le serveur appliquera le bon montant de toute façon.
        ids.map((id) => catalogue.zones(id).catch(() => null)),
      );
      if (annule) return;
      setZonesParBoutique(
        Object.fromEntries(
          ids.flatMap((id, i) => (reponses[i] ? [[id, reponses[i]!] as const] : [])),
        ),
      );
    })();
    return () => {
      annule = true;
    };
  }, [cleBoutiques]);

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
    if (lignes.length === 0) return;
    setEnvoi(true);
    setErreurEnvoi(null);
    try {
      // Aucune boutique n'est envoyée : le serveur route chaque article vers
      // la sienne et renvoie une commande par boutique concernée.
      const { commandes: creees } = await commandes.creer({
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
      setConfirmees(creees);
      vider();
      toast.succes(
        creees.length > 1 ? `${creees.length} commandes envoyées` : "Commande envoyée",
        `${creees.length > 1 ? "Chaque boutique" : "La boutique"} vous rappelle au ${coordonnees.telephone}.`,
      );
    } catch (e) {
      setErreurEnvoi(messageErreur(e, "Impossible d'envoyer la commande."));
    } finally {
      setEnvoi(false);
    }
  };

  if (confirmees) return <CommandeConfirmee commandes={confirmees} />;

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

  // Deux boutiques = deux remises distinctes, donc deux fois les frais. On
  // somme ce que chacune facture plutôt que d'afficher un montant unique qui
  // ne correspondrait à aucune commande.
  const frais =
    remise.mode === "RECUPERATION"
      ? 0
      : boutiques.reduce((n, b) => n + (zonesParBoutique[b.id]?.zones[0]?.prix ?? 0), 0);

  const boutiquesAvecRemise = boutiques.map((b) => ({
    ...b,
    prixLivraison: zonesParBoutique[b.id]?.zones[0]?.prix ?? null,
    pointRetrait: zonesParBoutique[b.id]?.recuperation ?? null,
  }));

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
          boutiques={boutiquesAvecRemise}
          onChange={(maj) => setRemise((r) => ({ ...r, ...maj }))}
          onSuivant={validerEtapeLivraison}
          onRetour={() => aller("coordonnees")}
        />
      ) : etape === "verification" ? (
        <EtapeVerification
          lignes={lignes}
          coordonnees={coordonnees}
          remise={remise}
          boutiques={boutiquesAvecRemise}
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
