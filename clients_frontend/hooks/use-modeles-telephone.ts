"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { messageErreur } from "@/lib/api";
import { catalogue } from "@/lib/endpoints";
import { grouperParModele, type ModeleTelephone } from "@/lib/compatibilite";
import type { Produit } from "@/lib/types";

/** Garde-fou : une boutique n'a pas 1 000 modèles pour une même marque, mais
 *  une pagination qui ne s'arrête jamais boucle sur un backend défaillant. */
const PAGES_MAX = 10;
const TAILLE_PAGE = 100; // maximum accepté par GET /api/produit/

/** Identité stable : évite de recalculer les modèles à chaque rendu. */
const AUCUN: Produit[] = [];

type Charge = { cle: string; produits: Produit[]; erreur: string | null };

type Etat = {
  modeles: ModeleTelephone[];
  produits: Produit[];
  chargement: boolean;
  erreur: string | null;
  reessayer: () => void;
};

/**
 * Les modèles de téléphone couverts par une catégorie pour une marque.
 *
 * Il n'existe pas d'endpoint dédié (voir « Modèles d'une marque » dans les
 * propositions d'évolution de client_endpoint.md) : on dérive la liste des
 * références renvoyées par `GET /api/produit/`, qui portent déjà le modèle
 * dans leur champ `nom`. Ces mêmes références servent ensuite de résultats
 * de recherche — un seul chargement pour les deux étapes du parcours.
 *
 * L'état porte la clé du jeu de données qu'il contient : « en chargement »
 * se déduit de l'écart entre la clé demandée et la clé chargée, plutôt que
 * d'un `setState` synchrone dans l'effet.
 */
export function useModelesTelephone(categorieId: number, marqueId: number | null): Etat {
  const [charge, setCharge] = useState<Charge | null>(null);
  const [essai, setEssai] = useState(0);

  // `essai` fait partie de la clé : réessayer relance vraiment un chargement.
  const cle = marqueId === null ? null : `${categorieId}:${marqueId}:${essai}`;

  const reessayer = useCallback(() => setEssai((n) => n + 1), []);

  useEffect(() => {
    if (cle === null || marqueId === null) return;

    let annule = false;
    (async () => {
      try {
        const cumul: Produit[] = [];
        for (let page = 1; page <= PAGES_MAX; page++) {
          const reponse = await catalogue.produits({
            category: categorieId,
            brand: marqueId,
            page,
            page_size: TAILLE_PAGE,
          });
          cumul.push(...reponse.results);
          if (!reponse.next) break;
        }
        if (!annule) setCharge({ cle, produits: cumul, erreur: null });
      } catch (e) {
        if (!annule) {
          setCharge({
            cle,
            produits: [],
            erreur: messageErreur(e, "Impossible de charger les modèles pour cette marque."),
          });
        }
      }
    })();

    return () => {
      annule = true;
    };
  }, [cle, categorieId, marqueId]);

  const aJour = cle !== null && charge?.cle === cle;
  const produits = aJour ? charge.produits : AUCUN;
  const modeles = useMemo(() => grouperParModele(produits), [produits]);

  return {
    modeles,
    produits,
    chargement: cle !== null && !aJour,
    erreur: aJour ? charge.erreur : null,
    reessayer,
  };
}
