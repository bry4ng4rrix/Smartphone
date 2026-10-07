'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import {
  AlertCircle,
  Bell,
  ClipboardList,
  PackageCheck,
  RefreshCw,
  Truck,
  Wallet,
} from 'lucide-react';
import { djangoClient } from '@/lib/django-client';
import { useRealtimeRefresh } from '@/lib/hooks/useRealtimeRefresh';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';

const fmt = (n: number | string | null | undefined) =>
  new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar';

/**
 * Tableau de bord du GÉRANT DE MAGASIN.
 *
 * Volontairement court : il répond à « qu'est-ce qui m'attend aujourd'hui
 * dans ma boutique ? », pas à « combien ai-je gagné ». Aucune donnée de
 * bénéfice, de marge, de coût d'achat ni de trésorerie n'y figure — et
 * surtout, l'API qui l'alimente n'en envoie aucune (voir
 * orders/dashboard.py::DashboardGerantView).
 *
 * Le centre de rapports complet reste sur /dashboard pour l'admin global.
 */
export function DashboardGerant() {
  const [data, setData] = useState<any | null>(null);
  const [loading, setLoading] = useState(true);

  const charger = useCallback(async (silencieux = false) => {
    if (!silencieux) setLoading(true);
    try {
      setData(await djangoClient.orders.dashboardGerant());
    } catch (err: any) {
      toast.error(err.message || 'Erreur de chargement du tableau de bord');
    } finally {
      if (!silencieux) setLoading(false);
    }
  }, []);

  useEffect(() => {
    charger();
  }, [charger]);

  useRealtimeRefresh(['order', 'order_status_history', 'product_variant'], () => charger(true));

  if (loading) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <Skeleton key={i} className="h-28" />
        ))}
      </div>
    );
  }

  if (!data) return null;

  const c = data.commandes ?? {};
  const bilan = data.bilan_du_jour ?? {};
  const stock = data.stock ?? {};
  const livreurs = data.demandes_livreurs ?? {};

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Tableau de bord</h1>
          <p className="text-sm text-muted-foreground">
            Votre magasin aujourd&apos;hui — {data.date}
          </p>
        </div>
        <Button variant="outline" size="icon" onClick={() => charger()}>
          <RefreshCw className="h-4 w-4" />
        </Button>
      </div>

      {/* Ce qui demande une action */}
      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Tuile
          href="/client"
          icone={ClipboardList}
          libelle="À approuver"
          valeur={c.a_approuver}
          accent={c.a_approuver > 0}
          detail="Commandes en ligne à confirmer par téléphone"
        />
        <Tuile
          href="/orders"
          icone={ClipboardList}
          libelle="Nouvelles"
          valeur={c.nouvelles}
          detail="En attente de préparation"
        />
        <Tuile
          href="/orders"
          icone={Truck}
          libelle="En cours"
          valeur={(c.en_preparation ?? 0) + (c.pretes ?? 0) + (c.en_livraison ?? 0)}
          detail="Préparation, prêtes et en livraison"
        />
        <Tuile
          href="/pickup"
          icone={PackageCheck}
          libelle="Récupérations"
          valeur={data.recuperations}
          accent={data.recuperations > 0}
          detail="Prêtes à retirer au comptoir"
        />
      </section>

      {/* Le jour qui s'achève */}
      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Tuile href="/bilan" icone={Wallet} libelle="Livrées aujourd'hui" valeur={bilan.livrees} />
        <Tuile href="/bilan" icone={Wallet} libelle="Retours aujourd'hui" valeur={bilan.retours} />
        <Tuile
          href="/bilan"
          icone={Wallet}
          libelle="À encaisser"
          valeurTexte={fmt(bilan.a_encaisser)}
          detail="Total des commandes livrées du jour"
        />
        <Tuile
          href="/notifications"
          icone={Bell}
          libelle="Notifications"
          valeur={data.notifications_non_lues}
          detail="Non lues"
        />
      </section>

      {/* Stock et équipe */}
      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Tuile
          href="/alerts"
          icone={AlertCircle}
          libelle="Ruptures"
          valeur={stock.ruptures}
          accent={stock.ruptures > 0}
          detail="Articles à zéro"
        />
        <Tuile
          href="/alerts"
          icone={AlertCircle}
          libelle="Stock bas"
          valeur={stock.stock_bas}
          accent={stock.stock_bas > 0}
          detail="Sous le seuil d'alerte"
        />
        <Tuile
          href="/bilan"
          icone={Truck}
          libelle="Dépenses livreurs"
          valeur={livreurs.depenses_en_attente}
          accent={livreurs.depenses_en_attente > 0}
          detail="En attente de votre décision"
        />
        <Tuile
          href="/bilan"
          icone={Truck}
          libelle="Avances livreurs"
          valeur={livreurs.avances_en_attente}
          accent={livreurs.avances_en_attente > 0}
          detail="À confirmer réception"
        />
      </section>
    </div>
  );
}

function Tuile({
  href,
  icone: Icone,
  libelle,
  valeur,
  valeurTexte,
  detail,
  accent = false,
}: {
  href: string;
  icone: React.ComponentType<{ className?: string }>;
  libelle: string;
  valeur?: number;
  valeurTexte?: string;
  detail?: string;
  accent?: boolean;
}) {
  return (
    <Link href={href}>
      <Card className="h-full transition-colors hover:border-blue-500/50">
        <CardContent className="p-4">
          <div className="flex items-center justify-between gap-2">
            <span className="text-xs font-medium text-muted-foreground">{libelle}</span>
            <Icone className={accent ? 'h-4 w-4 text-amber-500' : 'h-4 w-4 text-muted-foreground'} />
          </div>
          <p className="mt-2 text-2xl font-bold tabular-nums">
            {valeurTexte ?? valeur ?? 0}
          </p>
          {detail ? <p className="mt-1 text-xs text-muted-foreground">{detail}</p> : null}
        </CardContent>
      </Card>
    </Link>
  );
}
