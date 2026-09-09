import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../data/repositories/orders_repository.dart';
import '../../models/catalog.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/orders_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';
import 'order_create_screen.dart' show CartLine, AddOrderLineDialog;

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _dateFmt = DateFormat('dd/MM/yyyy');

/// Module Commandes (§7.1 README) : liste filtrable par statut/date/préparateur.
class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});

  // Une seule date (pas de plage Du/Au) — § demande. `dateDebut`/`dateFin`
  // sont réglés sur le même jour côté serveur (date_debut = date_fin).
  Future<void> _pickDate(BuildContext context, WidgetRef ref, OrdersFilter filter) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: filter.dateDebut ?? DateTime.now(),
    );
    if (date == null) return;
    ref.read(ordersFilterProvider.notifier).set(filter.copyWith(dateDebut: date, dateFin: date));
  }

  Future<void> _pickPreparateur(BuildContext context, WidgetRef ref, OrdersFilter filter) async {
    final selected = await showDialog<int?>(
      context: context,
      builder: (context) => _PreparateurPickerDialog(
        loadStaff: () => ref.read(ordersProvider.notifier).availableStaff('PREPARATEUR'),
      ),
    );
    if (selected == null && filter.preparateurId == null) return;
    ref
        .read(ordersFilterProvider.notifier)
        .set(filter.copyWith(preparateurId: selected, clearPreparateurId: selected == null));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider);
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);

    final filter = ref.watch(ordersFilterProvider);
    final hasActiveFilter =
        filter.statut != null || filter.dateDebut != null || filter.preparateurId != null || filter.nonLivree;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commandes'),
        actions: [
          IconButton(
            tooltip: 'Filtrer par date',
            icon: const Icon(Icons.event_outlined),
            onPressed: () => _pickDate(context, ref, filter),
          ),
          IconButton(
            tooltip: 'Filtrer par préparateur',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => _pickPreparateur(context, ref, filter),
          ),
          PopupMenuButton<String?>(
            tooltip: 'Filtrer par statut',
            icon: const Icon(Icons.filter_list),
            onSelected: (statut) => statut == 'NON_LIVREE'
                ? ref
                      .read(ordersFilterProvider.notifier)
                      .set(filter.copyWith(clearStatut: true, nonLivree: true))
                : ref
                      .read(ordersFilterProvider.notifier)
                      .set(filter.copyWith(statut: statut, clearStatut: statut == null, nonLivree: false)),
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('Tous les statuts')),
              const PopupMenuItem(value: 'NON_LIVREE', child: Text('Pas encore livrée')),
              for (final s in OrderStatus.values) PopupMenuItem(value: s.apiValue, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (hasActiveFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (filter.statut != null)
                    Chip(
                      label: Text(OrderStatusX.fromApi(filter.statut).label),
                      onDeleted: () =>
                          ref.read(ordersFilterProvider.notifier).set(filter.copyWith(clearStatut: true)),
                    ),
                  if (filter.dateDebut != null)
                    Chip(
                      label: Text(_dateFmt.format(filter.dateDebut!)),
                      onDeleted: () => ref
                          .read(ordersFilterProvider.notifier)
                          .set(OrdersFilter(statut: filter.statut, preparateurId: filter.preparateurId)),
                    ),
                  if (filter.preparateurId != null)
                    Chip(
                      label: const Text('Préparateur'),
                      onDeleted: () => ref
                          .read(ordersFilterProvider.notifier)
                          .set(filter.copyWith(clearPreparateurId: true)),
                    ),
                  if (filter.nonLivree)
                    Chip(
                      label: const Text('Pas encore livrée'),
                      onDeleted: () =>
                          ref.read(ordersFilterProvider.notifier).set(filter.copyWith(nonLivree: false)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
              child: switch (async) {
                AsyncData(value: final rawValue) => (() {
                  final value = filter.nonLivree
                      ? rawValue.where((o) => o.statutCourant != OrderStatus.livre).toList()
                      : rawValue;
                  return value.isEmpty
                      ? const EmptyState(message: 'Aucune commande.', icon: Icons.receipt_long_outlined)
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: value.length,
                          itemBuilder: (context, i) => _OrderTile(order: value[i]),
                        );
                })(),
                AsyncError(:final error) => ErrorState(
                  message: ApiClient.messageFromError(error),
                  onRetry: () => ref.read(ordersProvider.notifier).refresh(),
                ),
                _ => const LoadingState(),
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle commande'),
      ),
    );
  }
}

class _PreparateurPickerDialog extends StatefulWidget {
  const _PreparateurPickerDialog({required this.loadStaff});
  final Future<List<StaffOption>> Function() loadStaff;

  @override
  State<_PreparateurPickerDialog> createState() => _PreparateurPickerDialogState();
}

class _PreparateurPickerDialogState extends State<_PreparateurPickerDialog> {
  List<StaffOption>? _staff;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget
        .loadStaff()
        .then((staff) {
          if (mounted)
            setState(() {
              _staff = staff;
              _loading = false;
            });
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filtrer par préparateur'),
      content: SizedBox(
        width: 320,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(title: const Text('Tous'), onTap: () => Navigator.of(context).pop(null)),
                  for (final s in _staff ?? [])
                    ListTile(title: Text(s.fullName), onTap: () => Navigator.of(context).pop(s.id)),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
    );
  }
}

final _shortDateFmt = DateFormat('dd/MM HH:mm');

DateTime? _historyAt(Order order, OrderStatus statut) {
  for (final h in order.statusHistory) {
    if (h.nouveauStatut == statut) return h.timestamp;
  }
  return null;
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.order});
  final Order order;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => EditOrderDialog(order: order),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer la commande ${order.numero} ?'),
        content: Text('Cette action est définitive — la commande de ${order.clientNom} sera supprimée.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(ordersProvider.notifier).delete(order.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preparedAt = _historyAt(order, OrderStatus.enPreparation);
    // Tant que la commande n'est pas Livrée, on affiche la date de livraison
    // prévue (dateCommande) — une fois Livrée, l'heure réellement atteinte
    // (§ demande).
    final livreurAt = order.statutCourant == OrderStatus.livre
        ? _historyAt(order, OrderStatus.livre)
        : order.dateCommande;
    // Une commande assignée à un préparateur dès sa création part
    // directement en "En préparation" — restreindre la modification à
    // "Nouvelle" ne laissait presque aucune fenêtre pour la corriger
    // (§ demande). La suppression, elle, reste réservée à "Nouvelle".
    final canEdit = [OrderStatus.nouvelle, OrderStatus.enPreparation].contains(order.statutCourant);
    final canDelete = order.statutCourant == OrderStatus.nouvelle;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            onTap: () => context.push('/orders/${order.id}'),
            title: Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${order.clientNom} · ${DeliveryZoneCatalog.shortLabelFor(order.livraisonZone)}'),
                if (order.preparateurName != null)
                  Text(
                    'Préparateur : ${order.preparateurName}${preparedAt != null ? ' · ${_shortDateFmt.format(preparedAt.toLocal())}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (order.livreurName != null)
                  Text(
                    'Livreur : ${order.livreurName}'
                    '${livreurAt != null ? ' · ${order.statutCourant == OrderStatus.livre ? 'Livré le ' : 'Prévu le '}${_shortDateFmt.format(livreurAt.toLocal())}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                OrderStatusBadge(status: order.statutCourant),
                if (order.totalAPayer != null) ...[
                  const SizedBox(height: 4),
                  Text(_ar(order.totalAPayer!), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          if (canEdit || canDelete)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canEdit)
                    IconButton(
                      tooltip: 'Modifier',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _edit(context, ref),
                    ),
                  if (canDelete)
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.red,
                      onPressed: () => _delete(context, ref),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Modification d'une commande "Nouvelle" (client, téléphone, date, zone,
/// adresse, paiement, note, articles) — réservée au gérant (cet écran n'est
/// accessible qu'à lui, voir nav_items.dart) : rien n'est encore
/// préparé/déduit du stock à ce stade, donc les articles restent librement
/// modifiables (voir orders/views.py::partial_update).
class EditOrderDialog extends ConsumerStatefulWidget {
  const EditOrderDialog({required this.order});
  final Order order;

  @override
  ConsumerState<EditOrderDialog> createState() => _EditOrderDialogState();
}

class _EditOrderDialogState extends ConsumerState<EditOrderDialog> {
  late final _clientController = TextEditingController(text: widget.order.clientNom);
  late final _phoneController = TextEditingController(text: widget.order.telephone ?? '+261');
  late final _adresseController = TextEditingController(text: widget.order.adresseLivraison ?? '');
  late final _notePreparateurController = TextEditingController(text: widget.order.notePreparateur ?? '');
  late final _noteLivreurController = TextEditingController(text: widget.order.noteLivreur ?? '');
  late String _zone = widget.order.livraisonZone;
  late PaymentMode _modePaiement = widget.order.modePaiement;
  late DateTime _dateCommande = widget.order.dateCommande?.toLocal() ?? DateTime.now();
  late int? _preparateurId = widget.order.preparateurId;
  List<StaffOption> _preparateurs = [];
  late int? _livreurId = widget.order.livreurId;
  List<StaffOption> _livreurs = [];
  late final List<CartLine> _lines = [
    for (final it in widget.order.items)
      if (it.productVariantId != null)
        CartLine(
          reference: ReferenceOption(
            id: 0,
            typeId: 0,
            typeName: '',
            brandId: 0,
            brandName: '',
            referenceName: it.referenceName,
            prixVente: it.prixUnitaire ?? 0,
            couleurs: [
              ColorOption(variantId: it.productVariantId!, couleur: it.couleur, stockActuel: 1 << 30),
            ],
          ),
          couleur: it.couleur,
          variantId: it.productVariantId!,
          quantite: it.quantite,
        ),
  ];
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(ordersProvider.notifier)
        .availableStaff('PREPARATEUR')
        .then((staff) {
          if (mounted) setState(() => _preparateurs = staff);
        })
        .catchError((_) {});
    ref
        .read(ordersProvider.notifier)
        .availableStaff('LIVREUR')
        .then((staff) {
          if (mounted) setState(() => _livreurs = staff);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _clientController.dispose();
    _phoneController.dispose();
    _adresseController.dispose();
    _notePreparateurController.dispose();
    _noteLivreurController.dispose();
    super.dispose();
  }

  Future<void> _pickDateCommande() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateCommande,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dateCommande));
    if (time == null) return;
    setState(() => _dateCommande = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _addLine() async {
    final result = await showDialog<CartLine>(context: context, builder: (_) => const AddOrderLineDialog());
    if (result != null) setState(() => _lines.add(result));
  }

  Future<void> _submit() async {
    if (_clientController.text.trim().isEmpty) {
      setState(() => _error = 'Nom du client requis');
      return;
    }
    if (!RegExp(r'^\+261\d{9}$').hasMatch(_phoneController.text.trim())) {
      setState(() => _error = 'Téléphone au format +261XXXXXXXXX');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Ajoutez au moins un article');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(ordersProvider.notifier)
          .updateOrder(
            widget.order.id,
            clientNom: _clientController.text.trim(),
            telephone: _phoneController.text.trim(),
            livraisonZone: _zone,
            adresseLivraison: _zone == kRecuperationCode ? '' : _adresseController.text.trim(),
            modePaiement: _modePaiement.apiValue,
            dateCommande: _dateCommande,
            notePreparateur: _notePreparateurController.text.trim(),
            noteLivreur: _zone == kRecuperationCode ? '' : _noteLivreurController.text.trim(),
            items: [
              for (final l in _lines) OrderItemDraft(productVariant: l.variantId, quantite: l.quantite),
            ],
          );
      // Pré-assignation du préparateur/livreur — endpoints indépendants du
      // statut, comme à la création (voir orders/services.py::
      // assign_preparateur_early/assign_livreur_early).
      if (_preparateurId != null && _preparateurId != widget.order.preparateurId) {
        try {
          await ref.read(ordersProvider.notifier).assignPreparateur(widget.order.id, _preparateurId!);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Commande mise à jour, mais l'assignation du préparateur a échoué : ${ApiClient.messageFromError(e)}",
                ),
              ),
            );
          }
        }
      }
      if (_zone != kRecuperationCode && _livreurId != null && _livreurId != widget.order.livreurId) {
        try {
          await ref.read(ordersProvider.notifier).assignLivreur(widget.order.id, _livreurId!);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Commande mise à jour, mais l'assignation du livreur a échoué : ${ApiClient.messageFromError(e)}",
                ),
              ),
            );
          }
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Modifier la commande ${widget.order.numero}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 10),
              ],
              Text(
                'Articles',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (_lines.isNotEmpty)
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final l in _lines)
                        ListTile(
                          dense: true,
                          title: Text('${l.reference.referenceName} — ${l.couleur}'),
                          subtitle: Text('${l.quantite} × ${_ar(l.reference.prixVente)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => setState(() => _lines.remove(l)),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addLine,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un article'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientController,
                decoration: const InputDecoration(labelText: 'Nom client'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+261XXXXXXXXX'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDateCommande,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date et heure de livraison'),
                  child: Text(DateFormat('dd/MM/yyyy HH:mm').format(_dateCommande)),
                ),
              ),
              const SizedBox(height: 12),
              // Zones configurables (CRUD Paramètres, § demande) + le retrait
              // sur place, toujours proposé (structurellement à part).
              DropdownButtonFormField<String>(
                initialValue: _zone,
                decoration: const InputDecoration(labelText: 'Livraison'),
                items: [
                  for (final z
                      in ref.watch(deliveryZonesProvider).asData?.value ?? const <DeliveryZoneOption>[])
                    if (z.actif || z.code == _zone) DropdownMenuItem(value: z.code, child: Text(z.label)),
                  const DropdownMenuItem(value: kRecuperationCode, child: Text('Récupération (0 Ar)')),
                ],
                onChanged: (v) => setState(() => _zone = v ?? _zone),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _preparateurId,
                decoration: const InputDecoration(labelText: 'Préparateur', hintText: 'Non assigné'),
                items: [
                  for (final p in _preparateurs) DropdownMenuItem(value: p.id, child: Text(p.fullName)),
                ],
                onChanged: (v) => setState(() => _preparateurId = v),
              ),
              if (_zone != kRecuperationCode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _adresseController,
                  decoration: const InputDecoration(labelText: 'Adresse de livraison'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PaymentMode>(
                  initialValue: _modePaiement,
                  decoration: const InputDecoration(labelText: 'Paiement'),
                  items: [
                    for (final m in PaymentMode.values) DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (v) => setState(() => _modePaiement = v ?? _modePaiement),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _livreurId,
                  decoration: const InputDecoration(labelText: 'Livreur', hintText: 'Non assigné'),
                  items: [for (final l in _livreurs) DropdownMenuItem(value: l.id, child: Text(l.fullName))],
                  onChanged: (v) => setState(() => _livreurId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notePreparateurController,
                decoration: const InputDecoration(labelText: 'Note pour le préparateur'),
                maxLines: 2,
              ),
              if (_zone != kRecuperationCode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _noteLivreurController,
                  decoration: const InputDecoration(labelText: 'Note pour le livreur'),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
