import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/supplier.dart';

/// Couleur du badge par statut (mêmes teintes que le web).
Color supplierStatusColor(SupplierOrderStatus s) => switch (s) {
      SupplierOrderStatus.brouillon => const Color(0xFF64748B),
      SupplierOrderStatus.commande => const Color(0xFF2563EB),
      SupplierOrderStatus.acomptePaye => const Color(0xFFD97706),
      SupplierOrderStatus.preparation => const Color(0xFF7C3AED),
      SupplierOrderStatus.paye => const Color(0xFF059669),
      SupplierOrderStatus.expedie => const Color(0xFF0891B2),
      SupplierOrderStatus.enTransit => const Color(0xFF0284C7),
      SupplierOrderStatus.arrive => const Color(0xFFEA580C),
      SupplierOrderStatus.coutFinalise => const Color(0xFF16A34A),
    };

/// Statuts depuis lesquels chaque action est possible (miroir de
/// suppliers/services.py).
const Map<String, List<SupplierOrderStatus>> kTransitions = {
  'commander': [SupplierOrderStatus.brouillon],
  'preparer': [SupplierOrderStatus.commande, SupplierOrderStatus.acomptePaye, SupplierOrderStatus.paye],
  'expedier': [SupplierOrderStatus.commande, SupplierOrderStatus.acomptePaye, SupplierOrderStatus.preparation, SupplierOrderStatus.paye],
  'transit': [SupplierOrderStatus.expedie],
  'arriver': [SupplierOrderStatus.expedie, SupplierOrderStatus.enTransit],
  'finaliser': [SupplierOrderStatus.arrive],
};

bool actionPossible(String action, SupplierOrderStatus statut) => kTransitions[action]?.contains(statut) ?? false;

const List<({String value, String label, String symbole})> kDevises = [
  (value: 'USD', label: 'Dollar US (USD)', symbole: r'$'),
  (value: 'EUR', label: 'Euro (EUR)', symbole: '€'),
  (value: 'CNY', label: 'Yuan (CNY)', symbole: '¥'),
  (value: 'MGA', label: 'Ariary (MGA)', symbole: 'Ar'),
];

const List<({String value, String label})> kTypesPaiement = [
  (value: 'ACOMPTE', label: 'Acompte'),
  (value: 'SOLDE', label: 'Solde'),
  (value: 'PARTIEL', label: 'Paiement partiel'),
  (value: 'AUTRE', label: 'Autre'),
];

const List<({String value, String label})> kMethodesPaiement = [
  (value: 'VIREMENT', label: 'Virement bancaire'),
  (value: 'MOBILE_MONEY', label: 'Mobile money'),
  (value: 'ESPECES', label: 'Espèces'),
  (value: 'CARTE', label: 'Carte'),
  (value: 'AUTRE', label: 'Autre'),
];

const List<({String value, String label})> kModesTransport = [
  (value: 'AERIEN', label: 'Aérien'),
  (value: 'MARITIME', label: 'Maritime'),
  (value: 'ROUTIER', label: 'Routier'),
  (value: 'EXPRESS', label: 'Express / colis'),
  (value: 'AUTRE', label: 'Autre'),
];

final _ar = NumberFormat('#,##0', 'fr_FR');
final _deux = NumberFormat('#,##0.00', 'fr_FR');

String fmtAr(num v) => '${_ar.format(v.round()).replaceAll(',', ' ')} Ar';

String fmtDevise(num montant, String devise) {
  if (devise == 'MGA') return fmtAr(montant);
  final symbole = kDevises.firstWhere((d) => d.value == devise, orElse: () => (value: devise, label: devise, symbole: devise)).symbole;
  return '${_deux.format(montant).replaceAll(',', ' ')} $symbole';
}

String fmtTaux(num v) => '${NumberFormat('#,##0.####', 'fr_FR').format(v).replaceAll(',', ' ')} Ar';

/// `AAAA-MM-JJ` → `JJ/MM/AAAA` (sans décalage de fuseau).
String fmtDateIso(String? v) {
  if (v == null || v.isEmpty) return '—';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  return m == null ? v : '${m[3]}/${m[2]}/${m[1]}';
}

class SupplierStatusBadge extends StatelessWidget {
  const SupplierStatusBadge({super.key, required this.status, this.small = false});
  final SupplierOrderStatus status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = supplierStatusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: small ? 11 : 12, fontWeight: FontWeight.w600)),
    );
  }
}
