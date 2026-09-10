import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/json_utils.dart';

/// Données brutes de l'écran Rapports — portage de
/// `frontend/app/(app)/reports/page.tsx`, qui charge en parallèle
/// (Promise.all) les 4 sources ci-dessous via `djangoClient`.
///
/// Le web ne consomme PAS les modèles métier de l'app (Order, ProductReference,
/// StockMovement) mais des formes « à plat » construites par
/// `lib/django-client.ts` (services `sales` / `products` / `movements`). Ces
/// mappings sont reproduits ici à l'identique, sinon les chiffres affichés
/// divergeraient entre le web et l'app.
class ReportsData {
  const ReportsData({
    required this.sales,
    required this.products,
    required this.movements,
    required this.dashboardKpis,
  });

  final List<ReportSale> sales;
  final List<ReportProduct> products;
  final List<ReportMovement> movements;

  /// `kpis` de `GET /users/dashboard/`. Vide si l'appel échoue : le web
  /// l'enveloppe dans `.catch(() => ({}))`, l'erreur est donc silencieuse.
  /// Ces chiffres n'alimentent QUE le payload de l'analyse IA (seule source
  /// qui connaît le coût d'achat), jamais les cartes KPI de la page.
  final Map<String, dynamic> dashboardKpis;
}

/// Une « vente » = UNE LIGNE D'ARTICLE d'une commande livrée (le module
/// Ventes/Ticket n'existe plus, §5 Smartreadme.md). Mapping identique à
/// `djangoClient.sales.list()` : seules les commandes `statut_courant ===
/// 'LIVRE'` sont retenues, puis aplaties article par article.
class ReportSale {
  const ReportSale({
    required this.id,
    required this.productName,
    required this.quantity,
    this.salePrice,
    this.totalPrice,
    this.customerName,
    required this.isPaid,
    required this.totalProfit,
    this.soldAt,
    this.sellerName,
    this.shopName,
    this.paymentAmount,
    this.paymentDueDate,
  });

  final String id;
  final String productName;
  final int quantity;
  final double? salePrice;
  final double? totalPrice;
  final String? customerName;

  /// `true` en dur côté client : le backend ne gère pas encore le paiement
  /// partiel (§3 MVP), donc ni `payment_amount` ni `payment_due_date` ne
  /// sont exposés — les deux restent nuls ici, exactement comme sur le web.
  final bool isPaid;

  /// `0` en dur : le coût d'achat n'est pas exposé par `/orders/`.
  final double totalProfit;
  final DateTime? soldAt;

  /// Non exposés par `/orders/` (ni sur le web) — d'où les libellés de repli
  /// « Non attribué » / « Magasin inconnu » dans les classements.
  final String? sellerName;
  final String? shopName;
  final double? paymentAmount;
  final DateTime? paymentDueDate;

  /// Restant dû = max(total - déjà payé, 0).
  double get remaining {
    final due = (totalPrice ?? 0) - (paymentAmount ?? 0);
    return due > 0 ? due : 0;
  }

  /// Vente à crédit : non soldée, ou soldée partiellement.
  bool get isUnpaid => !isPaid || (paymentAmount ?? 0) < (totalPrice ?? 0);

  static List<ReportSale> fromOrder(Map<String, dynamic> order) {
    final items = (order['items'] as List? ?? const []);
    final orderId = asString(order['id']);
    final soldAt = asDateOrNull(order['updated_at']) ?? asDateOrNull(order['created_at']);
    return items.whereType<Map>().map((raw) {
      final item = raw.cast<String, dynamic>();
      final couleur = asString(item['couleur']);
      final prix = asDoubleOrNull(item['prix_unitaire']);
      final quantite = asInt(item['quantite'], 1);
      return ReportSale(
        id: '$orderId-${asString(item['id'])}',
        productName: asString(item['reference_name']) +
            (couleur.isNotEmpty && couleur != 'Standard' ? ' ($couleur)' : ''),
        quantity: quantite,
        salePrice: prix,
        totalPrice: prix != null ? prix * quantite : null,
        customerName: asStringOrNull(order['client_nom']),
        isPaid: true,
        totalProfit: 0,
        soldAt: soldAt,
      );
    }).toList();
  }
}

/// Référence catalogue aplatie — mapping de `mapReferenceToProduct()` du web :
/// `initial_quantity` = somme des stocks des variantes, `alert_threshold` =
/// plus petit seuil d'alerte (1 par défaut), `expiry_date` toujours nulle
/// (ce catalogue ne suit pas de péremption, §8.1).
class ReportProduct {
  const ReportProduct({
    required this.id,
    required this.name,
    required this.initialQuantity,
    required this.alertThreshold,
    this.expiryDate,
  });

  final int id;
  final String name;
  final int initialQuantity;
  final int alertThreshold;
  final DateTime? expiryDate;

  bool get isLowStock => initialQuantity <= alertThreshold;
  bool get isRupture => initialQuantity == 0;

  factory ReportProduct.fromReference(Map<String, dynamic> ref) {
    final variants = (ref['variants'] as List? ?? const []).whereType<Map>().toList();
    var stock = 0;
    int? minSeuil;
    for (final v in variants) {
      stock += asInt(v['stock_actuel']);
      final seuil = asIntOrNull(v['seuil_alerte']) ?? 1;
      minSeuil = minSeuil == null || seuil < minSeuil ? seuil : minSeuil;
    }
    return ReportProduct(
      id: asInt(ref['id']),
      name: asString(ref['reference_name']),
      initialQuantity: stock,
      alertThreshold: minSeuil ?? 1,
      expiryDate: asDateOrNull(ref['expiry_date']),
    );
  }
}

