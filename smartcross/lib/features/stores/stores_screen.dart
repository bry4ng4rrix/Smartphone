import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/permissions.dart';
import '../../data/repositories/stores_repository.dart' show StoreCreateResult;
import '../../models/magasin.dart';
import '../../state/auth_provider.dart';
import '../../state/stores_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../transfers/transfers_screen.dart';

/// `formatNumber` (fr-FR) et `formatCurrency` (fr-MG + ' Ar') du web : les
/// deux locales produisent le même groupement des milliers.
final _numberFmt = NumberFormat.decimalPattern('fr_FR');
String _fmtNumber(num v) => _numberFmt.format(v.round());
String _fmtAr(num v) => '${_numberFmt.format(v.round())} Ar';

/// Page `/stores` du web (frontend/app/(app)/stores/page.tsx) — « Magasins ».
///
/// Grille de cartes, une par magasin de la société : gérant, KPI
/// (produits / unités, valeur de stock, ventes livrées, profit), premiers
/// employés. L'admin (`isAdmin` du web = rôle Django `admin`) peut créer un
/// magasin (+ son compte gérant), modifier nom/logo et transférer des
/// produits vers un autre magasin (écran `TransfersScreen` en mode dialog).
///
/// Gating : comme sur le web, pas d'écran « Accès refusé » — les actions
/// admin ne sont simplement pas rendues (l'entrée de menu et la route sont
/// de toute façon `superAdminOnly`, cf. core/nav_items.dart).
///
/// Rechargement : « Actualiser », création, modification, transfert et
/// suppression rechargent de façon NON silencieuse (skeletons) ; le temps
/// réel WebSocket (`useRealtimeRefresh(['product_variant','order'])`) et le
/// tirer-pour-rafraîchir sont silencieux (voir [StoresNotifier]).
class StoresScreen extends ConsumerStatefulWidget {
  const StoresScreen({super.key});

