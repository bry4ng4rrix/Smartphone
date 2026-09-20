"use client";

import { TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";

export default function Error({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="mx-auto flex w-full max-w-xl flex-col justify-center px-4 py-24">
      <EmptyState
        icone={TriangleAlert}
        titre="Une erreur est survenue"
        description="La page n'a pas pu être affichée. Vous pouvez réessayer."
        action={
          <Button variant="primaire" onClick={reset}>
            Réessayer
          </Button>
        }
        className="glass"
      />
    </div>
  );
}
