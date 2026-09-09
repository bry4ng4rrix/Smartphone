/**
 * Fuseau métier de l'application : Madagascar — Indian/Antananarivo (UTC+3,
 * sans heure d'été, toute l'année).
 *
 * Le "jour J" (date à partir de laquelle un préparateur/livreur peut agir sur
 * une commande) doit être LE MÊME pour tout le monde : le serveur, le web et
 * l'app mobile. Sans ça, entre 00h00 et 03h00 à Antananarivo, un serveur en
 * UTC est encore la veille et refuse une commande planifiée « aujourd'hui »
 * (`orders/services.py::change_order_status`). Le backend fixe donc
 * `TIME_ZONE = 'Indian/Antananarivo'` (voir Stock/settings.py) et ce module
 * fait la même chose côté navigateur, indépendamment du fuseau de l'appareil.
 */
export const APP_TIME_ZONE = "Indian/Antananarivo";

/** Décalage fixe de Madagascar — utilisé pour composer des bornes ISO. */
export const APP_UTC_OFFSET = "+03:00";

const dayKeyFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: APP_TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/**
 * Jour calendaire à Antananarivo, au format `YYYY-MM-DD` — donc directement
 * comparable avec `<`/`<=` entre deux clés (ordre lexicographique = ordre
 * chronologique).
 */
export function appDayKey(date: Date | string | number = new Date()): string {
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) return "";
  return dayKeyFormatter.format(d);
}

/** Date d'aujourd'hui à Antananarivo (`YYYY-MM-DD`). */
export function appToday(): string {
  return appDayKey(new Date());
}

/**
 * Bornes ISO absolues d'une journée à Antananarivo (00:00:00 → 23:59:59.999),
 * à envoyer telles quelles au serveur en filtre `date_from`/`date_to`.
 */
export function appDayBounds(dayKey: string = appToday()) {
  return {
    start: new Date(`${dayKey}T00:00:00.000${APP_UTC_OFFSET}`).toISOString(),
    end: new Date(`${dayKey}T23:59:59.999${APP_UTC_OFFSET}`).toISOString(),
  };
}

/** Date affichée en heure d'Antananarivo — ex : « 10/09/2026 ». */
export function fmtAppDate(value?: string | Date | null): string {
  if (!value) return "—";
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("fr-FR", { timeZone: APP_TIME_ZONE });
}

/** Date + heure affichées en heure d'Antananarivo — ex : « 10/09/2026 09:30 ». */
export function fmtAppDateTime(value?: string | Date | null): string {
  if (!value) return "—";
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString("fr-FR", {
    timeZone: APP_TIME_ZONE,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * Valeur pour un `<input type="date">`/[DateTimeInput] (`YYYY-MM-DDTHH:mm`)
 * exprimée à l'heure d'Antananarivo — pour que « maintenant » proposé par
 * défaut dans un formulaire soit l'heure du magasin, pas celle de l'appareil.
 */
export function appDatetimeLocalValue(date: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  // `hour12: false` peut renvoyer "24" pour minuit selon le moteur.
  const hour = get("hour") === "24" ? "00" : get("hour");
  return `${get("year")}-${get("month")}-${get("day")}T${hour}:${get("minute")}`;
}

/**
 * Convertit une valeur `datetime-local` (`YYYY-MM-DDTHH:mm`, saisie par
 * l'utilisateur) en instant ISO absolu, en la lisant comme une heure
 * d'Antananarivo — et non comme l'heure du fuseau de l'appareil.
 */
export function appDatetimeLocalToIso(value: string): string {
  const normalized = value.length === 16 ? `${value}:00` : value;
  return new Date(`${normalized}${APP_UTC_OFFSET}`).toISOString();
}
