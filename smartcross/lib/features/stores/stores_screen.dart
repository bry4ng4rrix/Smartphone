import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/magasin.dart';
import '../../state/stores_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../transfers/transfers_screen.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

/// Module "Magasins" (§8 Smartreadme.md) — vue d'ensemble multi-magasin,
/// réservée à l'admin propriétaire de plusieurs magasins. Un gérant
/// mono-magasin voit ici sa seule boutique (le backend ne renvoie que ce
/// qu'il est autorisé à voir, `UsersByMagasinView`/`MagasinViewSet`).
class StoresScreen extends ConsumerWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Magasins')),
      body: switch (async) {
        AsyncData(:final value) => value.isEmpty
            ? const EmptyState(message: 'Aucun magasin.', icon: Icons.storefront_outlined)
            : RefreshIndicator(
                onRefresh: () => ref.read(storesProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _StoreCard(store: value[i], allStores: value),
                ),
              ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(storesProvider.notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const _CreateStoreDialog()),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Magasin'),
      ),
    );
  }
}

class _StoreCard extends ConsumerWidget {
  const _StoreCard({required this.store, required this.allStores});
  final Magasin store;
  final List<Magasin> allStores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherStores = allStores.where((m) => m.magasinId != store.magasinId).toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(store.shopName.isNotEmpty ? store.shopName[0].toUpperCase() : '?')),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.shopName, style: Theme.of(context).textTheme.titleMedium),
                      if (store.managerName != null) Text('Gérant : ${store.managerName}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Transférer du stock',
                  icon: const Icon(Icons.compare_arrows_outlined),
                  onPressed: otherStores.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => TransfersScreen(preselectedSourceId: store.magasinId)),
                          ),
                ),
                IconButton(
                  tooltip: 'Renommer',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => showDialog<void>(context: context, builder: (_) => _RenameStoreDialog(store: store)),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, store),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _StatChip(label: 'Produits', value: '${store.totalProducts ?? '—'}'),
                _StatChip(label: 'Stock', value: '${store.totalStockQuantity ?? '—'}'),
                _StatChip(label: 'Valeur stock', value: store.totalStockValue != null ? _ar(store.totalStockValue!) : '—'),
                _StatChip(label: 'Ventes', value: store.totalSoldValue != null ? _ar(store.totalSoldValue!) : '—'),
                _StatChip(
                  label: 'Bénéfice',
                  value: store.profit != null ? _ar(store.profit!) : '—',
                  color: (store.profit ?? 0) > 0 ? Colors.green : null,
                ),
              ],
            ),
            if (store.employers.isNotEmpty) ...[
              const Divider(height: 20),
              Text('Équipe', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final e in store.employers)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(e.isConfirmed ? Icons.check_circle_outline : Icons.hourglass_empty, size: 16, color: e.isConfirmed ? Colors.green : Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${e.fullName} · ${e.position ?? e.commandeRole ?? ''}', style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Magasin store) async {
    final password = await showDialog<String>(context: context, builder: (_) => _DeletePasswordDialog(shopName: store.shopName));
    if (password == null || password.isEmpty) return;
    try {
      await ref.read(storesProvider.notifier).delete(store.magasinId, password);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }
}

class _DeletePasswordDialog extends StatefulWidget {
  const _DeletePasswordDialog({required this.shopName});
  final String shopName;

  @override
  State<_DeletePasswordDialog> createState() => _DeletePasswordDialogState();
}

class _DeletePasswordDialogState extends State<_DeletePasswordDialog> {
  final _controller = TextEditingController();

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
        children: [
          Text('Supprimer le magasin "${widget.shopName}" ? Entrez votre mot de passe pour confirmer.'),
          const SizedBox(height: 12),
          TextField(controller: _controller, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Votre mot de passe')),
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

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
  String? _error;

  @override
  void dispose() {
    _shopNameController.dispose();
    _managerNameController.dispose();
    _managerEmailController.dispose();
    _managerPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(storesProvider.notifier).create(
            shopName: _shopNameController.text.trim(),
            managerFullName: _managerNameController.text.trim(),
            managerEmail: _managerEmailController.text.trim(),
            managerPassword: _managerPasswordController.text,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer un magasin'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _shopNameController,
                  decoration: const InputDecoration(labelText: 'Nom du magasin'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerNameController,
                  decoration: const InputDecoration(labelText: 'Nom du gérant'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerEmailController,
                  decoration: const InputDecoration(labelText: 'Email du gérant'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@')) ? 'Email invalide' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerPasswordController,
                  decoration: const InputDecoration(labelText: 'Mot de passe du gérant'),
                  obscureText: true,
                  validator: (v) => (v == null || v.length < 6) ? '6 caractères minimum' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Créer')),
      ],
    );
  }
}

class _RenameStoreDialog extends ConsumerStatefulWidget {
  const _RenameStoreDialog({required this.store});
  final Magasin store;

  @override
  ConsumerState<_RenameStoreDialog> createState() => _RenameStoreDialogState();
}

class _RenameStoreDialogState extends ConsumerState<_RenameStoreDialog> {
  late final _controller = TextEditingController(text: widget.store.shopName);
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(storesProvider.notifier).rename(widget.store.magasinId, _controller.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renommer le magasin'),
      content: TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Nom du magasin'), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
