import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../widgets/status_badge.dart';

/// `fmt(n)` du web : `new Intl.NumberFormat('fr-MG').format(Math.round(n))
/// + ' Ar'` — arrondi à l'entier, séparateur de milliers, suffixe « Ar ».
final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String supplierAr(num? v) => '${_moneyFmt.format((v ?? 0).round())} Ar';

/// `STATUT_COLOR` du web : BROUILLON gris (slate), COMMANDE bleu, RECU vert.
Color supplierStatusColor(SupplierOrderStatus statut) {
  switch (statut) {
    case SupplierOrderStatus.brouillon:
      return const Color(0xFF64748B);
    case SupplierOrderStatus.commande:
      return const Color(0xFF2563EB);
    case SupplierOrderStatus.recu:
      return const Color(0xFF16A34A);
  }
}

/// Badge de statut d'une commande fournisseur — libellé `STATUT_LABEL`
/// (Brouillon / Commandé / Reçu) et couleur `STATUT_COLOR` du web.
class SupplierStatusBadge extends StatelessWidget {
  const SupplierStatusBadge({super.key, required this.statut});
  final SupplierOrderStatus statut;

  @override
  Widget build(BuildContext context) {
    return StatusChip(label: statut.label, color: supplierStatusColor(statut));
  }
}

/// Dialogue de confirmation avant réception — le web appelle l'API dès le
/// clic ; sur mobile un tap accidentel sur une opération irréversible
/// (statut RECU + mouvements d'ENTRÉE) mérite une confirmation.
Future<bool> confirmSupplierReceive(BuildContext context, String numero) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Réceptionner $numero ?'),
      content: const Text(
        'Le stock sera incrémenté automatiquement pour chaque ligne de cette commande (entrée stock fournisseur). Cette action est irréversible.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.inventory_outlined, size: 18),
          label: const Text('Réceptionner'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
