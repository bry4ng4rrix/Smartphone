import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/assign_staff_dialog.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/status_badge.dart';
import 'orders_list_screen.dart' show EditOrderDialog;

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Action atteignable par le GÉRANT depuis le statut courant (miroir client
/// de `page.tsx::nextAction` pour `isGerant`, §5 README) — le gérant peut
/// désigner un préparateur/livreur pour démarrer une étape (`assign: true`,
/// via un sélecteur de staff), mais aussi faire progresser lui-même la
/// commande à chaque étape suivante, exactement comme le préparateur/livreur
/// le ferait depuis Dépôt/Tournée.
class _GerantAction {
  const _GerantAction({required this.target, required this.label, required this.icon, this.assign = false});
  final OrderStatus target;
  final String label;
  final IconData icon;
  final bool assign;
}

List<_GerantAction> _nextActions(Order order) {
  switch (order.statutCourant) {
    case OrderStatus.nouvelle:
      return const [
        _GerantAction(
          target: OrderStatus.enPreparation,
          label: 'Assigner un préparateur',
          icon: Icons.person_add_alt_outlined,
          assign: true,
        ),
        _GerantAction(
          target: OrderStatus.enPreparation,
          label: 'Commencer la préparation',
          icon: Icons.inventory_2_outlined,
        ),
      ];
    case OrderStatus.enPreparation:
      return const [_GerantAction(target: OrderStatus.prete, label: 'Commande prête', icon: Icons.check)];
    case OrderStatus.prete:
      // Retrait sur place : pas de livreur, le gérant clôture directement au
      // comptoir (voir services.py::change_order_status).
      if (order.livraisonZone == kRecuperationCode) {
        return const [
          _GerantAction(
            target: OrderStatus.livre,
            label: 'Récupérée par le client',
            icon: Icons.inventory_2_outlined,
          ),
        ];
      }
      return const [
        _GerantAction(
          target: OrderStatus.enLivraison,
          label: 'Assigner un livreur',
          icon: Icons.person_add_alt_outlined,
          assign: true,
        ),
        _GerantAction(
          target: OrderStatus.enLivraison,
          label: 'Récupérer / En livraison',
          icon: Icons.local_shipping_outlined,
        ),
      ];
    case OrderStatus.enLivraison:
      return const [
        _GerantAction(target: OrderStatus.livre, label: 'Livré', icon: Icons.check),
        _GerantAction(target: OrderStatus.retour, label: 'Retour', icon: Icons.undo),
      ];
    case OrderStatus.livre:
    case OrderStatus.retour:
    case OrderStatus.annulee:
      return const [];
  }
}

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);

    // Bouton "Modifier" directement depuis le détail (§ demande) — même
    // fenêtre d'édition que la liste, et mêmes statuts autorisés que côté
    // serveur (voir orders/services.py::_EDITABLE_STATUSES).
    final order = async.asData?.value;
    final canEdit =
        order != null && [OrderStatus.nouvelle, OrderStatus.enPreparation].contains(order.statutCourant);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail commande'),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Modifier la commande',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => EditOrderDialog(order: order),
                );
                ref.invalidate(orderDetailProvider(orderId));
              },
            ),
        ],
      ),
      body: switch (async) {
        AsyncData(:final value) => _OrderDetailBody(order: value),
        AsyncError(:final error) => ErrorState(
          message: ApiClient.messageFromError(error),
          onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        ),
        _ => const LoadingState(),
      },
    );
  }
}

class _OrderDetailBody extends ConsumerStatefulWidget {
  const _OrderDetailBody({required this.order});
  final Order order;

  @override
  ConsumerState<_OrderDetailBody> createState() => _OrderDetailBodyState();
}

class _OrderDetailBodyState extends ConsumerState<_OrderDetailBody> {
  bool _changing = false;

  Future<void> _changeStatus(_GerantAction action) async {
    if (action.assign) {
      // Nouvelle -> En préparation / Prête -> En livraison : le gérant
      // désigne manuellement qui prend la commande en charge (occupé ou non
      // n'empêche plus la sélection, voir services.py::_resolve_assignee) —
      // pas de note ici, l'affectation en elle-même est la confirmation
      // (miroir web : AssignStaffDialog n'a pas de champ note, voir page.tsx).
      final role = action.target == OrderStatus.enPreparation ? 'PREPARATEUR' : 'LIVREUR';
      final result = await showAssignStaffDialog(
        context,
        role: role,
        orderNumero: widget.order.numero,
        loadStaff: () => ref.read(ordersProvider.notifier).availableStaff(role),
      );
      if (result == null) return;
      if (!mounted) return;

      setState(() => _changing = true);
      try {
        await ref
            .read(ordersProvider.notifier)
            .changeStatus(
              widget.order.id,
              action.target.apiValue,
              preparateurId: action.target == OrderStatus.enPreparation ? result.staffId : null,
              livreurId: action.target == OrderStatus.enLivraison ? result.staffId : null,
              assignedAt: result.assignedAt,
            );
        ref.invalidate(orderDetailProvider(widget.order.id));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
        }
      } finally {
        if (mounted) setState(() => _changing = false);
      }
      return;
    }

