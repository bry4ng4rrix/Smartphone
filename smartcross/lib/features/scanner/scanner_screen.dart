import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../models/catalog.dart';
import '../../state/catalog_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');

/// `new Intl.NumberFormat('fr-MG').format(...) + ' Ar'` du web.
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

final _stampFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Couleurs de STATUT reprises telles quelles des classes Tailwind de la page
/// web (`bg-red-100 text-red-800`, `bg-orange-100 text-orange-800`,
/// `bg-green-100 text-green-800`) — ce ne sont pas des couleurs de thème.
const _redRupture = Color(0xFFDC2626);
const _orangeFaible = Color(0xFFEA580C);
const _greenEnStock = Color(0xFF16A34A);

/// Délai de debounce du champ de recherche — 350 ms, identique au
/// `setTimeout(() => search(query), 350)` de la page web.
const _kDebounce = Duration(milliseconds: 350);

// ---------------------------------------------------------------------------
// Capture caméra — point d'extension unique
// ---------------------------------------------------------------------------

/// Capture d'un code-barres / QR code.
///
/// AUCUN paquet de scan caméra n'est déclaré dans `pubspec.yaml` et ce
/// portage n'a pas le droit de l'ajouter : en attendant, cette fonction ouvre
/// la SAISIE MANUELLE du code. Le besoin comptoir reste couvert (douchette
/// Bluetooth — qui se comporte comme un clavier —, code recopié à l'œil,
/// contenu de QR collé depuis le presse-papier).
///
/// POUR BRANCHER LA CAMÉRA (une seule modification, ici) :
///   1. ajouter `mobile_scanner: ^7.0.0` aux `dependencies` de
///      `smartcross/pubspec.yaml` ;
///   2. déclarer la permission caméra : `android.permission.CAMERA` dans
///      `android/app/src/main/AndroidManifest.xml`, et la clé
///      `NSCameraUsageDescription` dans `ios/Runner/Info.plist` ;
///   3. remplacer le corps ci-dessous par l'ouverture d'une page
///      `MobileScanner` qui renvoie `barcode.rawValue` via
///      `Navigator.pop(context, rawValue)`, en gardant la saisie manuelle en
///      repli (permission refusée, appareil sans caméra).
///
/// Renvoie le code lu, ou `null` si l'utilisateur annule. AUCUN autre fichier
/// de l'écran n'est à toucher : tout le reste de la page (recherche produit,
/// cartes de résultats, navigation vers Commandes) fonctionne déjà.
Future<String?> scanBarcode(BuildContext context) async {
  final code = await showDialog<String>(
    context: context,
    builder: (_) => const _ManualCodeDialog(),
  );
  final trimmed = code?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// Saisie manuelle du code — repli de [scanBarcode] tant que la caméra n'est
/// pas branchée.
class _ManualCodeDialog extends StatefulWidget {
  const _ManualCodeDialog();

  @override
  State<_ManualCodeDialog> createState() => _ManualCodeDialogState();
}

class _ManualCodeDialogState extends State<_ManualCodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Saisir le code'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La lecture par caméra n\'est pas encore disponible : saisissez '
              'le code-barres ou le contenu du QR code.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Code',
                hintText: 'Code-barres ou contenu du QR',
                prefixIcon: Icon(Icons.qr_code_2),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Saisissez un code' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Valider')),
      ],
    );
  }
}

/// Réplique de `parseQRCodeData()` (frontend/lib/qrcode-generator.ts) : rend
/// le JSON du QR s'il est décodable, sinon `{ raw: <texte lu> }` — et ne lève
/// JAMAIS, exactement comme la version web.
///
/// Nuance JS→Dart : `JSON.parse('12345')` renvoie le nombre 12345 côté web
/// (donc un code-barres purement numérique n'est pas un objet exploitable) ;
/// on retombe ici sur `{ raw }` dans ce cas, ce qui est le comportement utile.
Map<String, dynamic> parseQrCodeData(String qrData) {
  try {
    final decoded = jsonDecode(qrData);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'raw': qrData};
  } catch (_) {
    return {'raw': qrData};
  }
}

/// Charge utile décodée d'un code lu — reprend les 6 champs produits par
/// `generateQRCode()` (sku, productName, imageId, size, colorVariant,
/// timestamp), plus le texte brut pour les codes non-JSON.
class ScannedCode {
  ScannedCode({required this.raw, required this.data});

