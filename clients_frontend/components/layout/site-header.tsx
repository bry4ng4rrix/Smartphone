"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Heart, Menu, Moon, Search, Sun, User } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Panel, PanelClose } from "@/components/ui/panel";
import { CartButton } from "@/components/layout/cart-drawer";
import { useAuth } from "@/providers/auth-provider";
import { useTheme } from "@/providers/theme-provider";
import { useWishlist } from "@/providers/wishlist-provider";
import { cn } from "@/lib/utils";

const LIENS = [
  { href: "/catalogue", label: "Catalogue" },
  { href: "/catalogue?category=4", label: "Housses" },
  { href: "/catalogue?category=5", label: "Cache-écrans" },
  { href: "/favoris", label: "Favoris" },
];

export function SiteHeader({ categories }: { categories: { id: number; nom: string }[] }) {
  const router = useRouter();
  const { statut, client } = useAuth();
  const { theme, basculer } = useTheme();
  const { ids } = useWishlist();
  const [menuOuvert, setMenuOuvert] = useState(false);
  const [rechercheOuverte, setRechercheOuverte] = useState(false);
  const [compact, setCompact] = useState(false);
  const champRecherche = useRef<HTMLInputElement>(null);

  // L'en-tête se resserre au défilement : plus de place pour le contenu.
  useEffect(() => {
    const surScroll = () => setCompact(window.scrollY > 12);
    // rAF : évite un setState synchrone au montage (cascade de rendus).
    const image = requestAnimationFrame(surScroll);
    window.addEventListener("scroll", surScroll, { passive: true });
    return () => {
      cancelAnimationFrame(image);
      window.removeEventListener("scroll", surScroll);
    };
  }, []);

  useEffect(() => {
    if (rechercheOuverte) champRecherche.current?.focus();
  }, [rechercheOuverte]);

  const liens = categories.length
    ? [{ href: "/catalogue", label: "Catalogue" }, ...categories.map((c) => ({ href: `/catalogue?category=${c.id}`, label: c.nom })), { href: "/favoris", label: "Favoris" }]
    : LIENS;

  const rechercher = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const valeur = new FormData(e.currentTarget).get("search");
    router.push(`/catalogue${valeur ? `?search=${encodeURIComponent(String(valeur))}` : ""}`);
    setRechercheOuverte(false);
  };

  return (
    <>
      <a
        href="#contenu"
        className="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-[100] focus:rounded-full focus:bg-foreground focus:px-4 focus:py-2 focus:text-sm focus:text-background"
      >
        Aller au contenu
      </a>

      <header className={cn("sticky top-0 z-50 transition-all duration-300", compact ? "py-2" : "py-3")}>
        <div className="mx-auto w-full max-w-[1400px] px-4 sm:px-6">
          <div className={cn("glass flex items-center gap-2 rounded-full transition-all duration-300", compact ? "px-3 py-2" : "px-4 py-2.5")}>
            <Button
              variant="fantome"
              size="icone"
              className="lg:hidden"
              onClick={() => setMenuOuvert(true)}
              aria-label="Ouvrir le menu"
            >
              <Menu aria-hidden />
            </Button>

            <Link href="/" className="group flex items-center gap-2 pr-2 pl-1 lg:pl-2">
              <span className="grid size-7 place-items-center rounded-lg bg-foreground text-[11px] font-bold text-background">S</span>
              <span className="text-[15px] font-semibold tracking-tight">
                Smartphone<span className="text-accent">.Mg</span>
              </span>
            </Link>

            <nav aria-label="Navigation principale" className="hidden items-center gap-1 lg:flex">
              {liens.map((lien) => (
                <Link
                  key={lien.href}
                  href={lien.href}
                  className="rounded-full px-3.5 py-2 text-[13px] font-medium text-muted transition-colors hover:bg-foreground/[0.05] hover:text-foreground"
                >
                  {lien.label}
                </Link>
              ))}
            </nav>

            <form onSubmit={rechercher} role="search" className="ml-auto hidden max-w-xs flex-1 md:block">
              <label htmlFor="recherche-entete" className="sr-only">
                Rechercher un produit
              </label>
              <div className="relative">
                <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted" aria-hidden />
                <input
                  id="recherche-entete"
                  name="search"
                  type="search"
                  placeholder="Rechercher…"
                  className="h-9 w-full rounded-full border border-transparent bg-foreground/[0.04] pr-3 pl-9 text-sm transition-colors placeholder:text-muted/80 focus:border-accent/50 focus:bg-surface"
                />
              </div>
            </form>

            <div className={cn("flex items-center gap-0.5", "ml-auto md:ml-0")}>
              <Button variant="fantome" size="icone" className="md:hidden" onClick={() => setRechercheOuverte(true)} aria-label="Rechercher">
                <Search aria-hidden />
              </Button>

              <Button
                variant="fantome"
                size="icone"
                onClick={basculer}
                aria-label={theme === "sombre" ? "Passer en thème clair" : "Passer en thème sombre"}
                className="hidden sm:inline-flex"
              >
                {theme === "sombre" ? <Sun aria-hidden /> : <Moon aria-hidden />}
              </Button>

              <Link
                href="/favoris"
                aria-label={`Favoris${ids.length ? ` (${ids.length})` : ""}`}
                className="hidden size-10 place-items-center rounded-full text-muted transition-colors hover:bg-foreground/[0.06] hover:text-foreground sm:grid"
              >
                <span className="relative">
                  <Heart className="size-[18px]" aria-hidden />
                  {ids.length > 0 ? <span className="absolute -top-0.5 -right-0.5 size-2 rounded-full bg-accent" /> : null}
                </span>
              </Link>

              <Link
                href={statut === "connecte" ? "/compte" : "/connexion"}
                aria-label={statut === "connecte" ? `Mon compte (${client?.nom ?? ""})` : "Se connecter"}
                className="grid size-10 place-items-center rounded-full text-muted transition-colors hover:bg-foreground/[0.06] hover:text-foreground"
              >
                <User className="size-[18px]" aria-hidden />
              </Link>

              <CartButton />
            </div>
          </div>
        </div>
      </header>

      {/* Menu mobile */}
      <Panel ouvert={menuOuvert} onOuvertChange={setMenuOuvert} titre="Menu" cote="bas">
        <nav aria-label="Navigation mobile" className="flex flex-col">
          {liens.map((lien) => (
            <PanelClose
              key={lien.href}
              render={<Link href={lien.href}>{lien.label}</Link>}
              className="border-b border-[var(--glass-border)] py-3.5 text-left text-[15px] font-medium last:border-0"
            />
          ))}
          <PanelClose
            render={<Link href={statut === "connecte" ? "/compte" : "/connexion"}>{statut === "connecte" ? "Mon compte" : "Se connecter"}</Link>}
            className="border-t border-[var(--glass-border)] py-3.5 text-left text-[15px] font-medium"
          />
          <button
            type="button"
            onClick={basculer}
            className="flex items-center gap-2 border-t border-[var(--glass-border)] py-3.5 text-left text-[15px] font-medium"
          >
            {theme === "sombre" ? <Sun className="size-4" aria-hidden /> : <Moon className="size-4" aria-hidden />}
            {theme === "sombre" ? "Thème clair" : "Thème sombre"}
          </button>
        </nav>
      </Panel>

      {/* Recherche mobile */}
      <Panel ouvert={rechercheOuverte} onOuvertChange={setRechercheOuverte} titre="Rechercher" cote="bas">
        <form onSubmit={rechercher} role="search" className="flex gap-2">
          <label htmlFor="recherche-mobile" className="sr-only">
            Rechercher un produit
          </label>
          <input
            ref={champRecherche}
            id="recherche-mobile"
            name="search"
            type="search"
            placeholder="Coque, cache-écran, marque…"
            className="h-11 w-full rounded-full border border-border bg-surface/60 px-4 text-sm"
          />
          <Button type="submit" variant="accent" size="icone">
            <Search aria-hidden />
          </Button>
        </form>
      </Panel>
    </>
  );
}
