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

/**
 * Heure à laquelle la veille "ouvre" les commandes du lendemain.
 *
 * La tournée du lendemain se prépare la veille au soir : à partir de 19h00
 * (heure de Madagascar), préparateur et livreur peuvent déjà agir sur les
 * commandes planifiées pour le jour suivant. Exemple : une commande du
 * 11/09 devient actionnable le 10/09 à 19h00.
 *
 * Doit rester synchronisé avec `orders/services.py::HEURE_OUVERTURE_VEILLE`,
 * qui est la seule autorité : ici on ne fait qu'anticiper l'affichage.
 */
export const HEURE_OUVERTURE_VEILLE = 19;

/**
 * Instant à partir duquel préparateur et livreur peuvent agir sur une
 * commande planifiée à `dateCommande` : 19h00 la veille du jour de livraison,
 * heure d'Antananarivo.
 *
 * Madagascar n'ayant pas d'heure d'été, retirer 24 h à 19h00 du jour J donne
 * toujours 19h00 la veille.
 */
export function ouvertureActions(dateCommande: string | Date): Date {
  const jour = appDayKey(dateCommande);
  const heure = String(HEURE_OUVERTURE_VEILLE).padStart(2, '0');
  const jourJ19h = new Date(`${jour}T${heure}:00:00${APP_UTC_OFFSET}`);
  return new Date(jourJ19h.getTime() - 24 * 60 * 60 * 1000);
}

/**
 * La commande est-elle actionnable maintenant par le préparateur/livreur ?
 * Une commande sans date planifiée l'est toujours.
 */
export function actionOuverte(dateCommande?: string | null): boolean {
  if (!dateCommande) return true;
  return Date.now() >= ouvertureActions(dateCommande).getTime();
}

/** Libellé de l'ouverture — ex : « 10/09/2026 à 19h00 ». */
export function fmtOuverture(dateCommande?: string | null): string {
  if (!dateCommande) return '—';
  const o = ouvertureActions(dateCommande);
  return `${fmtAppDate(o)} à ${o.toLocaleTimeString('fr-FR', {
    timeZone: APP_TIME_ZONE,
    hour: '2-digit',
    minute: '2-digit',
  })}`;
}

/** Heure courante (0-23) à Antananarivo. */
export function appHeure(): number {
  const h = Number(
    new Intl.DateTimeFormat('en-GB', {
      timeZone: APP_TIME_ZONE,
      hour: '2-digit',
      hour12: false,
    }).format(new Date()),
  );
  // Certains moteurs formatent minuit en "24".
  return h === 24 ? 0 : h;
}

/**
 * Dernier jour de livraison dont les commandes sont DÉJÀ actionnables.
 *
 * Avant 19h00 c'est aujourd'hui ; à partir de 19h00 les commandes du
 * lendemain s'ouvrent (voir `ouvertureActions`), donc c'est demain. Sert à
 * borner la liste du préparateur et du livreur : sans ça, à 19h05 leurs
 * commandes du lendemain seraient débloquées mais invisibles.
 */
export function dernierJourOuvert(): string {
  if (appHeure() < HEURE_OUVERTURE_VEILLE) return appToday();
  return appDayKey(new Date(Date.now() + 24 * 60 * 60 * 1000));
}