    // En préparation -> Prête / En livraison -> Livré/Retour : le gérant
    // fait progresser lui-même la commande, exactement comme le
    // préparateur/livreur le ferait depuis Dépôt/Tournée (même dialogue de
    // confirmation avec note optionnelle, voir order_confirm_dialog.dart).
    final result = await showOrderConfirmDialog(
      context,
      title: 'Confirmer : ${action.label}',
      order: widget.order,
      showPhoto: action.target == OrderStatus.prete,
    );
    if (result == null) return;
    if (!mounted) return;

    setState(() => _changing = true);
    try {
      await ref
          .read(ordersProvider.notifier)
          .changeStatus(
            widget.order.id,
            action.target.apiValue,
            note: result.note,
            photoPath: result.photoPath,
          );
      ref.invalidate(orderDetailProvider(widget.order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _cancel() async {
    final order = widget.order;
    final restocks = [
      OrderStatus.enPreparation,
      OrderStatus.prete,
      OrderStatus.enLivraison,
    ].contains(order.statutCourant);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Annuler la commande ${order.numero} ?'),
        content: Text(
          restocks
              ? 'La commande de ${order.clientNom} sera annulée. Le stock déjà déduit pour cette commande sera automatiquement restitué.'
              : 'La commande de ${order.clientNom} sera annulée.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Retour')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler la commande'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _changing = true);
    try {
      await ref.read(ordersProvider.notifier).cancel(order.id);
      ref.invalidate(orderDetailProvider(order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final nextActions = _nextActions(order);
    final canCancel = ![
      OrderStatus.livre,
      OrderStatus.retour,
      OrderStatus.annulee,
    ].contains(order.statutCourant);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(order.numero, style: Theme.of(context).textTheme.headlineSmall),
            OrderStatusBadge(status: order.statutCourant),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(icon: Icons.person_outline, label: 'Client', value: order.clientNom),
                if (order.telephone != null)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Téléphone',
                    value: order.telephone!,
                    onTap: () => launchUrl(Uri.parse('tel:${order.telephone}')),
                  ),
                _InfoRow(
                  icon: Icons.local_shipping_outlined,
                  label: 'Zone',
                  value: DeliveryZoneCatalog.labelFor(order.livraisonZone),
                ),
                if (order.adresseLivraison != null && order.adresseLivraison!.isNotEmpty)
                  _InfoRow(icon: Icons.place_outlined, label: 'Adresse', value: order.adresseLivraison!),
                // La date de création est automatique et immuable ; la date
                // saisie par le gérant, elle, est la livraison prévue
                // (§ demande — voir aussi page.tsx côté web).
                if (order.createdAt != null)
                  _InfoRow(
                    icon: Icons.add_shopping_cart_outlined,
                    label: 'Commande créée le',
                    value: DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt!.toLocal()),
                  ),
                if (order.dateCommande != null)
                  _InfoRow(
                    icon: Icons.event_outlined,
                    label: 'Livraison prévue le',
                    value: DateFormat('dd/MM/yyyy HH:mm').format(order.dateCommande!.toLocal()),
                  ),
                if (order.livraisonZone != kRecuperationCode)
                  _InfoRow(icon: Icons.payments_outlined, label: 'Paiement', value: order.modePaiement.label),
                if (order.preparateurName != null)
                  _InfoRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Préparateur',
                    value: order.preparateurName!,
                  ),
                if (order.livreurName != null)
                  _InfoRow(icon: Icons.moped_outlined, label: 'Livreur', value: order.livreurName!),
                if (order.notePreparateur != null && order.notePreparateur!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.notes_outlined,
                    label: 'Note préparateur',
                    value: order.notePreparateur!,
                  ),
                if (order.noteLivreur != null && order.noteLivreur!.isNotEmpty)
                  _InfoRow(icon: Icons.notes_outlined, label: 'Note livreur', value: order.noteLivreur!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Articles', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final item in order.items)
                ListTile(
                  title: Text('${item.referenceName} — ${item.couleur}'),
                  subtitle: item.prixUnitaire != null
                      ? Text('${item.quantite} × ${_ar(item.prixUnitaire!)}')
                      : Text('Quantité : ${item.quantite}'),
                  trailing: item.prixUnitaire != null ? Text(_ar(item.prixUnitaire! * item.quantite)) : null,
                ),
            ],
          ),
        ),
        if (order.fraisLivraison != null || order.totalAPayer != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  if (order.fraisLivraison != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [const Text('Frais de livraison'), Text(_ar(order.fraisLivraison!))],
                    ),
                  // Rien ne reste à encaisser quand le client a déjà payé
                  // d'avance : afficher un "Total à payer" ferait croire au
                  // livreur qu'il doit encore réclamer la somme (§ demande).
                  if (order.totalAPayer != null && order.modePaiement != PaymentMode.avant) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total à payer', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          _ar(order.totalAPayer!),
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (nextActions.isNotEmpty || canCancel) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            children: [
              for (final action in nextActions)
                action.target == OrderStatus.retour
                    ? OutlinedButton.icon(
                        onPressed: _changing ? null : () => _changeStatus(action),
                        icon: Icon(action.icon),
                        label: Text(action.label),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      )
                    : FilledButton.icon(
                        onPressed: _changing ? null : () => _changeStatus(action),
                        icon: Icon(action.icon),
                        label: Text(action.label),
                      ),
              if (canCancel)
                OutlinedButton.icon(
                  onPressed: _changing ? null : _cancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Annuler la commande'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
        ],
        if (order.statusHistory.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Chronologie', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _OrderTimelineCard(order: order),
          const SizedBox(height: 20),
          Text('Historique détaillé', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final h in order.statusHistory)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 20),
              title: Text('${h.ancienStatut?.label ?? '—'} → ${h.nouveauStatut.label}'),
              subtitle: Text(
                [
                  h.changedByName ?? 'Système',
                  if (h.timestamp != null) _dateFmt.format(h.timestamp!),
                  if (h.note != null && h.note!.isNotEmpty) h.note!,
                ].join(' · '),
              ),
              // Preuve que la préparation est faite — jointe au passage
              // "Prête" (§ demande), aussi visible et téléchargeable ici.
              trailing: h.photo == null
                  ? null
                  : InkWell(
                      onTap: () => launchUrl(Uri.parse(h.photo!)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(h.photo!, width: 40, height: 40, fit: BoxFit.cover),
                      ),
                    ),
            ),
        ],
      ],
    );
  }
}

