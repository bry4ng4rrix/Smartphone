import type { Metadata } from "next";
import { notFound } from "next/navigation";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { ProductDetail } from "@/components/product/product-detail";
import { ProductCard } from "@/components/catalog/product-card";
import { Reveal } from "@/components/ui/reveal";
import { ApiError } from "@/lib/api";
import { catalogue } from "@/lib/endpoints";
import { formatAr } from "@/lib/utils";
import type { Produit } from "@/lib/types";

async function chargerProduit(id: string): Promise<Produit> {
  try {
    return await catalogue.produit(id);
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) notFound();
    throw e;
  }
}

export async function generateMetadata(props: PageProps<"/produit/[id]">): Promise<Metadata> {
  const { id } = await props.params;
  try {
    const produit = await catalogue.produit(id);
    const description = `${produit.nom_complet} — ${produit.categorie.nom} / ${produit.sous_type.nom} à ${formatAr(
      produit.prix_vente,
    )} chez ${produit.boutique.nom}.`;
    return {
      title: produit.nom_complet,
      description,
      openGraph: {
        title: `${produit.nom_complet} · Smartphone.Mg`,
        description,
        type: "website",
        images: produit.photo ? [{ url: produit.photo }] : undefined,
      },
    };
  } catch {
    return { title: "Produit" };
  }
}

export default async function ProduitPage(props: PageProps<"/produit/[id]">) {
  const { id } = await props.params;
  const produit = await chargerProduit(id);

  // Suggestions : mêmes sous-type et boutique, en excluant le produit affiché.
  let similaires: Produit[] = [];
  try {
    const page = await catalogue.produits({ sous_type: produit.sous_type.id, boutique: produit.boutique.id, page_size: 5 });
    similaires = page.results.filter((p) => p.id !== produit.id).slice(0, 4);
  } catch {
    similaires = [];
  }

  return (
    <div className="mx-auto w-full max-w-[1400px] px-4 pt-6 pb-16 sm:px-6 sm:pt-10">
      <Link
        href="/catalogue"
        className="mb-6 inline-flex items-center gap-2 text-sm text-muted transition-colors hover:text-foreground"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Retour au catalogue
      </Link>

      <ProductDetail produit={produit} />

      {similaires.length > 0 ? (
        <section className="mt-20" aria-labelledby="similaires">
          <Reveal>
            <div className="mb-6 flex items-end justify-between gap-4">
              <div>
                <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Dans la même famille</p>
                <h2 id="similaires" className="mt-2 text-2xl font-semibold tracking-tight">
                  {produit.sous_type.nom}
                </h2>
              </div>
              <Link
                href={`/catalogue?sous_type=${produit.sous_type.id}`}
                className="hidden text-sm text-accent hover:underline sm:block"
              >
                Tout voir
              </Link>
            </div>
          </Reveal>

          <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
            {similaires.map((p) => (
              <ProductCard key={p.id} produit={p} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
