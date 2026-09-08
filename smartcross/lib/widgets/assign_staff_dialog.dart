import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repositories/orders_repository.dart';

/// Résultat de l'affectation choisie par le gérant : la personne désignée et
/// une heure manuelle optionnelle (§ demande — sélection + heure manuelles).
class AssignResult {
  const AssignResult({required this.staffId, required this.assignedAt});
  final int staffId;
  final DateTime assignedAt;
}

/// Le gérant choisit manuellement qui prend la commande en charge — occupé
/// ou non n'empêche plus la sélection (indicatif uniquement, § demande).
Future<AssignResult?> showAssignStaffDialog(
  BuildContext context, {
  required String role,
  required String orderNumero,
  required Future<List<StaffOption>> Function() loadStaff,
}) {
  return showDialog<AssignResult>(
    context: context,
    builder: (context) => _AssignStaffDialog(role: role, orderNumero: orderNumero, loadStaff: loadStaff),
  );
}

class _AssignStaffDialog extends StatefulWidget {
  const _AssignStaffDialog({required this.role, required this.orderNumero, required this.loadStaff});
  final String role;
  final String orderNumero;
  final Future<List<StaffOption>> Function() loadStaff;

  @override
  State<_AssignStaffDialog> createState() => _AssignStaffDialogState();
}

class _AssignStaffDialogState extends State<_AssignStaffDialog> {
  List<StaffOption>? _staff;
  int? _selectedId;
  DateTime _assignedAt = DateTime.now();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final staff = await widget.loadStaff();
      if (mounted) {
        setState(() {
          _staff = staff;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Erreur de chargement.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _assignedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_assignedAt));
    if (time == null || !mounted) return;
    setState(() => _assignedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = widget.role == 'PREPARATEUR' ? 'préparateur' : 'livreur';

    Widget content;
    if (_loading) {
      content = const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      content = Text(_error!);
    } else if (_staff == null || _staff!.isEmpty) {
      content = Text('Aucun $roleLabel enregistré pour ce magasin.');
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _selectedId,
            decoration: InputDecoration(labelText: 'Choisir un $roleLabel'),
            items: [
              for (final s in _staff!)
                DropdownMenuItem(value: s.id, child: Text('${s.fullName}${s.available ? '' : ' (occupé)'}')),
            ],
            onChanged: (v) => setState(() => _selectedId = v),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDateTime,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date et heure', suffixIcon: Icon(Icons.event_outlined)),
              child: Text(DateFormat('dd/MM/yyyy HH:mm').format(_assignedAt)),
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Assigner un $roleLabel'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Commande ${widget.orderNumero} — choisissez manuellement qui prend cette commande en charge.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () => Navigator.of(context).pop(AssignResult(staffId: _selectedId!, assignedAt: _assignedAt)),
          child: const Text('Assigner'),
        ),
      ],
    );
  }
}
