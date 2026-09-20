/**
 * Date et heure de livraison souhaitées.
 *
 * L'API les accepte dans `date_livraison_souhaitee` (`POST` et `PATCH`
 * /api/client/orders/) et les renvoie sous le même nom : elles alimentent
 * `Order.date_commande`, la date de livraison planifiée côté boutique.
 * Ces fonctions ne font que convertir entre les deux champs du formulaire
 * (date + heure) et la valeur ISO échangée avec l'API.
 */

/** `2026-09-22` + `14:00` → `2026-09-22T14:00:00` (heure locale, interprétée
 *  par Django dans le fuseau d'Antananarivo). Heure vide = minuit, comme la
 *  valeur par défaut des commandes saisies en interne. */
export function versIso(date: string, heure: string): string | undefined {
  if (!date) return undefined;
  return `${date}T${heure || "00:00"}:00`;
}

/** Valeur API → les deux champs du formulaire. */
export function depuisIso(iso: string | null | undefined): { date: string; heure: string } {
  if (!iso) return { date: "", heure: "" };
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return { date: "", heure: "" };
  const p = (n: number) => String(n).padStart(2, "0");
  return {
    date: `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`,
    heure: `${p(d.getHours())}:${p(d.getMinutes())}`,
  };
}

/** « 22/09/2026 à 14:00 », ou `null` si la date est absente. */
export function libelleSouhait(iso: string | null | undefined): string | null {
  const { date, heure } = depuisIso(iso);
  if (!date) return null;
  const [annee, mois, jour] = date.split("-");
  return `${jour}/${mois}/${annee}${heure && heure !== "00:00" ? ` à ${heure}` : ""}`;
}

/** Aujourd'hui au format ISO, pour borner le sélecteur de date. */
export function aujourdhuiIso(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
