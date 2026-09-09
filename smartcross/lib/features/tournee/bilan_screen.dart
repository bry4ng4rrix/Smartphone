import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _hourFmt = DateFormat('dd/MM HH:mm');
final _dayFmt = DateFormat('dd/MM/yyyy');

/// Prix produit seul = total à payer moins les frais de livraison — dérivé
/// sans le prix par article (jamais exposé au livreur, voir
/// orders/serializers.py::OrderItemPublicSerializer).
double _prixProduit(Order o) => (o.totalAPayer ?? 0) - (o.fraisLivraison ?? 0);

class _Totaux {
  const _Totaux({required this.count, required this.prix, required this.frais, required this.argent});
  final int count;
  final double prix;
  final double frais;
  final double argent;

  factory _Totaux.of(List<Order> orders) => _Totaux(
    count: orders.length,
    prix: orders.fold<double>(0, (s, o) => s + _prixProduit(o)),
    frais: orders.fold<double>(0, (s, o) => s + (o.fraisLivraison ?? 0)),
    argent: orders.fold<double>(0, (s, o) => s + (o.totalAPayer ?? 0)),
  );
}

/// Bilan de la journée du livreur (§ demande) : livraisons faites et retours
/// du jour, avec un ticket récapitulatif — les retours ne sont jamais
/// additionnés aux livraisons faites (rien n'a été encaissé dessus).
/// L'historique renvoyé par le serveur est déjà limité à CE livreur (voir
/// orders/views.py::get_queryset, branche `historique`).
final bilanDuJourProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return ref.read(ordersRepositoryProvider).list(historique: true, dateFrom: start, dateTo: end);
});

class BilanScreen extends ConsumerWidget {
  const BilanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bilanDuJourProvider);
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilan du jour'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(bilanDuJourProvider),
          ),
        ],
      ),
      body: switch (async) {
        AsyncData(:final value) => _BilanBody(orders: value),
        AsyncError(:final error) => ErrorState(
          message: ApiClient.messageFromError(error),
          onRetry: () => ref.invalidate(bilanDuJourProvider),
        ),
        _ => const LoadingState(),
      },
    );
  }
}

class _BilanBody extends StatelessWidget {
  const _BilanBody({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final livrees = orders.where((o) => o.statutCourant == OrderStatus.livre).toList();
    final retours = orders.where((o) => o.statutCourant == OrderStatus.retour).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _TicketCard(livrees: _Totaux.of(livrees), retours: _Totaux.of(retours)),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 18),
            const SizedBox(width: 6),
            Text(
              'Livraisons effectuées (${livrees.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (livrees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Aucune livraison effectuée aujourd\'hui.'),
          )
        else
          for (final o in livrees) _BilanOrderCard(order: o),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.undo, size: 18, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 6),
            Text(
              'Retours (${retours.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          "Colis rapportés — rien n'a été encaissé, ces montants ne comptent pas dans le total du ticket.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (retours.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Aucun retour aujourd\'hui.'),
          )
        else
          for (final o in retours) _BilanOrderCard(order: o),
      ],
    );
  }
}

class _BilanOrderCard extends StatelessWidget {
  const _BilanOrderCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    final muted = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_ar(order.totalAPayer ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                firstItem?.categoryName,
                firstItem?.typeName,
              ].where((e) => e != null && e.isNotEmpty).join(' • '),
              style: muted,
            ),
            for (final item in order.items)
              Text('• ${item.referenceName} — ${item.couleur} (x${item.quantite})'),
            const SizedBox(height: 4),
            Text(
              '${order.clientNom} · ${order.adresseLivraison?.isNotEmpty == true ? order.adresseLivraison : DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)}',
              style: muted,
            ),
            if (order.dateCommande != null)
              Text(_hourFmt.format(order.dateCommande!.toLocal()), style: muted),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Prix ${_ar(_prixProduit(order))}', style: muted),
                Text('Frais ${_ar(order.fraisLivraison ?? 0)}', style: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.livrees, required this.retours});
  final _Totaux livrees;
  final _Totaux retours;

  @override
  Widget build(BuildContext context) {
    Widget ligne(String label, String valeur, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color),
          ),
          Text(
            valeur,
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.receipt_long_outlined),
                  const SizedBox(height: 4),
                  Text(
                    'BILAN DU JOUR',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(_dayFmt.format(DateTime.now()), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 24),
            Text('LIVRAISONS EFFECTUÉES', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            ligne('Nombre', '${livrees.count}'),
            ligne('Total produits', _ar(livrees.prix)),
            ligne('Total frais livraison', _ar(livrees.frais)),
            const Divider(height: 16),
            ligne('TOTAL ARGENT', _ar(livrees.argent), bold: true),
            const Divider(height: 24),
            Text('RETOURS (hors total ci-dessus)', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            ligne('Nombre', '${retours.count}'),
            ligne('Total produits', _ar(retours.prix)),
            ligne('Total frais livraison', _ar(retours.frais)),
            const Divider(height: 16),
            ligne(
              'TOTAL NON ENCAISSÉ',
              _ar(retours.argent),
              bold: true,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}
