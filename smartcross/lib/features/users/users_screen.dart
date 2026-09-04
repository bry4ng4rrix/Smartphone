import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../models/company.dart';
import '../../models/user.dart';
import '../../state/auth_provider.dart';
import '../../state/company_provider.dart';
import '../../state/users_provider.dart';
import '../../widgets/async_state_widgets.dart';

final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Gestion des comptes préparateur/livreur (§4 Smartreadme.md, réservée au
/// gérant) + approbation des comptes auto-inscrits en attente + fonctions
/// "Super Admin" (mots de passe/abonnement/appareils, §11 README —
/// infrastructure SaaS conservée), affichées selon le rôle du compte connecté.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingUsersProvider).value?.length ?? 0;
    final currentUser = ref.watch(authProvider).user;
    final isAdmin = currentUser?.rawRole == 'admin';
    final isCompanyOwner = currentUser?.isCompanyOwner ?? false;

    final tabs = <Tab>[
      const Tab(text: 'Équipe'),
      Tab(text: pendingCount > 0 ? 'En attente ($pendingCount)' : 'En attente'),
      if (isAdmin) const Tab(text: 'Mots de passe'),
      if (isCompanyOwner) const Tab(text: 'Abonnement'),
      if (isCompanyOwner) const Tab(text: 'Appareils'),
    ];
    final views = <Widget>[
      const _TeamTab(),
      const _PendingTab(),
      if (isAdmin) const _PasswordResetsTab(),
      if (isCompanyOwner) const _SubscriptionTab(),
      if (isCompanyOwner) const _DevicesTab(),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Utilisateurs'),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs),
        ),
        body: TabBarView(children: views),
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
        leading: CircleAvatar(
          backgroundImage: user.photo != null ? NetworkImage(user.photo!) : null,
          child: user.photo == null ? Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?') : null,
        ),
        title: Text(user.fullName),
        subtitle: Text([
          user.email,
          if (user.phone != null && user.phone!.isNotEmpty) user.phone!,
          if (user.adresse != null && user.adresse!.isNotEmpty) user.adresse!,
        ].join(' · ')),
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

const _prStatusLabel = {'pending': 'En attente', 'approved': 'Approuvée', 'rejected': 'Rejetée'};
const _subStatusLabel = {'active': 'Actif', 'disabled': 'Désactivé', 'pending': 'En attente', 'trial': 'Essai', 'demo': 'Démo'};
const _requestTypeLabel = {
  'activation': "Activation d'abonnement",
  'device_deletion': "Suppression d'appareil",
  'payment': 'Paiement direct',
  'password_reset': 'Réinitialisation de mot de passe',
};

Color _statusColor(BuildContext context, String status) {
  switch (status) {
    case 'approved':
    case 'active':
      return Colors.green;
    case 'rejected':
    case 'disabled':
      return Colors.red;
    case 'trial':
      return Colors.blue;
    case 'demo':
      return Colors.purple;
    default:
      return Colors.orange;
  }
}

/// Onglet "Mots de passe" (admin uniquement) : demandes de réinitialisation
/// envoyées par les gérants/employés de la société ayant oublié leur mot de
/// passe (§11 README — infrastructure SaaS conservée).
class _PasswordResetsTab extends ConsumerWidget {
  const _PasswordResetsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(passwordResetRequestsProvider);
    final currentFilter = ref.watch(passwordResetRequestsProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pending', label: Text('En attente')),
                    ButtonSegment(value: 'approved', label: Text('Approuvées')),
                    ButtonSegment(value: 'rejected', label: Text('Rejetées')),
                    ButtonSegment(value: 'all', label: Text('Toutes')),
                  ],
                  selected: const {'pending'},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => currentFilter.setStatus(s.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (async) {
            AsyncData(:final value) => value.isEmpty
                ? const EmptyState(message: 'Aucune demande.', icon: Icons.key_outlined)
                : RefreshIndicator(
                    onRefresh: () => ref.read(passwordResetRequestsProvider.notifier).refresh(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: value.length,
                      itemBuilder: (context, i) => _PasswordResetTile(request: value[i]),
                    ),
                  ),
            AsyncError(:final error) => ErrorState(
                message: ApiClient.messageFromError(error),
                onRetry: () => ref.read(passwordResetRequestsProvider.notifier).refresh(),
              ),
            _ => const LoadingState(),
          },
        ),
      ],
    );
  }
}

