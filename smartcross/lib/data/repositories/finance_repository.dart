import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/finance.dart';

/// `/api/finance/*` — trésorerie (gain réel, journal, ventes, épargne,
/// encaissements). Miroir de `djangoClient.finance` (frontend/lib/
/// django-client.ts). Réservé au gérant.
class FinanceRepository {
  Dio get _dio => ApiClient.instance.dio;

  Map<String, dynamic> _q({int? magasinId, String? dateFrom, String? dateTo, String? origine}) => {
        'magasin_id': ?magasinId,
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
        'origine': ?origine,
      };

  Future<FinanceDashboard> dashboard({int? magasinId, String? dateFrom, String? dateTo}) async {
    final r = await _dio.get('finance/dashboard/', queryParameters: _q(magasinId: magasinId, dateFrom: dateFrom, dateTo: dateTo));
    return FinanceDashboard.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<JournalLigne>> journal({int? magasinId, String? dateFrom, String? dateTo, String? origine}) async {
    final r = await _dio.get('finance/journal/', queryParameters: _q(magasinId: magasinId, dateFrom: dateFrom, dateTo: dateTo, origine: origine));
    return ((r.data as Map)['lignes'] as List? ?? []).map((e) => JournalLigne.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<VenteLigne>> ventes({int? magasinId, String? dateFrom, String? dateTo}) async {
    final r = await _dio.get('finance/ventes/', queryParameters: _q(magasinId: magasinId, dateFrom: dateFrom, dateTo: dateTo));
    return ((r.data as Map)['ventes'] as List? ?? []).map((e) => VenteLigne.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<({double solde, List<EpargneMouvement> historique})> epargne({int? magasinId}) async {
    final r = await _dio.get('finance/epargne/', queryParameters: _q(magasinId: magasinId));
    final data = r.data as Map;
    return (
      solde: double.tryParse('${data['solde']}') ?? 0,
      historique: (data['historique'] as List? ?? []).map((e) => EpargneMouvement.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }

  /// Retrait d'épargne — `confirmation: true` obligatoire côté serveur.
  Future<void> retraitEpargne({int? magasinId, required double montant, String motif = ''}) =>
      _dio.post('finance/epargne/retrait/', queryParameters: _q(magasinId: magasinId), data: {
        'montant': montant,
        'motif': motif,
        'confirmation': true,
        'magasin_id': ?magasinId,
      });

  /// Remise en caisse des encaissements d'un livreur (ou d'une sélection).
  Future<({int nb, double brut, double depenses, double net})> remise({
    int? magasinId,
    int? livreurId,
    List<int>? encaissementIds,
    bool inclureDepenses = true,
  }) async {
    final r = await _dio.post('finance/encaissements/remise/', queryParameters: _q(magasinId: magasinId), data: {
      'livreur_id': ?livreurId,
      'encaissement_ids': ?encaissementIds,
      'inclure_depenses': inclureDepenses,
      'magasin_id': ?magasinId,
    });
    final d = r.data as Map;
    double n(dynamic v) => double.tryParse('$v') ?? 0;
    return (nb: int.tryParse('${d['nb']}') ?? 0, brut: n(d['brut']), depenses: n(d['depenses']), net: n(d['net']));
  }

  Future<({double reappro, double epargne, double depenses})> settings({int? magasinId}) async {
    final r = await _dio.get('finance/settings/', queryParameters: _q(magasinId: magasinId));
    final d = r.data as Map;
    double n(dynamic v) => double.tryParse('$v') ?? 0;
    return (reappro: n(d['pct_reappro']), epargne: n(d['pct_epargne']), depenses: n(d['pct_depenses']));
  }

  Future<void> updateSettings({int? magasinId, required double reappro, required double epargne, required double depenses}) =>
      _dio.patch('finance/settings/', queryParameters: _q(magasinId: magasinId), data: {
        'pct_reappro': reappro,
        'pct_epargne': epargne,
        'pct_depenses': depenses,
      });
}
