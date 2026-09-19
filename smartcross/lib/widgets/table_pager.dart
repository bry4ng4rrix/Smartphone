import 'package:flutter/material.dart';

/// Lignes par page des listes paginées côté client (catalogue, notes) —
/// même valeur que `PAGE_SIZE` de products/page.tsx.
const kTablePageSize = 50;

/// Page courante bornée à la liste : si elle rétrécit (filtre, suppression),
/// on retombe sur la dernière page existante.
int clampPage(int page, int total, int pageSize) {
  final pages = (total / pageSize).ceil().clamp(1, 1 << 30);
  return page.clamp(0, pages - 1);
}

/// Pied de tableau « 1–50 sur 312 · ‹ 1/7 › » (`TablePager` du web, même
/// gabarit que le pied du ReportTable du tableau de bord). Rien n'est rendu
/// s'il n'y a qu'une page.
class TablePager extends StatelessWidget {
  const TablePager({
    super.key,
    required this.page,
    required this.total,
    required this.pageSize,
    required this.onPageChange,
  });

  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPageChange;

  @override
  Widget build(BuildContext context) {
    final pages = (total / pageSize).ceil().clamp(1, 1 << 30);
    if (pages <= 1) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final courante = page.clamp(0, pages - 1);
    final fin = (courante + 1) * pageSize > total ? total : (courante + 1) * pageSize;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
      child: Row(
        children: [
          Expanded(
            child: Text('${courante * pageSize + 1}–$fin sur $total', style: TextStyle(fontSize: 12, color: muted)),
          ),
          IconButton(
            tooltip: 'Page précédente',
            visualDensity: VisualDensity.compact,
            onPressed: courante == 0 ? null : () => onPageChange(courante - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
          ),
          Text('${courante + 1}/$pages', style: TextStyle(fontSize: 12, color: muted)),
          IconButton(
            tooltip: 'Page suivante',
            visualDensity: VisualDensity.compact,
            onPressed: courante >= pages - 1 ? null : () => onPageChange(courante + 1),
            icon: const Icon(Icons.chevron_right, size: 18),
          ),
        ],
      ),
    );
  }
}
