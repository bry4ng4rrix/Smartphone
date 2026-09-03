import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({super.key, required this.status});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusChip(label: status.label, color: statusColor(context, status.apiValue));
  }
}

class StockLevelBadge extends StatelessWidget {
  const StockLevelBadge({super.key, required this.isRupture, required this.isStockBas});
  final bool isRupture;
  final bool isStockBas;

  @override
  Widget build(BuildContext context) {
    if (isRupture) return const StatusChip(label: 'Rupture', color: Color(0xFFEF4444));
    if (isStockBas) return const StatusChip(label: 'Stock bas', color: Color(0xFFF59E0B));
    return const StatusChip(label: 'En stock', color: Color(0xFF10B981));
  }
}
