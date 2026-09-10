import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/permissions.dart';
import '../../data/repositories/superadmin_repository.dart';
import '../../state/auth_provider.dart';
import '../../state/superadmin_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/kpi_card.dart';

/// Couleurs de STATUT reprises telles quelles des classes Tailwind de la page
/// web (même approche que `features/alerts/alerts_screen.dart`) : ce ne sont
/// pas des couleurs de thème.
const _blue600 = Color(0xFF2563EB); // Shield de l'en-tête
const _blue500 = Color(0xFF3B82F6); // stat « Magasins »
const _green500 = Color(0xFF22C55E); // stat « Utilisateurs total »
const _orange500 = Color(0xFFF97316); // stat « En attente »
const _green700 = Color(0xFF15803D); // badge Actif — texte
const _greenBorder = Color(0xFFBBF7D0); // badge Actif — bordure (green-200)
const _orange700 = Color(0xFFC2410C); // badge Inactif / En attente — texte
const _orangeBorder = Color(0xFFFED7AA); // bordure (orange-200)
const _red600 = Color(0xFFDC2626); // titre de la modale, icône poubelle

/// Les 3 rôles Django proposés par le `Select` inline de la colonne « Rôle »,
/// avec les libellés RÉELLEMENT affichés par le web.
///
/// (La page web déclare aussi une constante `roleLabel = { admin:
/// 'Administrateur', magasin: 'Gérant', employer: 'Commercial' }` — code mort,
/// jamais utilisée : les libellés du Select sont bien ceux ci-dessous.)
const _roleOptions = <String, String>{
  'admin': 'Admin',
  'magasin': 'Gérant',
  'employer': 'Commercial',
};

