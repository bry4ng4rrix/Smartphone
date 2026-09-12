import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/permissions.dart';
import '../../data/repositories/catalog_repository.dart' show catalogErrorMessage;
import '../../data/repositories/stores_repository.dart';
import '../../models/catalog.dart';
import '../../models/magasin.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart' show referencesProvider;
import '../../state/stores_provider.dart';
import '../../state/transfers_provider.dart';
import '../../widgets/async_state_widgets.dart';

/// Page `/transfers` du web (frontend/app/(app)/transfers/page.tsx) +
/// composant partagé `TransferProductsPanel`
/// (frontend/components/transfer-products-panel.tsx).
///
/// Transfert de stock entre magasins d'une même société : choisir un magasin
/// source, sélectionner des produits (variantes couleur) avec leurs
/// quantités, choisir un magasin de destination, valider.
///
/// Gating : `isAdmin` du web (= rôle Django `admin`, [UserPermissions
/// .isSuperAdmin]). Un non-admin voit l'écran « Accès refusé » — le web, lui,
/// reste bloqué sur un skeleton infini (bug documenté dans le cahier des
/// charges) : ici l'écran de refus est réellement rendu.
///
/// Deux modes, comme sur le web :
/// * page `/transfers` : rangée de boutons « Magasin source », panneau
///   monté à la sélection ; après un transfert réussi la source est
///   désélectionnée et la liste des magasins rechargée ;
/// * « dialog » (`TransferProductsDialog`, ouvert depuis Magasins) :
///   [preselectedSourceId] fourni, l'écran est poussé par-dessus Magasins ;
///   la source est imposée (description « Depuis `<magasin>` — … », pas de
///   rangée de sélection), le panier peut être pré-rempli ([initialCart]) ;
///   après un transfert réussi il se ferme et Magasins est rechargé.
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key, this.preselectedSourceId, this.initialCart = const []});

  /// Mode « dialog » (`TransferProductsDialog`) : magasin source imposé par
  /// l'appelant (page Magasins), non modifiable ici — le web n'affiche pas
  /// la rangée « Magasin source » dans le dialog.
  final int? preselectedSourceId;

  /// `initialCart` de `TransferProductsPanel` : panier (et quantités
  /// saisies) pré-remplis — réservé au mode dialog, vide par défaut.
  final List<TransferCartItem> initialCart;

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  int? _sourceId;

  /// Rechargement NON silencieux des magasins (`fetchStores()` du web :
  /// `setLoading(true)` -> skeletons). Riverpod 3 conserve la valeur
  /// précédente pendant un `AsyncLoading`, l'écran s'en souvient donc
  /// lui-même.
  bool _refreshing = false;

  bool get _dialogMode => widget.preselectedSourceId != null;

  @override
  void initState() {
    super.initState();
    _sourceId = widget.preselectedSourceId;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshStores() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(storesProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    if (!mounted) return;
    final after = ref.read(storesProvider);
    if (after.hasError) _snack('Erreur de chargement des magasins: ${ApiClient.messageFromError(after.error!)}');
  }

  /// `onSuccess` du panneau : toast « Transfert effectué », puis — page —
  /// désélection de la source + rechargement des magasins, ou — dialog —
  /// fermeture + rechargement de la page Magasins (`fetchData()`).
  void _onTransferSuccess() {
    _snack('Transfert effectué');
    // Les stocks des références ont changé (mouvements SORTIE/ENTRÉE) : le
    // catalogue partagé est invalidé sans attendre l'événement WebSocket.
    ref.invalidate(referencesProvider);
    if (_dialogMode && Navigator.of(context).canPop()) {
      ref.read(storesProvider.notifier).refresh();
      Navigator.of(context).pop();
      return;
    }
    setState(() => _sourceId = null);
    _refreshStores();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    // `userLoading` du web.
    if (auth.status == AuthStatus.loading) {
      return const Scaffold(body: LoadingState());
    }
    if (user == null || !user.isSuperAdmin) {
      return const _AccesRefuse();
    }

    final storesAsync = ref.watch(storesProvider);
    final initialLoading = !storesAsync.hasValue && !storesAsync.hasError;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.compare_arrows_outlined, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Flexible(child: Text('Transfert de produits', overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: (initialLoading || _refreshing)
          ? const LoadingState()
          : (storesAsync.hasError && !storesAsync.hasValue)
              ? ErrorState(
                  message: 'Erreur de chargement des magasins: ${ApiClient.messageFromError(storesAsync.error!)}',
                  onRetry: _refreshStores,
                )
              : _buildBody(storesAsync.value ?? const <Magasin>[]),
    );
  }

  Widget _buildBody(List<Magasin> stores) {
    Magasin? sourceStore;
    for (final s in stores) {
      if (s.magasinId == _sourceId) sourceStore = s;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _dialogMode ? _dialogHeader(sourceStore) : _pageHeader(stores),
        ),
        const Divider(height: 1),
        Expanded(
          child: sourceStore == null
              // Dialog web sans source : en-tête seul, corps vide. Page :
              // zone d'invite en pointillés.
              ? (_dialogMode ? const SizedBox.shrink() : _sourcePrompt())
              // La clé sur `magasin_id` force un REMOUNT complet du panneau
              // (panier, recherches, quantités, destination) à chaque
              // changement de source — `key={sourceStore.magasin_id}` du web.
              : _TransferPanel(
                  key: ValueKey('transfer-panel-${sourceStore.magasinId}'),
                  sourceStore: sourceStore,
                  stores: stores,
                  initialCart: widget.initialCart,
                  onSuccess: _onTransferSuccess,
                ),
        ),
      ],
    );
  }

  /// En-tête de la page `/transfers` : sous-titre + rangée « Magasin
  /// source : » (un bouton par magasin, logo ou icône Store, « Aucun
  /// magasin » si la liste est vide).
  Widget _pageHeader(List<Magasin> stores) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choisissez un magasin source, puis sélectionnez les produits (et leurs variantes) à transférer vers un autre magasin.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Magasin source :',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: stores.isEmpty
                  ? Text('Aucun magasin', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final store in stores) ...[
                            ChoiceChip(
                              avatar: _StoreLogo(url: store.shopLogo, size: 16),
                              label: Text(store.shopName),
                              selected: _sourceId == store.magasinId,
                              onSelected: (_) => setState(() => _sourceId = store.magasinId),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  /// `DialogDescription` de `TransferProductsDialog` : « Depuis `<magasin>`
  /// — sélectionnez des produits (et leurs variantes) et choisissez le
  /// magasin de destination. » — nom vide si la source est introuvable,
  /// comme sur le web. Pas de rangée « Magasin source » : elle est imposée.
  Widget _dialogHeader(Magasin? sourceStore) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        children: [
          const TextSpan(text: 'Depuis '),
          TextSpan(
            text: sourceStore?.shopName ?? '',
            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const TextSpan(text: ' — sélectionnez des produits (et leurs variantes) et choisissez le magasin de destination.'),
        ],
      ),
    );
  }

  /// « Sélectionnez un magasin source pour commencer. » — zone d'invite de
  /// la page tant qu'aucune source n'est choisie.
  Widget _sourcePrompt() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          'Sélectionnez un magasin source pour commencer.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Écran « Accès refusé » du web : Card centrée, icône bouclier rouge,
