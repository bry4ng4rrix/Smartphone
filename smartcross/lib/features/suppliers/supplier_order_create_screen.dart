import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/catalog.dart';
import '../../models/supplier.dart';
import '../../state/catalog_provider.dart';
import '../../state/suppliers_provider.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';

class _Line {
  _Line({required this.variant, required this.quantite});
  final ProductVariant variant;
  int quantite;
}

/// Formulaire Commande Fournisseur (§7.6 README) : coût total = fournisseur
/// + fret + douane + pub, réparti automatiquement sur chaque ligne côté
/// serveur — le client n'affiche qu'une estimation.
class SupplierOrderCreateScreen extends ConsumerStatefulWidget {
  const SupplierOrderCreateScreen({super.key});

  @override
  ConsumerState<SupplierOrderCreateScreen> createState() => _SupplierOrderCreateScreenState();
}

class _SupplierOrderCreateScreenState extends ConsumerState<SupplierOrderCreateScreen> {
  final _descController = TextEditingController();
  final _prixController = TextEditingController(text: '0');
  final _fretController = TextEditingController(text: '0');
  final _douaneController = TextEditingController(text: '0');
  final _adsController = TextEditingController(text: '0');
  final List<_Line> _lines = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _descController.dispose();
    _prixController.dispose();
    _fretController.dispose();
    _douaneController.dispose();
    _adsController.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  int get _totalQty => _lines.fold(0, (sum, l) => sum + l.quantite);
  double get _coutEstime => _num(_prixController) + _num(_fretController) + _num(_douaneController) + _num(_adsController);

  Future<void> _addLine() async {
    final references = ref.read(referencesProvider).value ?? [];
    final variants = <ProductVariant>[for (final r in references) ...r.variants];
    final selected = await showDialog<ProductVariant>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choisir un produit'),
        children: [
          SizedBox(
            width: 380,
            height: 400,
            child: variants.isEmpty
                ? const Center(child: Text('Aucune variante disponible.'))
                : ListView.builder(
                    itemCount: variants.length,
                    itemBuilder: (context, i) {
                      final v = variants[i];
                      return ListTile(title: Text(v.label), onTap: () => Navigator.of(context).pop(v));
                    },
                  ),
          ),
        ],
      ),
    );
    if (selected != null) setState(() => _lines.add(_Line(variant: selected, quantite: 1)));
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'Ajoutez au moins une ligne.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final order = await ref.read(supplierOrdersProvider.notifier).create(
            description: _descController.text.trim(),
            prixFournisseur: _num(_prixController),
            fretImport: _num(_fretController),
            douane: _num(_douaneController),
            metaAds: _num(_adsController),
            lines: [for (final l in _lines) SupplierOrderLineDraft(productVariant: l.variant.id, quantite: l.quantite)],
          );
      if (mounted) context.go('/suppliers/${order.id}');
    } catch (e) {
      setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle commande fournisseur')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
            const SizedBox(height: 16),
          ],
          TextField(controller: _descController, decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.notes_outlined))),
          const SizedBox(height: 14),
          TextField(
            controller: _prixController,
            decoration: const InputDecoration(labelText: 'Prix fournisseur (Ar)', prefixIcon: Icon(Icons.sell_outlined)),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _fretController,
            decoration: const InputDecoration(labelText: 'Fret / import (Ar)', prefixIcon: Icon(Icons.flight_outlined)),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _douaneController,
            decoration: const InputDecoration(labelText: 'Douane (Ar)', prefixIcon: Icon(Icons.gavel_outlined)),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _adsController,
            decoration: const InputDecoration(labelText: 'Budget pub Meta Ads (Ar)', prefixIcon: Icon(Icons.campaign_outlined)),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Lignes', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Ajouter')),
            ],
          ),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Aucune ligne — utilisez "Ajouter".', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final l in _lines)
                    ListTile(
                      title: Text(l.variant.label),
                      subtitle: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            onPressed: l.quantite > 1 ? () => setState(() => l.quantite--) : null,
                          ),
                          Text('${l.quantite}'),
                          IconButton(icon: const Icon(Icons.add_circle_outline, size: 18), onPressed: () => setState(() => l.quantite++)),
                        ],
                      ),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _lines.remove(l))),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Quantité totale'), Text('$_totalQty')]),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Coût total estimé', style: Theme.of(context).textTheme.titleMedium),
                      Text(_ar(_coutEstime), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Créer la commande'),
          ),
        ],
      ),
    );
  }
}
