import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/permissions.dart';
import '../../models/catalog.dart';
import '../../models/magasin.dart';
import '../../models/supplier.dart';
import '../../state/auth_provider.dart';
import '../../state/stores_provider.dart';
import '../../state/suppliers_provider.dart';
import 'supplier_status.dart';

/// Nouvel approvisionnement (§ 3) : UN fournisseur, UN produit (référence +
/// couleur), UNE quantité, la devise et le montant total prévu. Les
/// paiements, le transport et les frais se saisissent ensuite sur la fiche.
/// Renvoie l'id de l'approvisionnement créé (`context.pop(id)`).
class SupplierOrderCreateScreen extends ConsumerStatefulWidget {
  const SupplierOrderCreateScreen({super.key, this.supplierInitial});
  final Supplier? supplierInitial;

  @override
  ConsumerState<SupplierOrderCreateScreen> createState() => _SupplierOrderCreateScreenState();
}

class _SupplierOrderCreateScreenState extends ConsumerState<SupplierOrderCreateScreen> {
  final _search = TextEditingController();
  final _quantite = TextEditingController();
  final _montantPrevu = TextEditingController();
  final _description = TextEditingController();
  int? _supplierId;
  late String _devise = widget.supplierInitial?.devise ?? 'USD';
  int? _magasinId;
  List<ReferenceOption> _suggestions = const [];
  ReferenceOption? _reference;
  int? _variantId;
  bool _searching = false;
  Timer? _debounce;
  String? _submitting;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.supplierInitial?.id;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _quantite.dispose();
    _montantPrevu.dispose();
    _description.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _suggestions = const []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final list = await ref.read(suppliersRepositoryProvider).autocomplete(q.trim(), magasinId: _magasinId);
        if (mounted) setState(() { _suggestions = list; _searching = false; });
      } catch (_) {
        if (mounted) setState(() { _suggestions = const []; _searching = false; });
      }
    });
  }

  Future<void> _submit(String statut, {required bool needsMagasin}) async {
    final variantId = _variantId;
    if (_reference == null || variantId == null) { _snack('Choisissez le produit (référence + couleur).'); return; }
    final q = int.tryParse(_quantite.text.trim()) ?? 0;
    if (q < 1) { _snack('Indiquez la quantité de pièces.'); return; }
    if (needsMagasin && _magasinId == null) { _snack('Choisissez le magasin destinataire.'); return; }
    setState(() => _submitting = statut);
    try {
      final order = await ref.read(suppliersRepositoryProvider).create(
            supplierId: _supplierId,
            productVariantId: variantId,
            quantite: q,
            devise: _devise,
            montantPrevu: double.tryParse(_montantPrevu.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0,
            description: _description.text.trim(),
            statut: statut,
            magasinId: _magasinId,
          );
      ref.read(supplierOrdersProvider.notifier).refreshSilencieux();
      ref.invalidate(supplierKpisProvider);
      if (!mounted) return;
      _snack('Approvisionnement ${order.numero} créé');
      context.pop(order.id);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = null);
        _snack(ApiClient.messageFromError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authProvider).user;
    final needsMagasin = user != null && user.isAdmin && user.magasinId == null;
    final stores = needsMagasin ? (ref.watch(storesProvider).value ?? const <Magasin>[]) : const <Magasin>[];
    if (needsMagasin && _magasinId == null && stores.length == 1) _magasinId = stores.first.magasinId;
    final suppliers = ref.watch(suppliersListProvider).value ?? const <Supplier>[];
    final couleurs = _reference?.couleurs ?? const <ColorOption>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel approvisionnement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('Un approvisionnement = un fournisseur, un produit, une quantité. Pour un autre produit, créez un autre approvisionnement.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          if (needsMagasin) ...[
            DropdownButtonFormField<int>(
              initialValue: _magasinId,
              decoration: const InputDecoration(labelText: 'Magasin destinataire'),
              items: [for (final m in stores) DropdownMenuItem(value: m.magasinId, child: Text(m.shopName))],
              onChanged: (v) => setState(() { _magasinId = v; _reference = null; _variantId = null; _suggestions = const []; }),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<int?>(
            initialValue: _supplierId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Fournisseur'),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Sans fournisseur —')),
              for (final s in suppliers.where((s) => s.actif || s.id == _supplierId))
                DropdownMenuItem(value: s.id, child: Text('${s.nom}${s.pays.isNotEmpty ? ' · ${s.pays}' : ''}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _supplierId = v;
              final s = suppliers.where((x) => x.id == v).firstOrNull;
              if (s != null) _devise = s.devise;
            }),
          ),
          const SizedBox(height: 16),
          Text('PRODUIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (_reference == null) ...[
            TextField(
              controller: _search,
              onChanged: _onSearch,
              decoration: InputDecoration(
                labelText: 'Rechercher une référence',
                hintText: 'Ex : A15',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
            ),
            for (final r in _suggestions)
              ListTile(
                dense: true,
                title: Text('${r.brandName} ${r.referenceName}'),
                subtitle: Text('${r.typeName} · vente ${fmtAr(r.prixVente)}'),
                onTap: () => setState(() {
                  _reference = r;
                  _variantId = r.couleurs.length == 1 ? r.couleurs.first.variantId : null;
                  _suggestions = const [];
                }),
              ),
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${_reference!.brandName} ${_reference!.referenceName}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${_reference!.typeName} · prix de vente ${fmtAr(_reference!.prixVente)}'),
              trailing: TextButton(onPressed: () => setState(() { _reference = null; _variantId = null; _search.clear(); }), child: const Text('Changer')),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('variant-${_reference?.id}-$_variantId'),
                  initialValue: _variantId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Couleur / variante'),
                  items: [for (final c in couleurs) DropdownMenuItem(value: c.variantId, child: Text('${c.couleur} · stock ${c.stockActuel}', overflow: TextOverflow.ellipsis))],
                  onChanged: _reference == null ? null : (v) => setState(() => _variantId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _quantite,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantité (pièces)', hintText: 'Ex : 100'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('devise-$_devise'),
                  initialValue: _devise,
                  decoration: const InputDecoration(labelText: 'Devise du fournisseur'),
                  items: [for (final d in kDevises) DropdownMenuItem(value: d.value, child: Text(d.label, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _devise = v ?? 'USD'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _montantPrevu,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Montant prévu ($_devise)', hintText: 'Ex : 2000'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _description, decoration: const InputDecoration(labelText: 'Description', hintText: 'Ex : Envoi #001 — Coques iPhone')),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting != null ? null : () => _submit('BROUILLON', needsMagasin: needsMagasin),
                  child: _submitting == 'BROUILLON' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Brouillon'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _submitting != null ? null : () => _submit('COMMANDE', needsMagasin: needsMagasin),
                  child: _submitting == 'COMMANDE' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer la commande'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