/// « Cette page est réservée aux administrateurs. »
class _AccesRefuse extends StatelessWidget {
  const _AccesRefuse();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfert de produits')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_maybe_outlined, size: 48, color: Color(0xFFEF4444)),
                  const SizedBox(height: 16),
                  Text(
                    'Accès refusé',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cette page est réservée aux administrateurs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo rond du magasin (URL absolue renvoyée par `magasins/users/`), icône
/// « Store » grise en repli.
class _StoreLogo extends StatelessWidget {
  const _StoreLogo({required this.url, this.size = 20});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.storefront_outlined, size: size, color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TransferProductsPanel — cœur du flux
// -----------------------------------------------------------------------------

/// Une ligne du panier de transfert (`TransferCartItem` du web) — publique
/// pour que la page Magasins puisse pré-remplir le panier du mode dialog
/// (`initialCart`).
class TransferCartItem {
  TransferCartItem({
    required this.id,
    required this.name,
    required this.reference,
    required this.quantity,
    required this.maxQuantity,
    this.variantId,
    this.variantLabel,
  });

  /// Identifiant de la référence produit.
  final int id;
  final String name;
  final String reference;

  /// Quantité à transférer, bornée 1..[maxQuantity] par le panneau.
  int quantity;
  final int maxQuantity;

  /// Variante (couleur) — seuls les items qui en portent une sont envoyés.
  final int? variantId;
  final String? variantLabel;

  /// Copie indépendante : le panneau modifie `quantity` en place sans
  /// toucher à la liste fournie par l'appelant.
  TransferCartItem copy() => TransferCartItem(
        id: id,
        name: name,
        reference: reference,
        quantity: quantity,
        maxQuantity: maxQuantity,
        variantId: variantId,
        variantLabel: variantLabel,
      );
}

/// `cartKey(id, variantId)` du web : un produit et ses variantes peuvent
/// coexister dans le panier.
String _cartKey(int id, [int? variantId]) => variantId != null ? '$id:$variantId' : '$id';

/// `formatVariantLabel(size, color)` : parties non vides jointes par ' / '
/// (la taille est toujours vide sur ce tenant — vestige textile), ou
/// « Standard » si vide.
String _variantLabel(String? size, String? color) {
  final parts = [size, color].where((p) => p != null && p.trim().isNotEmpty).map((p) => p!.trim()).toList();
  return parts.join(' / ');
}

class _TransferPanel extends ConsumerStatefulWidget {
  const _TransferPanel({
    super.key,
    required this.sourceStore,
    required this.stores,
    required this.onSuccess,
    this.initialCart = const [],
  });

  final Magasin sourceStore;
  final List<Magasin> stores;
  final VoidCallback onSuccess;

  /// `initialCart` du web : panier ET quantités saisies (`qtyInputs`)
  /// initialisés depuis ces items, clé `cartKey(id, variantId)`.
  final List<TransferCartItem> initialCart;

  @override
  ConsumerState<_TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends ConsumerState<_TransferPanel> {
  int? _destinationId;
  final _productSearchController = TextEditingController();
  final _destinationSearchController = TextEditingController();
  String _productSearch = '';
  String _destinationSearch = '';
  final List<TransferCartItem> _cart = [];

  /// Quantité saisie par produit/variante AVANT ajout au panier
  /// (`qtyInputs` du web), bornée 1..max(stock, 1).
  final Map<String, int> _qtyInputs = {};
  final Set<int> _expanded = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // `useState(initialCart)` + `qtyInputs` dérivés de `initialCart`.
    for (final item in widget.initialCart) {
      final copy = item.copy();
      _cart.add(copy);
      _qtyInputs[_cartKey(copy.id, copy.variantId)] = copy.quantity;
    }
  }

  @override
  void dispose() {
    _productSearchController.dispose();
    _destinationSearchController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int _clamp(int value, int max) => value.clamp(1, math.max(max, 1));

  int _qtyInput(String key, int max) => _clamp(_qtyInputs[key] ?? 1, max);

  void _setQtyInput(String key, int value, int max) => setState(() => _qtyInputs[key] = _clamp(value, max));

  bool _inCart(int id, int? variantId) => _cart.any((c) => c.id == id && c.variantId == variantId);

  /// Nom affiché du produit : « `marque référence` » (le web n'affiche que
  /// la référence ; la marque la rend identifiable sur mobile).
  String _productName(ProductReference r) => '${r.brandName} ${r.referenceName}'.trim();

  int _stockOf(ProductReference r) => r.variants.fold(0, (s, v) => s + v.stockActuel);

  void _toggleExpand(int id) => setState(() {
        if (!_expanded.remove(id)) _expanded.add(id);
      });

  /// `addToTransferCart(product)` — produit SANS variante. Son stock étant la
  /// somme (vide) de ses variantes, il vaut toujours 0 : le bouton est
  /// désactivé et, par sécurité, l'ajout refuse « stock insuffisant ».
  void _addProduct(ProductReference r) {
    final stock = _stockOf(r);
    final name = _productName(r);
    if (stock <= 0) {
      _snack('$name : stock insuffisant');
      return;
    }
    if (_inCart(r.id, null)) {
      _snack('$name est déjà dans le panier');
      return;
    }
    final quantity = _qtyInput(_cartKey(r.id), stock);
    setState(() {
      _cart.add(TransferCartItem(id: r.id, name: name, reference: r.typeName, quantity: quantity, maxQuantity: stock));
    });
    _snack('$quantity × $name ajouté au panier');
  }

  /// `addVariantToTransferCart(product, variant)`.
  void _addVariant(ProductReference r, ProductVariant v) {
    final stock = v.stockActuel;
    final name = _productName(r);
    if (stock <= 0) {
      _snack('$name : stock insuffisant pour cette variante');
      return;
    }
    if (_inCart(r.id, v.id)) {
      _snack('Cette variante est déjà dans le panier');
      return;
    }
    final quantity = _qtyInput(_cartKey(r.id, v.id), stock);
    final label = _variantLabel(null, v.couleur);
    setState(() {
      _cart.add(TransferCartItem(
        id: r.id,
        name: name,
        reference: r.typeName,
        quantity: quantity,
        maxQuantity: stock,
        variantId: v.id,
        variantLabel: label,
      ));
    });
    _snack('$quantity × $name${label.isNotEmpty ? ' ($label)' : ''} ajouté au panier');
  }

  void _removeFromCart(int id, int? variantId) => setState(() {
        _cart.removeWhere((c) => c.id == id && c.variantId == variantId);
      });

  void _updateCartQuantity(TransferCartItem item, int value) => setState(() {
        item.quantity = _clamp(value, item.maxQuantity);
      });

  int get _cartTotalQty => _cart.fold(0, (s, c) => s + c.quantity);

  List<Magasin> get _destinationStores {
    final term = _destinationSearch.toLowerCase();
    return widget.stores
        .where((s) => s.magasinId != widget.sourceStore.magasinId && s.shopName.toLowerCase().contains(term))
        .toList();
  }

  Magasin? get _selectedDestination {
    for (final s in widget.stores) {
      if (s.magasinId == _destinationId) return s;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_destinationId == null || _cart.isEmpty) {
      _snack('Sélectionnez des produits et un magasin de destination');
      return;
    }
    setState(() => _submitting = true);
    try {
      // Règle métier : seuls les items portant une variante (couleur) sont
      // transférables — le backend travaille au niveau de la variante.
      final items = [
        for (final c in _cart)
          if (c.variantId != null)
            TransferItem(
              variantId: c.variantId!,
              quantity: c.quantity,
              label: '${c.name}${c.variantLabel != null ? ' (${c.variantLabel})' : ''}',
            ),
      ];
      if (items.isEmpty) {
        _snack('Sélectionnez au moins une couleur à transférer');
        return;
      }
      await ref.read(storesRepositoryProvider).transfer(
            sourceMagasinId: widget.sourceStore.magasinId,
            destinationMagasinId: _destinationId!,
            items: items,
          );
      widget.onSuccess();
    } catch (e) {
      // Le web n'affiche qu'un générique « Erreur lors du transfert » ; ici le
      // détail renvoyé par le serveur (ex : « Stock insuffisant pour X
      // (Noir). Disponible : 3. ») est montré quand il existe.
      _snack(catalogErrorMessage(e, 'Erreur lors du transfert'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Rendu
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(transferCatalogProvider(widget.sourceStore.magasinId));

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        if (wide) {
          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _productsHeader(),
                          Expanded(child: _productsBody(catalogAsync, asSliver: false)),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _cartHeader(),
                          Expanded(
                            child: _cart.isEmpty
                                ? _cartEmpty()
                                : ListView(padding: const EdgeInsets.all(8), children: _cartTiles()),
                          ),
                          const Divider(height: 1),
                          Flexible(
                            child: SingleChildScrollView(child: _destinationPanel()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _submitBar(),
            ],
          );
        }

        // Mobile : les trois zones s'empilent verticalement dans un seul
        // défilement, le bouton de validation reste ancré en bas.
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _productsHeader()),
                  _productsBody(catalogAsync, asSliver: true),
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1),
                        _cartHeader(),
                        if (_cart.isEmpty)
                          _cartEmpty()
                        else
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _cartTiles()),
                          ),
                        const Divider(height: 1),
                        _destinationPanel(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _submitBar(),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String text, {Widget? trailing, IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        ?trailing,
      ],
    );
  }

  Widget _productsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Produits du magasin'),
          const SizedBox(height: 8),
          TextField(
            controller: _productSearchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Rechercher un produit...',
              suffixIcon: _productSearch.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _productSearchController.clear();
                        setState(() => _productSearch = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _productSearch = v),
          ),
        ],
      ),
    );
  }

  /// Filtre client, insensible à la casse — sur le nom (marque + référence)
  /// et la référence, comme `p.name || p.reference` du web.
  List<ProductReference> _filtered(List<ProductReference> all) {
    final term = _productSearch.toLowerCase().trim();
    if (term.isEmpty) return all;
    return all.where((r) {
      return _productName(r).toLowerCase().contains(term) ||
          r.referenceName.toLowerCase().contains(term) ||
          r.typeName.toLowerCase().contains(term);
    }).toList();
  }

  /// Corps de la liste produits — en sliver (mobile) ou en boîte (large).
  Widget _productsBody(AsyncValue<List<ProductReference>> catalogAsync, {required bool asSliver}) {
    Widget box(Widget child) => asSliver ? SliverToBoxAdapter(child: child) : child;
    final scheme = Theme.of(context).colorScheme;

    if (catalogAsync.isLoading && !catalogAsync.hasValue) {
      return box(
        SizedBox(
          height: 128,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Chargement...', style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }
    if (catalogAsync.hasError && !catalogAsync.hasValue) {
      // Web : toast « Erreur de chargement des produits », liste vide. Ici le
      // message est affiché en place, avec un bouton pour réessayer.
      return box(
        ErrorState(
          message: 'Erreur de chargement des produits — ${ApiClient.messageFromError(catalogAsync.error!)}',
          onRetry: () => ref.invalidate(transferCatalogProvider(widget.sourceStore.magasinId)),
        ),
      );
    }
    final all = catalogAsync.value ?? const <ProductReference>[];
    final filtered = _filtered(all);
    if (filtered.isEmpty) {
      return box(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            all.isEmpty ? 'Aucun produit dans ce magasin' : 'Aucun résultat',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
      );
    }
    if (asSliver) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: SliverList.builder(
          itemCount: filtered.length,
          itemBuilder: (context, i) => _productTile(filtered[i]),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: filtered.length,
      itemBuilder: (context, i) => _productTile(filtered[i]),
    );
  }

  Widget _productTile(ProductReference r) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    final name = _productName(r);
    final variants = r.variants;

    if (variants.isEmpty) {
      // PRODUIT SANS VARIANTE : quantité + bouton « Sélectionner » /
      // « Sélectionné » (désactivés si déjà au panier ou stock <= 0).
      final inCart = _inCart(r.id, null);
      final stock = _stockOf(r);
      final key = _cartKey(r.id);
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('${r.typeName} · Stock : $stock', style: muted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _QtyField(
                value: _qtyInput(key, stock),
                max: stock,
                enabled: !inCart && stock > 0,
                onChanged: (v) => _setQtyInput(key, v, stock),
              ),
              const SizedBox(width: 6),
              inCart
                  ? FilledButton.tonalIcon(
                      onPressed: null,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Sélectionné'),
                    )
                  : OutlinedButton(
                      onPressed: stock > 0 ? () => _addProduct(r) : null,
                      child: const Text('Sélectionner'),
                    ),
            ],
          ),
        ),
      );
    }

    // PRODUIT AVEC VARIANTES : en-tête repliable + une ligne par couleur.
    // Le tri `SIZE_ORDER` du web (XS..4XL) est un no-op documenté : le
    // mapper web met toujours `size: ''` et le modèle Flutter n'a pas de
    // taille — l'ordre serveur des variantes est conservé.
    final totalStock = _stockOf(r);
    final expanded = _expanded.contains(r.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleExpand(r.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text('${r.typeName} · ${variants.length} variante(s) · Stock : $totalStock', style: muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: [for (final v in variants) _variantRow(r, v)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _variantRow(ProductReference r, ProductVariant v) {
    final scheme = Theme.of(context).colorScheme;
    final label = _variantLabel(null, v.couleur);
    final stock = v.stockActuel;
    final inCart = _inCart(r.id, v.id);
    final key = _cartKey(r.id, v.id);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
                children: [
                  TextSpan(text: label.isEmpty ? 'Standard' : label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' · Stock : $stock', style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _QtyField(
            value: _qtyInput(key, stock),
            max: stock,
            enabled: !inCart && stock > 0,
            compact: true,
            onChanged: (val) => _setQtyInput(key, val, stock),
          ),
          const SizedBox(width: 4),
          inCart
              ? IconButton.filledTonal(
                  onPressed: null,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Déjà dans le panier',
                  icon: const Icon(Icons.check, size: 16),
                )
              : IconButton.outlined(
                  onPressed: stock > 0 ? () => _addVariant(r, v) : null,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ajouter au panier',
                  icon: const Icon(Icons.add, size: 16),
                ),
        ],
      ),
    );
  }

  Widget _cartHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: _sectionLabel(
        'Panier de transfert',
        icon: Icons.shopping_cart_outlined,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(999)),
          child: Text('$_cartTotalQty unité(s)', style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _cartEmpty() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Aucun produit sélectionné',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
      ),
    );
  }

  List<Widget> _cartTiles() {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final item in _cart)
        Container(
          key: ValueKey('cart-${_cartKey(item.id, item.variantId)}'),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
                        children: [
                          TextSpan(text: item.name),
                          if (item.variantLabel != null && item.variantLabel!.isNotEmpty)
                            TextSpan(
                              text: ' — ${item.variantLabel}',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400),
                            ),
                        ],
                      ),
                    ),
                    Text('${item.reference} · max ${item.maxQuantity}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _QtyField(
                value: item.quantity,
                max: item.maxQuantity,
                enabled: true,
                onChanged: (v) => _updateCartQuantity(item, v),
              ),
              IconButton(
                tooltip: 'Retirer',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
                onPressed: () => _removeFromCart(item.id, item.variantId),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _destinationPanel() {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedDestination;
    final destinations = _destinationStores;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Magasin de destination'),
          const SizedBox(height: 8),
          TextField(
            controller: _destinationSearchController,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Rechercher un magasin...',
            ),
            onChanged: (v) => setState(() => _destinationSearch = v),
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.06),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(selected.shopName, style: const TextStyle(fontWeight: FontWeight.w500))),
                  IconButton(
                    tooltip: 'Désélectionner',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _destinationId = null),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (destinations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Aucun magasin trouvé',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            )
          else
            for (final store in destinations)
              Material(
                color: _destinationId == store.magasinId ? scheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _destinationId = store.magasinId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _destinationId == store.magasinId ? scheme.primary.withValues(alpha: 0.3) : Colors.transparent,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _StoreLogo(url: store.shopLogo, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            store.shopName,
                            style: TextStyle(fontWeight: _destinationId == store.magasinId ? FontWeight.w600 : FontWeight.w400),
                          ),
                        ),
                        if (_destinationId == store.magasinId) Icon(Icons.check, size: 16, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _submitBar() {
    final total = _cartTotalQty;
    final disabled = _submitting || _cart.isEmpty || _destinationId == null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: disabled ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.compare_arrows_outlined),
            label: Text(_submitting ? 'Transfert en cours...' : 'Transférer${total > 0 ? ' $total unité(s)' : ''}'),
          ),
        ),
      ),
    );
  }
}

/// Champ de quantité numérique borné (`Input type=number min=1 max=stock`
/// du web) : la valeur tapée est bornée 1..max à chaque frappe par le
/// parent ; un champ vidé reprend la valeur courante quand il perd le focus.
class _QtyField extends StatefulWidget {
  const _QtyField({
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  final int value;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  State<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<_QtyField> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.value}');
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _syncText();
  }

  void _syncText() {
    final text = '${widget.value}';
    if (_controller.text != text) {
      _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  @override
  void didUpdateWidget(covariant _QtyField old) {
    super.didUpdateWidget(old);
    final typed = int.tryParse(_controller.text);
    // Reflète la valeur bornée par le parent (ex : 50 saisi, stock 12 ->
    // « 12 »), sans écraser un champ que l'utilisateur vient de vider.
    if (!_focus.hasFocus || (typed != null && typed != widget.value)) _syncText();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.compact ? 52 : 60,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: widget.compact ? 12 : 14),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: widget.compact ? 6 : 8),
        ),
        onChanged: (text) {
          final n = int.tryParse(text.trim());
          if (n != null) widget.onChanged(n);
        },
        onSubmitted: (_) => _syncText(),
      ),
    );
  }
}
