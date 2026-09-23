import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { WifiOff } from "lucide-react";
import { ParcoursTelephone } from "@/components/compatibilite/parcours-telephone";
import { Aurora } from "@/components/ui/aurora";
import { EmptyState } from "@/components/ui/empty-state";
import { ButtonLink } from "@/components/ui/button";
import { catalogue } from "@/lib/endpoints";
import { categorieDuSlug, libelleParcours } from "@/lib/compatibilite";
import type { Categorie, Marque } from "@/lib/types";

/**
 * Page d'entrée Housse / Cache-écran : on demande d'abord le téléphone, au
 * lieu de déverser un listing général. Le listing reste accessible par
 * `/catalogue?category=...` — rien n'est retiré, un chemin est ajouté.
 */

async function charger(slug: string): Promise<{ categorie?: Categorie; marques: Marque[]; enPanne: boolean }> {
  try {
    const [categories, marques] = await Promise.all([catalogue.categories(), catalogue.marques()]);
    return { categorie: categorieDuSlug(categories, slug), marques, enPanne: false };
  } catch {
    return { marques: [], enPanne: true };
  }
}

export async function generateMetadata({ params }: PageProps<"/compatibilite/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  const libelle = libelleParcours(slug);
  if (!libelle) return {};
  return {
    title: `${libelle} par téléphone`,
    description: `Trouvez la ${libelle.toLowerCase()} compatible avec votre téléphone : choisissez la marque et le modèle, nous affichons les produits adaptés et disponibles.`,
  };
}

export default async function CompatibilitePage({ params }: PageProps<"/compatibilite/[slug]">) {
  const { slug } = await params;
  const libelle = libelleParcours(slug);
  if (!libelle) notFound();

  const { categorie, marques, enPanne } = await charger(slug);

  return (
    <div className="relative mx-auto w-full max-w-[1400px] px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <Aurora intensite="discrete" />

      <header>
        <p className="text-[11px] font-medium tracking-[0.18em] text-muted uppercase">{libelle}</p>
        <h1 className="mt-2 text-2xl font-medium tracking-tight sm:text-3xl">Pour quel téléphone ?</h1>
      </header>

      {enPanne ? (
        <EmptyState
          icone={WifiOff}
          titre="Catalogue momentanément injoignable."
          description="Impossible de charger les marques. Réessayez dans un instant."
          action={
            <ButtonLink href="/catalogue" variant="primaire">
              Voir le catalogue
            </ButtonLink>
          }
          className="hairline mt-8 bg-surface/40"
        />
      ) : !categorie ? (
        <EmptyState
          icone={WifiOff}
          titre={`Aucune catégorie « ${libelle} » dans cette boutique.`}
          description="Le catalogue complet reste accessible."
          action={
            <ButtonLink href="/catalogue" variant="primaire">
              Voir le catalogue
            </ButtonLink>
          }
          className="hairline mt-8 bg-surface/40"
        />
      ) : (
        <ParcoursTelephone categorie={categorie} slug={slug} libelle={libelle} marques={marques} />
      )}
    </div>
  );
}
