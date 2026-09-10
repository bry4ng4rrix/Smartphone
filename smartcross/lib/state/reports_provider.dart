import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_time.dart';
import '../data/repositories/reports_repository.dart';
import 'realtime_provider.dart';

final reportsRepositoryProvider = Provider((ref) => ReportsRepository());

/// Périodes proposées par le sélecteur du graphique (`PERIODS` du web).
const List<int> kReportsPeriods = [7, 30, 90];

/// Période sélectionnée, en jours. Purement CLIENT : la changer ne relance
/// aucun appel API et n'impacte que le graphique du CA et les compteurs de
/// mouvements (les KPI et les classements portent sur toutes les données).
/// Défaut 30, aucune persistance — comme le web.
class ReportsPeriodNotifier extends Notifier<int> {
  @override
  int build() => 30;

  void set(int days) => state = days;
}

final reportsPeriodProvider = NotifierProvider<ReportsPeriodNotifier, int>(ReportsPeriodNotifier.new);

/// Données de l'écran Rapports. Le `realtimeTickProvider` rejoue l'équivalent
/// de `useRealtimeRefresh(['product_variant','order','stock_movement'])` :
/// rechargement silencieux à chaque événement WebSocket.
class ReportsNotifier extends AsyncNotifier<ReportsData> {
  @override
  Future<ReportsData> build() {
    ref.watch(realtimeTickProvider);
    return ref.read(reportsRepositoryProvider).fetchAll();
  }

  /// Bouton « Actualiser » : rechargement NON silencieux (réaffiche l'état de
  /// chargement), comme `fetchData()` sans argument côté web.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(reportsRepositoryProvider).fetchAll());
  }
}

final reportsProvider = AsyncNotifierProvider<ReportsNotifier, ReportsData>(ReportsNotifier.new);

// ---------------------------------------------------------------------------
// Agrégats
// ---------------------------------------------------------------------------

/// Ligne du classement « Top produits vendus ».
class ProductStat {
  const ProductStat({required this.name, required this.qty, required this.revenue, required this.profit});

  final String name;
  final int qty;
  final double revenue;
  final double profit;
}

/// Ligne du classement « Performance des vendeurs ».
class SellerStat {
  const SellerStat({required this.name, required this.count, required this.revenue, required this.profit});

  final String name;
  final int count;
  final double revenue;
  final double profit;
}

/// Ligne du classement « Performance par magasin » (admin uniquement).
class ShopStat {
  const ShopStat({required this.name, required this.qty, required this.revenue, required this.profit});

  final String name;
  final int qty;
  final double revenue;
  final double profit;
}

/// Un jour du graphique du CA.
class RevenuePoint {
  const RevenuePoint({required this.day, required this.revenue});

  final DateTime day;
  final double revenue;

  /// Étiquette d'axe — `date.slice(5)` du web (MM-JJ), rendu en JJ/MM.
  String get label => '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
}

/// Compteurs des 3 tuiles « Mouvements de stock ».
class MovementCounts {
  const MovementCounts({required this.entrees, required this.sorties, required this.transferts});

  final int entrees;
  final int sorties;
  final int transferts;
}

/// Tous les calculs de la page, faits côté client comme sur le web.
class ReportsAnalytics {
  const ReportsAnalytics({
    required this.totalRevenue,
    required this.totalProfit,
    required this.totalQty,
    required this.totalStock,
    required this.transactions,
    required this.lowStockCount,
    required this.expiredCount,
    required this.unpaidSales,
    required this.unpaidValue,
    required this.unpaidSorted,
    required this.topProducts,
    required this.topSellers,
    required this.topShops,
    required this.revenueChart,
    required this.movementCounts,
    required this.ruptures,
    required this.stockBas,
    required this.produitsSansMouvement,
    required this.dashboardKpis,
    required this.isAdmin,
  });

  final double totalRevenue;
  final double totalProfit;
  final int totalQty;
  final int totalStock;
  final int transactions;
  final int lowStockCount;
  final int expiredCount;

  /// Ventes à crédit (non soldées ou partiellement payées).
  final List<ReportSale> unpaidSales;
  final double unpaidValue;

  /// Les 8 premières échéances (les ventes sans date d'échéance passent en
  /// dernier), affichées dans la carte « Ventes à crédit ».
  final List<ReportSale> unpaidSorted;

  final List<ProductStat> topProducts;
  final List<SellerStat> topSellers;

  /// Vide si l'utilisateur n'est pas `admin` : le web ne remplit `byShop`
  /// que dans ce cas.
  final List<ShopStat> topShops;

  final List<RevenuePoint> revenueChart;
  final MovementCounts movementCounts;

  // Listes envoyées à l'analyse IA uniquement.
  final List<ReportProduct> ruptures;
  final List<ReportProduct> stockBas;
  final List<ReportProduct> produitsSansMouvement;
  final Map<String, dynamic> dashboardKpis;
  final bool isAdmin;

