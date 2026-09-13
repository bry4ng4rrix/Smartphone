'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Banknote, Boxes, PiggyBank, Truck } from 'lucide-react';
import { fmtAr, fmtNb } from '@/lib/reports';

export interface Indicateurs {
  espece_disponible: number;
  solde_caisse: number;
  session_ouverte: boolean;
  epargne_couverte: boolean;
  valeur_stock: number;
  valeur_stock_vente: number;
  quantite_stock: number;
  argent_en_attente: number;
  attente_livreurs: number;
  attente_a_enregistrer: number;
  epargne: number;
}

function Indicateur({
  titre, valeur, detail, icon: Icon, couleur, loading,
}: { titre: string; valeur?: string; detail?: string; icon: React.ComponentType<{ className?: string }>; couleur?: string; loading?: boolean }) {
  return (
    <Card className="gap-2 py-4">
      <CardHeader className="pb-0 px-4">
        <CardDescription className="flex items-center gap-1.5 text-xs">
          <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden />
          {titre}
        </CardDescription>
        {loading ? <Skeleton className="h-7 w-32 mt-1" /> : <CardTitle className={`text-xl sm:text-2xl tabular-nums leading-tight break-words ${couleur || ''}`}>{valeur}</CardTitle>}
      </CardHeader>
      {detail && !loading && (
        <CardContent className="pt-0 px-4">
          <p className="text-xs text-muted-foreground leading-snug">{detail}</p>
        </CardContent>
      )}
    </Card>
  );
}

/** Les 4 indicateurs de tête de la page Caisse (calculés côté serveur). */
export function IndicateursCaisse({ data, loading }: { data: Indicateurs | null; loading: boolean }) {
  const n = (v: unknown) => Number(v || 0);
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3 sm:gap-4">
      <Indicateur
        loading={loading}
        titre="Espèces disponibles maintenant"
        icon={Banknote}
        valeur={data ? fmtAr(data.espece_disponible) : '—'}
        couleur={data && n(data.espece_disponible) < 0 ? 'text-red-600 dark:text-red-400' : 'text-emerald-600 dark:text-emerald-400'}
        detail={
          data
            ? `Solde caisse ${fmtAr(data.solde_caisse)} − épargne réservée ${fmtAr(data.epargne)}${data.session_ouverte ? '' : ' · caisse fermée (dernier montant compté)'}${!data.epargne_couverte ? ' · épargne non couverte par la caisse' : ''}`
            : undefined
        }
      />
      <Indicateur
        loading={loading}
        titre="Valeur du stock actuel"
        icon={Boxes}
        valeur={data ? fmtAr(data.valeur_stock) : '—'}
        detail={data ? `${fmtNb(data.quantite_stock)} articles × prix d'achat · valeur de vente ${fmtAr(data.valeur_stock_vente)}` : undefined}
      />
      <Indicateur
        loading={loading}
        titre="Argent en attente (livraisons)"
        icon={Truck}
        valeur={data ? fmtAr(data.argent_en_attente) : '—'}
        couleur={data && n(data.argent_en_attente) > 0 ? 'text-amber-600 dark:text-amber-400' : undefined}
        detail={data ? `chez les livreurs ${fmtAr(data.attente_livreurs)} · à enregistrer en caisse ${fmtAr(data.attente_a_enregistrer)}` : undefined}
      />
      <Indicateur
        loading={loading}
        titre="Épargne accumulée"
        icon={PiggyBank}
        valeur={data ? fmtAr(data.epargne) : '—'}
        couleur="text-blue-600 dark:text-blue-400"
        detail="Réserve intouchable par défaut — exclue des espèces disponibles"
      />
    </div>
  );
}
