import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../data/repositories/orders_repository.dart' show StaffOption;
import '../../models/catalog.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart';
import '../../state/orders_provider.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

class CartLine {
  CartLine({required this.reference, required this.couleur, required this.variantId, required this.quantite});
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
  // Deux notes distinctes, chacune destinée à un seul rôle (§ demande).
  final _notePreparateurController = TextEditingController();
  final _noteLivreurController = TextEditingController();
  // Code de zone (voir models/delivery_zone.dart) — vide tant que les zones
  // configurables ne sont pas chargées, puis la première zone active.
  String _zone = '';
  PaymentMode _modePaiement = PaymentMode.livraison;
  // Heure « au mur » d'Antananarivo (fuseau du magasin) — convertie en
  // instant absolu à l'envoi via appWallClockToUtc (core/app_time.dart).
  DateTime _dateCommande = appNow();
  final List<CartLine> _lines = [];
  bool _submitting = false;
  String? _error;
  bool _isPreparateur = false;

  // Assignation à la création (gérant uniquement, miroir web : CreateOrderDialog
  // affiche Préparateur + Livreur côte à côte — voir page.tsx). Les deux sont
  // de simples PRÉ-assignations, indépendantes du statut (endpoints dédiés
  // assign-preparateur/assign-livreur) : la commande reste "Nouvelle" (en
  // attente) jusqu'à ce que le préparateur clique lui-même "Commencer la
  // préparation" (§ demande) — orders/services.py::_resolve_assignee
  // réutilise alors ces personnes sans les redemander.
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
    if (_isPreparateur) _zone = kRecuperationCode;
    if (!_isPreparateur) _loadStaff();
  }

  Future<void> _loadStaff() async {
    final notifier = ref.read(ordersProvider.notifier);
    try {
      final results = await Future.wait([
        notifier.availableStaff('PREPARATEUR'),
        notifier.availableStaff('LIVREUR', dateCommande: appWallClockToUtc(_dateCommande)),
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
    _notePreparateurController.dispose();
    _noteLivreurController.dispose();
    super.dispose();
  }

  /// Zones payantes actives (CRUD Paramètres, § demande) — le retrait sur
  /// place reste à part (kRecuperationCode, jamais dans cette liste).
  /// `ref.read` et non `watch` : ce getter est aussi appelé depuis des
  /// callbacks (hors build), le rafraîchissement passe par le `watch` fait
  /// dans build().
  List<DeliveryZoneOption> get _zonesPayantes =>
      (ref.read(deliveryZonesProvider).asData?.value ?? const <DeliveryZoneOption>[])
          .where((z) => z.actif)
          .toList();

  // Estimation seulement — les frais réels sont recalculés côté serveur à
  // partir du code de zone (voir orders/models.py::Order.save).
  double get _frais => _zone == kRecuperationCode ? 0 : DeliveryZoneCatalog.fraisFor(_zone);

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
    final result = await showDialog<CartLine>(
      context: context,
      builder: (_) => AddOrderLineDialog(hidePrices: _isPreparateur),
    );
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
      final order = await ref
          .read(ordersProvider.notifier)
          .create(
            clientNom: _clientController.text.trim(),
            telephone: _phoneController.text.trim(),
            livraisonZone: _zone,
            items: [
              for (final l in _lines) OrderItemDraft(productVariant: l.variantId, quantite: l.quantite),
            ],
            notePreparateur: _notePreparateurController.text.trim(),
            noteLivreur: _zone == kRecuperationCode ? '' : _noteLivreurController.text.trim(),
            adresseLivraison: _adresseController.text.trim(),
            modePaiement: _modePaiement.apiValue,
            dateCommande: appWallClockToUtc(_dateCommande),
          );
      if (_preparateurId != null) {
        try {
          await ref.read(ordersProvider.notifier).assignPreparateur(order.id, _preparateurId!);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Commande créée, mais l'assignation du préparateur a échoué : ${ApiClient.messageFromError(e)}",
                ),
              ),
            );
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Commande créée, mais l'assignation du livreur a échoué : ${ApiClient.messageFromError(e)}",
                ),
              ),
            );
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
    // Les zones arrivent de façon asynchrone : dès qu'elles sont là, on
    // sélectionne la première zone payante (sauf préparateur, toujours en
    // retrait sur place). Le `watch` ici est ce qui reconstruit l'écran au
    // chargement des zones (les autres accès passent par `_zonesPayantes`).
    final zonesDisponibles = (ref.watch(deliveryZonesProvider).asData?.value ?? const <DeliveryZoneOption>[])
        .where((z) => z.actif)
        .toList();
    if (!_isPreparateur && _zone.isEmpty && zonesDisponibles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _zone.isEmpty) {
          setState(() => _zone = zonesDisponibles.first.code);
        }
      });
    }

    final isPickup = _zone == kRecuperationCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isPreparateur ? 'Nouvelle récupération' : 'Nouvelle commande'),
        actions: [
          IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close)),
        ],
      ),
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
            Text(
              'Ajouter un article',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _addLine,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un article'),
              ),
            ),
            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final l in _lines)
                      ListTile(
                        title: Text('${l.reference.brandName} ${l.reference.referenceName} — ${l.couleur}'),
                        subtitle: Text(
                          _isPreparateur
                              ? 'Quantité : ${l.quantite}'
                              : '${l.quantite} × ${_ar(l.reference.prixVente)} = ${_ar(l.sousTotal)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _lines.remove(l)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Type de commande',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            // Livraison ou retrait sur place — le retrait est un cas à part
            // (pas de livreur, pas de frais), les zones payantes viennent du
            // CRUD Paramètres (§ demande).
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.local_shipping_outlined, size: 18),
                  label: Text('À livrer'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.storefront_outlined, size: 18),
                  label: Text('Récupération sur place'),
                ),
              ],
              selected: {_zone == kRecuperationCode},
              onSelectionChanged: _isPreparateur
                  ? null
                  : (values) => setState(() {
                      final zones = _zonesPayantes;
                      _zone = values.first ? kRecuperationCode : (zones.isNotEmpty ? zones.first.code : '');
                    }),
              multiSelectionEnabled: false,
            ),
            const SizedBox(height: 18),
            Text(
              'Date et heure de livraison',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDateCommande,
              child: InputDecorator(
                decoration: InputDecoration(
                  hintText: 'Choisir la date',
                  prefixIcon: const Icon(Icons.event_outlined),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(DateFormat('dd/MM/yyyy HH:mm').format(_dateCommande)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vide = maintenant.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            if (!_isPreparateur) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Préparateur',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Livreur',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _preparateurId,
                      decoration: const InputDecoration(
                        hintText: 'Assigner plus tard',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      items: [
                        for (final p in _preparateurs) DropdownMenuItem(value: p.id, child: Text(p.fullName)),
                      ],
                      onChanged: (v) => setState(() => _preparateurId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _livreurId,
                      decoration: const InputDecoration(
                        hintText: 'Assigner plus tard',
                        prefixIcon: Icon(Icons.moped_outlined),
                      ),
                      items: [
                        for (final l in _livreurs) DropdownMenuItem(value: l.id, child: Text(l.fullName)),
                      ],
                      onChanged: (v) => setState(() => _livreurId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            if (!isPickup) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Zone de livraison',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Adresse de livraison',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _zonesPayantes.any((z) => z.code == _zone) ? _zone : null,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                        hintText: 'Zone de livraison',
                      ),
                      items: [
                        for (final z in _zonesPayantes) DropdownMenuItem(value: z.code, child: Text(z.label)),
                      ],
                      onChanged: (v) => setState(() => _zone = v ?? _zone),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _adresseController,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.place_outlined)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Paiement',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PaymentMode>(
                value: _modePaiement,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.payments_outlined)),
                items: [for (final m in PaymentMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                onChanged: (v) => setState(() => _modePaiement = v ?? _modePaiement),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nom client',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Téléphone',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _clientController,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined)),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || !RegExp(r'^\+261\d{9}$').hasMatch(v.trim()))
                        ? 'Format : +261XXXXXXXXX'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _isPreparateur ? 'Note (optionnel)' : 'Note pour le préparateur (optionnel)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notePreparateurController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.notes_outlined)),
              maxLines: 3,
            ),
            if (!_isPreparateur && !isPickup) ...[
              const SizedBox(height: 20),
              Text(
                'Note pour le livreur (optionnel)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _noteLivreurController,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.moped_outlined)),
                maxLines: 3,
              ),
            ],
            if (!_isPreparateur) ...[
              const SizedBox(height: 20),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [const Text('Frais de livraison'), Text(_ar(_frais))],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total estimé', style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            _ar(_totalEstime),
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
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

class AddOrderLineDialog extends ConsumerStatefulWidget {
  const AddOrderLineDialog({super.key, this.hidePrices = false});
  final bool hidePrices;

  @override
  ConsumerState<AddOrderLineDialog> createState() => _AddLineDialogState();
}

class _AddLineDialogState extends ConsumerState<AddOrderLineDialog> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<ReferenceOption> _results = [];
  List<ProductCategory> _categories = [];
  List<ProductType> _types = [];
  List<Brand> _brands = [];
  bool _loading = false;
  int? _categoryId;
  int? _typeId;
  int? _brandId;
  ReferenceOption? _selectedReference;
  ColorOption? _selectedColor;
  int _quantite = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final results = await Future.wait([repo.categories(), repo.types(), repo.brands()]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<ProductCategory>;
        _types = results[1] as List<ProductType>;
        _brands = results[2] as List<Brand>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categories = [];
        _types = [];
        _brands = [];
      });
    }
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final repo = ref.read(catalogRepositoryProvider);
        final results = await repo.autocomplete(
          query,
          categoryId: _categoryId,
          typeId: _typeId,
          brandId: _brandId,
        );
        if (mounted) setState(() => _results = results);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFilterOptions();
    _onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 420;
    final filterFields = [
      DropdownButtonFormField<int>(
        value: _categoryId,
        decoration: const InputDecoration(hintText: 'Catégorie'),
        items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.nom))],
        onChanged: (value) {
          setState(() {
            _categoryId = value;
            if (value == null) _typeId = null;
          });
          _onQueryChanged(_searchController.text);
        },
      ),
      DropdownButtonFormField<int>(
        value: _typeId,
        decoration: const InputDecoration(hintText: 'Sous-type'),
        items: [
          for (final t
              in _categoryId == null ? _types : _types.where((item) => item.categoryId == _categoryId))
            DropdownMenuItem(value: t.id, child: Text(t.nom)),
        ],
        onChanged: (value) {
          setState(() => _typeId = value);
          _onQueryChanged(_searchController.text);
        },
      ),
      DropdownButtonFormField<int>(
        value: _brandId,
        decoration: const InputDecoration(hintText: 'Marque'),
        items: [for (final b in _brands) DropdownMenuItem(value: b.id, child: Text(b.nom))],
        onChanged: (value) {
          setState(() => _brandId = value);
          _onQueryChanged(_searchController.text);
        },
      ),
    ];

    return AlertDialog(
      title: const Text('Ajouter un article'),
      content: SizedBox(
        width: isCompact ? screenWidth - 32 : 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ajouter un article',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (isCompact) ...[
                for (final field in filterFields) ...[field, const SizedBox(height: 8)],
              ] else
                Row(
                  children: [
                    for (int i = 0; i < filterFields.length; i++) ...[
                      Expanded(child: filterFields[i]),
                      if (i < filterFields.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher une référence (ex: A15)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
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
                            final colors = r.couleurs.map((c) => c.couleur).take(4).join(', ');
                            final more = r.couleurs.length > 4 ? '…' : '';
                            return ListTile(
                              title: Text('${r.brandName} ${r.referenceName}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.hidePrices ? r.typeName : '${r.typeName} — ${_ar(r.prixVente)}',
                                  ),
                                  if (colors.isNotEmpty)
                                    Text(
                                      'Couleurs: $colors$more',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
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
                  trailing: TextButton(
                    onPressed: () => setState(() => _selectedReference = null),
                    child: const Text('Changer'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Couleur', style: Theme.of(context).textTheme.labelLarge),
                for (final c in _selectedReference!.couleurs)
                  RadioListTile<int>(
                    value: c.variantId,
                    groupValue: _selectedColor?.variantId ?? -1,
                    onChanged: c.stockActuel > 0 ? (value) => setState(() => _selectedColor = c) : null,
                    title: Text('${c.couleur} (${c.stockActuel})'),
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Quantité'),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _quantite > 1 ? () => setState(() => _quantite--) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$_quantite', style: const TextStyle(fontWeight: FontWeight.w600)),
                        IconButton(
                          onPressed: () => setState(() => _quantite++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _selectedReference != null && _selectedColor != null
              ? () => Navigator.of(context).pop(
                  CartLine(
                    reference: _selectedReference!,
                    couleur: _selectedColor!.couleur,
                    variantId: _selectedColor!.variantId,
                    quantite: _quantite,
                  ),
                )
              : null,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}