  @override
  ConsumerState<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends ConsumerState<StoresScreen> {
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// `fetchData()` NON silencieux (bouton « Actualiser »).
  Future<void> _refresh() => ref.read(storesProvider.notifier).refresh();

  /// Tirer-pour-rafraîchir : `fetchData(true)` — la grille reste affichée ;
  /// un échec est signalé (geste explicite de l'utilisateur).
  Future<void> _silentRefresh() async {
    final error = await ref.read(storesProvider.notifier).refreshSilencieux();
    if (error != null) _snack('Erreur lors du chargement.');
  }

  Future<void> _openCreate() async {
    final result = await showDialog<StoreCreateResult>(
      context: context,
      builder: (_) => const _CreateStoreDialog(),
    );
    if (result == null || !mounted) return;
    _snack('Magasin créé.');
    final approvalError = result.approvalError;
    if (approvalError != null) {
      // Le magasin existe mais le compte gérant n'a pas pu être approuvé :
      // il reste « en attente » (approuvable depuis Super Admin).
      _snack("Le compte gérant n'a pas pu être approuvé : $approvalError");
    }
  }

  Future<void> _openEdit(Magasin store) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditStoreDialog(store: store),
    );
    if (updated == true && mounted) _snack('Magasin mis à jour avec succès');
  }

  /// `TransferProductsDialog` : l'écran de transfert est poussé plein écran
  /// avec la source imposée ; à la réussite il recharge cette page et se
  /// ferme (« Transfert effectué » y est affiché).
  void _openTransfer(Magasin store) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TransfersScreen(preselectedSourceId: store.magasinId),
      ),
    );
  }

  /// Suppression (fonctionnalité Flutter conservée — le web ne l'expose pas
  /// sur cette page) : `DELETE /users/magasins/{id}/`, mot de passe exigé
  /// par le backend.
  Future<void> _confirmDelete(Magasin store) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _DeletePasswordDialog(shopName: store.shopName),
    );
    if (password == null || password.isEmpty) return;
    try {
      await ref.read(storesProvider.notifier).delete(store.magasinId, password);
      _snack('Magasin supprimé.');
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    // `toast.error('Erreur lors du chargement.')` d'un rechargement non
    // silencieux qui échoue : les cartes précédentes restent affichées.
    ref.listen<AsyncValue<List<Magasin>>>(storesProvider, (previous, next) {
      if (next.hasError && next.hasValue && !next.isLoading) _snack('Erreur lors du chargement.');
    });

    final async = ref.watch(storesProvider);
    final isAdmin = ref.watch(authProvider.select((a) => a.user?.isAdmin ?? false));
    final stores = async.value ?? const <Magasin>[];
    // `loading` du web : chargement initial et rechargements non silencieux
    // (le temps réel ne passe jamais par AsyncLoading).
    final loading = async.isLoading;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.storefront_outlined),
            SizedBox(width: 8),
            Text('Magasins'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 8,
              children: [
                Text(
                  '${stores.length} magasin(s)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isAdmin)
                      FilledButton(onPressed: _openCreate, child: const Text('Créer un magasin')),
                    OutlinedButton.icon(
                      onPressed: loading ? null : _refresh,
                      icon: _SpinningIcon(spinning: loading, icon: Icons.refresh),
                      label: const Text('Actualiser'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const _SkeletonGrid()
                : (async.hasError && !async.hasValue)
                    ? ErrorState(
                        message: 'Erreur lors du chargement. ${ApiClient.messageFromError(async.error!)}',
                        onRetry: _refresh,
                      )
                    : RefreshIndicator(
                        onRefresh: _silentRefresh,
                        child: _ResponsiveGrid(
                          itemCount: stores.length,
                          itemBuilder: (context, i) => _StoreCard(
                            store: stores[i],
                            isAdmin: isAdmin,
                            onTransfer: () => _openTransfer(stores[i]),
                            onEdit: () => _openEdit(stores[i]),
                            onDelete: () => _confirmDelete(stores[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Grille responsive (1 colonne / md:2 / lg:3, comme le web)
// -----------------------------------------------------------------------------

int _columnsFor(double width) => width >= 1024
    ? 3
    : width >= 768
        ? 2
        : 1;

/// Cartes de hauteur variable disposées en colonnes : un `Wrap` dans une
/// `ListView` toujours défilante (pour le tirer-pour-rafraîchir). Grille
/// vide = aucun état dédié, comme le web (le sous-titre affiche
/// « 0 magasin(s) »).
class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.itemCount, required this.itemBuilder});
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 16.0;
        const gap = 16.0;
        final columns = _columnsFor(constraints.maxWidth);
        final available = constraints.maxWidth - padding * 2;
        final cardWidth = ((available - gap * (columns - 1)) / columns).clamp(160.0, double.infinity);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(padding, 4, padding, 96),
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < itemCount; i++) SizedBox(width: cardWidth, child: itemBuilder(context, i)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// `Array.from({ length: 3 }).map(<Skeleton className="h-48 rounded-xl" />)`.
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ResponsiveGrid(
      itemCount: 3,
      itemBuilder: (context, i) => Container(
        height: 192,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

/// Icône `RefreshCw animate-spin` : tourne tant que [spinning] est vrai.
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.spinning, required this.icon});
  final bool spinning;
  final IconData icon;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _SpinningIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _controller, child: Icon(widget.icon, size: 18));
  }
}

/// Logo rond du magasin (`shop_logo`, URL absolue), icône « Store » en repli.
class _StoreLogo extends StatelessWidget {
  const _StoreLogo({required this.url});
  final String? url;

  static const double size = 20;

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.storefront_outlined, size: size);
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
// Carte magasin
// -----------------------------------------------------------------------------

class _StoreCard extends StatefulWidget {
  const _StoreCard({
    required this.store,
    required this.isAdmin,
    required this.onTransfer,
    required this.onEdit,
    required this.onDelete,
  });

  final Magasin store;
  final bool isAdmin;
  final VoidCallback onTransfer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<_StoreCard> {
  /// Le web n'affiche que les 3 premiers employés (`slice(0, 3)`) ; ici les
  /// suivants restent accessibles via « Voir les N autres ».
  bool _showAllEmployers = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final employers = store.employers;
    final visibleEmployers = _showAllEmployers ? employers : employers.take(3).toList();
    final hiddenCount = employers.length - visibleEmployers.length;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- En-tête : logo + nom + actions admin ----------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _StoreLogo(url: store.shopLogo),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (widget.isAdmin) ...[
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    tooltip: 'Transférer des produits',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.compare_arrows_outlined, size: 18),
                    onPressed: widget.onTransfer,
                  ),
                  IconButton.outlined(
                    tooltip: 'Modifier le magasin',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: widget.onEdit,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Plus d\'actions',
                    onSelected: (value) {
                      if (value == 'delete') widget.onDelete();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: scheme.error, size: 18),
                            const SizedBox(width: 8),
                            Text('Supprimer le magasin', style: TextStyle(color: scheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // ---- Bloc gérant (`store.manager`) -----------------------------
            if (store.hasManager) ...[
              Text(store.managerName ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
              if (store.managerEmail != null) Text(store.managerEmail!, style: muted),
              const Divider(height: 20),
            ],

            // ---- 4 tuiles KPI (grid 2 colonnes) ----------------------------
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _KpiTile(
                      label: 'Produits',
                      value: '${_fmtNumber(store.totalStockQuantityOrZero)} unité(s) sur '
                          '${_fmtNumber(store.totalProductsOrZero)} produits',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _KpiTile(label: 'Stock', value: _fmtAr(store.totalStockValueOrZero))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _KpiTile(label: 'Ventes', value: _fmtAr(store.totalSoldValueOrZero))),
                  const SizedBox(width: 8),
                  Expanded(child: _KpiTile(label: 'Profit', value: _fmtAr(store.profitOrZero), profit: true)),
                ],
              ),
            ),

            // ---- Employés ---------------------------------------------------
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.people_outline, size: 16),
                const SizedBox(width: 8),
                Text('Employés (${employers.length})', style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            if (visibleEmployers.isNotEmpty) const SizedBox(height: 8),
            for (final emp in visibleEmployers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(emp.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                    ),
                    const SizedBox(width: 8),
                    _OutlineBadge(label: emp.isConfirmed ? 'Actif' : 'Attente'),
                  ],
                ),
              ),
            if (hiddenCount > 0 || (_showAllEmployers && employers.length > 3))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => setState(() => _showAllEmployers = !_showAllEmployers),
                  child: Text(_showAllEmployers ? 'Réduire' : 'Voir les $hiddenCount autre(s)'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tuile KPI bordée (`border rounded-lg p-3`) ; [profit] = fond vert clair
/// + texte vert (bg-green-50 / text-green-700, adaptés au mode sombre).
class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value, this.profit = false});
  final String label;
  final String value;
  final bool profit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final background = profit ? (dark ? const Color(0xFF052E16).withValues(alpha: 0.5) : const Color(0xFFF0FDF4)) : null;
    final valueColor = profit ? (dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D)) : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: valueColor, height: 1.2)),
        ],
      ),
    );
  }
}

