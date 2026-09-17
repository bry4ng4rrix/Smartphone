import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/supplier.dart';
import '../../state/suppliers_provider.dart';
import 'supplier_status.dart';

/// Fiche fournisseur (création / modification) — miroir de
/// `components/suppliers/supplier-form-dialog.tsx`. Renvoie `true` si
/// enregistré.
class SupplierFormDialog extends ConsumerStatefulWidget {
  const SupplierFormDialog({super.key, this.supplier});
  final Supplier? supplier;

  @override
  ConsumerState<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends ConsumerState<SupplierFormDialog> {
  late final _nom = TextEditingController(text: widget.supplier?.nom ?? '');
  late final _pays = TextEditingController(text: widget.supplier?.pays ?? 'Chine');
  late final _contact = TextEditingController(text: widget.supplier?.contact ?? '');
  late final _telephone = TextEditingController(text: widget.supplier?.telephone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _adresse = TextEditingController(text: widget.supplier?.adresse ?? '');
  late final _notes = TextEditingController(text: widget.supplier?.notes ?? '');
  late String _devise = widget.supplier?.devise ?? 'USD';
  late bool _actif = widget.supplier?.actif ?? true;
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in [_nom, _pays, _contact, _telephone, _email, _adresse, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nom.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le nom est requis.')));
      return;
    }
    setState(() => _submitting = true);
    final data = {
      'nom': _nom.text.trim(),
      'pays': _pays.text.trim(),
      'contact': _contact.text.trim(),
      'telephone': _telephone.text.trim(),
      'email': _email.text.trim(),
      'adresse': _adresse.text.trim(),
      'notes': _notes.text.trim(),
      'devise': _devise,
      'actif': _actif,
    };
    try {
      final repo = ref.read(suppliersRepositoryProvider);
      if (widget.supplier == null) {
        await repo.supplierCreate(data);
      } else {
        await repo.supplierUpdate(widget.supplier!.id, data);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget champ(TextEditingController c, String label, {TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label, isDense: true)),
        );
    return AlertDialog(
      title: Text(widget.supplier == null ? 'Nouveau fournisseur' : 'Modifier ${widget.supplier!.nom}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              champ(_nom, 'Nom *'),
              champ(_pays, 'Pays'),
              champ(_contact, 'Contact'),
              champ(_telephone, 'Téléphone', type: TextInputType.phone),
              champ(_email, 'E-mail', type: TextInputType.emailAddress),
              champ(_adresse, 'Adresse'),
              champ(_notes, 'Notes'),
              DropdownButtonFormField<String>(
                initialValue: _devise,
                decoration: const InputDecoration(labelText: 'Devise habituelle', isDense: true),
                items: [for (final d in kDevises) DropdownMenuItem(value: d.value, child: Text(d.label))],
                onChanged: (v) => setState(() => _devise = v ?? 'USD'),
              ),
              if (widget.supplier != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fournisseur actif'),
                  value: _actif,
                  onChanged: (v) => setState(() => _actif = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
