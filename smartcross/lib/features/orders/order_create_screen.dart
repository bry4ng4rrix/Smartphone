import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../data/repositories/orders_repository.dart' show StaffOption;
import '../../models/catalog.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart';
import '../../state/orders_provider.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;

// ---------------------------------------------------------------------------
// Helpers partagés par la création (ici) et la modification
// (orders_list_screen.dart::EditOrderDialog) — miroir de
// frontend/components/orders/create-order-dialog.tsx (`fmt`, `MODE_PAIEMENT`,
// `buildZoneOptions`, `OrderItemsEditor`, `CartItem`).
// ---------------------------------------------------------------------------

/// Format du téléphone accepté par le serveur (`+261XXXXXXXXX`).
final RegExp kTelephoneRegExp = RegExp(r'^\+261\d{9}$');

/// Libellés du mode de paiement — `MODE_PAIEMENT` du web (« Payé » /
/// « Paiement à la livraison »).
String modePaiementLabel(PaymentMode mode) => mode == PaymentMode.avant ? 'Payé' : 'Paiement à la livraison';

/// Toast de l'application (`toast.success` / `toast.error` de sonner).
void orderToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Une ligne du panier (`CartItem` du web) : référence + couleur choisie +
/// quantité. [stockActuel] sert au contrôle de stock à l'ajout ; pour un
/// article déjà présent sur une commande modifiée il vaut « infini »
/// (`stock_actuel: Infinity` côté web — plus de contrôle sur l'existant).
class CartLine {
  CartLine({
    required this.key,
    required this.reference,
    required this.couleur,
    required this.variantId,
    required this.quantite,
    required this.stockActuel,
  });

  final String key;
  final ReferenceOption reference;
  final String couleur;
  final int variantId;
  final int quantite;
  final int stockActuel;

  /// « Samsung A15 » — `reference_label` du web.
  String get label => [reference.brandName, reference.referenceName].where((s) => s.isNotEmpty).join(' ');

  double get sousTotal => reference.prixVente * quantite;
}

/// Sélecteur contrôlé (la valeur affichée suit toujours [value], même quand
/// elle est modifiée par programme — ex. retrait d'un filtre par sa pastille),
/// habillé comme un champ de formulaire.
class OrderFormDropdown<T> extends StatelessWidget {
  const OrderFormDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.enabled = true,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final present = value != null && items.any((i) => i.value == value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: labelText,
        // Libellé toujours flottant quand un texte d'attente est aussi
        // affiché, pour que les deux ne se superposent pas.
        floatingLabelBehavior: labelText != null && hintText != null ? FloatingLabelBehavior.always : null,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        enabled: enabled,
      ),
      isEmpty: !present,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: present ? value : null,
          isExpanded: true,
          isDense: true,
          hint: hintText == null ? null : Text(hintText!, overflow: TextOverflow.ellipsis),
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

/// Sélecteur d'articles — recherche catalogue (Catégorie → Sous-type,
/// Marque, texte) + panier — `OrderItemsEditor` du web, partagé entre la
/// création et la modification d'une commande. [showPrices] : le préparateur
/// ne voit aucune donnée financière (§4/§7.2 du cahier des charges).
class OrderItemsEditor extends ConsumerStatefulWidget {
  const OrderItemsEditor({super.key, required this.lines, required this.onChanged, required this.showPrices});

  final List<CartLine> lines;
  final ValueChanged<List<CartLine>> onChanged;
  final bool showPrices;

  @override
  ConsumerState<OrderItemsEditor> createState() => _OrderItemsEditorState();
}

class _OrderItemsEditorState extends ConsumerState<OrderItemsEditor> {
  final _searchController = TextEditingController();
  final _quantiteController = TextEditingController();
  Timer? _debounce;
  int? _categoryId;
  int? _typeId;
  int? _brandId;
  String _query = '';
  List<ReferenceOption> _suggestions = const [];
  bool _searching = false;
  ReferenceOption? _selectedRef;
  int? _variantId;
  int _requestSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _quantiteController.dispose();
    super.dispose();
  }

  bool get _hasFilter => _categoryId != null || _typeId != null || _brandId != null;

