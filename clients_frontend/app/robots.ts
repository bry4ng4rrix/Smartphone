import type { MetadataRoute } from "next";

const SITE = process.env.SITE_URL ?? "http://localhost:3000";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      // Espaces privés ou sans intérêt pour l'indexation.
      disallow: ["/compte", "/checkout", "/panier", "/favoris", "/connexion", "/inscription", "/backend/"],
    },
    sitemap: `${SITE}/sitemap.xml`,
  };
}
