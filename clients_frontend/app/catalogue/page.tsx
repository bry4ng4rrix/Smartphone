import type { Metadata } from "next";
import { WifiOff } from "lucide-react";
import { CatalogGrid } from "@/components/catalog/catalog-grid";
import { FiltresContenu, FiltresMobile, type Referentiels } from "@/components/catalog/filters";
import { EmptyState } from "@/components/ui/empty-state";
import { catalogue } from "@/lib/endpoints";
import type { Page, Produit } from "@/lib/types";

export const metadata: Metadata = {
  title: "Catalogue",
  description: "Housses, cache-écrans et accessoires pour smartphone — filtrez par catégorie, marque, couleur et prix.",
};

function nombre(valeur: string | string[] | undefined): number | undefined {
  const v = Array.isArray(valeur) ? valeur[0] : valeur;
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) ? n : undefined;
}

function texte(valeur: string | string[] | undefined): string | undefined {
  const v = Array.isArray(valeur) ? valeur[0] : valeur;
  return v || undefined;
}

export default async function CataloguePage(props: PageProps<"/catalogue">) {
  const sp = await props.searchParams;

  const params = {
    search: texte(sp.search),
    category: nombre(sp.category),
    sous_type: nombre(sp.sous_type),
    brand: nombre(sp.brand),
    couleur: texte(sp.couleur),
    available: texte(sp.available) === "1" ? "1" : undefined,
    min_price: nombre(sp.min_price),
    max_price: nombre(sp.max_price),
    boutique: nombre(sp.boutique),
  };

  let produits: Page<Produit> | null = null;
  let referentiels: Referentiels = { categories: [], sousTypes: [], marques: [], couleurs: [] };

  try {
    const [page, categories, sousTypes, marques, couleurs] = await Promise.all([
      catalogue.produits(params),
      catalogue.categories(params.boutique),
      catalogue.sousTypes({ boutique: params.boutique }),
      catalogue.marques(params.boutique),
      catalogue.couleurs(params.boutique),
    ]);
    produits = page;
    referentiels = { categories, sousTypes, marques, couleurs };
  } catch {
    produits = null;
  }

  return (
    <div className="mx-auto w-full max-w-[1400px] px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <header className="mb-8">
        <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Boutique</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">
          {params.search ? `Recherche « ${params.search} »` : "Catalogue"}
        </h1>
        <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted">
          Chaque produit est proposé dans les coloris réellement disponibles en boutique.
        </p>
      </header>

      {produits === null ? (
        <EmptyState
          icone={WifiOff}
          titre="Catalogue momentanément indisponible"
          description="Le serveur de la boutique ne répond pas. Réessayez dans quelques instants."
          className="hairline bg-surface/40"
        />
      ) : (
        <div className="lg:grid lg:grid-cols-[260px_1fr] lg:gap-10">
          <aside className="hidden lg:block">
            <div className="sticky top-24">
              <h2 className="mb-4 text-sm font-medium tracking-tight">Filtres</h2>
              <FiltresContenu referentiels={referentiels} />
            </div>
          </aside>

          <div>
            <div className="mb-4 lg:hidden">
              <FiltresMobile referentiels={referentiels} nbResultats={produits.count} />
            </div>
            <CatalogGrid key={JSON.stringify(params)} pageInitiale={produits} params={params} />
          </div>
        </div>
      )}
    </div>
  );
}
