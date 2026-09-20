import Image from "next/image";
import Link from "next/link";
import type { Boutique } from "@/lib/types";

export function SiteFooter({ boutiques }: { boutiques: Boutique[] }) {
  return (
    <footer className="mt-24 border-t border-border/70">
      <div className="mx-auto w-full max-w-[1400px] px-4 py-14 sm:px-6">
        <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
          <div className="lg:col-span-2">
            <Link href="/" className="flex items-center gap-2.5" aria-label="Smartphone.Mg — accueil">
              <Image
                src="/logo-mark.png"
                alt=""
                width={36}
                height={36}
                className="size-9 rounded-xl object-cover ring-1 ring-foreground/[0.06]"
              />
              <span className="text-[15px] font-semibold tracking-tight">
                Smartphone<span className="text-accent">.Mg</span>
              </span>
            </Link>
            <p className="mt-4 max-w-sm text-sm leading-relaxed text-muted">
              Housses, cache-écrans et accessoires pour smartphone. Commande en ligne, livraison à Antananarivo ou retrait sur place.
            </p>
          </div>

          <nav aria-label="Boutique" className="space-y-3 text-sm">
            <p className="text-[11px] font-medium tracking-[0.2em] text-muted uppercase">Boutique</p>
            <Link href="/catalogue" className="block text-muted transition-colors hover:text-foreground">
              Catalogue
            </Link>
            <Link href="/favoris" className="block text-muted transition-colors hover:text-foreground">
              Mes favoris
            </Link>
            <Link href="/panier" className="block text-muted transition-colors hover:text-foreground">
              Mon panier
            </Link>
          </nav>

          <nav aria-label="Compte" className="space-y-3 text-sm">
            <p className="text-[11px] font-medium tracking-[0.2em] text-muted uppercase">Compte</p>
            <Link href="/compte" className="block text-muted transition-colors hover:text-foreground">
              Mon profil
            </Link>
            <Link href="/compte/commandes" className="block text-muted transition-colors hover:text-foreground">
              Mes commandes
            </Link>
            <Link href="/connexion" className="block text-muted transition-colors hover:text-foreground">
              Connexion
            </Link>
          </nav>
        </div>

        <div className="mt-12 flex flex-col gap-3 border-t border-border/70 pt-6 text-xs text-muted sm:flex-row sm:items-center sm:justify-between">
          <p>© {new Date().getFullYear()} Smartphone.Mg — Antananarivo, Madagascar</p>
          {boutiques.length > 0 ? (
            <p>
              {boutiques.length > 1 ? "Boutiques : " : "Boutique : "}
              {boutiques.map((b) => b.nom).join(" · ")}
            </p>
          ) : null}
        </div>
      </div>
    </footer>
  );
}