/// Résumé "Prête le / En livraison depuis le / Livrée le" — une ligne par
/// statut effectivement atteint, dérivée de l'historique complet, pour une
/// lecture immédiate sans avoir à parcourir la liste détaillée en dessous.
class _OrderTimelineCard extends StatelessWidget {
  const _OrderTimelineCard({required this.order});
  final Order order;

  static const _milestones = [
    (OrderStatus.enPreparation, Icons.build_outlined, 'Préparation commencée le'),
    (OrderStatus.prete, Icons.inventory_2_outlined, 'Prête le'),
    (OrderStatus.enLivraison, Icons.local_shipping_outlined, 'En livraison depuis le'),
    (OrderStatus.livre, Icons.check_circle_outline, 'Livrée le'),
    (OrderStatus.retour, Icons.undo, 'Retour le'),
  ];

  @override
  Widget build(BuildContext context) {
    final timestamps = <OrderStatus, DateTime>{};
    for (final h in order.statusHistory) {
      timestamps.putIfAbsent(h.nouveauStatut, () => h.timestamp ?? DateTime.now());
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La création vient de createdAt (horodatage automatique), pas de
            // dateCommande qui porte désormais la livraison prévue — sinon une
            // livraison planifiée pour demain s'affichait "avant" la préparation.
            _TimelineRow(
              icon: Icons.add_shopping_cart_outlined,
              label: 'Commande créée le',
              date: order.createdAt,
              reached: order.createdAt != null,
            ),
            _TimelineRow(
              icon: Icons.event_outlined,
              label: 'Livraison prévue le',
              date: order.dateCommande,
              reached: order.dateCommande != null,
            ),
            for (final (status, icon, label) in _milestones)
              _TimelineRow(
                icon: icon,
                label: label,
                date: timestamps[status],
                reached: timestamps.containsKey(status),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.icon, required this.label, required this.date, required this.reached});
  final IconData icon;
  final String label;
  final DateTime? date;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    if (!reached) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label ', style: Theme.of(context).textTheme.bodyMedium),
                  TextSpan(
                    text: date != null ? _dateFmt.format(date!.toLocal()) : '—',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 10),
            Text('$label : ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: onTap != null ? Theme.of(context).colorScheme.primary : null,
                  decoration: onTap != null ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
