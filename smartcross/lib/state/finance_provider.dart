import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/finance_repository.dart';
import '../models/finance.dart';
import 'realtime_provider.dart';

final financeRepositoryProvider = Provider((ref) => FinanceRepository());

/// Paramètres d'une lecture de trésorerie : magasin + période (jours
/// d'Antananarivo, `AAAA-MM-JJ`).
typedef FinanceQuery = ({int? magasinId, String dateFrom, String dateTo});

/// Tableau de bord trésorerie — rechargé à chaque événement temps réel
/// (`tresorerie`, `caisse_movement`, `order`…) via [realtimeTickProvider].
final financeDashboardProvider = FutureProvider.autoDispose.family<FinanceDashboard, FinanceQuery>((ref, q) {
  ref.watch(realtimeTickProvider);
  return ref.read(financeRepositoryProvider).dashboard(magasinId: q.magasinId, dateFrom: q.dateFrom, dateTo: q.dateTo);
});

final financeJournalProvider = FutureProvider.autoDispose.family<List<JournalLigne>, FinanceQuery>((ref, q) {
  ref.watch(realtimeTickProvider);
  return ref.read(financeRepositoryProvider).journal(magasinId: q.magasinId, dateFrom: q.dateFrom, dateTo: q.dateTo);
});

final financeVentesProvider = FutureProvider.autoDispose.family<List<VenteLigne>, FinanceQuery>((ref, q) {
  ref.watch(realtimeTickProvider);
  return ref.read(financeRepositoryProvider).ventes(magasinId: q.magasinId, dateFrom: q.dateFrom, dateTo: q.dateTo);
});

final financeEpargneProvider = FutureProvider.autoDispose.family<({double solde, List<EpargneMouvement> historique}), int?>((ref, magasinId) {
  ref.watch(realtimeTickProvider);
  return ref.read(financeRepositoryProvider).epargne(magasinId: magasinId);
});
