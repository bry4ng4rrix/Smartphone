// Classes de couleur sémantiques partagées par la page Caisse — toujours
// avec leur variante sombre, pour ne jamais casser le mode dark.
export const POS = 'text-emerald-600 dark:text-emerald-400';
export const NEG = 'text-red-600 dark:text-red-400';
export const WARN = 'text-amber-600 dark:text-amber-400';
export const INFO = 'text-blue-600 dark:text-blue-400';

/** Couleur d'un montant selon son signe (0 = neutre). */
export const signe = (v: number | string | null | undefined) => {
  const n = Number(v || 0);
  return n > 0 ? POS : n < 0 ? NEG : 'text-muted-foreground';
};