/// `<Badge variant="outline">` : même couleur pour « Actif » et « Attente »,
/// seul le libellé change.
class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
    );
  }
}

// -----------------------------------------------------------------------------
// Dialog « Nouveau magasin » (handleRegisterStore)
// -----------------------------------------------------------------------------

class _CreateStoreDialog extends ConsumerStatefulWidget {
  const _CreateStoreDialog();

  @override
  ConsumerState<_CreateStoreDialog> createState() => _CreateStoreDialogState();
}

class _CreateStoreDialogState extends ConsumerState<_CreateStoreDialog> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _managerNameController = TextEditingController();
  final _managerEmailController = TextEditingController();
  final _managerPasswordController = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _shopNameController.dispose();
    _managerNameController.dispose();
    _managerEmailController.dispose();
    _managerPasswordController.dispose();
    super.dispose();
  }

  /// Le web ne valide rien côté client ; le backend, lui, refuse un email
  /// invalide ou déjà pris. Les champs sont ici simplement requis.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref.read(storesProvider.notifier).create(
            shopName: _shopNameController.text.trim(),
            managerFullName: _managerNameController.text.trim(),
            managerEmail: _managerEmailController.text.trim(),
            managerPassword: _managerPasswordController.text,
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      // `toast.error(err?.message || 'Erreur lors de la création.')` — le
      // dialog reste ouvert, les champs ne sont pas vidés.
      if (mounted) setState(() => _error = _errorMessage(e, 'Erreur lors de la création.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Nouveau magasin'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ajouter un magasin', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _shopNameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nom du magasin'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nom du gérant'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerEmailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Requis'
                      : !v.contains('@')
                          ? 'Email invalide'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerPasswordController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _saving ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Afficher' : 'Masquer',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Création...'),
                          ],
                        )
                      : const Text('Créer'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dialog « Modifier le magasin » (handleUpdateStore)
// -----------------------------------------------------------------------------

class _EditStoreDialog extends ConsumerStatefulWidget {
  const _EditStoreDialog({required this.store});
  final Magasin store;

  @override
  ConsumerState<_EditStoreDialog> createState() => _EditStoreDialogState();
}

class _EditStoreDialogState extends ConsumerState<_EditStoreDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.store.shopName);
  XFile? _logoFile;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// `<input type="file" accept="image/*">` : galerie ou appareil photo.
  Future<void> _pickLogo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);
      if (file != null && mounted) setState(() => _logoFile = file);
    } catch (e) {
      if (mounted) setState(() => _error = "Impossible de sélectionner l'image : ${ApiClient.messageFromError(e)}");
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(storesProvider.notifier).updateStore(
            widget.store.magasinId,
            shopName: _nameController.text.trim(),
            logoPath: _logoFile?.path,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // `toast.error(err.message || 'Erreur lors de la mise à jour')`.
      if (mounted) setState(() => _error = _errorMessage(e, 'Erreur lors de la mise à jour'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final existingLogo = widget.store.shopLogo;
    final hasPreview = _logoFile != null || (existingLogo != null && existingLogo.isNotEmpty);

    return AlertDialog(
      title: const Text('Modifier le magasin'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Modifier le nom et le logo du magasin.', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _saving ? null : _submit(),
                  decoration: const InputDecoration(labelText: 'Nom du magasin'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                Text('Logo du magasin', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickLogo,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(_logoFile == null ? 'Choisir une image' : 'Changer l\'image'),
                      ),
                    ),
                    if (_logoFile != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Retirer l\'image choisie',
                        icon: const Icon(Icons.close),
                        onPressed: _saving ? null : () => setState(() => _logoFile = null),
                      ),
                    ],
                  ],
                ),
                if (_logoFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _logoFile!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (hasPreview) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _logoFile != null
                          ? Image.file(File(_logoFile!.path), fit: BoxFit.contain)
                          : Image.network(
                              existingLogo!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stack) => const Icon(Icons.storefront_outlined),
                            ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Enregistrement...'),
                          ],
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dialog de suppression (mot de passe exigé par le backend)
// -----------------------------------------------------------------------------

class _DeletePasswordDialog extends StatefulWidget {
  const _DeletePasswordDialog({required this.shopName});
  final String shopName;

  @override
  State<_DeletePasswordDialog> createState() => _DeletePasswordDialogState();
}

class _DeletePasswordDialogState extends State<_DeletePasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirmer la suppression'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Supprimer le magasin « ${widget.shopName} » ? Entrez votre mot de passe pour confirmer.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            onSubmitted: (_) => Navigator.of(context).pop(_controller.text),
            decoration: InputDecoration(
              labelText: 'Votre mot de passe',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Afficher' : 'Masquer',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          child: const Text('Supprimer'),
        ),
      ],
    );
  }
}

/// `err.message || fallback` : le détail renvoyé par le serveur quand il
/// existe (ex : « admin_email: Administrateur introuvable avec cet
/// email. »), sinon le message générique du web.
String _errorMessage(Object error, String fallback) {
  final message = ApiClient.messageFromError(error).trim();
  return message.isEmpty ? fallback : message;
}
