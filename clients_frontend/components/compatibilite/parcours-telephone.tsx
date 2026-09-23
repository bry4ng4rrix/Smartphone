"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { PhoneSelector } from "@/components/compatibilite/phone-selector";
import { ResultatsCompatibles } from "@/components/compatibilite/resultats-compatibles";
import { CommandeSpeciale } from "@/components/compatibilite/commande-speciale";
import { useModelesTelephone } from "@/hooks/use-modeles-telephone";
import { accrocheParcours, prixIndicatif, trouverModele } from "@/lib/compatibilite";
import type { Categorie, Marque } from "@/lib/types";

type Etape = "selection" | "resultats" | "commande";

/**
 * Chef d'orchestre du parcours Housse / Cache-écran.
 *
 * Entonnoir guidé, donc état local plutôt qu'état d'URL : le catalogue reste
 * la surface filtrable et partageable (`/catalogue?...`), cette page-ci
 * accompagne une décision en trois temps.
 */
export function ParcoursTelephone({
  categorie,
  slug,
  libelle,
  marques,
}: {
  categorie: Categorie;
  slug: string;
  libelle: string;
  marques: Marque[];
}) {
  const [marqueId, setMarqueId] = useState<number | null>(null);
  const [modele, setModele] = useState("");
  const [etape, setEtape] = useState<Etape>("selection");
  const [recherche, setRecherche] = useState<{ marque: Marque; modele: string } | null>(null);

  const { modeles, chargement, erreur, reessayer } = useModelesTelephone(categorie.id, marqueId);

  /** Produits de la catégorie qui vont sur le téléphone recherché. */
  const compatibles = useMemo(() => {
    if (!recherche) return [];
    return trouverModele(modeles, recherche.modele)?.produits ?? [];
  }, [modeles, recherche]);

  const lancerRecherche = () => {
    const marque = marques.find((m) => m.id === marqueId);
    if (!marque || !modele.trim()) return;
    setRecherche({ marque, modele: modele.trim() });
    setEtape("resultats");
  };

  const revenirSelection = () => {
    setEtape("selection");
    setRecherche(null);
  };

  const telephone = recherche ? `${recherche.marque.nom} ${recherche.modele}`.trim() : "";

  return (
    <div className="mt-8">
      {etape === "selection" ? (
        <PhoneSelector
          libelle={libelle}
          marques={marques}
          marqueId={marqueId}
          onMarqueChange={(id) => {
            setMarqueId(id);
            setModele("");
          }}
          modele={modele}
          onModeleChange={setModele}
          modeles={modeles}
          chargement={chargement}
          erreur={erreur}
          onReessayer={reessayer}
          onRechercher={lancerRecherche}
        />
      ) : (
        <>
          <button
            type="button"
            onClick={revenirSelection}
            className="mb-6 inline-flex items-center gap-1.5 text-sm text-muted transition-colors hover:text-foreground"
          >
            <ArrowLeft className="size-4" aria-hidden />
            Changer de téléphone
          </button>

          {etape === "resultats" ? (
            <ResultatsCompatibles
              libelle={libelle}
              accroche={accrocheParcours(slug)}
              telephone={telephone}
              produits={compatibles}
              onCommandeSpeciale={() => setEtape("commande")}
            />
          ) : recherche ? (
            <CommandeSpeciale
              categorie={categorie}
              marque={recherche.marque}
              modele={recherche.modele}
              boutiqueId={categorie.boutique}
              prixIndicatif={prixIndicatif(compatibles)}
              onRetour={() => setEtape("resultats")}
            />
          ) : null}
        </>
      )}

      <p className="mt-10 text-center text-sm text-muted">
        Vous cherchez autre chose ?{" "}
        <Link href="/catalogue" className="text-accent hover:underline">
          Parcourir tout le catalogue
        </Link>
      </p>
    </div>
  );
}
