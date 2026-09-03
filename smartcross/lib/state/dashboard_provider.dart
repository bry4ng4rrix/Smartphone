import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/dashboard_repository.dart';
import '../models/dashboard.dart';
import 'realtime_provider.dart';

final dashboardRepositoryProvider = Provider((ref) => DashboardRepository());

enum DashboardPeriodPreset { jour, semaine, mois, personnalise }

class DashboardFilter {
  const DashboardFilter({this.preset = DashboardPeriodPreset.mois, this.dateDebut, this.dateFin});
  final DashboardPeriodPreset preset;
  final DateTime? dateDebut;
  final DateTime? dateFin;

  DashboardFilter copyWith({DashboardPeriodPreset? preset, DateTime? dateDebut, DateTime? dateFin}) {
    return DashboardFilter(
      preset: preset ?? this.preset,
      dateDebut: dateDebut ?? this.dateDebut,
      dateFin: dateFin ?? this.dateFin,
    );
  }

  (DateTime?, DateTime?) resolveRange() {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    switch (preset) {
      case DashboardPeriodPreset.jour:
        return (day, day);
      case DashboardPeriodPreset.semaine:
        return (day.subtract(Duration(days: day.weekday - 1)), day);
      case DashboardPeriodPreset.mois:
        return (DateTime(day.year, day.month, 1), day);
      case DashboardPeriodPreset.personnalise:
        return (dateDebut, dateFin);
    }
  }
}

class DashboardFilterNotifier extends Notifier<DashboardFilter> {
  @override
  DashboardFilter build() => const DashboardFilter();

  void set(DashboardFilter filter) => state = filter;
}

final dashboardFilterProvider = NotifierProvider<DashboardFilterNotifier, DashboardFilter>(DashboardFilterNotifier.new);

class DashboardNotifier extends AsyncNotifier<DashboardData> {
  late final _repo = ref.read(dashboardRepositoryProvider);

  @override
  Future<DashboardData> build() {
    ref.watch(realtimeTickProvider);
    final filter = ref.watch(dashboardFilterProvider);
    final (debut, fin) = filter.resolveRange();
    return _repo.fetch(dateDebut: debut, dateFin: fin);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final filter = ref.read(dashboardFilterProvider);
      final (debut, fin) = filter.resolveRange();
      return _repo.fetch(dateDebut: debut, dateFin: fin);
    });
  }
}

final dashboardProvider = AsyncNotifierProvider<DashboardNotifier, DashboardData>(DashboardNotifier.new);
