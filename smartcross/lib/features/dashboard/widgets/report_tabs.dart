import 'package:flutter/material.dart';

import '../../../models/reports.dart';

/// Port de components/reports/report-tabs.tsx : onglets sur écran large
/// (≥ 1024 px), bouton « Liste des rapports · {section} » ouvrant un menu
/// sur mobile.
class ReportTabs extends StatelessWidget {
  const ReportTabs({super.key, required this.actif, required this.onChange});

  final ReportSection actif;
  final ValueChanged<ReportSection> onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final large = MediaQuery.sizeOf(context).width >= 1024;

    if (large) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final s in kReportSections)
              ChoiceChip(
                label: Text(s.label, style: const TextStyle(fontSize: 13)),
                selected: s == actif,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onChange(s),
              ),
          ],
        ),
      );
    }

    return MenuAnchor(
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(MediaQuery.sizeOf(context).width - 32, 0)),
      ),
      menuChildren: [
        for (final s in kReportSections)
          MenuItemButton(
            onPressed: () => onChange(s),
            trailingIcon: s == actif ? const Icon(Icons.check, size: 16) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.label, style: const TextStyle(fontSize: 14)),
                Text(s.description, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), alignment: Alignment.centerLeft),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          children: [
            const Icon(Icons.format_list_numbered, size: 16),
            const SizedBox(width: 8),
            const Text('Liste des rapports'),
            const SizedBox(width: 6),
            Expanded(
              child: Text('· ${actif.label}', style: TextStyle(color: muted), overflow: TextOverflow.ellipsis),
            ),
            Icon(Icons.expand_more, size: 16, color: muted),
          ],
        ),
      ),
    );
  }
}
