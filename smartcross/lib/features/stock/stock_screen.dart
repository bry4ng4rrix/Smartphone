import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/catalog.dart';
import '../../models/stock.dart';
import '../../state/catalog_provider.dart';
import '../../state/stock_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Module Stock (§7.4/7.5 README) : ruptures/réapprovisionnement et
/// historique des mouvements. Le stock lui-même n'est jamais modifié
/// directement ici — uniquement via mouvements tracés (entrée/sortie).
class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stock'),
          bottom: const TabBar(tabs: [Tab(text: 'Ruptures'), Tab(text: 'Mouvements')]),
        ),
        body: const TabBarView(children: [_RupturesTab(), _MovementsTab()]),
      ),
    );
  }
}

class _RupturesTab extends ConsumerWidget {
  const _RupturesTab();

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(stockRepositoryProvider).ruptureExportPdfBytes();
      final file = XFile.fromData(bytes, name: 'reapprovisionnement.pdf', mimeType: 'application/pdf');
      await SharePlus.instance.share(ShareParams(files: [file], text: 'Liste de réapprovisionnement'));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rupturesProvider);

    return Scaffold(
      body: switch (async) {
        AsyncData(:final value) => value.isEmpty
            ? const EmptyState(message: 'Aucune rupture ni stock bas.', icon: Icons.check_circle_outline)
            : RefreshIndicator(
                onRefresh: () => ref.read(rupturesProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _RuptureTile(item: value[i]),
                ),
              ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(rupturesProvider.notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
      floatingActionButton: (async.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _exportPdf(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exporter PDF'),
            )
          : null,
    );
  }
}

class _RuptureTile extends ConsumerWidget {
  const _RuptureTile({required this.item});
  final RuptureItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text('${item.brandName} ${item.referenceName} — ${item.couleur}'),
        subtitle: Text('${item.categoryName} / ${item.typeName} · Stock : ${item.stockActuel} · Seuil : ${item.seuilAlerte}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StockLevelBadge(isRupture: item.isRupture, isStockBas: !item.isRupture),
            IconButton(
              tooltip: 'Ajuster le stock',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _AdjustDialog(variantId: item.id, label: '${item.brandName} ${item.referenceName} — ${item.couleur}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementsTab extends ConsumerWidget {
  const _MovementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movementsProvider(null));

    return Scaffold(
      body: switch (async) {
        AsyncData(:final value) => value.isEmpty
            ? const EmptyState(message: 'Aucun mouvement de stock.', icon: Icons.sync_alt)
            : RefreshIndicator(
                onRefresh: () => ref.read(movementsProvider(null).notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: value.length,
                  itemBuilder: (context, i) => _MovementTile(movement: value[i]),
                ),
              ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(movementsProvider(null).notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const _AdjustDialogWithPicker()),
        icon: const Icon(Icons.add),
        label: const Text('Ajustement'),
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});
  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final isEntree = movement.type == StockMovementType.entree;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isEntree ? Colors.green : Colors.red).withValues(alpha: 0.15),
          child: Icon(isEntree ? Icons.arrow_downward : Icons.arrow_upward, color: isEntree ? Colors.green : Colors.red, size: 18),
        ),
        title: Text(movement.variantLabel),
        subtitle: Text(
          '${movement.type.label} de ${movement.quantite} · ${movement.origine}'
          '${movement.note != null && movement.note!.isNotEmpty ? ' · ${movement.note}' : ''}'
          '${movement.timestamp != null ? '\n${_dateFmt.format(movement.timestamp!)}' : ''}'
          '${movement.userName != null ? ' · ${movement.userName}' : ''}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// Ajustement manuel pré-rempli pour une variante connue (depuis l'onglet
/// Ruptures — §7.4 README : réservé au gérant).
class _AdjustDialog extends ConsumerStatefulWidget {
  const _AdjustDialog({required this.variantId, required this.label});
  final int variantId;
  final String label;

  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog> {
  StockMovementType _type = StockMovementType.entree;
  final _qtyController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(stockRepositoryProvider).adjust(
            productVariantId: widget.variantId,
            type: _type.apiValue,
            quantite: qty,
            note: _noteController.text.trim(),
          );
      ref.invalidate(rupturesProvider);
      ref.invalidate(movementsProvider(null));
      ref.invalidate(referencesProvider);
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
      title: Text('Ajuster : ${widget.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<StockMovementType>(
            segments: const [
              ButtonSegment(value: StockMovementType.entree, label: Text('Entrée')),
              ButtonSegment(value: StockMovementType.sortie, label: Text('Sortie')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: _qtyController, decoration: const InputDecoration(labelText: 'Quantité'), keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note (optionnel)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// Même dialog, mais avec un sélecteur de variante (accès depuis l'onglet
/// Mouvements, sans variante pré-sélectionnée).
class _AdjustDialogWithPicker extends ConsumerStatefulWidget {
  const _AdjustDialogWithPicker();

  @override
  ConsumerState<_AdjustDialogWithPicker> createState() => _AdjustDialogWithPickerState();
}

class _AdjustDialogWithPickerState extends ConsumerState<_AdjustDialogWithPicker> {
  ProductVariant? _variant;

  @override
  Widget build(BuildContext context) {
    final references = ref.watch(referencesProvider).value ?? [];
    final variants = <ProductVariant>[for (final r in references) ...r.variants];

    if (_variant == null) {
      return AlertDialog(
        title: const Text('Choisir un produit'),
        content: SizedBox(
          width: 380,
          height: 400,
          child: variants.isEmpty
              ? const Center(child: Text('Aucune variante disponible.'))
              : ListView.builder(
                  itemCount: variants.length,
                  itemBuilder: (context, i) {
                    final v = variants[i];
                    return ListTile(
                      title: Text(v.label),
                      subtitle: Text('Stock actuel : ${v.stockActuel}'),
                      onTap: () => setState(() => _variant = v),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler'))],
      );
    }

    return _AdjustDialog(variantId: _variant!.id, label: _variant!.label);
  }
}
