import type { Metadata } from "next";
import { Suspense } from "react";
import { FormulaireInscription } from "@/components/account/auth-forms";
import { Skeleton } from "@/components/ui/skeleton";

export const metadata: Metadata = { title: "Créer un compte", robots: { index: false } };

export default function InscriptionPage() {
  return (
    <div className="mx-auto flex w-full max-w-md flex-col justify-center px-4 py-14 sm:py-20">
      <div className="glass rounded-2xl p-7 sm:p-9">
        <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Espace client</p>
        <h1 className="mt-2 mb-7 text-2xl font-semibold tracking-tight">Créer un compte</h1>
        <Suspense fallback={<Skeleton className="h-96 w-full" />}>
          <FormulaireInscription />
        </Suspense>
      </div>
    </div>
  );
}