  /// La recherche se déclenche dès qu'un filtre est choisi (même sans
  /// texte), pour afficher directement les éléments correspondant à la
  /// sélection — 250 ms de temporisation comme le web.
  void _scheduleSearch() {
    _debounce?.cancel();
    if (_query.isEmpty && !_hasFilter) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final seq = ++_requestSeq;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      List<ReferenceOption> results;
      try {
        results = await ref
            .read(catalogRepositoryProvider)
            .autocomplete(_query, categoryId: _categoryId, typeId: _typeId, brandId: _brandId);
      } catch (_) {
        results = const [];
      }
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    });
  }

  void _onQueryChanged(String text) {
    setState(() {
      _query = text;
      _selectedRef = null;
      _variantId = null;
    });
    _scheduleSearch();
  }

  void _selectReference(ReferenceOption r) {
    setState(() {
      _selectedRef = r;
      _variantId = null;
      _query = '';
      _suggestions = const [];
      _searchController.text = '${r.brandName} ${r.referenceName}'.trim();
    });
  }

  void _addItem() {
    final selected = _selectedRef;
    final variantId = _variantId;
    if (selected == null || variantId == null) {
      orderToast(context, 'Sélectionnez une référence et une couleur');
      return;
    }
    ColorOption? variant;
    for (final c in selected.couleurs) {
      if (c.variantId == variantId) variant = c;
    }
    if (variant == null) return;
    final qty = int.tryParse(_quantiteController.text.trim()) ?? 0;
    if (qty < 1) {
      orderToast(context, 'Quantité invalide');
      return;
    }
    if (qty > variant.stockActuel) {
      orderToast(context, 'Stock insuffisant (disponible: ${variant.stockActuel})');
      return;
    }
    widget.onChanged([
      ...widget.lines,
      CartLine(
        key: '$variantId-${DateTime.now().microsecondsSinceEpoch}',
        reference: selected,
        couleur: variant.couleur,
        variantId: variantId,
        quantite: qty,
        stockActuel: variant.stockActuel,
      ),
    ]);
    // Après ajout : la saisie est vidée, les filtres catégorie/sous-type/
    // marque sont conservés (comme le web).
    setState(() {
      _query = '';
      _searchController.clear();
      _suggestions = const [];
      _selectedRef = null;
      _variantId = null;
      _quantiteController.clear();
    });
  }

  void _removeAt(int index) {
    final next = [...widget.lines]..removeAt(index);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Les listes de filtres échouent en silence (liste vide), comme le web.
    final categories = ref.watch(categoriesProvider).asData?.value ?? const <ProductCategory>[];
    final types = ref.watch(typesProvider).asData?.value ?? const <ProductType>[];
    final brands = ref.watch(brandsProvider).asData?.value ?? const <Brand>[];
    final typesForCategory = _categoryId == null ? types : types.where((t) => t.categoryId == _categoryId).toList();
    final compact = MediaQuery.sizeOf(context).width < 520;
    final selected = _selectedRef;
    final showSuggestions = selected == null && (_query.isNotEmpty || _hasFilter);

    String nomCategorie(int id) => categories.where((c) => c.id == id).map((c) => c.nom).firstOrNull ?? '$id';
    String nomType(int id) => types.where((t) => t.id == id).map((t) => t.nom).firstOrNull ?? '$id';
    String nomMarque(int id) => brands.where((b) => b.id == id).map((b) => b.nom).firstOrNull ?? '$id';

    final filterFields = <Widget>[
      OrderFormDropdown<int>(
        value: _categoryId,
        hintText: 'Catégorie',
        items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.nom))],
        onChanged: (v) {
          setState(() {
            _categoryId = v;
            _typeId = null;
          });
          _scheduleSearch();
        },
      ),
      OrderFormDropdown<int>(
        value: _typeId,
        hintText: 'Sous-type',
        items: [for (final t in typesForCategory) DropdownMenuItem(value: t.id, child: Text(t.nom))],
        onChanged: (v) {
          setState(() => _typeId = v);
          _scheduleSearch();
        },
      ),
      OrderFormDropdown<int>(
        value: _brandId,
        hintText: 'Marque',
        items: [for (final b in brands) DropdownMenuItem(value: b.id, child: Text(b.nom))],
        onChanged: (v) {
          setState(() => _brandId = v);
          _scheduleSearch();
        },
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ajouter un article', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (compact)
                for (final f in filterFields) ...[f, const SizedBox(height: 8)]
              else ...[
                Row(
                  children: [
                    for (int i = 0; i < filterFields.length; i++) ...[
                      Expanded(child: filterFields[i]),
                      if (i < filterFields.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_hasFilter) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Filtres :', style: theme.textTheme.bodySmall),
                    if (_categoryId != null)
                      InputChip(
                        label: Text(nomCategorie(_categoryId!)),
                        onDeleted: () {
                          setState(() {
                            _categoryId = null;
                            _typeId = null;
                          });
                          _scheduleSearch();
                        },
                      ),
                    if (_typeId != null)
                      InputChip(
                        label: Text(nomType(_typeId!)),
                        onDeleted: () {
                          setState(() => _typeId = null);
                          _scheduleSearch();
                        },
                      ),
                    if (_brandId != null)
                      InputChip(
                        label: Text(nomMarque(_brandId!)),
                        onDeleted: () {
                          setState(() => _brandId = null);
                          _scheduleSearch();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher une référence (ex: A15)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
                onChanged: _onQueryChanged,
              ),
              if (showSuggestions) ...[
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: _searching
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('Recherche…', style: TextStyle(color: scheme.onSurfaceVariant)),
                        )
                      : _suggestions.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Aucun résultat pour cette sélection.',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _suggestions.length,
                                itemBuilder: (context, i) {
                                  final s = _suggestions[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: '${s.brandName} ${s.referenceName} '.trimLeft()),
                                          TextSpan(
                                            text: '(${s.typeName})',
                                            style: TextStyle(color: scheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: widget.showPrices ? Text(arFmt(s.prixVente)) : null,
                                    onTap: () => _selectReference(s),
                                  );
                                },
                              ),
                            ),
                ),
              ],
              if (selected != null) ...[
                const SizedBox(height: 10),
                OrderFormDropdown<int>(
                  value: _variantId,
                  labelText: 'Couleur',
                  hintText: 'Couleur',
                  items: [
                    for (final c in selected.couleurs)
                      DropdownMenuItem(
                        value: c.variantId,
                        // Couleur épuisée : proposée mais non sélectionnable.
                        enabled: c.stockActuel > 0,
                        child: Text(
                          '${c.couleur} (stock: ${c.stockActuel})',
                          style: c.stockActuel > 0 ? null : TextStyle(color: scheme.outline),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _variantId = v),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _quantiteController,
                        decoration: const InputDecoration(labelText: 'Quantité', hintText: 'Ex: 1'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ),
                    if (widget.showPrices) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Prix (Ar)', enabled: false),
                          child: Text(arFmt(selected.prixVente)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter à la commande'),
                ),
              ],
            ],
          ),
        ),
        if (widget.lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (int i = 0; i < widget.lines.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('${widget.lines[i].label} (${widget.lines[i].couleur}) x${widget.lines[i].quantite}')),
                  if (widget.showPrices) ...[
                    const SizedBox(width: 8),
                    Text(arFmt(widget.lines[i].sousTotal)),
                  ],
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeAt(i),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// « Type de commande » : deux boutons « À livrer » / « Récupération sur
/// place » (le bouton actif est plein, l'autre en contour — comme le web).
/// Deux boutons extensibles plutôt qu'un `SegmentedButton`, dont les
/// libellés ne tiendraient pas sur un téléphone étroit.
class OrderTypeToggle extends StatelessWidget {
  const OrderTypeToggle({super.key, required this.pickup, required this.onChanged, this.enabled = true});

  /// Vrai = retrait sur place (`RECUPERATION`), faux = à livrer.
  final bool pickup;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget bouton({required bool value, required IconData icon, required String label}) {
      final selected = pickup == value;
      final onPressed = enabled ? () => onChanged(value) : null;
      final content = Text(label, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center);
      return Expanded(
        child: selected
            ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: content)
            : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: content),
      );
    }

    return Row(
      children: [
        bouton(value: false, icon: Icons.local_shipping_outlined, label: 'À livrer'),
        const SizedBox(width: 8),
        bouton(value: true, icon: Icons.inventory_2_outlined, label: 'Récupération sur place'),
      ],
    );
  }
}

/// Champ « date et heure » : sélecteur de date puis d'heure (l'équivalent
/// du `DateTimeInput` web). Les valeurs sont des heures « au mur »
/// d'Antananarivo (voir core/app_time.dart). [onClear] (facultatif) permet de
/// vider le champ (« Vide = maintenant. »).
class OrderDateTimeField extends StatelessWidget {
  const OrderDateTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelText,
    this.hintText,
    this.onClear,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? labelText;
  final String? hintText;
  final VoidCallback? onClear;

  static final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> _pick(BuildContext context) async {
    final now = appNow();
    final first = now.subtract(const Duration(days: 365));
    final last = now.add(const Duration(days: 365));
    var initial = value ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;
    onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: value != null && onClear != null
              ? IconButton(tooltip: 'Vider', icon: const Icon(Icons.close), onPressed: onClear)
              : const Icon(Icons.calendar_today_outlined),
        ),
        isEmpty: value == null,
        child: Text(
          value == null ? (hintText ?? '') : _fmt.format(value!),
          style: value == null ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
        ),
      ),
    );
  }
}

