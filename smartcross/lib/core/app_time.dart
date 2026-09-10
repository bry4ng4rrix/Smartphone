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

import 'constants.dart';

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

/// Heure à laquelle la veille "ouvre" les commandes du lendemain pour le
/// PRÉPARATEUR : 19h00 heure de Madagascar, soit 5 heures avant le début du
/// jour J. Il prépare ainsi les colis du lendemain la veille au soir.
///
/// Doit rester synchronisé avec
/// `orders/services.py::HEURE_OUVERTURE_PREPARATEUR`, seule autorité — ici on
/// ne fait qu'anticiper l'affichage.
const int kHeureOuverturePreparateur = 19;

/// Instant absolu (UTC) à partir duquel [role] peut agir sur une commande
/// planifiée à [dateCommande]. L'ouverture diffère selon le métier :
///
/// * [UserRole.preparateur] — 19h00 la VEILLE du jour de livraison ;
/// * [UserRole.livreur] — minuit le JOUR de livraison : il ne part en tournée
///   que le jour même, rien à débloquer la veille.
///
/// Madagascar n'ayant pas d'heure d'été, retirer 24 h à 19h00 du jour de
/// livraison donne toujours 19h00 la veille.
DateTime ouvertureActions(DateTime dateCommande, UserRole role) {
  final jour = appDay(dateCommande);
  if (role == UserRole.preparateur) {
    return appWallClockToUtc(
      DateTime(jour.year, jour.month, jour.day, kHeureOuverturePreparateur),
    ).subtract(const Duration(days: 1));
  }
  return appWallClockToUtc(DateTime(jour.year, jour.month, jour.day));
}

/// La commande est-elle actionnable maintenant par ce rôle ? Une commande
/// sans date planifiée l'est toujours.
bool actionOuverte(DateTime? dateCommande, UserRole role) {
  if (dateCommande == null) return true;
  return !DateTime.now().toUtc().isBefore(ouvertureActions(dateCommande, role));
}

/// Dernier jour de livraison dont les commandes sont DÉJÀ actionnables par ce
/// rôle. Pour le préparateur, à partir de 19h00 les commandes du lendemain
/// s'ouvrent : sans cette borne elles seraient débloquées mais invisibles.
/// Pour le livreur, la fenêtre s'arrête toujours à aujourd'hui.
DateTime dernierJourOuvert(UserRole role) {
  final jour = appToday();
  if (role == UserRole.preparateur &&
      appNow().hour >= kHeureOuverturePreparateur) {
    return jour.add(const Duration(days: 1));
  }
  return jour;
}
