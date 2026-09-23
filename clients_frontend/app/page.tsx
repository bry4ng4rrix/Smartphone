import Image from "next/image";
import Link from "next/link";
import { ArrowRight, PackageCheck, ShieldCheck, Store, Truck } from "lucide-react";
import { ProductCard } from "@/components/catalog/product-card";
import { Aurora } from "@/components/ui/aurora";
import { Reveal } from "@/components/ui/reveal";
import { EmptyState } from "@/components/ui/empty-state";
import { catalogue } from "@/lib/endpoints";
import { lienCategorie } from "@/lib/compatibilite";
import type { Categorie, Marque, Produit } from "@/lib/types";
import { WifiOff } from "lucide-react";

type Donnees = {
  total: number;
  disponibles: Produit[];
  categories: Array<Categorie & { nb: number }>;
  marques: Marque[];
  boutique: string | null;
  enPanne: boolean;
};

/** Tout ce que la page affiche vient de l'API — aucun chiffre décoratif. */
async function charger(): Promise<Donnees> {
  try {
    const [tous, dispo, categories, marques, boutiques] = await Promise.all([
      catalogue.produits({ page_size: 1 }),
      catalogue.produits({ available: "1", page_size: 8 }),
      catalogue.categories(),
      catalogue.marques(),
      catalogue.boutiques(),
    ]);

    // Nombre réel de produits disponibles par catégorie (affiché sous la
    // tuile) — une page vide suffit, seul le total compte.
    const avecNb = await Promise.all(
      categories.map(async (c) => {
        try {
          const page = await catalogue.produits({ category: c.id, available: "1", page_size: 1 });
          return { ...c, nb: page.count };
        } catch {
          return { ...c, nb: 0 };
        }
      }),
    );

    return {
      total: tous.count,
      disponibles: dispo.results,
      categories: avecNb,
      marques,
      boutique: boutiques[0]?.nom ?? null,
      enPanne: false,
    };
  } catch {
    return { total: 0, disponibles: [], categories: [], marques: [], boutique: null, enPanne: true };
  }
}

/**
 * Composition du hero : quatre tuiles fixes, une par catégorie phare, avec sa
 * photo (public/hero/). Elles ne dépendent plus de l'ordre de l'API — celle-ci
 * ne fournit que le lien et le nombre de références, quand la catégorie est
 * bien présente en base.
 */
const TUILES_HERO = [
  { cle: "housse", titre: "Housse", src: "/hero/housse.png" },
  { cle: "cache", titre: "Cache écran", src: "/hero/cache.png" },
  { cle: "charge", titre: "Chargeur", src: "/hero/chargeur.png" },
  // Catégorie SANTE en base, présentée sous le libellé « Autre » côté client.
  { cle: "sante", titre: "Autre", src: "/hero/sante.png" },
] as const;