  final String raw;
  final Map<String, dynamic> data;

  factory ScannedCode.parse(String raw) => ScannedCode(raw: raw, data: parseQrCodeData(raw));

  String? _field(String key) {
    final value = data[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? get sku => _field('sku');
  String? get productName => _field('productName');
  String? get imageId => _field('imageId');
  String? get size => _field('size');
  String? get colorVariant => _field('colorVariant');

  /// Horodatage ISO du QR, ramené à l'heure d'Antananarivo (core/app_time.dart).
  DateTime? get timestamp {
    final value = _field('timestamp');
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : appLocal(parsed);
  }

  /// Vrai QR produit (JSON à champs connus) plutôt qu'un code-barres brut.
  bool get isStructured => productName != null || sku != null;

  /// Terme injecté dans la recherche : le nom du produit d'abord, à défaut le
  /// SKU, à défaut le texte brut du code.
  String get searchTerm => productName ?? sku ?? raw;
}

// ---------------------------------------------------------------------------
// Modèle de résultat
// ---------------------------------------------------------------------------

/// Statut de stock — `stockStatus(p)` du web, au caractère près :
/// `initial_quantity === 0` → Rupture ; `<= alert_threshold` → Faible ;
/// sinon → En stock.
enum _StockStatus {
  rupture,
  faible,
  enStock;

  String get label => switch (this) {
        _StockStatus.rupture => 'Rupture',
        _StockStatus.faible => 'Faible',
        _StockStatus.enStock => 'En stock',
      };

  Color get color => switch (this) {
        _StockStatus.rupture => _redRupture,
        _StockStatus.faible => _orangeFaible,
        _StockStatus.enStock => _greenEnStock,
      };
}

/// Un résultat de recherche : équivalent Flutter de l'objet plat « Product »
/// que `mapReferenceToProduct()` (frontend/lib/django-client.ts) fabrique à
/// partir d'une `ProductReference` du catalogue.
class _ScannerProduct {
  const _ScannerProduct({
    required this.id,
    required this.name,
    required this.reference,
    required this.brand,
    required this.category,
    required this.type,
    required this.description,
    required this.shellPrice,
    required this.initialQuantity,
    required this.alertThreshold,
    required this.variants,
  });

  final int id;
  final String name;
  final String reference;
  final String brand;
  final String category;
  final String type;
  final String description;
  final double shellPrice;
  final int initialQuantity;
  final int alertThreshold;
  final List<ProductVariant> variants;

  factory _ScannerProduct.fromReference(ProductReference ref) {
    // Web : `initial_quantity` = SOMME des `stock_actuel` des variantes,
    // `alert_threshold` = MINIMUM des `seuil_alerte` (1 par défaut quand la
    // référence n'a aucune variante).
    final totalStock = ref.variants.fold<int>(0, (sum, v) => sum + v.stockActuel);
    final minAlert = ref.variants.isEmpty
        ? 1
        : ref.variants.map((v) => v.seuilAlerte).reduce(math.min);
    return _ScannerProduct(
      id: ref.id,
      name: ref.referenceName,
      reference: ref.referenceName,
      brand: ref.brandName,
      category: ref.categoryName,
      type: ref.typeName,
      description: [ref.typeName, ref.brandName].where((s) => s.isNotEmpty).join(' — '),
      shellPrice: ref.prixVente,
      initialQuantity: totalStock,
      alertThreshold: minAlert,
      variants: ref.variants,
    );
  }

  _StockStatus get status {
    if (initialQuantity == 0) return _StockStatus.rupture;
    if (initialQuantity <= alertThreshold) return _StockStatus.faible;
    return _StockStatus.enStock;
  }
}

// ---------------------------------------------------------------------------
// Écran
// ---------------------------------------------------------------------------

/// Page `/scanner` du web (`frontend/app/(app)/scanner/page.tsx`) : recherche
/// rapide (lookup) dans le catalogue produit par nom de référence ou marque.
///
/// Malgré son nom et son icône QR, la page web n'ouvre AUCUNE caméra : c'est
/// une simple recherche texte. Le portage mobile garde ce comportement à
/// l'identique et y ajoute le maillon qui manquait sur téléphone : un bouton
/// « Scanner un code » branché sur [scanBarcode] — aujourd'hui une saisie
/// manuelle, demain la caméra (voir la doc de [scanBarcode]).
///
/// La vente instantanée a été retirée côté web : chaque résultat renvoie vers
/// « Créer une commande » (`/orders`), SANS transmettre le produit — le
/// produit est re-choisi dans le formulaire de commande. Le portage reproduit
/// ce comportement tel quel.
///
/// Gating : AUCUN. La page web n'importe même pas `useCurrentUser`, aucun
/// garde, aucune redirection — elle est accessible à tout utilisateur
/// connecté. Le contrôle d'accès reste, comme partout ailleurs, du ressort de
/// `core/router.dart` / `core/nav_items.dart`.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  /// Terme de recherche débouncé (350 ms) — l'équivalent du `query` passé à
  /// `search()` côté web.
  String _query = '';

  /// Dernier code lu par [scanBarcode], conservé pour afficher sa charge
  /// utile décodée (§ lib/qrcode-generator.ts) tant qu'on ne l'efface pas.
  ScannedCode? _scanned;

  /// Rechargements du catalogue en vol pour la recherche courante — la
  /// liste précédente reste affichée pendant ce temps (web : `loading`).
  int _searchesInFlight = 0;

  bool get _searching => _searchesInFlight > 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Frappe clavier : rebuild immédiat (bouton « effacer », bascule du bloc
  /// résultats) puis application du terme après 350 ms d'inactivité.
  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_kDebounce, () {
      if (!mounted) return;
      setState(() => _query = value);
      _searchCatalog(value);
    });
  }