/// Formulaire « Nouvelle commande » (§6 README) — `CreateOrderDialog` du web,
/// source UNIQUE pour le gérant (livraison ou retrait) et le préparateur
/// (retrait sur place uniquement, sans donnée financière). Prix, frais et
/// total réels sont calculés côté serveur ; le total affiché ici n'est
/// qu'une estimation.
class OrderCreateScreen extends ConsumerStatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen> {
  final _clientController = TextEditingController();
  final _phoneController = TextEditingController(text: '+261');
  // Second numéro facultatif — le client donne souvent un numéro de secours,
  // ou celui de la personne qui réceptionne à sa place (§ demande).
  final _phone2Controller = TextEditingController();
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
  // `null` = champ vidé -> non envoyé -> le serveur prend « maintenant ».
  DateTime? _dateCommande = appNow();
  List<CartLine> _lines = const [];
  bool _submitting = false;
  String? _error;
  bool _isPreparateur = false;

  // Pré-assignation à la création (gérant uniquement) : deux endpoints
  // indépendants du statut (assign-preparateur / assign-livreur). La
  // commande reste « Nouvelle » jusqu'à ce que le préparateur clique
  // lui-même « Commencer la préparation » (§ demande).
  List<StaffOption> _preparateurs = const [];
  List<StaffOption> _livreurs = const [];
  int? _preparateurId;
  int? _livreurId;

