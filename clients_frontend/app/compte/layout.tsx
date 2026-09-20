import { AccountNav } from "@/components/account/account-nav";
import { AuthGuard } from "@/components/account/auth-guard";

export default function CompteLayout({ children }: LayoutProps<"/compte">) {
  return (
    <div className="mx-auto w-full max-w-[1200px] px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Espace client</p>
      <div className="mt-6 lg:grid lg:grid-cols-[240px_1fr] lg:gap-10">
        <aside className="mb-6 lg:mb-0">
          <div className="lg:sticky lg:top-24">
            <AccountNav />
          </div>
        </aside>
        <div>
          <AuthGuard>{children}</AuthGuard>
        </div>
      </div>
    </div>
  );
}