  /// Applique un terme SANS attendre le debounce (retour de scan, touche
  /// Entrée).
  void _applyNow(String value) {
    _debounce?.cancel();
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    setState(() => _query = value);
    _searchCatalog(value);
  }

  /// `search(q)` du web : à chaque terme débouncé NON vide, le catalogue est
  /// rechargé (`djangoClient.products.search` refait un
  /// `GET /catalog/references/` puis filtre en JS) — les stocks affichés sont
  /// donc toujours ceux du serveur au moment de la recherche. Ici le filtrage
  /// est immédiat sur la liste en cache et le rechargement se fait en
  /// arrière-plan sans masquer les résultats (le web les remplace par
  /// « Recherche... » le temps de l'appel). Terme vide : aucun appel, comme
  /// `if (!q) { setResults([]); return; }`.
  ///
  /// Un échec laisse la liste précédente en place et passe par le toast du
  /// `ref.listen` de [build] (`toast.error(err.message || ...)`).
  Future<void> _searchCatalog(String query) async {
    if (query.isEmpty) return;
    final current = ref.read(referencesProvider);
    // Premier chargement déjà en vol (déclenché par le `watch` du build) :
    // inutile de doubler la requête.
    if (current.isLoading && !current.hasValue) return;
    setState(() => _searchesInFlight++);
    try {
      await ref.read(referencesProvider.notifier).refreshSilencieux();
    } finally {
      if (mounted) setState(() => _searchesInFlight--);
    }
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _scanned = null;
    });
  }

  /// Bouton « Scanner un code » : lit un code (caméra à terme, saisie
  /// manuelle aujourd'hui), décode sa charge utile comme le ferait
  /// `parseQRCodeData()` du web, puis lance la recherche sur le nom de
  /// produit (à défaut le SKU, à défaut le code brut).
  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final scanned = ScannedCode.parse(code);
    setState(() => _scanned = scanned);
    _applyNow(scanned.searchTerm);
  }

  /// Rafraîchissement manuel du catalogue.
  ///
  /// AJOUT mobile assumé : le web relance un `GET /catalog/references/`
  /// complet à CHAQUE frappe débouncée (djangoClient.products.search filtre
  /// ensuite en JavaScript). Ici la liste est chargée une fois puis filtrée
  /// en local — d'où ce bouton (et le tirer-pour-rafraîchir) pour reprendre
  /// la main sur la fraîcheur des stocks. Aucune information n'est perdue,
  /// une action est simplement ajoutée.
  Future<void> _refresh() async {
    await ref.read(referencesProvider.notifier).refresh();
  }

  void _showError(Object error) {
    if (!mounted) return;
    // Web : `toast.error(err.message || 'Erreur lors de la recherche')`, les
    // résultats précédents restant affichés.
    final message = ApiClient.messageFromError(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.isEmpty ? 'Erreur lors de la recherche' : message)),
    );
  }

  /// `refs.filter(r => r.reference_name.toLowerCase().includes(q) ||
  /// (r.brand_name || '').toLowerCase().includes(q))` — contains, insensible
  /// à la casse, sans fuzzy ni repli sur les accents, et SANS trim (le web ne
  /// trime pas non plus la saisie).
  List<_ScannerProduct> _filter(List<ProductReference> refs, String query) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();
    return refs
        .where((r) =>
            r.referenceName.toLowerCase().contains(q) || r.brandName.toLowerCase().contains(q))
        .map(_ScannerProduct.fromReference)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Champ vide → AUCUN appel API, comme `search()` côté web qui sort
    // immédiatement quand la query est vide (`if (!q) { setResults([]); return; }`).
    final AsyncValue<List<ProductReference>> catalog = _query.isEmpty
        ? const AsyncValue<List<ProductReference>>.data(<ProductReference>[])
        : ref.watch(referencesProvider);

    if (_query.isNotEmpty) {
      ref.listen<AsyncValue<List<ProductReference>>>(referencesProvider, (previous, next) {
        if (next.hasError && !next.isLoading && previous?.error != next.error) {
          _showError(next.error!);
        }
      });
    }

    final products = _filter(catalog.value ?? const <ProductReference>[], _query);
    final rawText = _controller.text;
    // Web : bloc résultats rendu si `(query || results.length > 0)`, écran
    // « idle » si `(!query && results.length === 0)`.
    final showResults = rawText.isNotEmpty || products.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recherche produit'),
        actions: [
          IconButton(
            tooltip: 'Scanner un code',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scan,
          ),
          IconButton(
            tooltip: 'Actualiser le catalogue',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Text(
              'Recherchez une référence du catalogue par nom, marque ou modèle.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              // Web : `inputRef.current?.focus()` au montage — clavier ouvert
              // d'emblée.
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              // Le web n'a ni <form> ni gestion de la touche Entrée : on se
              // contente d'appliquer le terme sans attendre le debounce.
              onSubmitted: (value) => _applyNow(value),
              decoration: InputDecoration(
                hintText: 'Marque, référence...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: rawText.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scanner un code'),
              ),
            ),
            if (_scanned != null) ...[
              const SizedBox(height: 12),
              _ScannedCodeCard(
                scanned: _scanned!,
                onClear: () => setState(() => _scanned = null),
              ),
            ],
            const SizedBox(height: 16),
            if (showResults)
              _ResultsBlock(
                catalog: catalog,
                products: products,
                query: rawText,
                searching: _searching,
                onRetry: _refresh,
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: EmptyState(
                  message: 'Tapez pour rechercher un produit',
                  icon: Icons.qr_code_2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bloc résultats : porte les 4 états de la page web (chargement, erreur,
/// aucun résultat, liste).
class _ResultsBlock extends StatelessWidget {
  const _ResultsBlock({
    required this.catalog,
    required this.products,
    required this.query,
    required this.searching,
    required this.onRetry,
  });

  final AsyncValue<List<ProductReference>> catalog;
  final List<_ScannerProduct> products;
  final String query;

  /// Rechargement du catalogue en arrière-plan pour ce terme (web :
  /// `loading` pendant `products.search`) — la liste reste visible.
  final bool searching;

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    // Web : `loading ? <p>Recherche...</p>` — on garde le libellé, avec le
    // widget de chargement partagé du projet.
    if (catalog.isLoading && !catalog.hasValue) {
      return Column(
        children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: LoadingState()),
          Text('Recherche…', style: muted),
        ],
      );
    }

    // Le web se contente d'un toast et conserve les résultats précédents : on
    // ne bascule sur l'écran d'erreur que s'il n'y a rien à montrer.
    if (catalog.hasError && !catalog.hasValue) {
      return ErrorState(
        message: ApiClient.messageFromError(catalog.error!),
        onRetry: onRetry,
      );
    }

    // Recherche en cours sur des résultats déjà affichés : le libellé du web
    // (« Recherche... ») accompagne une barre de progression discrète.
    final searchingBanner = searching
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(child: LinearProgressIndicator(minHeight: 2)),
                const SizedBox(width: 8),
                Text('Recherche…', style: muted),
              ],
            ),
          )
        : null;

    if (products.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?searchingBanner,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              message: 'Aucun produit trouvé pour « $query »',
              icon: Icons.inventory_2_outlined,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?searchingBanner,
        Text(
          products.length > 1
              ? '${products.length} produits trouvés'
              : '${products.length} produit trouvé',
          style: muted,
        ),
        const SizedBox(height: 8),
        for (final product in products) _ProductCard(product: product),
      ],
    );
  }
}

