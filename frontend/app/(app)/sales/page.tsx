'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

// Le module Ventes/Ticket (caisse rapide) est retiré : le seul flux de
// vente est désormais la Commande à 6 statuts (§5 Smartreadme.md), qui
// couvre aussi la vente sur place via la zone "Récupération".
export default function SalesRedirectPage() {
  const router = useRouter();
  useEffect(() => {
    router.replace('/orders');
  }, [router]);
  return null;
}
