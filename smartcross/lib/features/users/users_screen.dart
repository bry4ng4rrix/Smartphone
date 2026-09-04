import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/user.dart';
import '../../state/users_provider.dart';
import '../../widgets/async_state_widgets.dart';

/// Gestion des comptes préparateur/livreur (§4 Smartreadme.md, réservée au
/// gérant) + approbation des comptes auto-inscrits en attente.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingUsersProvider).value?.length ?? 0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Utilisateurs'),
          bottom: TabBar(tabs: [
            const Tab(text: 'Équipe'),
            Tab(text: pendingCount > 0 ? 'En attente ($pendingCount)' : 'En attente'),
          ]),
        ),
        body: const TabBarView(children: [_TeamTab(), _PendingTab()]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const _CreateUserDialog()),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Ajouter'),
        ),
      ),
    );
  }
}

class _TeamTab extends ConsumerWidget {
  const _TeamTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accountsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(accountsProvider.notifier).refresh(),
      child: switch (async) {
        AsyncData(:final value) => value.isEmpty
            ? const EmptyState(message: 'Aucun compte préparateur/livreur.', icon: Icons.people_outline)
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: value.length,
                itemBuilder: (context, i) => _UserTile(user: value[i]),
              ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(accountsProvider.notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
    );
  }
}

class _PendingTab extends ConsumerWidget {
  const _PendingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingUsersProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(pendingUsersProvider.notifier).refresh(),
      child: switch (async) {
        AsyncData(:final value) => value.isEmpty
            ? const EmptyState(message: 'Aucune demande en attente.', icon: Icons.hourglass_empty)
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: value.length,
                itemBuilder: (context, i) {
                  final u = value[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(u.fullName),
                      subtitle: Text('${u.email}${u.position != null ? ' · ${u.position}' : ''}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                            tooltip: 'Approuver',
                            onPressed: () => ref.read(pendingUsersProvider.notifier).approve(u.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                            tooltip: 'Rejeter',
                            onPressed: () => ref.read(pendingUsersProvider.notifier).reject(u.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        AsyncError(:final error) => ErrorState(
            message: ApiClient.messageFromError(error),
            onRetry: () => ref.read(pendingUsersProvider.notifier).refresh(),
          ),
        _ => const LoadingState(),
      },
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user});
  final AppUser user;

  Future<void> _changeRole(WidgetRef ref, BuildContext context, UserRole role) async {
    try {
      await ref.read(accountsProvider.notifier).updateCommandeRole(user.id, role.apiValue);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _confirmDelete(WidgetRef ref, BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => _PasswordConfirmDialog(userName: user.fullName),
    );
    if (password == null || password.isEmpty) return;
    try {
      await ref.read(accountsProvider.notifier).delete(user.id, password);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(child: Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?')),
        title: Text(user.fullName),
        subtitle: Text(user.email + (user.phone != null && user.phone!.isNotEmpty ? ' · ${user.phone}' : '')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(value: UserRole.preparateur, label: Text('Prép.')),
                ButtonSegment(value: UserRole.livreur, label: Text('Livr.')),
              ],
              selected: {if (user.role == UserRole.livreur) UserRole.livreur else UserRole.preparateur},
              onSelectionChanged: (s) => _changeRole(ref, context, s.first),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(ref, context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Suppression d'un compte : nécessite le mot de passe du gérant connecté
/// (confirmation, §4 Smartreadme.md — même règle que le web).
class _PasswordConfirmDialog extends StatefulWidget {
  const _PasswordConfirmDialog({required this.userName});
  final String userName;

  @override
  State<_PasswordConfirmDialog> createState() => _PasswordConfirmDialogState();
}

class _PasswordConfirmDialogState extends State<_PasswordConfirmDialog> {
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
          Text('Supprimer le compte de "${widget.userName}" ? Entrez votre mot de passe pour confirmer.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Votre mot de passe'),
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

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _role = UserRole.preparateur;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accountsProvider.notifier).create(
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            commandeRole: _role.apiValue,
            phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
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
      title: const Text('Nouveau compte'),
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
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nom complet'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@')) ? 'Email invalide' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Téléphone (optionnel)')),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Mot de passe'),
                  obscureText: true,
                  validator: (v) => (v == null || v.length < 6) ? '6 caractères minimum' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rôle module Commande'),
                  items: [
                    for (final r in [UserRole.preparateur, UserRole.livreur]) DropdownMenuItem(value: r, child: Text(r.label)),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
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
