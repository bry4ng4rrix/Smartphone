"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { Produit, Variante } from "@/lib/types";

/**
 * Panier local (localStorage) — fonctionnalité 100 % frontend : l'API n'a pas
 * de panier serveur, la commande est créée d'un bloc au checkout.
 *
 * Le prix mémorisé (`prix`) sert à deux choses : l'affichage, et
 * `prix_attendu` à la création de commande — le serveur refuse la commande
 * si son prix a changé entre-temps. Le total affiché reste indicatif : seul
 * `total_a_payer` renvoyé par l'API fait foi.
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

const CLE = "smg_client_panier";
const MAX_PAR_LIGNE = 99;

type CartApi = {
  lignes: LignePanier[];
  pret: boolean;
  nbArticles: number;
  sousTotal: number;
  boutiqueId: number | null;
  ouvert: boolean;
  ouvrir: () => void;
  fermer: () => void;
  /** `false` si l'article vient d'une autre boutique que le panier en cours. */
  ajouter: (produit: Produit, variante: Variante, quantite?: number) => boolean;
  /** Vide le panier puis ajoute — utilisé après confirmation du changement de boutique. */
  remplacerPar: (produit: Produit, variante: Variante, quantite?: number) => void;
  definirQuantite: (varianteId: number, quantite: number) => void;
  retirer: (varianteId: number) => void;
  vider: () => void;
};

const CartContext = createContext<CartApi | null>(null);

function lire(): LignePanier[] {
  try {
    const brut = localStorage.getItem(CLE);
    if (!brut) return [];
    const data: unknown = JSON.parse(brut);
    if (!Array.isArray(data)) return [];
    return data.filter(
      (l): l is LignePanier =>
        !!l && typeof l === "object" && typeof (l as LignePanier).varianteId === "number" && typeof (l as LignePanier).quantite === "number",
    );
  } catch {
    return [];
  }
}

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
  const [lignes, setLignes] = useState<LignePanier[]>([]);
  const [pret, setPret] = useState(false);
  const [ouvert, setOuvert] = useState(false);

  useEffect(() => {
    setLignes(lire());
    setPret(true);
  }, []);

  useEffect(() => {
    if (!pret) return;
    try {
      localStorage.setItem(CLE, JSON.stringify(lignes));
    } catch {
      /* stockage indisponible : le panier ne survivra pas au rechargement */
    }
  }, [lignes, pret]);

  // Panier partagé entre les onglets ouverts.
  useEffect(() => {
    const surStorage = (e: StorageEvent) => {
      if (e.key === CLE) setLignes(lire());
    };
    window.addEventListener("storage", surStorage);
    return () => window.removeEventListener("storage", surStorage);
  }, []);

  const empiler = useCallback((produit: Produit, variante: Variante, quantite: number) => {
    setLignes((actuelles) => {
      const index = actuelles.findIndex((l) => l.varianteId === variante.id);
      if (index === -1) return [...actuelles, ligneDepuis(produit, variante, quantite)];
      const copie = [...actuelles];
      copie[index] = {
        ...copie[index],
        // Le prix catalogue peut avoir changé depuis l'ajout : on garde le plus récent.
        prix: produit.prix_vente,
        quantite: Math.min(copie[index].quantite + quantite, MAX_PAR_LIGNE),
      };
      return copie;
    });
  }, []);

  const boutiqueId = lignes[0]?.boutiqueId ?? null;

  const ajouter = useCallback<CartApi["ajouter"]>(
    (produit, variante, quantite = 1) => {
      // Une commande = une boutique (règle serveur) : on ne mélange pas.
      if (boutiqueId !== null && boutiqueId !== produit.boutique.id) return false;
      empiler(produit, variante, quantite);
      return true;
    },
    [boutiqueId, empiler],
  );

  const remplacerPar = useCallback<CartApi["remplacerPar"]>(
    (produit, variante, quantite = 1) => setLignes([ligneDepuis(produit, variante, quantite)]),
    [],
  );

  const definirQuantite = useCallback((varianteId: number, quantite: number) => {
    setLignes((actuelles) =>
      quantite < 1
        ? actuelles.filter((l) => l.varianteId !== varianteId)
        : actuelles.map((l) => (l.varianteId === varianteId ? { ...l, quantite: Math.min(quantite, MAX_PAR_LIGNE) } : l)),
    );
  }, []);

  const retirer = useCallback((varianteId: number) => setLignes((a) => a.filter((l) => l.varianteId !== varianteId)), []);
  const vider = useCallback(() => setLignes([]), []);

  const valeur = useMemo<CartApi>(
    () => ({
      lignes,
      pret,
      nbArticles: lignes.reduce((n, l) => n + l.quantite, 0),
      sousTotal: lignes.reduce((n, l) => n + l.prix * l.quantite, 0),
      boutiqueId,
      ouvert,
      ouvrir: () => setOuvert(true),
      fermer: () => setOuvert(false),
      ajouter,
      remplacerPar,
      definirQuantite,
      retirer,
      vider,
    }),
    [lignes, pret, boutiqueId, ouvert, ajouter, remplacerPar, definirQuantite, retirer, vider],
  );

  return <CartContext.Provider value={valeur}>{children}</CartContext.Provider>;
}

export function useCart(): CartApi {
  const ctx = useContext(CartContext);
  if (!ctx) throw new Error("useCart doit être utilisé dans <CartProvider>");
  return ctx;
}
