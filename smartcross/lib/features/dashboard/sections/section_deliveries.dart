import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/reports.dart';
import '../../../state/reports_provider.dart';
import '../widgets/report_printable.dart';

/// « Livraisons » — port de components/reports/section-deliveries.tsx.
///
/// STUB : en cours de portage par un autre agent. Contrat :
/// `ReportRequest.pour(ReportSection.deliveries, filter, extra: …)` +
/// `ref.watch(reportsProvider(request))`, données typées [DeliveriesData].
class SectionDeliveries extends ConsumerWidget {
  const SectionDeliveries({super.key, required this.filter});

  final ReportsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('Section en cours de portage'));
  }
}

/// Version imprimable de la section (KPI + tableaux, mêmes colonnes que
/// l'écran) — `null` tant que la section n'est pas portée.
ReportPrintable? deliveriesPrintable(DeliveriesData data) => null;