/// Une carte de résultat — transposition mobile (une colonne) de la grille
/// `grid-cols-1 md:grid-cols-2 lg:grid-cols-3` du web. Toutes les
/// informations de la Card web sont présentes : nom, badge de stock, marque
/// en police mono, Catégorie, Stock, Prix vente, bouton « Créer une
/// commande ». Le détail par couleur est un ajout mobile (le web n'affiche
/// que l'agrégat).
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final _ScannerProduct product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = product.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(label: status.label, color: status.color),
              ],
            ),
            const SizedBox(height: 2),
            // Web : marque en `font-mono text-xs text-muted-foreground`.
            Text(
              product.brand.isEmpty ? '-' : product.brand,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Field(
                    label: 'Catégorie',
                    value: product.category.isEmpty ? '-' : product.category,
                  ),
                ),
                Expanded(
                  child: _Field(
                    label: 'Stock',
                    // Web : `{p.initial_quantity} u.` en font-semibold.
                    value: '${product.initialQuantity} u.',
                    strong: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Field(label: 'Prix vente', value: _ar(product.shellPrice)),
            if (product.variants.isNotEmpty) ...[
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(
                    'Détail des couleurs (${product.variants.length})',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  children: [
                    _Field(label: 'Sous-type', value: product.type.isEmpty ? '-' : product.type),
                    const SizedBox(height: 6),
                    _Field(
                      label: 'Description',
                      value: product.description.isEmpty ? '-' : product.description,
                    ),
                    const SizedBox(height: 6),
                    _Field(label: "Seuil d'alerte", value: '${product.alertThreshold}'),
                    const SizedBox(height: 10),
                    for (final variant in product.variants)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                variant.couleur.isEmpty ? 'Standard' : variant.couleur,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              '${variant.stockActuel} u.',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            StockLevelBadge(
                              isRupture: variant.isRupture,
                              isStockBas: variant.isStockBas,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                // Web : `<Link href="/orders">Créer une commande</Link>` —
                // navigation simple vers la liste des commandes, SANS
                // transmettre le produit sélectionné (aucun query param,
                // aucun state). Reproduit tel quel.
                onPressed: () => context.go('/orders'),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('Créer une commande'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Charge utile du dernier code lu — reprend les champs de
/// `generateQRCode()` / `parseQRCodeData()` (frontend/lib/qrcode-generator.ts).
class _ScannedCodeCard extends StatelessWidget {
  const _ScannedCodeCard({required this.scanned, required this.onClear});

  final ScannedCode scanned;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stamp = scanned.timestamp;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    scanned.isStructured ? 'QR produit lu' : 'Code lu',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Effacer le code lu',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                ),
              ],
            ),
            Text(
              scanned.raw,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (scanned.isStructured) ...[
              const SizedBox(height: 8),
              if (scanned.sku != null) _Field(label: 'SKU', value: scanned.sku!),
              if (scanned.productName != null) _Field(label: 'Produit', value: scanned.productName!),
              if (scanned.imageId != null) _Field(label: 'Image', value: scanned.imageId!),
              if (scanned.size != null) _Field(label: 'Taille', value: scanned.size!),
              if (scanned.colorVariant != null) _Field(label: 'Couleur', value: scanned.colorVariant!),
              if (stamp != null) _Field(label: 'Horodatage', value: _stampFmt.format(stamp)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cellule « libellé au-dessus, valeur en dessous » — la grille
/// `text-xs muted` + valeur de la Card web.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(
          value.trim().isEmpty ? '-' : value,
          style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w500),
        ),
      ],
    );
  }
}
