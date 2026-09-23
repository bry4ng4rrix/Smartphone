import 'api_client.dart';

/// URL de média telle que CE device peut la charger.
///
/// Le serveur construit ses URLs absolues à partir de l'hôte de la requête.
/// Deux cas la rendent injoignable depuis un téléphone ou un émulateur :
///
///  * un message poussé en direct par le socket porte l'hôte de l'EXPÉDITEUR
///    — `localhost` si le collègue travaille sur le web de la même machine ;
///  * une réponse servie derrière un proxy interne (`http://backend:8010`)
///    porte un nom d'hôte qui n'existe que dans le réseau Docker.
///
/// On rebase alors sur l'URL serveur configurée dans l'app. Une URL relative
/// (`/media/...`, renvoyée quand le serializer n'a pas reçu la requête) est
/// simplement préfixée. Tout autre hôte (CDN, IP du LAN) est laissé tel quel.
///
/// Renvoie `null` pour une entrée vide, afin que les widgets puissent
/// directement afficher leur image de remplacement.
String? mediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  final base = ApiClient.instance.baseUrl;
  if (!uri.hasScheme) {
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  const injoignables = {
    'localhost',
    '127.0.0.1',
    '0.0.0.0',
    '::1',
    '[::1]',
    // Nom de service du réseau Docker (docker-compose.prod.yml) : résolu par
    // le proxy du front client, jamais par un appareil.
    'backend',
  };
  if (injoignables.contains(uri.host)) {
    final origine = Uri.parse(base);
    return Uri(
      scheme: origine.scheme,
      host: origine.host,
      port: origine.hasPort ? origine.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }
  return url;
}
