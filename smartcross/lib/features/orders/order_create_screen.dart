import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../data/repositories/orders_repository.dart' show StaffOption;
import '../../models/catalog.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart';
import '../../state/orders_provider.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

class _CartLine {
  _CartLine({required this.reference, required this.couleur, required this.variantId, required this.quantite});
  final ReferenceOption reference;
  final String couleur;
  final int variantId;
  int quantite;

  double get sousTotal => reference.prixVente * quantite;
}

/// Formulaire "Nouvelle commande" (§6 README) — le gérant saisit la
/// commande, prix/frais/total réels sont calculés côté serveur ; le total
/// affiché ici n'est qu'une estimation client.
class OrderCreateScreen extends ConsumerStatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientController = TextEditingController();
  final _phoneController = TextEditingController(text: '+261');
  final _adresseController = TextEditingController();
  final _noteController = TextEditingController();
  DeliveryZone _zone = DeliveryZone.zone1;
  DateTime _dateCommande = DateTime.now();
  final List<_CartLine> _lines = [];
  bool _submitting = false;
  String? _error;
  bool _isPreparateur = false;

  // Assignation à la création (gérant uniquement, miroir web : CreateOrderDialog
  // affiche Préparateur + Livreur côte à côte — voir page.tsx). Le
  // préparateur est assigné juste après la création (transition NOUVELLE ->
  // EN_PREPARATION). Le livreur, lui, ne peut pas déclencher EN_LIVRAISON
  // depuis NOUVELLE (orders/services.py n'autorise cette transition que
  // depuis PRETE) — mais il peut être PRÉ-assigné dès maintenant (endpoint
  // dédié assign-livreur, indépendant du statut) : orders/services.py::
  // _resolve_assignee réutilise alors ce livreur sans le redemander une fois
  // la commande Prête et passée manuellement à "En livraison".
  List<StaffOption> _preparateurs = [];
  List<StaffOption> _livreurs = [];
  int? _preparateurId;
  int? _livreurId;

  @override
  void initState() {
    super.initState();
    // Le préparateur ne peut créer que des commandes "Récupération sur
    // place" (§ demande), sans donnée financière (miroir web : isPreparateur
    // -> zone forcée + showPrices = false, voir page.tsx).
    _isPreparateur = ref.read(authProvider).user?.role == UserRole.preparateur;
    if (_isPreparateur) _zone = DeliveryZone.recuperation;
    if (!_isPreparateur) _loadStaff();
  }

  Future<void> _loadStaff() async {
    final notifier = ref.read(ordersProvider.notifier);
    try {
      final results = await Future.wait([
        notifier.availableStaff('PREPARATEUR'),
        notifier.availableStaff('LIVREUR', dateCommande: _dateCommande),
      ]);
      if (!mounted) return;
      setState(() {
        _preparateurs = results[0];
        _livreurs = results[1];
      });
    } catch (_) {
      // Non bloquant — l'assignation reste possible plus tard depuis le détail.
    }
  }

  @override
  void dispose() {
    _clientController.dispose();
    _phoneController.dispose();
    _adresseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get _frais {
    switch (_zone) {
      case DeliveryZone.zone1:
        return 3000;
      case DeliveryZone.zone2:
        return 4000;
      case DeliveryZone.zone3:
        return 5000;
      case DeliveryZone.recuperation:
        return 0;
    }
  }

  double get _totalEstime => _lines.fold<double>(0, (sum, l) => sum + l.sousTotal) + _frais;

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
    // Rafraîchit la disponibilité livreur pour ce nouveau créneau (voir
    // orders/views.py::available_staff — conflit d'horaire indicatif).
    if (!_isPreparateur) _loadStaff();
  }

  Future<void> _addLine() async {
    final result = await showDialog<_CartLine>(context: context, builder: (_) => _AddLineDialog(hidePrices: _isPreparateur));
    if (result != null) setState(() => _lines.add(result));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      setState(() => _error = 'Ajoutez au moins un article.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final order = await ref.read(ordersProvider.notifier).create(
            clientNom: _clientController.text.trim(),
            telephone: _phoneController.text.trim(),
            livraisonZone: _zone.apiValue,
            items: [for (final l in _lines) OrderItemDraft(productVariant: l.variantId, quantite: l.quantite)],
            note: _noteController.text.trim(),
            adresseLivraison: _adresseController.text.trim(),
            dateCommande: _dateCommande,
          );
      if (_preparateurId != null) {
        try {
          await ref.read(ordersProvider.notifier).changeStatus(
                order.id,
                'EN_PREPARATION',
                preparateurId: _preparateurId,
                assignedAt: DateTime.now(),
              );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Commande créée, mais l'assignation du préparateur a échoué : ${ApiClient.messageFromError(e)}"),
            ));
          }
        }
      }
      // Pré-assignation du livreur — indépendante du statut, réutilisée
      // automatiquement au passage "En livraison" une fois la commande prête
      // (voir orders/services.py::assign_livreur_early).
      if (_livreurId != null) {
        try {
          await ref.read(ordersProvider.notifier).assignLivreur(order.id, _livreurId!);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Commande créée, mais l'assignation du livreur a échoué : ${ApiClient.messageFromError(e)}"),
            ));
          }
        }
      }
      if (mounted) context.go('/orders/${order.id}');
    } catch (e) {
      setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isPreparateur ? 'Nouvelle récupération' : 'Nouvelle commande')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _clientController,
              decoration: const InputDecoration(labelText: 'Nom client', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+261XXXXXXXXX', prefixIcon: Icon(Icons.phone_outlined)),
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || !RegExp(r'^\+261\d{9}$').hasMatch(v.trim())) ? 'Format : +261XXXXXXXXX' : null,
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDateCommande,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date et heure de la commande', prefixIcon: Icon(Icons.event_outlined)),
                child: Text(DateFormat('dd/MM/yyyy HH:mm').format(_dateCommande)),
              ),
            ),
            if (!_isPreparateur) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<DeliveryZone>(
                initialValue: _zone,
                decoration: const InputDecoration(labelText: 'Livraison', prefixIcon: Icon(Icons.local_shipping_outlined)),
                items: [for (final z in DeliveryZone.values) DropdownMenuItem(value: z, child: Text(z.label))],
                onChanged: (v) => setState(() => _zone = v ?? _zone),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _preparateurId,
                decoration: const InputDecoration(labelText: 'Préparateur (optionnel)', prefixIcon: Icon(Icons.inventory_2_outlined)),
                hint: const Text('Assigner plus tard'),
                items: [for (final p in _preparateurs) DropdownMenuItem(value: p.id, child: Text(p.fullName))],
                onChanged: (v) => setState(() => _preparateurId = v),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _livreurId,
                decoration: const InputDecoration(labelText: 'Livreur (optionnel)', prefixIcon: Icon(Icons.moped_outlined)),
                hint: const Text('Assigner plus tard'),
                items: [for (final l in _livreurs) DropdownMenuItem(value: l.id, child: Text(l.fullName))],
                onChanged: (v) => setState(() => _livreurId = v),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Pré-assigné dès maintenant, sans attendre que la commande soit prête. Le passage "En livraison" reste une action manuelle, mais n\'aura pas besoin de choisir à nouveau le livreur.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ],
            if (_zone != DeliveryZone.recuperation) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _adresseController,
                decoration: const InputDecoration(labelText: 'Adresse de livraison (optionnel)', prefixIcon: Icon(Icons.place_outlined)),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optionnel)', prefixIcon: Icon(Icons.notes_outlined)),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Articles', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Ajouter')),
              ],
            ),
            if (_lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Aucun article — utilisez "Ajouter".', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final l in _lines)
                      ListTile(
                        title: Text('${l.reference.brandName} ${l.reference.referenceName} — ${l.couleur}'),
                        subtitle: Text(
                          _isPreparateur ? 'Quantité : ${l.quantite}' : '${l.quantite} × ${_ar(l.reference.prixVente)} = ${_ar(l.sousTotal)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _lines.remove(l)),
                        ),
                      ),
                  ],
                ),
              ),
            if (!_isPreparateur) ...[
              const SizedBox(height: 20),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Frais de livraison'), Text(_ar(_frais))]),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total estimé', style: Theme.of(context).textTheme.titleMedium),
                          Text(_ar(_totalEstime), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Créer la commande'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddLineDialog extends ConsumerStatefulWidget {
  const _AddLineDialog({this.hidePrices = false});
  final bool hidePrices;

  @override
  ConsumerState<_AddLineDialog> createState() => _AddLineDialogState();
}