  @override
  void initState() {
    super.initState();
    // Le préparateur ne crée que des retraits sur place (§ demande), sans
    // donnée financière (miroir web : isPreparateur -> zone forcée +
    // showPrices = false).
    final user = ref.read(authProvider).user;
    _isPreparateur = user != null && user.isPreparateur;
    if (_isPreparateur) _zone = kRecuperationCode;
    if (!_isPreparateur) {
      _loadPreparateurs();
      _loadLivreurs();
    }
  }

  Future<void> _loadPreparateurs() async {
    try {
      final staff = await ref.read(ordersProvider.notifier).availableStaff('PREPARATEUR');
      if (mounted) setState(() => _preparateurs = staff);
    } catch (_) {
      if (mounted) setState(() => _preparateurs = const []);
    }
  }

  /// Réinterrogé à chaque changement de date/heure : « disponible » reflète
  /// aussi un éventuel conflit d'horaire du livreur (indicatif seulement,
  /// voir orders/views.py::available_staff).
  Future<void> _loadLivreurs() async {
    try {
      final staff = await ref
          .read(ordersProvider.notifier)
          .availableStaff('LIVREUR', dateCommande: _dateCommande == null ? null : appWallClockToUtc(_dateCommande!));
      if (mounted) setState(() => _livreurs = staff);
    } catch (_) {
      if (mounted) setState(() => _livreurs = const []);
    }
  }

  @override
  void dispose() {
    _clientController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    _adresseController.dispose();
    _notePreparateurController.dispose();
    _noteLivreurController.dispose();
    super.dispose();
  }

  /// Zones payantes actives (CRUD Paramètres, § demande) — le retrait sur
  /// place reste à part (kRecuperationCode, jamais dans cette liste).
  List<DeliveryZoneOption> _zonesPayantes(List<DeliveryZoneOption> zones) => zones.where((z) => z.actif).toList();

  // Estimation seulement — les frais réels sont recalculés côté serveur à
  // partir du code de zone (voir orders/models.py::Order.save).
  double get _frais => _zone == kRecuperationCode ? 0 : DeliveryZoneCatalog.fraisFor(_zone);

