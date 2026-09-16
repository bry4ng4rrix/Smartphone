'use client';

/**
 * Compteurs de commandes par statut, au-dessus du tableau (§ demande).
 *
 * Chaque pastille indique combien de commandes de la liste courante sont
 * dans cet état ET sert de filtre : cliquer dessus n'affiche que celles-là,
 * recliquer revient à « Toutes ». Les compteurs sont calculés sur la liste
 * déjà filtrée par date / recherche / onglet, mais AVANT le filtre de
 * statut — sinon un filtre actif mettrait tous les autres compteurs à zéro.
 */
export interface CompteurStatut {
  value: string;
  label: string;
  count: number;
}

/** Pastille de couleur par statut — mêmes teintes que les badges du tableau. */
const POINT: Record<string, string> = {
  ALL: 'bg-primary',
  NON_LIVREE: 'bg-sky-500',
  EN_ATTENTE_APPROBATION: 'bg-orange-500',
  NOUVELLE: 'bg-slate-400',
  EN_PREPARATION: 'bg-amber-500',
  PRETE: 'bg-blue-500',
  EN_LIVRAISON: 'bg-purple-500',
  LIVRE: 'bg-emerald-500',
  RETOUR: 'bg-red-500',
  ANNULEE: 'bg-zinc-500',
};

export function OrdersStatusCounts({
  compteurs,
  value,
  onChange,
  loading,
  total,
  className = '',
}: {
  compteurs: CompteurStatut[];
  /** Statut filtré actuellement ("ALL" = aucun filtre). */
  value: string;
  /** Absent = compteurs en lecture seule (aucun filtre de statut sur cette vue). */
  onChange?: (value: string) => void;
  loading?: boolean;
  /**
   * Montant total (déjà formaté) des commandes du statut sélectionné —
   * « Toutes » = toutes les commandes de la liste, « Livré » = les livrées,
   * etc. (§ demande). Affiché à droite des pastilles ; absent = rien.
   */
  total?: { label: string; montant: string; count: number };
  className?: string;
}) {
  if (loading) {
    return (
      <div className={`flex gap-2 overflow-hidden ${className}`} aria-hidden>
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="h-12 w-24 shrink-0 animate-pulse rounded-lg border bg-muted/50" />
        ))}
      </div>
    );
  }

  return (
    <div
      className={`-mx-4 sm:-mx-6 px-4 sm:px-6 flex gap-2 overflow-x-auto pb-1 ${className}`}
      role={onChange ? 'group' : 'list'}
      aria-label="Nombre de commandes par statut"
    >
      {compteurs.map((c) => {
        const actif = value === c.value;
        const contenu = (
          <>
            <span className="flex items-center gap-1.5 text-[11px] font-medium text-muted-foreground">
              <span className={`h-2 w-2 rounded-full shrink-0 ${POINT[c.value] || 'bg-muted-foreground'}`} aria-hidden />
              <span className="truncate">{c.label}</span>
            </span>
            <span className="text-lg font-bold tabular-nums leading-none">{c.count}</span>
          </>
        );
        const classes = `flex min-w-[96px] shrink-0 flex-col items-start justify-between gap-1 rounded-lg border px-2.5 py-1.5 text-left transition-colors ${
          actif ? 'border-primary bg-primary/10 ring-1 ring-primary/30' : 'bg-card hover:bg-muted/50'
        } ${c.count === 0 && !actif ? 'opacity-60' : ''}`;

        if (!onChange) {
          return (
            <div key={c.value} role="listitem" className={classes}>
              {contenu}
            </div>
          );
        }
        return (
          <button
            key={c.value}
            type="button"
            aria-pressed={actif}
            aria-label={`${c.label} : ${c.count} commande(s)`}
            onClick={() => onChange(actif && c.value !== 'ALL' ? 'ALL' : c.value)}
            className={`${classes} focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring`}
          >
            {contenu}
          </button>
        );
      })}
      {total && (
        <div
          className="ml-auto flex min-w-[150px] shrink-0 flex-col items-end justify-between gap-1 rounded-lg border border-primary/40 bg-primary/5 px-3 py-1.5 text-right"
          role={onChange ? undefined : 'listitem'}
          aria-live="polite"
          aria-label={`Total ${total.label} : ${total.montant}`}
        >
          <span className="text-[11px] font-medium text-muted-foreground truncate max-w-[200px]">
            Total · {total.label}
          </span>
          <span className="text-lg font-bold tabular-nums leading-none">{total.montant}</span>
        </div>
      )}
    </div>
  );
}
