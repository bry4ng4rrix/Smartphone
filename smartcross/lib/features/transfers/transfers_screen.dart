import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../data/repositories/stores_repository.dart';
import '../../models/catalog.dart';
import '../../models/magasin.dart';
import '../../state/stores_provider.dart';
import '../../widgets/async_state_widgets.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

/// Module "Transferts" (§8 Smartreadme.md) — déplace du stock d'un magasin
/// vers un autre, par variante (couleur). Réservé à l'admin propriétaire de
/// plusieurs magasins (le backend refuse sinon, `TransferProductsView`).
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key, this.preselectedSourceId});
  final int? preselectedSourceId;

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  int? _sourceId;
  int? _destinationId;
  final Map<int, int> _quantities = {}; // variantId -> qty
  final Map<int, String> _labels = {};
  final Map<int, int> _available = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _sourceId = widget.preselectedSourceId;
  }

  Future<void> _submit(List<Magasin> stores) async {
    if (_sourceId == null || _destinationId == null || _quantities.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(storesRepositoryProvider).transfer(
            sourceMagasinId: _sourceId!,
            destinationMagasinId: _destinationId!,
            items: [
              for (final entry in _quantities.entries)
                if (entry.value > 0) TransferItem(variantId: entry.key, quantity: entry.value, label: _labels[entry.key] ?? ''),
            ],
          );
      ref.invalidate(storesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transfert effectué')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(storesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transfert de stock')),
      body: switch (storesAsync) {
        AsyncData(value: final stores) => stores.length < 2
            ? const EmptyState(message: 'Il faut au moins deux magasins pour transférer du stock.', icon: Icons.compare_arrows_outlined)
            : _buildBody(stores),
        AsyncError(:final error) => ErrorState(message: ApiClient.messageFromError(error), onRetry: () => ref.read(storesProvider.notifier).refresh()),
        _ => const LoadingState(),
      },
    );
  }

  Widget _buildBody(List<Magasin> stores) {
    _sourceId ??= stores.first.magasinId;
    final destinations = stores.where((m) => m.magasinId != _sourceId).toList();
    if (_destinationId == null && destinations.isNotEmpty) _destinationId = destinations.first.magasinId;
    if (_destinationId != null && !destinations.any((m) => m.magasinId == _destinationId)) {
      _destinationId = destinations.isNotEmpty ? destinations.first.magasinId : null;
    }

    final cartCount = _quantities.values.where((q) => q > 0).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _sourceId,
                  decoration: const InputDecoration(labelText: 'Depuis', isDense: true),
                  items: [for (final m in stores) DropdownMenuItem(value: m.magasinId, child: Text(m.shopName, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() {
                    _sourceId = v;
                    _quantities.clear();
                    _labels.clear();
                    _available.clear();
                  }),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _destinationId,
                  decoration: const InputDecoration(labelText: 'Vers', isDense: true),
                  items: [for (final m in destinations) DropdownMenuItem(value: m.magasinId, child: Text(m.shopName, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _destinationId = v),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _ProductPicker(magasinId: _sourceId!, quantities: _quantities, labels: _labels, available: _available, onChanged: () => setState(() {})),
        ),
        if (cartCount > 0)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_submitting || _destinationId == null) ? null : () => _submit(stores),
                icon: const Icon(Icons.compare_arrows_outlined),
                label: Text(_submitting ? 'Transfert…' : 'Transférer ($cartCount)'),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({
    required this.magasinId,
    required this.quantities,
    required this.labels,
    required this.available,
    required this.onChanged,
  });
  final int magasinId;
  final Map<int, int> quantities;
  final Map<int, String> labels;
  final Map<int, int> available;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  late Future<List<ProductReference>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(storesRepositoryProvider).catalogFor(widget.magasinId);
  }

  @override
  void didUpdateWidget(covariant _ProductPicker old) {
    super.didUpdateWidget(old);
    if (old.magasinId != widget.magasinId) {
      _future = ref.read(storesRepositoryProvider).catalogFor(widget.magasinId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProductReference>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingState();
        if (snapshot.hasError) return ErrorState(message: ApiClient.messageFromError(snapshot.error!), onRetry: () {});
        final references = snapshot.data ?? [];
        if (references.isEmpty) return const EmptyState(message: 'Aucun produit dans ce magasin.', icon: Icons.style_outlined);

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: references.length,
          itemBuilder: (context, i) {
            final ref = references[i];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                title: Text('${ref.brandName} ${ref.referenceName}'),
                subtitle: Text('${ref.categoryName} / ${ref.typeName} — ${_ar(ref.prixVente)}'),
                children: [
                  for (final v in ref.variants)
                    _VariantRow(
                      label: '${ref.referenceName} (${v.couleur})',
                      variantId: v.id,
                      stockActuel: v.stockActuel,
                      quantities: widget.quantities,
                      labels: widget.labels,
                      available: widget.available,
                      onChanged: widget.onChanged,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _VariantRow extends StatefulWidget {
  const _VariantRow({
    required this.label,
    required this.variantId,
    required this.stockActuel,
    required this.quantities,
    required this.labels,
    required this.available,
    required this.onChanged,
  });
  final String label;
  final int variantId;
  final int stockActuel;
  final Map<int, int> quantities;
  final Map<int, String> labels;
  final Map<int, int> available;
  final VoidCallback onChanged;

  @override
  State<_VariantRow> createState() => _VariantRowState();
}

class _VariantRowState extends State<_VariantRow> {
  late final _controller = TextEditingController(text: widget.quantities[widget.variantId]?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String text) {
    final qty = int.tryParse(text) ?? 0;
    final clamped = qty.clamp(0, widget.stockActuel);
    widget.available[widget.variantId] = widget.stockActuel;
    widget.labels[widget.variantId] = widget.label;
    if (clamped <= 0) {
      widget.quantities.remove(widget.variantId);
    } else {
      widget.quantities[widget.variantId] = clamped;
    }
    if (clamped != qty) {
      _controller.value = TextEditingValue(text: clamped == 0 ? '' : clamped.toString(), selection: TextSelection.collapsed(offset: clamped.toString().length));
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(widget.label),
      subtitle: Text('Disponible : ${widget.stockActuel}'),
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          enabled: widget.stockActuel > 0,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: '0'),
          onChanged: _apply,
        ),
      ),
    );
  }
}
