import type { Metadata } from "next";
import { FavorisVue } from "@/components/catalog/favoris-vue";

export const metadata: Metadata = { title: "Mes favoris", robots: { index: false } };

export default function FavorisPage() {
  return (
    <div className="mx-auto w-full max-w-[1400px] px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Ma sélection</p>
      <h1 className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">Mes favoris</h1>
      <p className="mt-2 max-w-xl text-sm text-muted">
        Enregistrés sur cet appareil uniquement — les fiches sont rechargées depuis la boutique à chaque visite.
      </p>
      <FavorisVue />
    </div>
  );
}
