import Link from "next/link";
import { Compass } from "lucide-react";
import { EmptyState } from "@/components/ui/empty-state";

export default function NotFound() {
  return (
    <div className="mx-auto flex w-full max-w-xl flex-col justify-center px-4 py-24">
      <EmptyState
        icone={Compass}
        titre="Page introuvable"
        description="Cette page n'existe pas ou n'est plus disponible."
        action={
          <Link
            href="/catalogue"
            className="inline-flex h-11 items-center rounded-full bg-foreground px-6 text-sm font-medium text-background"
          >
            Retour au catalogue
          </Link>
        }
        className="glass"
      />
    </div>
  );
}