/// Page `/superadmin` du web (`frontend/app/(app)/superadmin/page.tsx`) :
/// console de super-administration — vue globale des magasins (équipes) de la
/// société et de TOUS les comptes, avec changement de rôle inline et
/// suppression de compte protégée par mot de passe.
///
/// Gating : `isSuperAdmin` (= `role === 'admin'`, voir `core/permissions.dart`).
/// Le web fait une `router.replace('/dashboard')` silencieuse ; sur mobile une
/// redirection muette laisserait l'utilisateur sans explication, donc l'écran
/// « Accès refusé » explicite ci-dessous est rendu à la place (même parti pris
/// que les pages web qui, elles, affichent une carte ShieldAlert). Comme sur
/// le web, AUCUNE requête n'est lancée tant que l'utilisateur n'est pas
/// super-admin : le corps (et donc `superadminProvider`) n'est monté que dans
/// la branche autorisée.
class SuperadminScreen extends ConsumerWidget {
  const SuperadminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (auth.status == AuthStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Super Administration')),
        body: const LoadingState(),
      );
    }

    final user = auth.user;
    if (user == null || !user.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Super Administration')),
        body: const _AccessDenied(),
      );
    }

    return const _SuperadminBody();
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gpp_maybe_outlined, size: 48, color: _red600),
                const SizedBox(height: 12),
                Text(
                  'Accès refusé',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cette page est réservée au Super Administrateur.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Seul un compte de rôle « admin » (propriétaire ou co-administrateur de la société) peut ouvrir la Super Administration.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuperadminBody extends ConsumerStatefulWidget {
  const _SuperadminBody();

  @override
  ConsumerState<_SuperadminBody> createState() => _SuperadminBodyState();
}

class _SuperadminBodyState extends ConsumerState<_SuperadminBody> {
  /// Équivalent de `changingRole` (web) : id de la ligne dont le rôle est en
  /// cours de modification — son sélecteur est désactivé pendant l'appel.
  int? _changingRole;

  Future<void> _refresh() => ref.read(superadminProvider.notifier).refresh();

  Future<void> _changeRole(SuperadminUser user, String role) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _changingRole = user.id);
    try {
      await ref.read(superadminProvider.notifier).changeRole(user.id, role);
      messenger.showSnackBar(const SnackBar(content: Text('Rôle modifié')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _changingRole = null);
    }
  }

  Future<void> _confirmDelete(SuperadminUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await showDialog<bool>(
      context: context,
      // La fermeture par clic extérieur est gérée par la modale elle-même
      // (verrouillée pendant l'envoi, comme `handleOpenChange` du web).
      barrierDismissible: false,
      builder: (_) => _ConfirmDeleteDialog(user: user),
    );
    if (deleted == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Utilisateur supprimé')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(superadminProvider);
    final loading = async.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: _blue600),
            SizedBox(width: 8),
            Flexible(child: Text('Super Administration', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          // Bouton « Actualiser » du web (icône RefreshCw qui tourne pendant
          // le chargement, désactivé tant que `loading`).
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
        ],
      ),
      body: switch (async) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: _refresh,
          child: _Content(
            stores: value,
            changingRole: _changingRole,
            onChangeRole: _changeRole,
            onDelete: _confirmDelete,
          ),
        ),
        // Le web se contente d'un `console.error` (écran figé sur les données
        // précédentes, sans message ni retry) : impraticable sur mobile, où
        // l'échec du tout premier chargement laisserait une page vide sans
        // explication. On utilise l'état d'erreur standard du projet.
        AsyncError(:final error) => ErrorState(
          message: ApiClient.messageFromError(error),
          onRetry: _refresh,
        ),
        _ => const LoadingState(),
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.stores,
    required this.changingRole,
    required this.onChangeRole,
    required this.onDelete,
  });

  final List<SuperadminStore> stores;
  final int? changingRole;
  final void Function(SuperadminUser user, String role) onChangeRole;
  final void Function(SuperadminUser user) onDelete;

  @override
  Widget build(BuildContext context) {
    final users = flattenSuperadminUsers(stores);
    final pending = users.where((u) => !u.isConfirmed).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Gestion globale des utilisateurs et magasins',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        KpiGrid(
          children: [
            KpiCard(
              label: 'Magasins',
              value: '${stores.length}',
              icon: Icons.storefront_outlined,
              accentColor: _blue500,
            ),
            KpiCard(
              label: 'Utilisateurs total',
              value: '${users.length}',
              icon: Icons.people_outline,
              accentColor: _green500,
            ),
            KpiCard(
              label: 'En attente',
              value: '$pending',
              icon: Icons.people_outline,
              accentColor: _orange500,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          title: 'Toutes les équipes',
          description: '${stores.length} équipe(s) enregistrée(s)',
        ),
        const SizedBox(height: 8),
        if (stores.isEmpty)
          const EmptyState(
            message: 'Aucune équipe enregistrée.',
            icon: Icons.storefront_outlined,
          )
        else
          for (final store in stores) _StoreCard(store: store),
        const SizedBox(height: 20),
        _SectionHeader(
          title: 'Tous les utilisateurs',
          description: '${users.length} compte(s) enregistré(s)',
        ),
        const SizedBox(height: 8),
        if (users.isEmpty)
          const EmptyState(
            message: 'Aucun compte enregistré.',
            icon: Icons.people_outline,
          )
        else
          for (final user in users)
            _UserCard(
              user: user,
              changing: changingRole == user.id,
              onChangeRole: (role) => onChangeRole(user, role),
              onDelete: () => onDelete(user),
            ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Une ligne du tableau « Toutes les équipes » (colonnes Magasin / Gérant /
/// Membres / Statut), rendue en carte. Aucune action par ligne côté web.
class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});

  final SuperadminStore store;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    store.shopName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                // isActive = !!s.manager?.is_confirmed
                _StatusBadge(active: store.isActive, label: store.isActive ? 'Actif' : 'Inactif'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline, size: 15, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Gérant : ${store.manager?.fullName ?? '-'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people_outline, size: 15, color: muted),
                const SizedBox(width: 6),
                Text(
                  'Membres : ${store.memberCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne du tableau « Tous les utilisateurs » (Nom / Email / Magasin /
/// Rôle / Statut / Actions), rendue en carte.
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.changing,
    required this.onChangeRole,
    required this.onDelete,
  });

  final SuperadminUser user;
  final bool changing;
  final void Function(String role) onChangeRole;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isAdminRow = user.role == 'admin';
    // Un rôle inconnu (jamais renvoyé en principe) ne doit pas casser le
    // sélecteur : on affiche la valeur brute en `hint` sans la sélectionner.
    final knownRole = _roleOptions.containsKey(user.role);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(
                  active: user.isConfirmed,
                  label: user.isConfirmed ? 'Actif' : 'En attente',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.storefront_outlined, size: 15, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    user.shopName?.isNotEmpty == true ? user.shopName! : '-',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Rôle',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: knownRole ? user.role : null,
                        hint: Text(
                          user.role.isEmpty ? '-' : user.role,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        isDense: true,
                        isExpanded: true,
                        // Désactivé pendant l'appel (`changingRole === u.id`)
                        // ET pour un compte `admin` : la ligne « admin » est
                        // toujours le fondateur de la société ici, action que
                        // le backend refuserait de toute façon. On désactive
                        // plutôt que de retirer le contrôle, comme le web.
                        onChanged: (changing || isAdminRow)
                            ? null
                            : (value) {
                                if (value != null && value != user.role) onChangeRole(value);
                              },
                        items: [
                          for (final entry in _roleOptions.entries)
                            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (changing) ...[
                  const SizedBox(width: 10),
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                // Le bouton de suppression n'existe QUE pour les lignes non
                // admin (cellule vide sinon, côté web).
                if (!isAdminRow) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline, color: _red600),
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge `variant='outline'` du web (fond transparent + bordure colorée),
/// volontairement différent des `StatusChip` pleins du reste de l'app.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = active ? _green700 : _orange700;
    final border = active ? _greenBorder : _orangeBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Portage du composant partagé `<ConfirmDeleteDialog />`
/// (`frontend/components/confirm-delete-dialog.tsx`) dans son usage
/// /superadmin : suppression définitive d'un compte, confirmée par le mot de
/// passe de l'utilisateur COURANT (ré-authentification).
///
/// Renvoie `true` via `Navigator.pop` en cas de succès (le message de succès
/// est émis par la page appelante, pas par la modale — comme sur le web).
class _ConfirmDeleteDialog extends ConsumerStatefulWidget {
  const _ConfirmDeleteDialog({required this.user});

  final SuperadminUser user;

  @override
  ConsumerState<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends ConsumerState<_ConfirmDeleteDialog> {
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Validation cliente du web : `if (!password) setError('Mot de passe
    // requis.')` — aucun appel réseau. Le bouton est de toute façon désactivé
    // tant que le champ est vide ; ce garde-fou couvre la validation clavier.
    if (_password.text.isEmpty) {
      setState(() => _error = 'Mot de passe requis.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(superadminProvider.notifier).deleteUser(widget.user.id, _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Échec : la modale RESTE OUVERTE, le mot de passe saisi est conservé,
      // l'erreur s'affiche en ligne (aucun toast d'erreur ici).
      if (mounted) setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_loading && _password.text.isNotEmpty;

    return PopScope(
      // `handleOpenChange` du web : impossible de fermer la modale tant que la
      // requête est en cours (Échap, retour arrière, bouton Annuler).
      canPop: !_loading,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gpp_maybe_outlined, size: 20, color: _red600),
            SizedBox(width: 8),
            Expanded(child: Text('Supprimer cet utilisateur', style: TextStyle(color: _red600))),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Vous êtes sur le point de supprimer définitivement '),
                      TextSpan(
                        text: widget.user.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(
                        text: '. Cette action est irréversible. Entrez votre mot de passe pour confirmer.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  enabled: !_loading,
                  // L'erreur affichée disparaît dès la première frappe.
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) {
                    if (!_loading) _submit();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Votre mot de passe',
                    hintText: '••••••••',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: _red600, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: _loading
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Suppression...'),
                    ],
                  )
                : const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
  }
}
