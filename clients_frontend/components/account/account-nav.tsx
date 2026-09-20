"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Package, UserRound } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/providers/auth-provider";

const LIENS = [
  { href: "/compte", label: "Mon profil", icone: UserRound },
  { href: "/compte/commandes", label: "Mes commandes", icone: Package },
];

export function AccountNav() {
  const pathname = usePathname();
  const { client } = useAuth();

  return (
    <div>
      {client ? (
        <div className="glass mb-4 rounded-xl p-4">
          <p className="text-sm font-medium tracking-tight">{client.nom}</p>
          <p className="mt-0.5 truncate text-xs text-muted">{client.email}</p>
        </div>
      ) : null}

      <nav aria-label="Espace client" className="flex gap-1 overflow-x-auto no-scrollbar lg:flex-col">
        {LIENS.map((lien) => {
          const actif = lien.href === "/compte" ? pathname === "/compte" : pathname.startsWith(lien.href);
          return (
            <Link
              key={lien.href}
              href={lien.href}
              aria-current={actif ? "page" : undefined}
              className={cn(
                "flex shrink-0 items-center gap-2.5 rounded-full px-4 py-2.5 text-sm transition-colors lg:rounded-lg",
                actif ? "bg-foreground text-background" : "text-muted hover:bg-foreground/[0.05] hover:text-foreground",
              )}
            >
              <lien.icone className="size-4" aria-hidden />
              {lien.label}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
