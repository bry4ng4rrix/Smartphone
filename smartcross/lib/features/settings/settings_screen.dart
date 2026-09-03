import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../data/repositories/auth_repository.dart';
import '../../state/auth_provider.dart';

/// Profil et sécurité du compte connecté — infrastructure conservée du
/// backend générique (indépendante du cahier des charges Smartphone.Mg).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _savingProfile = false;
  String? _profileError;

  final _oldPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();
  bool _savingPassword = false;
  String? _passwordError;
  String? _passwordSuccess;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameController.text = user?.fullName ?? '';
    _phoneController.text = user?.phone ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _oldPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      await AuthRepository().updateProfile(fullName: _nameController.text.trim(), phone: _phoneController.text.trim());
      await ref.read(authProvider.notifier).refreshUser();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
    } catch (e) {
      setState(() => _profileError = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPwController.text.length < 6) {
      setState(() => _passwordError = '6 caractères minimum');
      return;
    }
    if (_newPwController.text != _confirmPwController.text) {
      setState(() => _passwordError = 'Les mots de passe ne correspondent pas');
      return;
    }
    setState(() {
      _savingPassword = true;
      _passwordError = null;
      _passwordSuccess = null;
    });
    try {
      await AuthRepository().changePassword(oldPassword: _oldPwController.text, newPassword: _newPwController.text);
      _oldPwController.clear();
      _newPwController.clear();
      _confirmPwController.clear();
      setState(() => _passwordSuccess = 'Mot de passe changé avec succès');
    } catch (e) {
      setState(() => _passwordError = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mon profil', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(controller: TextEditingController(text: user?.email), decoration: const InputDecoration(labelText: 'Email'), enabled: false),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: InputDecoration(labelText: 'Rôle'),
                    controller: TextEditingController(text: user?.role.label ?? ''),
                    enabled: false,
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nom complet')),
                  const SizedBox(height: 10),
                  TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Téléphone')),
                  if (_profileError != null) ...[
                    const SizedBox(height: 8),
                    Text(_profileError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _savingProfile ? null : _saveProfile, child: Text(_savingProfile ? 'Enregistrement…' : 'Enregistrer')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Changer le mot de passe', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(controller: _oldPwController, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel')),
                  const SizedBox(height: 10),
                  TextField(controller: _newPwController, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe')),
                  const SizedBox(height: 10),
                  TextField(controller: _confirmPwController, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le nouveau mot de passe')),
                  if (_passwordError != null) ...[
                    const SizedBox(height: 8),
                    Text(_passwordError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_passwordSuccess != null) ...[
                    const SizedBox(height: 8),
                    Text(_passwordSuccess!, style: const TextStyle(color: Colors.green)),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _savingPassword ? null : _changePassword, child: Text(_savingPassword ? 'Enregistrement…' : 'Changer')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Déconnexion'),
              onTap: () => ref.read(authProvider.notifier).logout(),
            ),
          ),
        ],
      ),
    );
  }
}
