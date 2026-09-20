import type { Metadata } from "next";
import { CommandesListe } from "@/components/orders/commandes-liste";

export const metadata: Metadata = { title: "Mes commandes", robots: { index: false } };

export default function CommandesPage() {
  return (
    <>
      <h1 className="mb-1 text-2xl font-semibold tracking-tight sm:text-3xl">Mes commandes</h1>
      <p className="mb-6 text-sm text-muted">Suivez l&apos;avancement de chaque commande, de la validation à la livraison.</p>
      <CommandesListe />
    </>
  );
}