/** Nom comparable : sans accent ni casse (« CACHE ÉCRAN » → « cache ecran »). */
function normaliser(nom: string): string {
  return nom
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

const ETAPES = [
  { icone: Store, titre: "Vous commandez", texte: "Ajoutez vos accessoires au panier et choisissez livraison ou retrait sur place." },
  { icone: ShieldCheck, titre: "La boutique valide", texte: "Votre commande est vérifiée puis confirmée. Elle reste modifiable jusque-là." },
  { icone: PackageCheck, titre: "Préparation", texte: "Les articles sont emballés et préparés pour le départ." },
  { icone: Truck, titre: "Livraison", texte: "Le livreur vous apporte la commande, ou vous la retirez en boutique." },
];

export default async function Accueil() {
  const { total, disponibles, categories, marques, boutique, enPanne } = await charger();

  return (
    <>
      {/* Fond animé de la page : fixé en haut de la fenêtre, il passe derrière
          l'en-tête flottant et se fond vers le bas — aucune bande sombre ne
          vient couper la composition. */}
      <Aurora />

      {/* ------------------------------------------------------------ Hero */}
      <section className="relative px-4 pt-10 pb-16 sm:px-6 sm:pt-16 sm:pb-24">
        <div className="mx-auto w-full max-w-[1400px]">
          <div className="grid items-center gap-10 lg:grid-cols-[1.1fr_0.9fr]">
            <div>
              <p className="text-[11px] font-medium tracking-[0.24em] text-muted uppercase">
                {boutique ?? "Smartphone.Mg"} — Antananarivo
              </p>
              <h1 className="mt-5 text-[2.5rem] leading-[1.05] font-semibold tracking-[-0.02em] text-balance sm:text-6xl lg:text-7xl">
                L&apos;accessoire juste,
                <br />
                <span className="text-muted">pour votre téléphone.</span>
              </h1>
              <p className="mt-6 max-w-md text-[15px] leading-relaxed text-muted">
                Housses, cache-écrans et accessoires sélectionnés pour les modèles qui circulent vraiment à Madagascar.
                Commande en ligne, validation par la boutique, livraison ou retrait.
              </p>

              <div className="mt-9 flex flex-wrap items-center gap-3">
                <Link
                  href="/catalogue"
                  className="group inline-flex h-13 items-center gap-2 rounded-full bg-foreground px-8 text-[15px] font-medium text-background transition-all duration-300 hover:-translate-y-px hover:shadow-[0_18px_44px_-16px_color-mix(in_oklab,var(--foreground)_70%,transparent)]"
                >
                  Découvrir le catalogue
                  <ArrowRight className="size-4 transition-transform duration-300 group-hover:translate-x-0.5" aria-hidden />
                </Link>
                {total > 0 ? (
                  <span className="glass rounded-full px-4 py-2.5 text-[13px] text-muted">
                    <span className="font-semibold text-foreground tabular-nums">{total}</span> références en ligne
                  </span>
                ) : null}
              </div>
            </div>

            {/* Composition éditoriale : quatre tuiles fixes (TUILES_HERO), pas
                les quatre premières catégories renvoyées par l'API. */}
            <div className="grid grid-cols-2 gap-3 sm:gap-4">
              {TUILES_HERO.map((tuile, i) => {
                const categorie = categories.find((c) => normaliser(c.nom).includes(tuile.cle));
                return (
                  <Reveal key={tuile.cle} delai={i * 90}>
                    <Link
                      href={categorie ? lienCategorie(categorie) : "/catalogue"}
                      className="glass elevate hover:elevate-hover group flex aspect-[4/5] flex-col overflow-hidden rounded-xl"
                    >
                      <span className="relative flex-1 overflow-hidden bg-white">
                        <Image
                          src={tuile.src}
                          alt=""
                          fill
                          sizes="(min-width: 1024px) 22vw, 45vw"
                          priority={i < 2}
                          className="object-cover transition-transform duration-700 ease-[cubic-bezier(0.22,1,0.36,1)] group-hover:scale-[1.04]"
                        />
                        {/* Fond blanc des photos studio : un dégradé rattache
                            le bas de l'image au bandeau sombre du libellé. */}
                        <span
                          className="absolute inset-x-0 bottom-0 h-1/3 bg-gradient-to-t from-black/25 to-transparent"
                          aria-hidden
                        />
                      </span>

                      <span className="flex flex-col p-5">
                        <span className="text-[10px] tracking-[0.2em] text-muted uppercase">Catégorie</span>
                        <span className="mt-1 text-lg leading-tight font-medium tracking-tight">{tuile.titre}</span>
                        {/* Le compteur ne s'affiche que si la catégorie existe
                            vraiment côté API — aucun chiffre décoratif. */}
                        <span className="mt-1 flex items-center gap-2 text-xs text-muted tabular-nums">
                          {categorie ? `${categorie.nb} référence${categorie.nb > 1 ? "s" : ""}` : "Voir le catalogue"}
                          <ArrowRight
                            className="size-3.5 transition-transform duration-300 group-hover:translate-x-1"
                            aria-hidden
                          />
                        </span>
                      </span>
                    </Link>
                  </Reveal>
                );
              })}
            </div>
          </div>
        </div>
      </section>

      {enPanne ? (
        <div className="mx-auto w-full max-w-[1400px] px-4 sm:px-6">
          <EmptyState
            icone={WifiOff}
            titre="Boutique momentanément indisponible"
            description="Le serveur ne répond pas. Réessayez dans quelques instants."
            className="hairline bg-surface/40"
          />
        </div>
      ) : null}

      {/* ------------------------------------------------ Disponibles */}
      {disponibles.length > 0 ? (
        <section className="mx-auto w-full max-w-[1400px] px-4 py-6 sm:px-6" aria-labelledby="dispo">
          <Reveal>
            <div className="mb-6 flex items-end justify-between gap-4">
              <div>
                <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">En rayon</p>
                <h2 id="dispo" className="mt-2 text-2xl font-semibold tracking-tight sm:text-3xl">
                  Disponibles maintenant
                </h2>
              </div>
              <Link href="/catalogue?available=1" className="shrink-0 text-sm text-accent hover:underline">
                Tout voir
              </Link>
            </div>
          </Reveal>

          <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
            {disponibles.map((p, i) => (
              <ProductCard key={p.id} produit={p} priority={i < 2} />
            ))}
          </div>
        </section>
      ) : null}

      {/* ------------------------------------------------ Marques */}
      {marques.length > 0 ? (
        <section className="mx-auto w-full max-w-[1400px] px-4 py-14 sm:px-6" aria-labelledby="marques">
          <Reveal>
            <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Compatibilité</p>
            <h2 id="marques" className="mt-2 text-2xl font-semibold tracking-tight sm:text-3xl">
              Pour votre modèle
            </h2>
            <div className="mt-6 flex flex-wrap gap-2">
              {marques.map((m) => (
                <Link
                  key={m.id}
                  href={`/catalogue?brand=${m.id}`}
                  className="hairline rounded-full px-4 py-2 text-sm text-muted transition-all duration-300 hover:-translate-y-px hover:text-foreground"
                >
                  {m.nom}
                </Link>
              ))}
            </div>
          </Reveal>
        </section>
      ) : null}

      {/* ------------------------------------------------ Parcours */}
      <section className="mx-auto w-full max-w-[1400px] px-4 pb-8 sm:px-6" aria-labelledby="parcours">
        <Reveal>
          <div className="glass grain aurora relative overflow-hidden rounded-2xl px-6 py-12 sm:px-12">
            <Aurora portee="bloc" intensite="discrete" />
            <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Comment ça marche</p>
            <h2 id="parcours" className="mt-2 max-w-lg text-2xl leading-tight font-semibold tracking-tight sm:text-3xl">
              De la commande à la livraison, vous suivez chaque étape.
            </h2>

            <ol className="mt-10 grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
              {ETAPES.map((e, i) => (
                <li key={e.titre}>
                  <span className="flex size-10 items-center justify-center rounded-full bg-foreground/[0.06] text-muted">
                    <e.icone className="size-4" aria-hidden />
                  </span>
                  <p className="mt-4 text-[11px] tracking-[0.2em] text-muted uppercase tabular-nums">0{i + 1}</p>
                  <p className="mt-1 font-medium tracking-tight">{e.titre}</p>
                  <p className="mt-1.5 text-sm leading-relaxed text-muted">{e.texte}</p>
                </li>
              ))}
            </ol>
          </div>
        </Reveal>
      </section>
    </>
  );
}
