import type { Metadata } from "next";
import { ProfilVue } from "@/components/account/profil-vue";

export const metadata: Metadata = { title: "Mon profil", robots: { index: false } };

export default function ComptePage() {
  return (
    <>
      <h1 className="mb-6 text-2xl font-semibold tracking-tight sm:text-3xl">Mon profil</h1>
      <ProfilVue />
    </>
  );
}
