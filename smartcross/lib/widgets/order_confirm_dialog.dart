import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../models/order.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String arFmt(num v) => '${_moneyFmt.format(v.round())} Ar';

/// "Jour J" = jour du champ dateCommande (planning) — le préparateur/livreur
/// voit toutes ses commandes à venir mais ne peut agir dessus qu'à partir de
/// ce jour (le serveur applique la même règle, voir orders/services.py).
bool isJourJ(DateTime? dateCommande) {
  if (dateCommande == null) return true;
  final d = dateCommande.toLocal();
  final today = DateTime.now();
  final dueDate = DateTime(d.year, d.month, d.day);
  final todayDate = DateTime(today.year, today.month, today.day);
  return !dueDate.isAfter(todayDate);
}

final _dueDateFmt = DateFormat('dd/MM/yyyy');
String dueDateLabel(DateTime dateCommande) => _dueDateFmt.format(dateCommande.toLocal());

/// Confirmation avant toute action de statut (préparateur/livreur) — résumé
/// de la commande (client, téléphone, articles, prix) + note optionnelle.
/// Retourne la note saisie (chaîne vide possible) si confirmé, `null` si annulé.
Future<String?> showOrderConfirmDialog(
  BuildContext context, {
  required String title,
  required Order order,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _OrderConfirmDialog(title: title, order: order),
  );
}

class _OrderConfirmDialog extends StatefulWidget {
  const _OrderConfirmDialog({required this.title, required this.order});
  final String title;
  final Order order;

  @override
  State<_OrderConfirmDialog> createState() => _OrderConfirmDialogState();
}

class _OrderConfirmDialogState extends State<_OrderConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isRecuperation = order.livraisonZone == DeliveryZone.recuperation;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : muted),
              Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        );

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Commande ${order.numero} — vérifiez le résumé avant de confirmer.', style: muted),
            const SizedBox(height: 10),
            row('Client', order.clientNom),
            if (order.telephone != null) row('Téléphone', order.telephone!),
            row('Zone', order.livraisonZone.shortLabel),
            if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
              row('Adresse', order.adresseLivraison!),
            const Divider(height: 20),
            for (final item in order.items) row('${item.referenceName} (${item.couleur})', 'x${item.quantite}'),
            if (order.totalAPayer != null) ...[
              const Divider(height: 20),
              if (!isRecuperation && order.fraisLivraison != null) ...[
                row('Prix de vente', arFmt(order.totalAPayer! - order.fraisLivraison!)),
                row('Frais de livraison', arFmt(order.fraisLivraison!)),
              ],
              row('Total', arFmt(order.totalAPayer!), bold: true),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Note (optionnel)', hintText: 'ex : client absent'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Confirmer')),
      ],
    );
  }
}
