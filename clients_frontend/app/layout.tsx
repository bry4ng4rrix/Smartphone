import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { SiteHeader } from "@/components/layout/site-header";
import { SiteFooter } from "@/components/layout/site-footer";
import { CartDrawer } from "@/components/layout/cart-drawer";
import { AuthProvider } from "@/providers/auth-provider";
import { CartProvider } from "@/providers/cart-provider";
import { ThemeProvider, SCRIPT_THEME } from "@/providers/theme-provider";
import { ToastProvider } from "@/providers/toast-provider";
import { WishlistProvider } from "@/providers/wishlist-provider";
import { catalogue } from "@/lib/endpoints";
import type { Boutique, Categorie } from "@/lib/types";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL(process.env.SITE_URL ?? "http://localhost:3000"),
  title: {
    default: "Smartphone.Mg — Accessoires premium pour smartphone",
    template: "%s · Smartphone.Mg",
  },
  description:
    "Housses, cache-écrans et accessoires pour smartphone à Madagascar. Commande en ligne, livraison à Antananarivo ou retrait sur place.",
  openGraph: {
    type: "website",
    locale: "fr_MG",
    siteName: "Smartphone.Mg",
    title: "Smartphone.Mg — Accessoires premium pour smartphone",
    description: "Housses, cache-écrans et accessoires pour smartphone à Madagascar.",
  },
  // Les icônes viennent des conventions de fichiers (app/favicon.ico,
  // app/icon.png, app/apple-icon.png), toutes dérivées de public/logo.jpeg.
  // L'image de partage vient de app/opengraph-image.png.
  applicationName: "Smartphone.Mg",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#faf9f7" },
    { media: "(prefers-color-scheme: dark)", color: "#0b0b0e" },
  ],
};

/** La barre de navigation affiche les catégories réelles de la boutique. */
async function donneesEntete(): Promise<{ categories: Categorie[]; boutiques: Boutique[] }> {
  try {
    const [categories, boutiques] = await Promise.all([catalogue.categories(), catalogue.boutiques()]);
    return { categories, boutiques };
  } catch {
    // L'API est injoignable : l'enveloppe du site doit rester utilisable.
    return { categories: [], boutiques: [] };
  }
}

export default async function RootLayout({ children }: LayoutProps<"/">) {
  const { categories, boutiques } = await donneesEntete();

  return (
    <html lang="fr" suppressHydrationWarning className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <head>
        <script dangerouslySetInnerHTML={{ __html: SCRIPT_THEME }} />
      </head>
      <body className="flex min-h-full flex-col">
        <ThemeProvider>
          <ToastProvider>
            <AuthProvider>
              <CartProvider>
                <WishlistProvider>
                  <SiteHeader categories={categories.map((c) => ({ id: c.id, nom: c.nom }))} />
                  <main id="contenu" className="flex-1">
                    {children}
                  </main>
                  <SiteFooter boutiques={boutiques} />
                  <CartDrawer />
                </WishlistProvider>
              </CartProvider>
            </AuthProvider>
          </ToastProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