/// Sens du mouvement de stock — `type` brut du serveur (ENTREE | SORTIE).
/// `transfert` n'existe pas encore côté backend (catalog/models.py ::
/// StockMovement.TYPE_CHOICES) mais la tuile est conservée pour la parité
/// avec le web.
enum ReportMovementKind { entree, sortie, transfert }

/// Mouvement de stock — mapping de `djangoClient.movements.list()`.
class ReportMovement {
  const ReportMovement({
    required this.id,
    required this.productName,
    required this.kind,
    required this.originLabel,
    required this.change,
    this.userName,
    this.note,
    this.createdAt,
  });

  final int id;
  final String productName;
  final ReportMovementKind kind;

  /// Libellé d'origine (« Préparation de commande », « Réception
  /// fournisseur »…) — c'est ce que le web place dans `movement_type`.
  final String originLabel;
  final int change;
  final String? userName;
  final String? note;
  final DateTime? createdAt;

  static const Map<String, String> _originLabels = {
    'PREPARATION': 'Préparation de commande',
    'RETOUR': 'Retour de commande',
    'ANNULATION': 'Annulation de commande',
    'LIVRE': 'Commande livrée',
    'FOURNISSEUR': 'Réception fournisseur',
    'AJUSTEMENT': 'Ajustement manuel',
  };

  factory ReportMovement.fromJson(Map<String, dynamic> json) {
    final couleur = asString(json['couleur']);
    final type = asString(json['type']);
    final quantite = asInt(json['quantite']);
    final origine = asString(json['origine']);
    return ReportMovement(
      id: asInt(json['id']),
      productName: asString(json['reference_name']) +
          (couleur.isNotEmpty && couleur != 'Standard' ? ' ($couleur)' : ''),
      kind: switch (type) {
        'SORTIE' => ReportMovementKind.sortie,
        'TRANSFERT' => ReportMovementKind.transfert,
        _ => ReportMovementKind.entree,
      },
      originLabel: _originLabels[origine] ?? origine,
      change: type == 'SORTIE' ? -quantite : quantite,
      userName: asStringOrNull(json['user_name']),
      note: asStringOrNull(json['note']),
      createdAt: asDateOrNull(json['timestamp']),
    );
  }
}

/// Résultat de l'analyse IA. Le serveur renvoie son message d'erreur dans le
/// MÊME champ `analysis` (avec un statut 500) : le texte est alors affiché en
/// rouge plutôt que masqué — comportement repris du web.
class AiAnalysisResult {
  const AiAnalysisResult({required this.analysis, required this.isError});

  final String analysis;
  final bool isError;
}

/// Sources de l'écran Rapports. Aucun endpoint dédié côté serveur : comme le
/// web, tout est agrégé côté client à partir des commandes, du catalogue et
/// de l'historique de stock.
class ReportsRepository {
  Dio get _dio => ApiClient.instance.dio;

  Future<ReportsData> fetchAll() async {
    final results = await Future.wait<Response?>([
      _dio.get('orders/'),
      _dio.get('catalog/references/'),
      _dio.get('catalog/movements/'),
      // Échec silencieux (`.catch(() => ({}))` côté web) : ces KPI ne servent
      // qu'à l'analyse IA, la page reste utilisable sans eux.
      _dio.get('users/dashboard/').then<Response?>((r) => r).catchError((_) => null),
    ]);

    final orders = _rows(results[0]?.data);
    final sales = <ReportSale>[];
    for (final order in orders) {
      if (asString(order['statut_courant']) != 'LIVRE') continue;
      sales.addAll(ReportSale.fromOrder(order));
    }

    final products = _rows(results[1]?.data).map(ReportProduct.fromReference).toList();
    final movements = _rows(results[2]?.data).map(ReportMovement.fromJson).toList();

    final dashboard = results[3]?.data;
    final kpis = dashboard is Map ? dashboard['kpis'] : null;

    return ReportsData(
      sales: sales,
      products: products,
      movements: movements,
      dashboardKpis: kpis is Map ? kpis.cast<String, dynamic>() : const {},
    );
  }

  /// `POST /api/ai/analyze` — proxy vers le modèle Ollama local
  /// (frontend/app/api/ai/analyze/route.ts côté web). Le modèle tourne en CPU
  /// sur le VPS : plusieurs minutes de génération sont normales, d'où le
  /// délai de 10 minutes aligné sur celui du web (600 000 ms).
  Future<AiAnalysisResult> analyze(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post(
        'ai/analyze/',
        data: payload,
        options: Options(
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      final data = response.data;
      final analysis = data is Map ? asString(data['analysis']) : '';
      return AiAnalysisResult(analysis: analysis, isError: false);
    } on DioException catch (e) {
      // La route renvoie son message d'erreur (en français) dans `analysis`
      // avec un statut 500 : on l'affiche tel quel, en rouge.
      final data = e.response?.data;
      if (data is Map && data['analysis'] is String && (data['analysis'] as String).isNotEmpty) {
        return AiAnalysisResult(analysis: data['analysis'] as String, isError: true);
      }
      return AiAnalysisResult(
        analysis: "Erreur réseau lors de l'appel à l'analyse IA. ${ApiClient.messageFromError(e)}",
        isError: true,
      );
    } catch (e) {
      return const AiAnalysisResult(
        analysis: "Erreur réseau lors de l'appel à l'analyse IA.",
        isError: true,
      );
    }
  }

  /// DRF renvoie soit une liste brute, soit une enveloppe paginée
  /// `{results: [...]}` — les deux sont acceptées, comme côté web.
  List<Map<String, dynamic>> _rows(dynamic data) {
    final list = data is List
        ? data
        : data is Map
            ? (data['results'] as List? ?? const [])
            : const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
}
