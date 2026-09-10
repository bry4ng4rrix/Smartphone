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

/// Heure à laquelle la veille "ouvre" les commandes du lendemain.
///
/// La tournée du lendemain se prépare la veille au soir : à partir de 19h00
/// (heure de Madagascar), préparateur et livreur peuvent déjà agir sur les
/// commandes planifiées pour le jour suivant. Exemple : une commande du 11/09
/// devient actionnable le 10/09 à 19h00.
///
/// Doit rester synchronisé avec `orders/services.py::HEURE_OUVERTURE_VEILLE`,
/// seule autorité — ici on ne fait qu'anticiper l'affichage.
const int kHeureOuvertureVeille = 19;

/// Instant absolu (UTC) à partir duquel préparateur et livreur peuvent agir
/// sur une commande planifiée à [dateCommande] : 19h00 la veille du jour de
/// livraison, heure d'Antananarivo.
///
/// Madagascar n'ayant pas d'heure d'été, retirer 24 h à 19h00 du jour de
/// livraison donne toujours 19h00 la veille.
DateTime ouvertureActions(DateTime dateCommande) {
  final jour = appDay(dateCommande);
  return appWallClockToUtc(
    DateTime(jour.year, jour.month, jour.day, kHeureOuvertureVeille),
  ).subtract(const Duration(days: 1));
}

/// La commande est-elle actionnable maintenant ? Une commande sans date
/// planifiée l'est toujours.
bool actionOuverte(DateTime? dateCommande) {
  if (dateCommande == null) return true;
  return !DateTime.now().toUtc().isBefore(ouvertureActions(dateCommande));
}

/// Dernier jour de livraison dont les commandes sont DÉJÀ actionnables :
/// aujourd'hui avant 19h00, demain à partir de 19h00. Sert à borner la liste
/// du préparateur et du livreur — sans ça, à 19h05 leurs commandes du
/// lendemain seraient débloquées mais invisibles.
DateTime dernierJourOuvert() {
  final maintenant = appNow();
  final jour = appToday();
  if (maintenant.hour < kHeureOuvertureVeille) return jour;
  return jour.add(const Duration(days: 1));
}
