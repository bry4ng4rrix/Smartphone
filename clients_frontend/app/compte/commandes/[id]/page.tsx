import type { Metadata } from "next";
import { Suspense } from "react";
import { CommandeDetail } from "@/components/orders/commande-detail";
import { Skeleton } from "@/components/ui/skeleton";

export const metadata: Metadata = { title: "Suivi de commande", robots: { index: false } };

export default async function CommandePage(props: PageProps<"/compte/commandes/[id]">) {
  const { id } = await props.params;
  return (
    <Suspense fallback={<Skeleton className="h-96 w-full" />}>
      <CommandeDetail id={id} />
    </Suspense>
  );
}
