/// Fuseau métier de l'application : Madagascar — Indian/Antananarivo,
/// UTC+3 toute l'année (pas d'heure d'été, jamais).
///
/// Le "jour J" (jour à partir duquel un préparateur/livreur peut agir sur une
/// commande) doit être LE MÊME pour le serveur, le web et l'app mobile. Sans
/// ça, entre 00h00 et 03h00 à Antananarivo, un serveur réglé en UTC est encore
/// la veille et refuse une commande planifiée « aujourd'hui » — c'est
/// exactement l'erreur « Cette commande est planifiée pour le JJ/MM/AAAA ».
/// Le backend fixe donc `TIME_ZONE = 'Indian/Antananarivo'`
/// (Stock/settings.py) et ce module fait la même chose côté app, quel que soit
/// le fuseau réglé sur l'appareil.
library;

/// Décalage fixe de Madagascar par rapport à UTC.
const Duration kAppUtcOffset = Duration(hours: 3);

/// Instant courant exprimé en heure d'Antananarivo (objet "naïf" : ses champs
/// year/month/day/hour se lisent directement comme l'heure du magasin).
DateTime appNow() => DateTime.now().toUtc().add(kAppUtcOffset);

/// Convertit un instant quelconque en heure d'Antananarivo.
DateTime appLocal(DateTime instant) => instant.toUtc().add(kAppUtcOffset);

/// Jour calendaire (minuit) d'un instant, à Antananarivo.
DateTime appDay(DateTime instant) {
  final d = appLocal(instant);
  return DateTime(d.year, d.month, d.day);
}

/// Jour calendaire d'aujourd'hui, à Antananarivo.
DateTime appToday() => appDay(DateTime.now());

/// Lit une heure "au mur" (celle affichée/saisie par l'utilisateur) comme une
/// heure d'Antananarivo et renvoie l'instant absolu correspondant, en UTC —
/// à envoyer au serveur.
DateTime appWallClockToUtc(DateTime wallClock) => DateTime.utc(
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second,
    ).subtract(kAppUtcOffset);

/// Bornes absolues (UTC) d'une journée entière à Antananarivo — pour les
/// filtres `date_from`/`date_to` envoyés au serveur.
({DateTime start, DateTime end}) appDayBounds([DateTime? day]) {
  final d = day == null ? appToday() : appDay(day);
  return (
    start: appWallClockToUtc(DateTime(d.year, d.month, d.day)),
    end: appWallClockToUtc(DateTime(d.year, d.month, d.day, 23, 59, 59)),
  );
}
