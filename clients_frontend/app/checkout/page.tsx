import type { Metadata } from "next";
import { AuthGuard } from "@/components/account/auth-guard";
import { CheckoutVue } from "@/components/checkout/checkout-vue";

export const metadata: Metadata = { title: "Commander", robots: { index: false } };

export default function CheckoutPage() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 pt-8 pb-16 sm:px-6 sm:pt-12">
      <p className="text-[11px] font-medium tracking-[0.22em] text-muted uppercase">Finaliser</p>
      <h1 className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">Commander</h1>
      <div className="mt-8">
        <AuthGuard>
          <CheckoutVue />
        </AuthGuard>
      </div>
    </div>
  );
}
