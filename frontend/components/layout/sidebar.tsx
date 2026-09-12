"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, usePathname } from "next/navigation";
import {
  BarChart3,
  Shirt,
  TrendingUp,
  Truck,
  Settings,
  Menu,
  X,
  LogOut,
  Bell,
  Users,
  AlertCircle,
  Shield,
  Store,
  QrCode,
  MessageCircle,
  ShoppingCart,
  ArrowLeftRight,
  Wallet,
  PackageCheck,
  Receipt,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useCurrentUser } from "@/lib/auth/useCurrentUser";
import { djangoClient } from "@/lib/django-client";

type NavItem = {
  label: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  /** Visible seulement par le rôle Django "admin". */
  superAdminOnly?: boolean;
  /** Visible par le gérant (admin ou magasin). */
  adminOnly?: boolean;
  /** Visible seulement par le livreur. */
  livreurOnly?: boolean;
  /** Visible par le livreur ET par le gérant. */
  livreurOrGerant?: boolean;
  hidePreparateur?: boolean;
  hideLivreur?: boolean;
};

const navigationItems: NavItem[] = [
  {
    label: "Tableau de bord",
    href: "/dashboard",
    icon: BarChart3,
    adminOnly: true,
  },

  {
    label: "Commandes",
    href: "/orders",
    icon: ShoppingCart,
  },
  {
    label: "Récupération",
    href: "/pickup",
    icon: PackageCheck,
    adminOnly: true,
  },
  {
    // Le livreur y voit SON bilan du jour ; le gérant y voit celui de
    // chaque livreur, par onglet et par date (§ demande).
    label: "Bilan du jour",
    href: "/bilan",
    icon: Receipt,
    livreurOrGerant: true,
  },
  {
    label: "Produits",
    href: "/products",
    icon: Shirt,
    hideLivreur: true,
  },

  {
    label: "Caisse",
    href: "/caisse",
    icon: Wallet,
    hidePreparateur: true,
    hideLivreur: true,
  },

  {
    label: "Chats",
    href: "/chats",
    icon: MessageCircle,
  },
  {
    label: "Mouvements",
    href: "/movements",
    icon: TrendingUp,
    adminOnly: true,
  },
  {
    label: "Alertes",
    href: "/alerts",
    icon: AlertCircle,
    adminOnly: true,
  },

  {
    label: "Fournisseurs",
    href: "/suppliers",
    icon: Truck,
    adminOnly: true,
  },
  {
    label: "Transferts",
    href: "/transfers",
    icon: ArrowLeftRight,
    superAdminOnly: true,
  },

  {
    label: "Notifications",
    href: "/notifications",
    icon: Bell,
    adminOnly: true,
  },
  {
    label: "Magasins",
    href: "/stores",
    icon: Store,
    superAdminOnly: true,
  },
  {
    label: "Super Admin",
    href: "/users",
    icon: Shield,
    superAdminOnly: true,
  },
  {
    label: "Paramètres",
    href: "/settings",
    icon: Settings,
    superAdminOnly: true,
  },
];