  int get alertesStock => lowStockCount + expiredCount;

  static ReportsAnalytics compute(ReportsData data, int period, bool isAdmin) {
    final sales = data.sales;
    final products = data.products;
    final today = appToday();

    var totalRevenue = 0.0;
    var totalProfit = 0.0;
    var totalQty = 0;
    for (final s in sales) {
      totalRevenue += s.totalPrice ?? 0;
      totalProfit += s.totalProfit;
      totalQty += s.quantity;
    }
    final totalStock = products.fold<int>(0, (sum, p) => sum + p.initialQuantity);

    final unpaid = sales.where((s) => s.isUnpaid).toList();
    final unpaidValue = unpaid.fold<double>(0, (sum, s) => sum + s.remaining);

    final expiredCount =
        products.where((p) => p.expiryDate != null && p.expiryDate!.isBefore(today)).length;
    final lowStockCount = products.where((p) => p.isLowStock).length;

    // --- Ventes par produit (qté, CA, bénéfice), top 10 par quantité.
    final byProduct = <String, ProductStat>{};
    for (final s in sales) {
      final name = s.productName.isNotEmpty ? s.productName : 'Inconnu';
      final current = byProduct[name];
      byProduct[name] = ProductStat(
        name: name,
        qty: (current?.qty ?? 0) + s.quantity,
        revenue: (current?.revenue ?? 0) + (s.totalPrice ?? 0),
        profit: (current?.profit ?? 0) + s.totalProfit,
      );
    }
    final topProducts = _stableSorted<ProductStat>(
      byProduct.values.toList(),
      (a, b) => b.qty.compareTo(a.qty),
    ).take(10).toList();

    // --- Ventes par vendeur, top 8 par CA. `seller_name` n'est pas exposé
    // par /orders/ : toutes les lignes retombent sur « Non attribué », comme
    // sur le web.
    final bySeller = <String, SellerStat>{};
    for (final s in sales) {
      final name = s.sellerName?.isNotEmpty == true ? s.sellerName! : 'Non attribué';
      final current = bySeller[name];
      bySeller[name] = SellerStat(
        name: name,
        count: (current?.count ?? 0) + 1,
        revenue: (current?.revenue ?? 0) + (s.totalPrice ?? 0),
        profit: (current?.profit ?? 0) + s.totalProfit,
      );
    }
    final topSellers = _stableSorted<SellerStat>(
      bySeller.values.toList(),
      (a, b) => b.revenue.compareTo(a.revenue),
    ).take(8).toList();

    // --- Ventes par magasin — calculé UNIQUEMENT pour un admin (comparaison
    // multi-magasins), liste complète non tronquée.
    final byShop = <String, ShopStat>{};
    if (isAdmin) {
      for (final s in sales) {
        final name = s.shopName?.isNotEmpty == true ? s.shopName! : 'Magasin inconnu';
        final current = byShop[name];
        byShop[name] = ShopStat(
          name: name,
          qty: (current?.qty ?? 0) + s.quantity,
          revenue: (current?.revenue ?? 0) + (s.totalPrice ?? 0),
          profit: (current?.profit ?? 0) + s.totalProfit,
        );
      }
    }
    final topShops = _stableSorted<ShopStat>(
      byShop.values.toList(),
      (a, b) => b.revenue.compareTo(a.revenue),
    );

    // --- Graphique du CA : un seau par jour sur la période, aujourd'hui
    // inclus. Journées bornées à l'heure d'Antananarivo (core/app_time.dart),
    // là où le web découpe en UTC.
    final buckets = <String, double>{};
    final days = <DateTime>[];
    for (var i = period - 1; i >= 0; i--) {
      final d = DateTime(today.year, today.month, today.day - i);
      days.add(d);
      buckets[_dayKey(d)] = 0;
    }
    for (final s in sales) {
      if (s.soldAt == null) continue;
      final key = _dayKey(appDay(s.soldAt!));
      if (buckets.containsKey(key)) {
        buckets[key] = buckets[key]! + (s.totalPrice ?? 0);
      }
    }
    final revenueChart = [
      for (final d in days) RevenuePoint(day: d, revenue: buckets[_dayKey(d)] ?? 0),
    ];

    // --- Répartition des mouvements sur la période.
    final periodStart = appNow().subtract(Duration(days: period));
    var entrees = 0;
    var sorties = 0;
    var transferts = 0;
    for (final m in data.movements) {
      if (m.createdAt == null) continue;
      if (appLocal(m.createdAt!).isBefore(periodStart)) continue;
      switch (m.kind) {
        case ReportMovementKind.entree:
          entrees++;
        case ReportMovementKind.sortie:
          sorties++;
        case ReportMovementKind.transfert:
          transferts++;
      }
    }

    // --- Ventes à crédit : échéance la plus proche d'abord, sans échéance en
    // dernier, 8 lignes maximum.
    final unpaidSorted = _stableSorted<ReportSale>(unpaid, (a, b) {
      if (a.paymentDueDate == null) return 1;
      if (b.paymentDueDate == null) return -1;
      return a.paymentDueDate!.compareTo(b.paymentDueDate!);
    }).take(8).toList();

    // --- Listes réservées au payload de l'analyse IA.
    final ruptures = products.where((p) => p.isRupture).take(15).toList();
    final stockBas =
        products.where((p) => p.initialQuantity > 0 && p.isLowStock).take(15).toList();
    final sansMouvement = products.where((p) => !byProduct.containsKey(p.name)).take(15).toList();

    return ReportsAnalytics(
      totalRevenue: totalRevenue,
      totalProfit: totalProfit,
      totalQty: totalQty,
      totalStock: totalStock,
      transactions: sales.length,
      lowStockCount: lowStockCount,
      expiredCount: expiredCount,
      unpaidSales: unpaid,
      unpaidValue: unpaidValue,
      unpaidSorted: unpaidSorted,
      topProducts: topProducts,
      topSellers: topSellers,
      topShops: topShops,
      revenueChart: revenueChart,
      movementCounts: MovementCounts(entrees: entrees, sorties: sorties, transferts: transferts),
      ruptures: ruptures,
      stockBas: stockBas,
      produitsSansMouvement: sansMouvement,
      dashboardKpis: data.dashboardKpis,
      isAdmin: isAdmin,
    );
  }