class _AddLineDialogState extends ConsumerState<_AddLineDialog> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<ReferenceOption> _results = [];
  bool _loading = false;
  ReferenceOption? _selectedReference;
  ColorOption? _selectedColor;
  int _quantite = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final repo = ref.read(catalogRepositoryProvider);
        final results = await repo.autocomplete(query);
        if (mounted) setState(() => _results = results);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un article'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher une référence',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) : null,
              ),
              onChanged: _onQueryChanged,
            ),
            const SizedBox(height: 8),
            if (_selectedReference == null)
              SizedBox(
                height: 240,
                child: _results.isEmpty
                    ? const Center(child: Text('Aucun résultat'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          return ListTile(
                            title: Text('${r.brandName} ${r.referenceName}'),
                            subtitle: Text(widget.hidePrices ? r.typeName : '${r.typeName} — ${_ar(r.prixVente)}'),
                            onTap: () => setState(() => _selectedReference = r),
                          );
                        },
                      ),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${_selectedReference!.brandName} ${_selectedReference!.referenceName}'),
                subtitle: widget.hidePrices ? null : Text(_ar(_selectedReference!.prixVente)),
                trailing: TextButton(onPressed: () => setState(() => _selectedReference = null), child: const Text('Changer')),
              ),
              const SizedBox(height: 8),
              Text('Couleur', style: Theme.of(context).textTheme.labelLarge),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _selectedReference!.couleurs)
                    ChoiceChip(
                      label: Text('${c.couleur} (${c.stockActuel})'),
                      selected: _selectedColor?.variantId == c.variantId,
                      onSelected: c.stockActuel > 0 ? (_) => setState(() => _selectedColor = c) : null,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Quantité'),
                  Row(
                    children: [
                      IconButton(onPressed: _quantite > 1 ? () => setState(() => _quantite--) : null, icon: const Icon(Icons.remove_circle_outline)),
                      Text('$_quantite', style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(onPressed: () => setState(() => _quantite++), icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _selectedReference != null && _selectedColor != null
              ? () => Navigator.of(context).pop(_CartLine(
                    reference: _selectedReference!,
                    couleur: _selectedColor!.couleur,
                    variantId: _selectedColor!.variantId,
                    quantite: _quantite,
                  ))
              : null,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}
