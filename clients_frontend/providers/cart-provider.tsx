"use client";

import { createContext, useCallback, useContext, useMemo, useState, useSyncExternalStore } from "react";
import { creerStorePersistant } from "@/lib/store";
import type { Produit, Variante } from "@/lib/types";

/**
 * Panier local (localStorage) — fonctionnalité 100 % frontend : l'API n'a pas
 * de panier serveur, la commande est créée d'un bloc au checkout.
 *
 * Le prix mémorisé sert à l'affichage et à `prix_attendu` lors de la
 * création : le serveur refuse la commande si le prix a changé entre-temps.
 * Le total affiché reste indicatif — seul `total_a_payer` renvoyé par l'API
 * fait foi.
 */
export type LignePanier = {
  varianteId: number;
  produitId: number;
  nom: string;
  nomComplet: string;
  couleur: string;
  prix: number;
  photo: string | null;
  boutiqueId: number;
  boutiqueNom: string;
  quantite: number;
};

const MAX_PAR_LIGNE = 99;
const VIDE: LignePanier[] = [];

const store = creerStorePersistant<LignePanier[]>("smg_client_panier", VIDE, (donnees) =>
  Array.isArray(donnees)
    ? (donnees.filter(
        (l) => !!l && typeof l === "object" && typeof l.varianteId === "number" && typeof l.quantite === "number",
      ) as LignePanier[])
    : null,
);

type CartApi = {
  lignes: LignePanier[];
  nbArticles: number;
  sousTotal: number;
  /** Les boutiques représentées dans le panier, dans l'ordre d'apparition. */
  boutiqueIds: number[];
  ouvert: boolean;
  ouvrir: () => void;
  fermer: () => void;
  /**
   * Ajoute un article, quelle que soit sa boutique : le panier peut en mêler
   * plusieurs. À la commande, le serveur l'éclate en une commande par
   * boutique propriétaire des articles — le client n'a donc jamais à choisir
   * entre deux magasins, ni à vider son panier pour changer.
   */
  ajouter: (produit: Produit, variante: Variante, quantite?: number) => void;
  /** Ajoute des lignes déjà résolues (assistant). Renvoie le nombre ajouté. */
  ajouterLignes: (lignes: LignePanier[]) => number;
  definirQuantite: (varianteId: number, quantite: number) => void;
  retirer: (varianteId: number) => void;
  vider: () => void;
};

const CartContext = createContext<CartApi | null>(null);

function ligneDepuis(produit: Produit, variante: Variante, quantite: number): LignePanier {
  return {
    varianteId: variante.id,
    produitId: produit.id,
    nom: produit.nom,
    nomComplet: produit.nom_complet,
    couleur: variante.couleur,
    prix: produit.prix_vente,
    photo: produit.photo,
    boutiqueId: produit.boutique.id,
    boutiqueNom: produit.boutique.nom,
    quantite,
  };
}

export function CartProvider({ children }: { children: React.ReactNode }) {
  const lignes = useSyncExternalStore(store.subscribe, store.get, store.getServer);
  const [ouvert, setOuvert] = useState(false);

  const boutiqueIds = useMemo(
    () => [...new Set(lignes.map((l) => l.boutiqueId))],
    [lignes],
  );

  const empiler = useCallback((produit: Produit, variante: Variante, quantite: number) => {
    store.set((actuelles) => {
      const index = actuelles.findIndex((l) => l.varianteId === variante.id);
      if (index === -1) return [...actuelles, ligneDepuis(produit, variante, quantite)];
      const copie = [...actuelles];
      copie[index] = {
        ...copie[index],
        // Le prix catalogue a pu changer depuis l'ajout : on garde le plus récent.
        prix: produit.prix_vente,
        quantite: Math.min(copie[index].quantite + quantite, MAX_PAR_LIGNE),
      };
      return copie;
    });
  }, []);

  const ajouter = useCallback<CartApi["ajouter"]>(
    (produit, variante, quantite = 1) => empiler(produit, variante, quantite),
    [empiler],
  );

  const ajouterLignes = useCallback<CartApi["ajouterLignes"]>(
    (nouvelles) => {
      let ajoutees = 0;
      store.set((actuelles) => {
        let copie = actuelles;
        for (const ligne of nouvelles) {
          ajoutees++;
          const index = copie.findIndex((l) => l.varianteId === ligne.varianteId);
          if (index === -1) {
            copie = [...copie, ligne];
          } else {
            const suite = [...copie];
            suite[index] = { ...suite[index], prix: ligne.prix, quantite: Math.min(suite[index].quantite + ligne.quantite, MAX_PAR_LIGNE) };
            copie = suite;
          }
        }
        return copie;
      });
      return ajoutees;
    },
    [],
  );

  const definirQuantite = useCallback((varianteId: number, quantite: number) => {
    store.set((actuelles) =>
      quantite < 1
        ? actuelles.filter((l) => l.varianteId !== varianteId)
        : actuelles.map((l) => (l.varianteId === varianteId ? { ...l, quantite: Math.min(quantite, MAX_PAR_LIGNE) } : l)),
    );
  }, []);

  const retirer = useCallback((varianteId: number) => store.set((a) => a.filter((l) => l.varianteId !== varianteId)), []);
  const vider = useCallback(() => store.set([]), []);

  const valeur = useMemo<CartApi>(
    () => ({
      lignes,
      nbArticles: lignes.reduce((n, l) => n + l.quantite, 0),
      sousTotal: lignes.reduce((n, l) => n + l.prix * l.quantite, 0),
      boutiqueIds,
      ouvert,
      ouvrir: () => setOuvert(true),
      fermer: () => setOuvert(false),
      ajouter,
      ajouterLignes,
      definirQuantite,
      retirer,
      vider,
    }),
    [lignes, boutiqueIds, ouvert, ajouter, ajouterLignes, definirQuantite, retirer, vider],
  );

  return <CartContext.Provider value={valeur}>{children}</CartContext.Provider>;
}

export function useCart(): CartApi {
  const ctx = useContext(CartContext);
  if (!ctx) throw new Error("useCart doit être utilisé dans <CartProvider>");
  return ctx;
}