class _PasswordResetTile extends ConsumerWidget {
  const _PasswordResetTile({required this.request});
  final PasswordResetRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.userName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(request.userEmail, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Chip(
                  label: Text(_prStatusLabel[request.status] ?? request.status),
                  backgroundColor: _statusColor(context, request.status).withValues(alpha: 0.12),
                  labelStyle: TextStyle(color: _statusColor(context, request.status)),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [request.userRole, if (request.magasinName != null) 'Magasin : ${request.magasinName}'].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (request.createdAt != null)
              Text(_dateTimeFmt.format(request.createdAt!.toLocal()), style: Theme.of(context).textTheme.bodySmall),
            if (request.status == 'pending') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => ref.read(passwordResetRequestsProvider.notifier).resolve(request.id, 'approve'),
                    icon: const Icon(Icons.check, size: 16, color: Colors.green),
                    label: const Text('Approuver'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => ref.read(passwordResetRequestsProvider.notifier).resolve(request.id, 'reject'),
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text('Rejeter'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Onglet "Abonnement" (propriétaire de la société uniquement) : statut,
/// essai restant, demande d'activation, historique des demandes.
class _SubscriptionTab extends ConsumerWidget {
  const _SubscriptionTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(companySubscriptionProvider);
    final requestsAsync = ref.watch(companyRequestsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(companySubscriptionProvider);
        await ref.read(companyRequestsProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          switch (subAsync) {
            AsyncData(:final value) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Chip(
                            label: Text(_subStatusLabel[value.status] ?? value.status),
                            backgroundColor: _statusColor(context, value.status).withValues(alpha: 0.12),
                            labelStyle: TextStyle(color: _statusColor(context, value.status)),
                            side: BorderSide.none,
                          ),
                          if (value.status == 'trial' && value.daysLeftInTrial != null) ...[
                            const SizedBox(width: 8),
                            Text('${value.daysLeftInTrial} jour(s) restant(s) à l\'essai', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                      if (value.offerName != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Offre : ${value.offerName}${value.offerDurationMonths != null ? ' · Durée : ${value.offerDurationMonths} mois' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (value.status != 'active' && value.status != 'demo') ...[
                        const SizedBox(height: 12),
                        _RequestActivationButton(requestsAsync: requestsAsync),
                      ],
                    ],
                  ),
                ),
              ),
            AsyncError(:final error) => ErrorState(message: ApiClient.messageFromError(error), onRetry: () => ref.invalidate(companySubscriptionProvider)),
            _ => const LoadingState(),
          },
          const SizedBox(height: 16),
          switch (requestsAsync) {
            AsyncData(:final value) when value.isNotEmpty => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Historique des demandes', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      for (final r in value)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(_requestTypeLabel[r.requestType] ?? r.requestType)),
                              Chip(
                                label: Text(_prStatusLabel[r.status] ?? r.status),
                                backgroundColor: _statusColor(context, r.status).withValues(alpha: 0.12),
                                labelStyle: TextStyle(color: _statusColor(context, r.status), fontSize: 12),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

class _RequestActivationButton extends ConsumerStatefulWidget {
  const _RequestActivationButton({required this.requestsAsync});
  final AsyncValue<List<CompanyRequest>> requestsAsync;

  @override
  ConsumerState<_RequestActivationButton> createState() => _RequestActivationButtonState();
}

class _RequestActivationButtonState extends ConsumerState<_RequestActivationButton> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final hasPending = widget.requestsAsync.value?.any((r) => r.requestType == 'activation' && r.status == 'pending') ?? false;
    return FilledButton(
      onPressed: (_sending || hasPending)
          ? null
          : () async {
              setState(() => _sending = true);
              try {
                await ref.read(companyRequestsProvider.notifier).requestActivation();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
              } finally {
                if (mounted) setState(() => _sending = false);
              }
            },
      child: Text(hasPending ? 'Demande déjà envoyée' : (_sending ? 'Envoi…' : "Demander l'activation")),
    );
  }
}

/// Onglet "Appareils" (propriétaire de la société uniquement) : appareils
/// connectés aux comptes de la société, avec demande de suppression.
class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyDevicesProvider);
    final requestsAsync = ref.watch(companyRequestsProvider);

    return switch (async) {
      AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.read(companyDevicesProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Chip(
                  label: Text('${value.count} / ${value.limit} appareils'),
                  backgroundColor: (value.count >= value.limit ? Colors.red : Colors.blue).withValues(alpha: 0.12),
                  labelStyle: TextStyle(color: value.count >= value.limit ? Colors.red : Colors.blue),
                  side: BorderSide.none,
                ),
              ),
              if (value.count >= value.limit)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                    "Limite d'appareils atteinte. Supprimez un appareil ci-dessous ou contactez Label Technology pour augmenter votre offre.",
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              const SizedBox(height: 8),
              if (value.devices.isEmpty) const EmptyState(message: 'Aucun appareil enregistré.', icon: Icons.devices_outlined),
              for (final d in value.devices) _DeviceTile(device: d, requestsAsync: requestsAsync),
            ],
          ),
        ),
      AsyncError(:final error) => ErrorState(message: ApiClient.messageFromError(error), onRetry: () => ref.read(companyDevicesProvider.notifier).refresh()),
      _ => const LoadingState(),
    };
  }
}

class _DeviceTile extends ConsumerStatefulWidget {
  const _DeviceTile({required this.device, required this.requestsAsync});
  final CompanyDevice device;
  final AsyncValue<List<CompanyRequest>> requestsAsync;

  @override
  ConsumerState<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends ConsumerState<_DeviceTile> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final hasPending = widget.requestsAsync.value?.any((r) => r.requestType == 'device_deletion' && r.status == 'pending') ?? false;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text('${widget.device.userName} (${widget.device.userRole})'),
        subtitle: Text(
          [
            widget.device.label ?? widget.device.userAgent ?? '',
            if (widget.device.ipAddress != null) widget.device.ipAddress!,
          ].where((s) => s.isNotEmpty).join(' · '),
        ),
        trailing: OutlinedButton(
          onPressed: (_sending || hasPending)
              ? null
              : () async {
                  setState(() => _sending = true);
                  try {
                    await ref.read(companyDevicesProvider.notifier).requestDeletion(widget.device.id);
                    await ref.read(companyRequestsProvider.notifier).refresh();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande envoyée')));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
                  } finally {
                    if (mounted) setState(() => _sending = false);
                  }
                },
          child: Text(hasPending ? 'Demande envoyée' : (_sending ? 'Envoi…' : 'Demander la suppression')),
        ),
      ),
    );
  }
}
