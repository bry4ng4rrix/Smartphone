import type { Metadata } from "next";
import { PanierVue } from "@/components/cart/panier-vue";

export const metadata: Metadata = { title: "Mon panier", robots: { index: false } };

export default function PanierPage() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">Mon panier</h1>
      <PanierVue />
    </div>
  );
}
