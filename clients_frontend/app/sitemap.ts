import type { MetadataRoute } from "next";
import { catalogue } from "@/lib/endpoints";

const SITE = process.env.SITE_URL ?? "http://localhost:3000";

/** Pages publiques + fiches produit réellement présentes au catalogue. */
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const pages: MetadataRoute.Sitemap = [
    { url: `${SITE}/`, changeFrequency: "weekly", priority: 1 },
    { url: `${SITE}/catalogue`, changeFrequency: "daily", priority: 0.9 },
  ];

  try {
    const [categories, produits] = await Promise.all([
      catalogue.categories(),
      catalogue.produits({ page_size: 100 }),
    ]);

    for (const c of categories) {
      pages.push({ url: `${SITE}/catalogue?category=${c.id}`, changeFrequency: "weekly", priority: 0.7 });
    }
    for (const p of produits.results) {
      pages.push({ url: `${SITE}/produit/${p.id}`, changeFrequency: "weekly", priority: 0.6 });
    }
  } catch {
    // API injoignable au moment de la génération : le plan de site se limite
    // aux pages fixes plutôt que d'échouer.
  }

  return pages;
}
