import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/secure_storage.dart';
import '../../models/reports.dart' show formatReportsDate;

/// Assistant de l'application (bulle flottante) — portage de
/// `frontend/components/assistant-bubble.tsx` côté réseau.
///
/// ## DÉPENDANCE À LIRE AVANT TOUT : l'assistant est servi par le site web
///
/// Sur le web, la bulle appelle une route **Next.js**,
/// `POST /api/ai/assistant` (`frontend/app/api/ai/assistant/route.ts`), qui
/// tient le mode d'emploi de l'application (constante `GUIDE`), les prompts
/// (« guide », « rapport ») et parle au modèle **Ollama local du VPS**
/// (`frontend/lib/ollama.ts`). C'est aussi elle qui, pour les actions
/// (commande dictée, stocks depuis un fichier Excel), retrouve les produits
/// dans le catalogue et appelle l'API Django avec le token de l'utilisateur
/// (`frontend/lib/assistant-actions.ts`).
///
/// **Le backend Django n'expose PAS cette route.** L'app mobile ne peut donc
/// utiliser l'assistant que si le frontend web est déployé à côté du serveur
/// — ce qui est le cas du déploiement de référence (`docker-compose.prod.yml`
/// : `backend` sur `BACKEND_PORT`, 8010, et `frontend` sur `FRONTEND_PORT`,
/// 3010, du même hôte). Réimplémenter la route côté Django ou côté app
/// aurait dupliqué le GUIDE et les prompts, qui doivent rester en un seul
/// exemplaire (« pour changer le ton ou le contenu, éditez GUIDE… puis
/// relancez le conteneur frontend », route.ts) : l'app appelle donc la MÊME
/// route, à une adresse dérivée de l'URL de base configurée dans l'écran
/// « Configuration serveur » ([ApiClient.baseUrl]) — voir [assistantUri].
///
/// Quand le site web n'est pas joignable à cette adresse, les appels lèvent
/// [AssistantIndisponibleException], dont le message explique quoi déployer.
///
/// ## Modes de la route (un seul `POST`, corps JSON sauf fichier joint)
///
/// * `{mode: 'guide', question}` — question sur le fonctionnement de l'app,
///   OU ordre de créer une commande (« Crée une commande pour Rakoto… ») :
///   la route renvoie alors une `proposition` à confirmer ([question]) ;
/// * multipart `file` + `question` — fichier Excel de stocks (gérant) :
///   proposition de mise à jour des stocks ([fichierStocks]) ;
/// * `{mode: 'executer', proposition}` — l'utilisateur a confirmé : la
///   proposition est appliquée TELLE QUELLE via l'API Django ([executer]) ;
/// * `{mode: 'rapport', rapport}` — rapport commenté à partir des chiffres
///   de `GET /api/orders/reports/` fournis par l'appelant ([rapport]).
///
/// La réponse est toujours `{reponse: string, proposition?: Proposition}`
/// ([AssistantReply]) — y compris en erreur (statut 500 avec une `reponse`
/// « Désolé, je n'ai pas pu répondre… ») : comme le web, on lit `reponse`
/// quel que soit le statut HTTP.
///
/// Rien ne part vers un service tiers : le modèle tourne sur le VPS.
class AssistantRepository {
  /// Client dédié au site web : autre hôte, autres délais, et pas
  /// l'intercepteur JWT d'[ApiClient] (la route ne renvoie jamais 401 : une
  /// session expirée est signalée dans `reponse`).
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
    // La route répond `{reponse}` même en 500 (erreur Ollama) : on veut
    // lire ce corps, pas une DioException.
    validateStatus: (_) => true,
  ));

  /// Client de l'API Django (rafraîchissement du token, chiffres des
  /// rapports).
  Dio get _api => ApiClient.instance.dio;

  /// Chemin de la route Next.js, identique au `fetch('/api/ai/assistant')`
  /// de la bulle web.
  static const String kRoutePath = '/api/ai/assistant';

  /// Ports hôte par défaut de `docker-compose.prod.yml` / `.env.example` :
  /// `BACKEND_PORT` (Django, l'URL configurée dans l'app) et
  /// `FRONTEND_PORT` (Next.js, où vit la route de l'assistant). Les scripts
  /// de dev suivent la même convention (`manage.py runserver 8010`,
  /// `npm run dev` sur 3010 — roadmap.md § 4).
  static const int kBackendPortDefault = 8010;
  static const int kFrontendPortDefault = 3010;

  /// Adresse de la route de l'assistant, dérivée de l'URL de base du serveur
  /// ([ApiClient.baseUrl] par défaut — celle de l'écran « Configuration
  /// serveur »). Deux topologies de déploiement sont couvertes :
  ///
  /// 1. **Ports distincts sur le même hôte** (le compose de référence, et le
  ///    poste de dev) : `http://hôte:8010` → `http://hôte:3010/api/ai/assistant`.
  ///    Seul le port backend PAR DÉFAUT (8010) est traduit — avec des ports
  ///    personnalisés, l'app ne peut pas deviner `FRONTEND_PORT`.
  /// 2. **Reverse proxy TLS sans port explicite** (roadmap.md § 2, « un
  ///    reverse proxy devant les conteneurs ») : le site et l'API partagent
  ///    l'origine, `https://domaine.mg` → `https://domaine.mg/api/ai/assistant`
  ///    (le proxy doit router `/api/ai/*` vers le frontend et le reste de
  ///    `/api/*` vers Django). Un éventuel préfixe de chemin est conservé.
  static Uri assistantUri([String? baseUrl]) {
    final base = Uri.parse(baseUrl ?? ApiClient.instance.baseUrl);
    final prefix = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    final int? port;
    if (!base.hasPort) {
      port = null;
    } else if (base.port == kBackendPortDefault) {
      port = kFrontendPortDefault;
    } else {
      port = base.port;
    }
    return Uri(
      scheme: base.scheme.isEmpty ? 'http' : base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: port,
      path: '$prefix$kRoutePath',
    );
  }

  /// Délais d'attente de la réponse, alignés sur les profils Ollama de la
  /// route (`frontend/lib/ollama.ts` : `fast` 180 s, `analyse` 900 s) avec
  /// une marge pour que ce soit le serveur qui signale un dépassement, avec
  /// son propre message, plutôt que l'app.
  static const Duration kDelaiRapide = Duration(seconds: 200);
  static const Duration kDelaiAnalyse = Duration(seconds: 920);

  // ---------------------------------------------------------------------------
  // Modes de la route
  // ---------------------------------------------------------------------------

  /// `{mode: 'guide', question}` — question sur l'application ou commande
  /// dictée. Réponse texte, avec une [AssistantProposition] jointe quand la
  /// route a reconnu un ordre de créer une commande (gérant, préparateur).
  Future<AssistantReply> question(String question) async {
    final auth = await _entetesAuth();
    return _poster(
      data: {'mode': 'guide', 'question': question},
      headers: auth,
      delai: kDelaiRapide,
    );
  }

  /// Fichier Excel de stocks joint (trombone, gérant) — multipart `file` +
  /// `question` (message facultatif). Pas de modèle côté serveur : la
  /// route lit le fichier, calcule les écarts avec le stock actuel et
  /// renvoie une proposition « Mise à jour des stocks » à confirmer.
  ///
  /// La route refuse (dans `reponse`) un nom sans extension `.xls`/`.xlsx`
  /// et un fichier de plus de 5 Mo — mêmes contrôles que le web, faits par
  /// le serveur. Les octets sont lus par l'appelant : sur Android,
  /// `file_picker` peut renvoyer un document sans chemin disque (SAF).
  Future<AssistantReply> fichierStocks({
    required Uint8List bytes,
    required String filename,
    String question = '',
  }) async {
    final auth = await _entetesAuth();
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: _excelMediaType(filename)),
      'question': question,
    });
    return _poster(data: form, headers: auth, delai: kDelaiRapide, sendTimeout: const Duration(minutes: 2));
  }

  /// `{mode: 'executer', proposition}` — l'utilisateur a cliqué
  /// « Confirmer » : la proposition est renvoyée TELLE QUELLE (aucun passage
  /// par le modèle) et appliquée via l'API Django avec le token de
  /// l'utilisateur — ses droits s'appliquent (403 → message dans `reponse`).
  Future<AssistantReply> executer(AssistantProposition proposition) async {
    final auth = await _entetesAuth();
    return _poster(
      data: {'mode': 'executer', 'proposition': proposition.raw},
      headers: auth,
      delai: kDelaiRapide,
    );
  }

  /// `{mode: 'rapport', rapport}` — rédige le rapport commenté des chiffres
  /// [rapport] (réponse brute de `GET /api/orders/reports/`, voir
  /// [chiffresDerniersJours]). Profil « analyse » : 1 à 2 minutes sur le VPS.
  /// Pas de token : les chiffres sont fournis dans le corps, comme sur le web.
  ///
  /// [question] : « demande particulière » que la route accepte en plus des
  /// chiffres (`promptRapport(rapport, question)`) ; la bulle web n'en envoie
  /// pas.
  Future<AssistantReply> rapport(Map<String, dynamic> rapport, {String question = ''}) {
    return _poster(
      data: {
        'mode': 'rapport',
        'rapport': rapport,
        if (question.trim().isNotEmpty) 'question': question.trim(),
      },
      delai: kDelaiAnalyse,
    );
  }

  // ---------------------------------------------------------------------------
  // Chiffres du rapport (API Django)
  // ---------------------------------------------------------------------------

  /// Chiffres des [jours] derniers jours, aujourd'hui (Antananarivo)
  /// compris — `djangoClient.reports.get(J−29, J)` de `genererRapport()`
  /// pour 30 jours. Même endpoint que `ReportsRepository.fetch`, mais
  /// renvoyé BRUT : c'est ce JSON, intégral, que la route donne au modèle.
  ///
  /// GÉRANT UNIQUEMENT : le serveur répond 403 à tout autre compte (le
  /// bouton n'est affiché qu'au gérant, comme sur le web).
  Future<Map<String, dynamic>> chiffresDerniersJours(int jours) async {
    final fin = appToday();
    final debut = DateTime(fin.year, fin.month, fin.day - (jours - 1));
    final response = await _api.get(
      'orders/reports/',
      queryParameters: {
        'date_from': formatReportsDate(debut),
        'date_to': formatReportsDate(fin),
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Réponse inattendue du serveur pour les rapports.');
    }
    return data.cast<String, dynamic>();
  }

  // ---------------------------------------------------------------------------
  // Plomberie
  // ---------------------------------------------------------------------------

  /// `entetesAuth()` de la bulle web : le token d'accès n'est valable que
  /// quelques minutes, et la route s'en sert pour agir auprès de l'API au
  /// nom de l'utilisateur. Un appel léger à `users/me/` par [ApiClient]
  /// force son rafraîchissement (intercepteur 401) avant de le transmettre ;
  /// l'échec de cet appel est ignoré, comme sur le web (`.catch(() => null)`).
  Future<Map<String, String>> _entetesAuth() async {
    try {
      await _api.get('users/me/');
    } catch (_) {
      // Sans importance : on transmet le token tel qu'il est.
    }
    final token = await TokenStorage.instance.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  Future<AssistantReply> _poster({
    required Object data,
    Map<String, String> headers = const {},
    required Duration delai,
    Duration? sendTimeout,
  }) async {
    final uri = assistantUri();
    final Response<dynamic> response;
    try {
      response = await _dio.postUri(
        uri,
        data: data,
        options: Options(headers: headers, receiveTimeout: delai, sendTimeout: sendTimeout),
      );
    } on DioException catch (e) {
      // Hôte injoignable (rien n'écoute à cette adresse) — à distinguer d'un
      // modèle trop lent (receiveTimeout), qui n'est pas un problème de
      // déploiement et se signale comme un échec ordinaire.
      if (_injoignable(e)) {
        throw AssistantIndisponibleException(
          "Impossible de joindre l'assistant à $uri. Il est servi par le site web "
          '(Next.js), qui doit être déployé à côté du serveur — voir docker-compose.prod.yml '
          '(FRONTEND_PORT) ou le reverse proxy.',
        );
      }
      rethrow;
    }
    final body = response.data;
    if (body is Map && body['reponse'] is String) {
      return AssistantReply.fromJson(body.cast<String, dynamic>());
    }
    // Pas une réponse de l'assistant : page 404 de Django, HTML d'un proxy…
    // Le site web n'est pas là où on l'attend.
    throw AssistantIndisponibleException(
      "L'assistant n'est pas disponible à $uri (réponse ${response.statusCode ?? '?'} "
      "sans contenu d'assistant). Le site web (Next.js) doit être déployé à côté du "
      'serveur, sur le même hôte — voir docker-compose.prod.yml (FRONTEND_PORT).',
    );
  }

  static bool _injoignable(DioException e) {
    if (e.response != null) return false;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return true;
      case DioExceptionType.unknown:
        return e.error is SocketException;
      default:
        return false;
    }
  }

  /// Type MIME du fichier joint, d'après son extension — `accept=".xlsx,.xls"`
  /// de l'input web.
  static DioMediaType _excelMediaType(String filename) {
    if (filename.toLowerCase().endsWith('.xls')) {
      return DioMediaType('application', 'vnd.ms-excel');
    }
    return DioMediaType('application', 'vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }
}

// -----------------------------------------------------------------------------
// Types échangés avec la route — `frontend/lib/assistant-types.ts`
// -----------------------------------------------------------------------------

/// `ReponseAssistant` : le texte de l'assistant, et éventuellement une
/// action à confirmer.
class AssistantReply {
  const AssistantReply({required this.reponse, this.proposition});

  final String reponse;
  final AssistantProposition? proposition;

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    final proposition = json['proposition'];
    return AssistantReply(
      reponse: json['reponse'] as String? ?? '',
      proposition: proposition is Map ? AssistantProposition.fromJson(proposition.cast<String, dynamic>()) : null,
    );
  }
}

/// `Proposition` : action proposée par l'assistant, à confirmer avant
/// exécution. [resume] est ce qu'on montre à l'utilisateur ; [raw] est la
/// proposition COMPLÈTE telle que reçue (payload de la commande, ou
/// ajustements de stock + nom du fichier), renvoyée à l'identique au mode
/// « executer » — ce qui est exécuté est exactement ce qui a été affiché.
class AssistantProposition {
  const AssistantProposition({required this.type, required this.resume, required this.raw});

  /// `creer_commande` ou `maj_stock`.
  final String type;

  /// Lignes du récapitulatif.
  final List<String> resume;

  /// La proposition intégrale (à ne jamais modifier côté app).
  final Map<String, dynamic> raw;

  static const String typeCommande = 'creer_commande';
  static const String typeStock = 'maj_stock';

  bool get estCommande => type == typeCommande;

  /// Titre de la carte : « Nouvelle commande » / « Mise à jour des stocks ».
  String get titre => estCommande ? 'Nouvelle commande' : 'Mise à jour des stocks';

  factory AssistantProposition.fromJson(Map<String, dynamic> json) {
    return AssistantProposition(
      type: json['type'] as String? ?? '',
      resume: (json['resume'] as List? ?? const []).map((e) => e.toString()).toList(),
      raw: json,
    );
  }
}

/// Le site web (qui héberge la route de l'assistant) n'est pas joignable à
/// l'adresse dérivée de l'URL du serveur — voir [AssistantRepository] pour
/// la dépendance de déploiement. [message] est destiné à l'utilisateur.
class AssistantIndisponibleException implements Exception {
  const AssistantIndisponibleException(this.message);

  final String message;

  @override
  String toString() => message;
}
