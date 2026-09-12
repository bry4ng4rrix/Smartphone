import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_time.dart';
import '../core/constants.dart';
import '../data/repositories/orders_repository.dart';

/// Résultat de l'affectation choisie par le gérant : la personne désignée et
/// une heure manuelle optionnelle (§ demande — sélection + heure manuelles).
///
/// [assignedAt] est un instant absolu (UTC), prêt à partir au serveur ;
/// `null` = maintenant (« Vide = maintenant. »). Seule la transition de
/// statut (`POST /orders/{id}/status/`) en tient compte : les endpoints de
/// pré-assignation `assign-preparateur` / `assign-livreur` horodatent
/// eux-mêmes, exactement comme `doAssign` côté web ignore la valeur.
class AssignResult {
  const AssignResult({required this.staffId, this.assignedAt});
  final int staffId;
  final DateTime? assignedAt;
}

/// Le gérant choisit manuellement qui prend la commande en charge — occupé
/// ou non n'empêche plus la sélection (indicatif uniquement, § demande).
/// [role] = 'PREPARATEUR' | 'LIVREUR'. Retourne `null` si annulé.
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
  // Heure « au mur » d'Antananarivo, pré-remplie à maintenant (heure du
  // magasin, quel que soit le fuseau de l'appareil) ; `null` = maintenant.
  DateTime? _assignedAt = appNow();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
    final base = _assignedAt ?? appNow();
    final today = appToday();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: today.subtract(const Duration(days: 60)),
      lastDate: today.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null || !mounted) return;
    setState(() => _assignedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = widget.role == 'PREPARATEUR' ? 'préparateur' : 'livreur';
    final muted = Theme.of(context).textTheme.bodySmall;

    Widget content;
    if (_loading) {
      content = const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
        ],
      );
    } else if (_staff == null || _staff!.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('Aucun $roleLabel enregistré pour ce magasin.', style: muted, textAlign: TextAlign.center),
        ),
      );
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
              decoration: InputDecoration(
                labelText: 'Date et heure',
                helperText: 'Vide = maintenant.',
                suffixIcon: _assignedAt == null
                    ? const Icon(Icons.event_outlined)
                    : IconButton(
                        tooltip: 'Vider (= maintenant)',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _assignedAt = null),
                      ),
              ),
              child: Text(_assignedAt == null ? 'Maintenant' : DateFormat('dd/MM/yyyy HH:mm').format(_assignedAt!)),
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Assigner un $roleLabel'),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 340),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Commande ${widget.orderNumero} — choisissez manuellement qui prend cette commande en charge.',
                style: muted,
              ),
              const SizedBox(height: 12),
              content,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () => Navigator.of(context).pop(
                  AssignResult(
                    staffId: _selectedId!,
                    assignedAt: _assignedAt == null ? null : appWallClockToUtc(_assignedAt!),
                  ),
                ),
          child: const Text('Assigner'),
        ),
      ],
    );
  }
}