  double get _total => _lines.fold<double>(0, (sum, l) => sum + l.sousTotal) + _frais;

  bool get _isPickup => _zone == kRecuperationCode;

  Future<void> _submit() async {
    final clientNom = _clientController.text.trim();
    final telephone = _phoneController.text.trim();
    final telephone2 = _phone2Controller.text.trim();
    if (clientNom.isEmpty) {
      _fail('Nom du client requis');
      return;
    }
    if (!kTelephoneRegExp.hasMatch(telephone)) {
      _fail('Téléphone au format +261XXXXXXXXX');
      return;
    }
    // Le second numéro est facultatif, mais s'il est saisi il doit être au
    // même format — sinon le serveur le refuserait après coup.
    if (telephone2.isNotEmpty && !kTelephoneRegExp.hasMatch(telephone2)) {
      _fail('Autre téléphone au format +261XXXXXXXXX');
      return;
    }
    if (_lines.isEmpty) {
      _fail('Ajoutez au moins un article');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final order = await ref
          .read(ordersProvider.notifier)
          .create(
            clientNom: clientNom,
            telephone: telephone,
            telephone2: telephone2,
            livraisonZone: _zone,
            items: [for (final l in _lines) OrderItemDraft(productVariant: l.variantId, quantite: l.quantite)],
            notePreparateur: _notePreparateurController.text.trim(),
            noteLivreur: _isPickup ? '' : _noteLivreurController.text.trim(),
            adresseLivraison: _adresseController.text.trim(),
            modePaiement: _modePaiement.apiValue,
            // Champ vidé -> pas envoyé -> le serveur prend « maintenant ».
            dateCommande: _dateCommande == null ? null : appWallClockToUtc(_dateCommande!),
          );
      var assignmentFailed = false;
      if (_preparateurId != null) {
        try {
          await ref.read(ordersProvider.notifier).assignPreparateur(order.id, _preparateurId!);
        } catch (e) {
          assignmentFailed = true;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                "Commande créée, mais l'assignation du préparateur a échoué : ${ApiClient.messageFromError(e)} "
                '(à assigner depuis le tableau).',
              ),
            ),
          );
        }
      }
      // Pré-assignation du livreur — réutilisée automatiquement au passage
      // « En livraison » une fois la commande prête.
      if (_livreurId != null) {
        try {
          await ref.read(ordersProvider.notifier).assignLivreur(order.id, _livreurId!);
        } catch (e) {
          assignmentFailed = true;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                "Commande créée, mais l'assignation du livreur a échoué : ${ApiClient.messageFromError(e)} "
                '(à assigner depuis le tableau).',
              ),
            ),
          );
        }
      }
      if (!assignmentFailed) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _preparateurId != null || _livreurId != null ? 'Commande créée et assignée' : 'Commande créée',
            ),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(order);
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _fail(String message) {
    setState(() => _error = message);
    orderToast(context, message);
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Les zones arrivent de façon asynchrone : dès qu'elles sont là, on
    // sélectionne la première zone payante (sauf préparateur, toujours en
    // retrait sur place).
    final zones = ref.watch(deliveryZonesProvider).asData?.value ?? const <DeliveryZoneOption>[];
    final zonesPayantes = _zonesPayantes(zones);
    if (!_isPreparateur && _zone.isEmpty && zonesPayantes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _zone.isEmpty) setState(() => _zone = zonesPayantes.first.code);
      });
    }
    final showPrices = !_isPreparateur;
    final wide = MediaQuery.sizeOf(context).width >= 600;

    Widget twoCols(Widget a, Widget b) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 12), b]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle commande'),
        actions: [
          IconButton(
            tooltip: 'Fermer',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Vente Facebook ou sur place — §6 du cahier des charges.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
            const SizedBox(height: 16),
          ],
          OrderItemsEditor(
            lines: _lines,
            onChanged: (lines) => setState(() => _lines = lines),
            showPrices: showPrices,
          ),
          const SizedBox(height: 16),
          if (_isPreparateur)
            Text(
              'Retrait sur place uniquement — la commande apparaîtra dans "Récupérations" une fois prête, '
              'à valider comme livrée au comptoir par le gérant.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else ...[
            _sectionTitle('Type de commande'),
            // Livraison ou retrait sur place — le retrait est un cas à part
            // (pas de livreur, pas de frais), les zones payantes viennent du
            // CRUD Paramètres (§ demande).
            OrderTypeToggle(
              pickup: _isPickup,
              onChanged: (pickup) => setState(() {
                _zone = pickup ? kRecuperationCode : (zonesPayantes.isNotEmpty ? zonesPayantes.first.code : '');
              }),
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('Date et heure de livraison'),
          OrderDateTimeField(
            value: _dateCommande,
            hintText: 'Maintenant',
            onChanged: (d) {
              setState(() => _dateCommande = d);
              // Rafraîchit la disponibilité livreur pour ce nouveau créneau.
              if (!_isPreparateur) _loadLivreurs();
            },
            onClear: () {
              setState(() => _dateCommande = null);
              if (!_isPreparateur) _loadLivreurs();
            },
          ),
          const SizedBox(height: 4),
          Text('Vide = maintenant.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
          if (!_isPreparateur) ...[
            const SizedBox(height: 16),
            twoCols(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Préparateur'),
                  OrderFormDropdown<int>(
                    value: _preparateurId,
                    hintText: 'Assigner plus tard',
                    prefixIcon: Icons.inventory_2_outlined,
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('Assigner plus tard')),
                      for (final p in _preparateurs)
                        DropdownMenuItem(value: p.id, child: Text('${p.fullName}${p.available ? '' : ' (occupé)'}')),
                    ],
                    onChanged: (v) => setState(() => _preparateurId = v),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Livreur'),
                  OrderFormDropdown<int>(
                    value: _livreurId,
                    hintText: 'Assigner plus tard',
                    prefixIcon: Icons.moped_outlined,
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('Assigner plus tard')),
                      for (final l in _livreurs)
                        DropdownMenuItem(value: l.id, child: Text('${l.fullName}${l.available ? '' : ' (occupé)'}')),
                    ],
                    onChanged: (v) => setState(() => _livreurId = v),
                  ),
                ],
              ),
            ),
          ],
          if (!_isPickup) ...[
            const SizedBox(height: 16),
            twoCols(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Zone de livraison'),
                  OrderFormDropdown<String>(
                    value: _zone,
                    hintText: 'Zone de livraison',
                    prefixIcon: Icons.local_shipping_outlined,
                    items: [for (final z in zonesPayantes) DropdownMenuItem(value: z.code, child: Text(z.label))],
                    onChanged: (v) => setState(() => _zone = v ?? _zone),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Adresse de livraison'),
                  TextField(
                    controller: _adresseController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.place_outlined),
                      hintText: 'Ex: Lot II M 45 Antanimena, Antananarivo',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Paiement'),
            OrderFormDropdown<PaymentMode>(
              value: _modePaiement,
              prefixIcon: Icons.payments_outlined,
              items: [for (final m in PaymentMode.values) DropdownMenuItem(value: m, child: Text(modePaiementLabel(m)))],
              onChanged: (v) => setState(() => _modePaiement = v ?? _modePaiement),
            ),
          ],
          const SizedBox(height: 16),
          twoCols(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('Nom client'),
                TextField(
                  controller: _clientController,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline), hintText: 'Rakoto Jean'),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('Téléphone'),
                TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined), hintText: '+261340000000'),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Autre téléphone (optionnel)'),
          TextField(
            controller: _phone2Controller,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined), hintText: '+261340000000'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _sectionTitle(_isPreparateur ? 'Note (optionnel)' : 'Note pour le préparateur (optionnel)'),
          TextField(
            controller: _notePreparateurController,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.notes_outlined)),
            maxLines: 3,
          ),
          if (!_isPreparateur && !_isPickup) ...[
            const SizedBox(height: 16),
            _sectionTitle('Note pour le livreur (optionnel)'),
            TextField(
              controller: _noteLivreurController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.moped_outlined)),
              maxLines: 3,
            ),
          ],
          if (showPrices) ...[
            const SizedBox(height: 16),
            Card(
              color: scheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [const Text('Frais de livraison'), Text(arFmt(_frais))],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total à payer', style: theme.textTheme.titleMedium),
                        Text(arFmt(_total), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Création…'),
                          ],
                        )
                      : const Text('Créer la commande'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