  /// Payload envoyé à l'analyse IA. Les chiffres financiers viennent du
  /// dashboard (seule source qui connaît le coût d'achat) avec repli sur les
  /// agrégats de la page ; `topMagasins` n'est envoyé que pour un admin.
  Map<String, dynamic> aiPayload() {
    num? kpi(String key) {
      final v = dashboardKpis[key];
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    return {
      'periode': 'toutes périodes confondues',
      'ca': kpi('ca') ?? totalRevenue,
      'beneficeNet': kpi('total_profit') ?? totalProfit,
      'valeurStock': kpi('total_stock_value') ?? kpi('stock_value'),
      'beneficeEstimeStock': kpi('benefice_estime_stock'),
      'ventesImpayeesCount': unpaidSales.length,
      'topProduits': [
        for (final p in topProducts)
          {'name': p.name, 'qty': p.qty, 'revenue': p.revenue, 'profit': p.profit},
      ],
      'produitsSansMouvement': [for (final p in produitsSansMouvement) {'name': p.name}],
      'rupturesStock': [for (final p in ruptures) {'name': p.name, 'stock': 0}],
      'stockBas': [
        for (final p in stockBas)
          {'name': p.name, 'stock': p.initialQuantity, 'seuil': p.alertThreshold},
      ],
      'repartitionMouvements': {
        'Entrée': movementCounts.entrees,
        'Sortie': movementCounts.sorties,
        'Transfert': movementCounts.transferts,
      },
      'topVendeurs': [for (final s in topSellers) {'name': s.name, 'revenue': s.revenue}],
      if (isAdmin) 'topMagasins': [for (final s in topShops) {'name': s.name, 'revenue': s.revenue}],
    };
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// `List.sort` de Dart n'est pas stable, contrairement à `Array.sort` en
  /// JS : on décore avec l'index d'insertion pour que deux lignes à égalité
  /// gardent l'ordre d'origine (et donc le même classement que le web).
  static List<T> _stableSorted<T>(List<T> items, int Function(T a, T b) compare) {
    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final result = compare(a.$2, b.$2);
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }
}

// ---------------------------------------------------------------------------
// Analyse IA
// ---------------------------------------------------------------------------

/// État de la carte « Analyse IA Stratégique » (3 états locaux du composant
/// web : analysis / loading / error).
class AiAnalysisState {
  const AiAnalysisState({this.analysis = '', this.loading = false, this.error = false});

  final String analysis;
  final bool loading;
  final bool error;
}

class AiAnalysisNotifier extends Notifier<AiAnalysisState> {
  @override
  AiAnalysisState build() => const AiAnalysisState();

  /// Génère (ou régénère) l'analyse. Aucune annulation possible pendant la
  /// génération, aucune persistance : l'analyse est perdue au démontage.
  Future<void> generate(Map<String, dynamic> payload) async {
    state = AiAnalysisState(analysis: state.analysis, loading: true);
    final result = await ref.read(reportsRepositoryProvider).analyze(payload);
    state = AiAnalysisState(analysis: result.analysis, error: result.isError);
  }
}

final aiAnalysisProvider =
    NotifierProvider<AiAnalysisNotifier, AiAnalysisState>(AiAnalysisNotifier.new);