export function Sidebar() {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const pathname = usePathname();
  const {
    user,
    isAdmin,
    isSuperAdmin,
    isAdminOrSuperAdmin,
    isPreparateur,
    isLivreur,
    loading,
  } = useCurrentUser();

  // Badge "Chats" : nombre de messages non lus (§ demande).
  //
  // Le chat a son propre WebSocket, ouvert seulement sur la page Chats : le
  // menu, lui, est monté partout. On interroge donc un compteur léger — une
  // simple requête COUNT côté serveur — périodiquement, et immédiatement à
  // chaque changement de page pour que le badge retombe dès qu'on vient de
  // lire la conversation.
  const [unreadChats, setUnreadChats] = useState(0);

  const refreshUnread = useCallback(() => {
    if (!djangoClient.isAuthenticated()) return;
    djangoClient.chat
      .unreadCount()
      .then(setUnreadChats)
      .catch(() => {});
  }, []);

  useEffect(() => {
    refreshUnread();
    const id = setInterval(refreshUnread, 30000);
    return () => clearInterval(id);
  }, [refreshUnread, pathname]);

  const handleLogout = async () => {
    await djangoClient.auth.logout();
    router.push("/login");
    router.refresh();
  };

  return (
    <>
      {/* Mobile toggle */}
      <Button
        variant="ghost"
        size="icon"
        className="fixed left-4 top-4 z-40 lg:hidden"
        onClick={() => setOpen(!open)}
      >
        {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
      </Button>

      {/* Sidebar */}
      <aside
        className={cn(
          "fixed left-0 top-0 z-30 h-screen w-64 bg-linear-to-b from-white via-slate-50 to-slate-100 text-slate-900 shadow-xl transition-transform duration-300 lg:relative lg:translate-x-0 border-r border-slate-200 dark:from-stone-950 dark:via-stone-900 dark:to-stone-950 dark:text-white dark:border-stone-800",
          open ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex flex-col h-full">
          {/* Logo */}
          <div className="p-6 border-b border-slate-200 bg-linear-to-r from-slate-50/50 to-transparent dark:border-slate-700/50 dark:from-slate-900/50">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-linear-to-br from-blue-500 to-cyan-600 flex items-center justify-center shadow-lg dark:from-blue-400 dark:to-cyan-500 overflow-hidden">
                <img
                  src={
                    user?.store_logo ||
                    "https://res.cloudinary.com/dxj0d1v3g/image/upload/v1697040915/valheri-wear/logo_2x_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1.png"
                  }
                  alt="Logo"
                  className="w-full h-full object-cover"
                />
              </div>
              <div>
                <h1 className="text-lg font-bold tracking-wide text-slate-900 dark:text-white truncate max-w-[140px]">
                  {user?.store_name || (isAdmin ? "Société" : "Valheri Wear")}
                </h1>
                <p className="text-xs text-slate-500 font-medium dark:text-slate-400">
                  Smart kajy
                </p>
              </div>
            </div>
          </div>

          {/* Navigation */}
          <nav className="flex-1 p-4 space-y-1 overflow-y-auto">
            {navigationItems
              .filter((item) => {
                // Pendant le chargement on affiche tout pour éviter le flash
                if (loading) return !item.superAdminOnly;
                if (item.superAdminOnly && !isSuperAdmin) return false;
                if (item.adminOnly && !isAdminOrSuperAdmin) return false;
                if (item.hidePreparateur && isPreparateur) return false;
                if (item.hideLivreur && isLivreur) return false;
                if (item.livreurOnly && !isLivreur) return false;
                if (item.livreurOrGerant && !isLivreur && !isAdminOrSuperAdmin)
                  return false;
                return true;
              })
              .map((item) => {
                const Icon = item.icon;
                const isActive = pathname === item.href;

                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    onClick={() => setOpen(false)}
                    className={cn(
                      "flex items-center gap-3 px-4 py-3 rounded-lg transition-all duration-200 group",
                      isActive
                        ? "bg-linear-to-r from-blue-600 to-blue-500 text-white shadow-lg shadow-blue-500/20"
                        : "text-slate-600 hover:bg-slate-100 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-slate-800/60 dark:hover:text-white",
                    )}
                  >
                    <Icon
                      className={cn(
                        "h-5 w-5 transition-transform duration-200",
                        !isActive && "group-hover:scale-110",
                      )}
                    />
                    <span className="text-sm font-medium">{item.label}</span>
                    {item.href === "/chats" && unreadChats > 0 ? (
                      <span
                        className={cn(
                          "ml-auto min-w-5 h-5 px-1.5 inline-flex items-center justify-center rounded-full text-[11px] font-semibold tabular-nums",
                          isActive
                            ? "bg-white text-blue-600"
                            : "bg-red-500 text-white",
                        )}
                        aria-label={`${unreadChats} message${unreadChats > 1 ? "s" : ""} non lu${unreadChats > 1 ? "s" : ""}`}
                      >
                        {unreadChats > 99 ? "99+" : unreadChats}
                      </span>
                    ) : (
                      isActive && (
                        <div className="ml-auto h-2 w-2 rounded-full bg-white shadow-lg" />
                      )
                    )}
                  </Link>
                );
              })}
          </nav>

          {/* Footer */}
          <div className="p-4 border-t border-slate-200 bg-linear-to-r from-slate-50/50 to-transparent dark:border-slate-700/50 dark:from-slate-900/50">
            <Button
              variant="ghost"
              className={cn(
                "w-full justify-start text-sm font-medium transition-all duration-200",
                "text-slate-500 hover:text-slate-900 hover:bg-slate-100 dark:text-slate-400 dark:hover:text-white dark:hover:bg-slate-800/60",
              )}
              onClick={handleLogout}
            >
              <LogOut className="h-4 w-4 mr-2" />
              Déconnexion
            </Button>
          </div>
        </div>
      </aside>

      {/* Mobile overlay */}
      {open && (
        <div
          className="fixed inset-0 bg-black/50 z-20 lg:hidden backdrop-blur-sm"
          onClick={() => setOpen(false)}
        />
      )}
    </>
  );
}
