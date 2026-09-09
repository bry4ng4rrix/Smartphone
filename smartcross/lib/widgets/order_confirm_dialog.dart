import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/app_time.dart';
import '../core/constants.dart';
import '../models/delivery_zone.dart';
import '../models/order.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String arFmt(num v) => '${_moneyFmt.format(v.round())} Ar';

/// "Jour J" = jour du champ dateCommande (planning) — le préparateur/livreur
/// voit toutes ses commandes à venir mais ne peut agir dessus qu'à partir de
/// ce jour (le serveur applique la même règle, voir orders/services.py).
///
/// La comparaison se fait sur le jour calendaire d'ANTANANARIVO (voir
/// core/app_time.dart), pas sur le fuseau de l'appareil : c'est la même
/// référence que le serveur, sinon l'app autorise l'action alors que le
/// serveur la refuse (ou l'inverse).
bool isJourJ(DateTime? dateCommande) {
  if (dateCommande == null) return true;
  return !appDay(dateCommande).isAfter(appToday());
}

final _dueDateFmt = DateFormat('dd/MM/yyyy');
String dueDateLabel(DateTime dateCommande) => _dueDateFmt.format(appLocal(dateCommande));

/// Résultat de [showOrderConfirmDialog] : la note saisie (chaîne vide
/// possible) et, si [showOrderConfirmDialog] l'a proposé, le chemin local de
/// la photo choisie (preuve de préparation — § demande).
class OrderConfirmResult {
  const OrderConfirmResult({required this.note, this.photoPath});
  final String note;
  final String? photoPath;
}

/// Confirmation avant toute action de statut (préparateur/livreur/gérant) —
/// résumé de la commande (client, téléphone, articles, prix) + note
/// optionnelle, et (si [showPhoto]) une photo justificative optionnelle.
/// [hideAmounts] masque tous les montants (commande déjà réglée d'avance :
/// le livreur n'a rien à encaisser — § demande). Retourne `null` si annulé.
Future<OrderConfirmResult?> showOrderConfirmDialog(
  BuildContext context, {
  required String title,
  required Order order,
  bool showPhoto = false,
  bool hideAmounts = false,
}) {
  return showDialog<OrderConfirmResult>(
    context: context,
    builder: (context) => _OrderConfirmDialog(
      title: title,
      order: order,
      showPhoto: showPhoto,
      hideAmounts: hideAmounts,
    ),
  );
}

class _OrderConfirmDialog extends StatefulWidget {
  const _OrderConfirmDialog({
    required this.title,
    required this.order,
    this.showPhoto = false,
    this.hideAmounts = false,
  });
  final String title;
  final Order order;
  final bool showPhoto;
  final bool hideAmounts;

  @override
  State<_OrderConfirmDialog> createState() => _OrderConfirmDialogState();
}

class _OrderConfirmDialogState extends State<_OrderConfirmDialog> {
  final _controller = TextEditingController();
  XFile? _photo;

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file != null) setState(() => _photo = file);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isRecuperation = order.livraisonZone == kRecuperationCode;
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
            row('Zone', DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)),
            if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
              row('Adresse', order.adresseLivraison!),
            if (!isRecuperation) row('Paiement', order.modePaiement.label),
            const Divider(height: 20),
            for (final item in order.items) row('${item.referenceName} (${item.couleur})', 'x${item.quantite}'),
            if (widget.hideAmounts) ...[
              const Divider(height: 20),
              row('À encaisser', 'Rien — déjà payé', bold: true),
            ] else if (order.totalAPayer != null) ...[
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
            if (widget.showPhoto) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_photo == null ? 'Photo de la préparation (optionnel)' : 'Reprendre la photo'),
                    ),
                  ),
                  if (_photo != null) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(_photo!.path), width: 44, height: 44, fit: BoxFit.cover),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            OrderConfirmResult(note: _controller.text.trim(), photoPath: _photo?.path),
          ),
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}
