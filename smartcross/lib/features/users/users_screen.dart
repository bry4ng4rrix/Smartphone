import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../data/repositories/users_repository.dart';
import '../../models/company.dart';
import '../../models/user.dart';
import '../../state/auth_provider.dart';
import '../../state/users_provider.dart';
import '../../widgets/async_state_widgets.dart';

// =============================================================================
// Couleurs de STATUT reprises des classes Tailwind de la page web (même
// approche que les autres écrans) : ce ne sont pas
// des couleurs de thème.
// =============================================================================
const _purple500 = Color(0xFFA855F7); // icône rôle admin (Shield)
const _blue500 = Color(0xFF3B82F6); // icône rôle gérant (Briefcase)
const _green500 = Color(0xFF22C55E); // icône rôle employé (Users) + pastille en ligne
const _blue600 = Color(0xFF2563EB); // bouton « Modifier rôle »
const _blue700 = Color(0xFF1D4ED8); // email dans une demande de réinit.
const _red500 = Color(0xFFEF4444); // ShieldAlert « Accès Refusé »
const _red600 = Color(0xFFDC2626); // bouton « Supprimer », titre modale
const _red700 = Color(0xFFB91C1C); // bouton « Rejeter » (réinit.)
const _red200 = Color(0xFFFECACA);
const _green600 = Color(0xFF16A34A); // bouton « Approuver » (inscription)
const _green700 = Color(0xFF15803D); // texte « Actif », bouton Approuver (réinit.)
const _green200 = Color(0xFFBBF7D0);
const _slate300 = Color(0xFFCBD5E1); // pastille hors ligne
const _violet500 = Color(0xFF8B5CF6); // icône KeyRound d'une demande
const _orange100 = Color(0xFFFFEDD5); // fond badge compteur
const _orange800 = Color(0xFF9A3412); // texte badge compteur / statut pending
const _orange50 = Color(0xFFFFF7ED);
const _orange200 = Color(0xFFFED7AA);
const _green50 = Color(0xFFF0FDF4);
const _green800 = Color(0xFF166534);
const _red50 = Color(0xFFFEF2F2);
const _red800 = Color(0xFF991B1B);

/// `useDebouncedValue(searchTerm)` du web : 250 ms par défaut.
const _kSearchDebounce = Duration(milliseconds: 250);

/// Tick de recalcul des libellés relatifs (« il y a X minutes ») — 10 min,
/// sans aucun appel réseau, comme le `setInterval` de la page.
const _kRelativeTimeTick = Duration(minutes: 10);

// =============================================================================
// Libellés et formats — identiques au web
// =============================================================================

/// `getRoleLabel` : libellés des LISTES (différents de ceux des Select).
String _roleLabel(String? role) => switch (role) {
  'admin' => 'Administrateur',
  'magasin' => 'Gérant',
  'employer' => 'Employé',
  _ => role ?? '',
};

/// Libellés des Select « Rôle * » / « Nouveau rôle ».
String _roleOptionLabel(String role) => switch (role) {
  'admin' => 'Administrateur',
  'magasin' => 'Gérant de magasin',
  'employer' => 'Employé / Commercial',
  _ => role,
};

/// `getRoleIcon` : Shield violet / Briefcase bleu / Users vert.
Widget _roleIcon(String? role) => switch (role) {
  'admin' => const Icon(Icons.shield_outlined, size: 16, color: _purple500),
  'magasin' => const Icon(Icons.work_outline, size: 16, color: _blue500),
  _ => const Icon(Icons.people_outline, size: 16, color: _green500),
};

const _prStatusLabel = <String, String>{'pending': 'En attente', 'approved': 'Approuvée', 'rejected': 'Rejetée'};

/// Abréviations `MMM` de date-fns en locale `fr` (évite d'initialiser les
/// données de locale `intl` pour trois formats).
const _frMonthsShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// `format(date, 'dd MMM yyyy', { locale: fr })`, en heure d'Antananarivo.
String _fmtDate(DateTime instant) {
  final d = appLocal(instant);
  return '${_two(d.day)} ${_frMonthsShort[d.month - 1]} ${d.year}';
}

/// `format(date, 'dd MMM yyyy HH:mm', { locale: fr })`.
String _fmtDateTime(DateTime instant) {
  final d = appLocal(instant);
  return '${_fmtDate(instant)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// `new Date(x).toLocaleString('fr-FR')` : `jj/mm/aaaa hh:mm:ss`.
String _fmtLocaleString(DateTime instant) {
  final d = appLocal(instant);
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// `formatRelativeTime` : < 1 min « à l'instant », puis minutes, heures
/// (arrondies), jours (arrondis) ; écart négatif ramené à 0.
String _relativeTime(DateTime now, DateTime instant) {
  final diffMs = now.difference(appLocal(instant)).inMilliseconds;
  final diffMin = (diffMs / 60000).round().clamp(0, 1 << 31).toInt();
  if (diffMin < 1) return "à l'instant";
  if (diffMin < 60) return 'il y a $diffMin minute${diffMin > 1 ? 's' : ''}';
  final diffH = (diffMin / 60).round();
  if (diffH < 24) return 'il y a $diffH heure${diffH > 1 ? 's' : ''}';
  final diffD = (diffH / 24).round();
  return 'il y a $diffD jour${diffD > 1 ? 's' : ''}';
}

bool _matches(String term, String? fullName, String? email) {
  if (term.isEmpty) return true;
  final t = term.toLowerCase();
  return (fullName ?? '').toLowerCase().contains(t) || (email ?? '').toLowerCase().contains(t);
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// =============================================================================
// Écran
// =============================================================================

/// Page `/users` du web (libellé sidebar « Super Admin », titre « Super
/// Administration ») : console d'administration des comptes de la société —
/// équipe active de TOUS les magasins accessibles (admins, gérants, employés)
/// avec état de connexion, inscriptions en attente à approuver/rejeter,
/// création de compte (employé avec sous-rôle préparateur/livreur, gérant de
/// magasin, administrateur pour le fondateur), changement de rôle, suppression
/// protégée par mot de passe et (admin) demandes de réinitialisation de mot de
/// passe.
///
/// Gating (identique à `useCurrentUser`) : `isManager` (= admin ou magasin)
/// ouvre la page, sinon écran « Accès Refusé » ; `isAdmin` débloque l'onglet
/// « Réinit. mots de passe », l'option « Gérant de magasin » et les boutons
/// Modifier rôle / Supprimer sur les lignes non admin ; `isCompanyOwner`
/// débloque tout ce qui touche un compte administrateur.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  Timer? _tick;
  String _search = '';
  DateTime _now = appNow();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(_kRelativeTimeTick, (_) {
      if (mounted) setState(() => _now = appNow());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tick?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_kSearchDebounce, () {
      if (mounted) setState(() => _search = value);
    });
  }

  Future<void> _reloadAll() {
    // Chaque action recharge tout (« fetchUsers() » du web) et rafraîchit
    // aussi le repère des libellés relatifs.
    _now = appNow();
    return ref.read(accountsProvider.notifier).reloadAll();
  }

  Future<void> _openCreate(AppUser current) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateUserDialog(currentUser: current),
    );
    if (created == true) await _reloadAll();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (auth.status == AuthStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Super Administration')),
        body: const LoadingState(),
      );
    }
    final current = auth.user;
    // `if (!isManager && !currentUserLoading)` -> écran « Accès Refusé ».
    if (current == null || !current.isGerant) {
      return Scaffold(
        appBar: AppBar(title: const Text('Super Administration')),
        body: const _AccessDenied(),
      );
    }

    final isAdmin = current.isAdmin;
    final activeCount = ref.watch(accountsProvider).value?.length ?? 0;
    final pendingCount = ref.watch(pendingUsersProvider).value?.length ?? 0;
    // Compteur calculé sur la liste DÉJÀ filtrée par le Select (comme le web :
    // il tombe à 0 si le filtre est sur « Approuvées » / « Rejetées »).
    final prPendingCount = isAdmin
        ? (ref.watch(passwordRequestsProvider).value?.where((r) => r.status == 'pending').length ?? 0)
        : 0;

    final tabs = <Widget>[
      _TabLabel(text: 'Utilisateurs actifs', count: activeCount, orange: false),
      _TabLabel(text: 'En attente', count: pendingCount, orange: true),
      if (isAdmin) _TabLabel(text: 'Réinit. mots de passe', count: prPendingCount, orange: true),
    ];
    final views = <Widget>[
      _ActiveTab(search: _search, current: current, now: _now, onReload: _reloadAll),
      _PendingTab(search: _search, onReload: _reloadAll),
      if (isAdmin) const _PasswordResetsTab(),
    ];

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: const Text('Super Administration')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gérez les accès de votre équipe.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        // La saisie reste instantanée (le bouton « effacer »
                        // suit chaque frappe), seul le filtrage est différé.
                        child: ListenableBuilder(
                          listenable: _searchController,
                          builder: (context, _) => TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Rechercher...',
                              prefixIcon: const Icon(Icons.search),
                              isDense: true,
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Effacer',
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        _searchController.clear();
                                        _debounce?.cancel();
                                        setState(() => _search = '');
                                      },
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Bouton « Ajouter » : visible si isManager — donc
                      // aussi pour un gérant de magasin.
                      FilledButton.icon(
                        onPressed: () => _openCreate(current),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Ajouter'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(child: t)],
            ),
            Expanded(child: TabBarView(children: views)),
          ],
        ),
      ),
    );
  }
}

/// Libellé d'onglet + badge de compteur (rendu uniquement si > 0) : gris
/// (`variant='secondary'`) pour Actifs, orange pour En attente / Réinit.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, required this.count, required this.orange});

  final String text;
  final int count;
  final bool orange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: orange ? _orange100 : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: orange ? _orange800 : scheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Écran « Accès Refusé » du web : Card centrée, ShieldAlert rouge, titre et
/// texte — aucun bouton de retour.
class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gpp_maybe_outlined, size: 48, color: _red500),
                const SizedBox(height: 16),
                Text(
                  'Accès Refusé',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  "Vous n'avez pas les permissions pour gérer les utilisateurs.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// En-tête de Card (CardTitle + CardDescription) du web.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.description, this.icon});

  final String title;
  final String description;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

// =============================================================================
// Onglet « Utilisateurs actifs »
// =============================================================================

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab({required this.search, required this.current, required this.now, required this.onReload});

  final String search;
  final AppUser current;
  final DateTime now;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accountsProvider);

    return switch (async) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: onReload,
        child: _ActiveList(
          users: value.where((u) => _matches(search, u.fullName, u.email)).toList(),
          current: current,
          now: now,
          onReload: onReload,
        ),
      ),
      // Le web se contente d'un toast « Erreur de chargement: … » en gardant
      // l'ancien tableau ; sur mobile un premier chargement en échec
      // laisserait une page vide, d'où l'état d'erreur standard avec retry.
      AsyncError(:final error) => ErrorState(
        message: 'Erreur de chargement: ${ApiClient.messageFromError(error)}',
        onRetry: () => ref.read(accountsProvider.notifier).refresh(),
      ),
      _ => const LoadingState(),
    };
  }
}

/// Liste des comptes « groupés par magasin » : un en-tête par magasin
/// (ordre d'apparition, donc l'ordre de l'API), puis une carte par compte.
class _ActiveList extends ConsumerWidget {
  const _ActiveList({required this.users, required this.current, required this.now, required this.onReload});

  final List<AppUser> users;
  final AppUser current;
  final DateTime now;
  final Future<void> Function() onReload;

  Future<void> _editRole(BuildContext context, AppUser user) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditRoleDialog(user: user, isCompanyOwner: current.canManageCompany),
    );
    if (changed == true) await onReload();
  }

  Future<void> _editCommandeRole(BuildContext context, AppUser user) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CommandeRoleDialog(user: user),
    );
    if (changed == true) await onReload();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AppUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmDeleteDialog(
        name: user.fullName.isNotEmpty ? user.fullName : user.email,
        onConfirm: (password) => ref.read(accountsProvider.notifier).delete(user.id, password),
      ),
    );
    if (deleted == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Utilisateur supprimé')));
      await onReload();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Groupes par magasin, dans l'ordre de première apparition.
    final groups = <String, List<AppUser>>{};
    for (final u in users) {
      final key = (u.shopName == null || u.shopName!.isEmpty) ? '-' : u.shopName!;
      groups.putIfAbsent(key, () => []).add(u);
    }

    final items = <Widget>[
      const _CardHeader(title: 'Équipe active', description: 'Utilisateurs confirmés groupés par magasin'),
    ];
    if (users.isEmpty) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text('Aucun utilisateur trouvé', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    } else {
      for (final entry in groups.entries) {
        items.add(_GroupHeader(shopName: entry.key, count: entry.value.length));
        for (final u in entry.value) {
          // Règle exacte du web : gérer un compte admin (fondateur ou
          // co-admin) est réservé au fondateur ; les lignes gérant/employé
          // restent gérables par tout admin. Jamais sur soi-même.
          final canManage = (u.rawRole == 'admin' ? current.canManageCompany : current.isAdmin) && u.id != current.id;
          items.add(
            _UserCard(
              user: u,
              now: now,
              canManage: canManage,
              // Sous-rôle Commande : tout gérant (admin ou magasin), employés
              // seulement (users/views.py::EmployerCommandeRoleUpdateView).
              canEditCommandeRole: u.rawRole == 'employer' && current.isGerant,
              onEditRole: () => _editRole(context, u),
              onEditCommandeRole: () => _editCommandeRole(context, u),
              onDelete: () => _delete(context, ref, u),
            ),
          );
        }
      }
    }
    items.add(const SizedBox(height: 80));

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.shopName, required this.count});

  final String shopName;
  final int count;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(shopName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text('$count', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

/// Avatar : photo ronde si présente, sinon monogramme (1re lettre en
/// majuscule de full_name || email || '?').
class _Avatar extends StatelessWidget {
  const _Avatar({required this.photo, required this.fullName, required this.email});

  final String? photo;
  final String fullName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final letter = (fullName.isNotEmpty ? fullName : (email.isNotEmpty ? email : '?'))[0].toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundImage: (photo != null && photo!.isNotEmpty) ? NetworkImage(photo!) : null,
      child: Text(
        letter,
        style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    );
  }
}

/// Bloc « Utilisateur » commun aux onglets Actifs / En attente : avatar +
/// nom (fallback « Sans nom ») + email + « téléphone · adresse ».
class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({
    required this.fullName,
    required this.email,
    this.photo,
    this.phone,
    this.adresse,
    this.trailing,
  });

  final String fullName;
  final String email;
  final String? photo;
  final String? phone;
  final String? adresse;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final contact = [
      if (phone != null && phone!.isNotEmpty) phone!,
      if (adresse != null && adresse!.isNotEmpty) adresse!,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(photo: photo, fullName: fullName, email: email),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullName.isNotEmpty ? fullName : 'Sans nom',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(email, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
              if (contact.isNotEmpty)
                Text(contact, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// Une ligne du tableau « Utilisateurs actifs » (Utilisateur / Rôle /
/// Magasin / Poste / Connexion-Déconnexion / Actif / Actions), en carte.
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.now,
    required this.canManage,
    required this.canEditCommandeRole,
    required this.onEditRole,
    required this.onEditCommandeRole,
    required this.onDelete,
  });

  final AppUser user;
  final DateTime now;
  final bool canManage;
  final bool canEditCommandeRole;
  final VoidCallback onEditRole;
  final VoidCallback onEditCommandeRole;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final small = theme.textTheme.bodySmall?.copyWith(color: muted);
    final online = user.isCurrentlyOnline;
    final subRole = user.rawRole == 'employer' && (user.role == UserRole.preparateur || user.role == UserRole.livreur)
        ? user.role.label
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IdentityBlock(
              fullName: user.fullName,
              email: user.email,
              photo: user.photo,
              phone: user.phone,
              adresse: user.adresse,
              trailing: user.isActive
                  ? null
                  : const _OutlineBadge(label: 'En attente', color: _orange800, border: _orange200),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roleIcon(user.rawRole),
                    const SizedBox(width: 6),
                    Text(_roleLabel(user.rawRole), style: theme.textTheme.bodyMedium),
                  ],
                ),
                if (subRole != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      subRole,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Magasin : ${(user.shopName == null || user.shopName!.isEmpty) ? '-' : user.shopName}', style: small),
            Text('Poste : ${(user.position == null || user.position!.isEmpty) ? '-' : user.position}', style: small),
            const SizedBox(height: 6),
            if (user.lastLoginAt != null) ...[
              Text('Connexion : ${_fmtDateTime(user.lastLoginAt!)}', style: small),
              Text(
                'Déconnexion : ${online ? 'En ligne' : (user.lastLogoutAt != null ? _fmtDateTime(user.lastLogoutAt!) : '-')}',
                style: small,
              ),
            ] else
              Text('Connexion / Déconnexion : -', style: small),
            const SizedBox(height: 6),
            _ActivityIndicator(user: user, now: now),
            if (canManage || canEditCommandeRole) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    if (canEditCommandeRole)
                      OutlinedButton.icon(
                        onPressed: onEditCommandeRole,
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Sous-rôle'),
                      ),
                    if (canManage)
                      OutlinedButton(
                        onPressed: onEditRole,
                        style: OutlinedButton.styleFrom(foregroundColor: _blue600),
                        child: const Text('Modifier rôle'),
                      ),
                    if (canManage)
                      TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(foregroundColor: _red600),
                        child: const Text('Supprimer'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Colonne « Actif » : pastille verte + « Actif il y a … », pastille grise +
/// « Hors ligne il y a … », ou « Jamais connecté ».
class _ActivityIndicator extends StatelessWidget {
  const _ActivityIndicator({required this.user, required this.now});

  final AppUser user;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (user.lastLoginAt == null) {
      return Text('Jamais connecté', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted));
    }
    final online = user.isCurrentlyOnline;
    final label = online
        ? 'Actif ${_relativeTime(now, user.lastLoginAt!)}'
        : 'Hors ligne ${user.lastLogoutAt != null ? _relativeTime(now, user.lastLogoutAt!) : ''}'.trimRight();
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: online ? _green500 : _slate300, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: online ? _green700 : muted)),
        ),
      ],
    );
  }
}

/// Badge `variant='outline'` du web (fond léger + bordure + texte colorés).
class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge({required this.label, required this.color, required this.border, this.background});

  final String label;
  final Color color;
  final Color border;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
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

// =============================================================================
// Onglet « En attente »
// =============================================================================

class _PendingTab extends ConsumerStatefulWidget {
  const _PendingTab({required this.search, required this.onReload});

  final String search;
  final Future<void> Function() onReload;

  @override
  ConsumerState<_PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends ConsumerState<_PendingTab> {
  /// Verrou par ligne pendant l'appel (le web n'en a pas : double-clic
  /// possible — on protège sans rien retirer).
  final _busy = <int>{};

  Future<void> _approve(PendingUser u) async {
    setState(() => _busy.add(u.id));
    try {
      await ref.read(pendingUsersProvider.notifier).approve(u.id);
      if (!mounted) return;
      _toast(context, 'Utilisateur approuvé');
      await widget.onReload();
    } catch (e) {
      if (mounted) _toast(context, ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  Future<void> _reject(PendingUser u) async {
    // `window.confirm('Rejeter et supprimer cet utilisateur ?')`
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rejeter cet utilisateur'),
        content: const Text('Rejeter et supprimer cet utilisateur ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(u.id));
    try {
      await ref.read(pendingUsersProvider.notifier).reject(u.id);
      if (!mounted) return;
      _toast(context, 'Utilisateur rejeté');
      await widget.onReload();
    } catch (e) {
      if (mounted) _toast(context, ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(pendingUsersProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return switch (async) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: widget.onReload,
        child: Builder(
          builder: (context) {
            final filtered = value.where((u) => _matches(widget.search, u.fullName, u.email)).toList();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
              children: [
                const _CardHeader(
                  title: "En attente d'approbation",
                  description: 'Comptes créés mais non encore approuvés',
                ),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Text(
                          'Aucune demande en attente',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(color: muted, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text('Tous les utilisateurs ont été traités.', style: TextStyle(color: muted, fontSize: 13)),
                      ],
                    ),
                  )
                else
                  for (final u in filtered)
                    _PendingCard(
                      user: u,
                      busy: _busy.contains(u.id),
                      onApprove: () => _approve(u),
                      onReject: () => _reject(u),
                    ),
              ],
            );
          },
        ),
      ),
      // Le web avale cette erreur (`.catch(() => [])` -> onglet vide sans
      // message) ; sur mobile on préfère dire que le chargement a échoué.
      AsyncError(:final error) => ErrorState(
        message: ApiClient.messageFromError(error),
        onRetry: () => ref.read(pendingUsersProvider.notifier).refresh(),
      ),
      _ => const LoadingState(),
    };
  }
}

/// Une ligne du tableau « En attente » (Utilisateur / Rôle / Magasin-Poste /
/// Date inscription / Actions), en carte.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.user, required this.busy, required this.onApprove, required this.onReject});

  final PendingUser user;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final shopOrPosition = (user.shopName != null && user.shopName!.isNotEmpty)
        ? user.shopName!
        : (user.position != null && user.position!.isNotEmpty)
        ? user.position!
        : '-';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IdentityBlock(
              fullName: user.fullName,
              email: user.email,
              photo: user.photo,
              phone: user.phone,
              adresse: user.adresse,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _roleIcon(user.role),
                const SizedBox(width: 6),
                Text(_roleLabel(user.role), style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text('Magasin / Poste : $shopOrPosition', style: small),
            Text('Date inscription : ${user.createdAt != null ? _fmtDate(user.createdAt!) : '-'}', style: small),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : onApprove,
                    style: OutlinedButton.styleFrom(foregroundColor: _green600),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approuver'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: _red600),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rejeter'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Onglet « Réinit. mots de passe » (admin uniquement)
// =============================================================================

class _PasswordResetsTab extends ConsumerStatefulWidget {
  const _PasswordResetsTab();

  @override
  ConsumerState<_PasswordResetsTab> createState() => _PasswordResetsTabState();
}

class _PasswordResetsTabState extends ConsumerState<_PasswordResetsTab> {
  /// `resolvingRequestId` : verrou par ligne, les autres restent cliquables.
  int? _resolvingId;

  Future<void> _resolve(PasswordResetRequest r, String action) async {
    setState(() => _resolvingId = r.id);
    try {
      await ref.read(passwordRequestsProvider.notifier).resolve(r.id, action);
      if (mounted) _toast(context, action == 'approve' ? 'Demande approuvée' : 'Demande rejetée');
    } catch (e) {
      if (mounted) {
        final message = ApiClient.messageFromError(e);
        _toast(context, message.isNotEmpty ? message : 'Erreur lors du traitement');
      }
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(passwordRequestsProvider);
    final filter = ref.watch(passwordRequestFilterProvider);
    final loading = async.isLoading;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final header = _CardHeader(
      icon: Icons.key_outlined,
      title: 'Réinitialisations de mot de passe',
      description: 'Demandes de vos gérants de magasin et commerciaux ayant oublié leur mot de passe',
    );

    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: filter,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Statut', isDense: true),
              items: [
                for (final entry in kPasswordRequestFilters.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              // Filtre SERVEUR : chaque changement relance la requête.
              onChanged: (v) {
                if (v != null) ref.read(passwordRequestFilterProvider.notifier).set(v);
              },
            ),
          ),
          const SizedBox(width: 8),
          // Bouton RefreshCw seul : désactivé et « qui tourne » pendant le
          // chargement.
          loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton.outlined(
                  tooltip: 'Actualiser',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.read(passwordRequestsProvider.notifier).refresh(),
                ),
        ],
      ),
    );

    final emptyLabel = filter == 'all'
        ? 'Aucune demande'
        : 'Aucune demande ${(_prStatusLabel[filter] ?? '').toLowerCase()}';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
      children: [
        header,
        controls,
        switch (async) {
          AsyncData(:final value) =>
            value.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(emptyLabel, style: TextStyle(color: muted)),
                    ),
                  )
                : Column(
                    children: [
                      for (final r in value)
                        _PasswordResetCard(
                          request: r,
                          resolving: _resolvingId == r.id,
                          onApprove: () => _resolve(r, 'approve'),
                          onReject: () => _resolve(r, 'reject'),
                        ),
                    ],
                  ),
          AsyncError(:final error) => ErrorState(
            message: 'Erreur lors du chargement des demandes: ${ApiClient.messageFromError(error)}',
            onRetry: () => ref.read(passwordRequestsProvider.notifier).refresh(),
          ),
          _ => const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: LoadingState()),
        },
      ],
    );
  }
}

/// Carte d'une demande de réinitialisation : icône KeyRound violette, « nom —
/// email », rôle · magasin, date, badge de statut, Approuver / Rejeter si
/// `pending`.
class _PasswordResetCard extends StatelessWidget {
  const _PasswordResetCard({
    required this.request,
    required this.resolving,
    required this.onApprove,
    required this.onReject,
  });

  final PasswordResetRequest request;
  final bool resolving;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final small = theme.textTheme.bodySmall?.copyWith(color: muted);
    final (color, border, background) = switch (request.status) {
      'approved' => (_green800, _green200, _green50),
      'rejected' => (_red800, _red200, _red50),
      _ => (_orange800, _orange200, _orange50),
    };

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
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.key_outlined, size: 20, color: _violet500),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${request.userName} — ',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(
                              text: request.userEmail,
                              style: const TextStyle(color: _blue700),
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        [
                          _roleLabel(request.userRole),
                          if (request.magasinName != null && request.magasinName!.isNotEmpty)
                            'Magasin : ${request.magasinName}',
                        ].join(' · '),
                        style: small,
                      ),
                      const SizedBox(height: 4),
                      Text(request.createdAt != null ? _fmtLocaleString(request.createdAt!) : '-', style: small),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _OutlineBadge(
                  label: _prStatusLabel[request.status] ?? request.status,
                  color: color,
                  border: border,
                  background: background,
                ),
              ],
            ),
            if (request.status == 'pending') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: resolving ? null : onApprove,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green700,
                        side: const BorderSide(color: _green200),
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approuver'),
                    ),
                    OutlinedButton.icon(
                      onPressed: resolving ? null : onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _red700,
                        side: const BorderSide(color: _red200),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Rejeter'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Dialog « Créer un utilisateur »
// =============================================================================

/// Sous-rôle module Commande proposé à la création d'un employé (ajout
/// mobile : le web ne le renseigne pas, il est attribué plus tard par le
/// gérant). Chaîne vide = aucun (un `DropdownMenuItem` à valeur `null` ne
/// s'afficherait pas comme sélectionné).
const _kNoCommandeRole = '';
const _commandeRoleOptions = <String, String>{
  'PREPARATEUR': 'Préparateur',
  'LIVREUR': 'Livreur',
  _kNoCommandeRole: 'Aucun (attribué plus tard)',
};

String _commandeRoleFromUser(UserRole role) => switch (role) {
  UserRole.preparateur => 'PREPARATEUR',
  UserRole.livreur => 'LIVREUR',
  _ => _kNoCommandeRole,
};

/// Formulaire `handleAddUser` du web. Renvoie `true` (via `Navigator.pop`)
/// après une création réussie ; l'écran recharge alors les listes.
class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog({required this.currentUser});

  final AppUser currentUser;

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _position = TextEditingController();
  final _shopName = TextEditingController();
  String _role = DjangoRole.employer;
  String _commandeRole = 'PREPARATEUR';
  bool _submitting = false;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _position.dispose();
    _shopName.dispose();
    super.dispose();
  }

  /// Détection « already exists » sur `username` / `email` (message DRF
  /// d'unicité) -> libellé du web ; sinon message du serveur ou repli.
  String _createErrorMessage(Object e) {
    if (UsersRepository.isDuplicateAccountError(e)) {
      return "Un utilisateur avec ce nom d'utilisateur ou cet email existe déjà.";
    }
    final message = ApiClient.messageFromError(e);
    return message.isNotEmpty ? message : 'Une erreur est survenue pendant la création du compte.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Contrôle JS supplémentaire du web, AVANT tout appel réseau.
    if (_password.text.length < 6) {
      _toast(context, 'Le mot de passe doit contenir au moins 6 caractères');
      return;
    }
    setState(() => _submitting = true);
    try {
      final position = _position.text.trim();
      final created = await ref
          .read(accountsProvider.notifier)
          .create(
            fullName: _fullName.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            role: _role,
            // Poste libre ; à défaut, le libellé du sous-rôle choisi (comportement
            // mobile historique).
            position: position.isNotEmpty
                ? position
                : (_commandeRole == _kNoCommandeRole ? '' : _commandeRoleOptions[_commandeRole]),
            shopName: _shopName.text.trim(),
            commandeRole: _commandeRole == _kNoCommandeRole ? null : _commandeRole,
          );
      if (!mounted) return;
      _toast(
        context,
        created.role == DjangoRole.admin
            ? 'Administrateur créé avec succès'
            : "Utilisateur créé en attente d'approbation",
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      // Le dialog reste ouvert, les champs gardent leur valeur.
      if (mounted) _toast(context, _createErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.currentUser;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final roles = <String>[
      DjangoRole.employer,
      if (current.isAdmin) DjangoRole.magasin,
      if (current.canManageCompany) DjangoRole.admin,
    ];

    return AlertDialog(
      title: const Text('Créer un utilisateur'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Le compte sera créé et en attente d'approbation.", style: TextStyle(color: muted, fontSize: 13)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullName,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nom complet *', hintText: 'Jean Dupont'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email *', hintText: 'jean@exemple.com'),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Requis';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t)) return 'Email invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  enabled: !_submitting,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mot de passe *', hintText: '••••••••'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rôle *'),
                  items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(_roleOptionLabel(r)))],
                  onChanged: _submitting ? null : (v) => setState(() => _role = v ?? _role),
                ),
                if (_role == DjangoRole.employer) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _commandeRole,
                    decoration: const InputDecoration(labelText: 'Sous-rôle module Commande'),
                    items: [
                      for (final entry in _commandeRoleOptions.entries)
                        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                    ],
                    onChanged: _submitting ? null : (v) => setState(() => _commandeRole = v ?? _commandeRole),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _position,
                    enabled: !_submitting,
                    decoration: const InputDecoration(labelText: 'Poste / Fonction', hintText: 'Ex: Vendeur'),
                  ),
                ],
                if (_role == DjangoRole.magasin) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _shopName,
                    enabled: !_submitting,
                    decoration: const InputDecoration(labelText: 'Nom du magasin *', hintText: 'Ex: Boutique Ivandry'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Création...'),
                          ],
                        )
                      : const Text("Créer l'utilisateur"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Dialog « Modifier le rôle » (rôle Django)
// =============================================================================

/// `handleUpdateRole` du web : `PUT /users/role/<id>/`. Renvoie `true` après
/// succès ; reste ouvert avec un toast en cas d'erreur.
class _EditRoleDialog extends ConsumerStatefulWidget {
  const _EditRoleDialog({required this.user, required this.isCompanyOwner});

  final AppUser user;
  final bool isCompanyOwner;

  @override
  ConsumerState<_EditRoleDialog> createState() => _EditRoleDialogState();
}

class _EditRoleDialogState extends ConsumerState<_EditRoleDialog> {
  String? _role;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _role = widget.user.rawRole;
  }

  Future<void> _save() async {
    final role = _role;
    if (role == null || role.isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(accountsProvider.notifier).updateRole(widget.user.id, role);
      if (!mounted) return;
      // Le web affiche la valeur brute du rôle, pas son libellé.
      _toast(context, 'Rôle mis à jour : $role');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <String>[if (widget.isCompanyOwner) DjangoRole.admin, DjangoRole.magasin, DjangoRole.employer];
    // Le rôle courant reste sélectionnable même s'il n'est pas proposé (cas
    // théorique d'une ligne admin sans droit fondateur).
    final current = widget.user.rawRole;
    if (current != null && current.isNotEmpty && !options.contains(current)) options.insert(0, current);
    final target = widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.email;
    final canSave = _role != null && _role!.isNotEmpty && _role != widget.user.rawRole && !_loading;

    return AlertDialog(
      title: const Text('Modifier le rôle'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Changer le rôle de $target',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Nouveau rôle'),
              items: [for (final r in options) DropdownMenuItem(value: r, child: Text(_roleOptionLabel(r)))],
              onChanged: _loading ? null : (v) => setState(() => _role = v),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: _loading
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Enregistrer'),
                  ],
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// =============================================================================
// Dialog « Sous-rôle module Commande » (préparateur / livreur)
// =============================================================================

/// `PUT /users/employers/<id>/commande-role/` — réservé au gérant (admin ou
/// magasin), pour un employé. Fonctionnalité mobile conservée (le web n'a pas
/// d'équivalent sur cette page).
class _CommandeRoleDialog extends ConsumerStatefulWidget {
  const _CommandeRoleDialog({required this.user});

  final AppUser user;

  @override
  ConsumerState<_CommandeRoleDialog> createState() => _CommandeRoleDialogState();
}

class _CommandeRoleDialogState extends ConsumerState<_CommandeRoleDialog> {
  late String _value = _commandeRoleFromUser(widget.user.role);
  bool _loading = false;

  String get _initial => _commandeRoleFromUser(widget.user.role);

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await ref
          .read(accountsProvider.notifier)
          .updateCommandeRole(widget.user.id, _value == _kNoCommandeRole ? null : _value);
      if (!mounted) return;
      _toast(context, 'Sous-rôle mis à jour : ${_commandeRoleOptions[_value] ?? 'Aucun'}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.email;
    return AlertDialog(
      title: const Text('Sous-rôle module Commande'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Préparateur ou livreur pour $target',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _value,
              decoration: const InputDecoration(labelText: 'Sous-rôle'),
              items: [
                for (final entry in _commandeRoleOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _loading ? null : (v) => setState(() => _value = v ?? _value),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: (_loading || _value == _initial) ? null : _save,
          child: Text(_loading ? 'Enregistrement...' : 'Enregistrer'),
        ),
      ],
    );
  }
}

// =============================================================================
// Dialog de suppression protégée (ConfirmDeleteDialog du web)
// =============================================================================

/// Portage du composant partagé `<ConfirmDeleteDialog />` : suppression
/// définitive confirmée par le mot de passe de l'opérateur. Renvoie `true`
/// après succès ; l'erreur (client ou serveur) s'affiche EN LIGNE et la
/// modale reste ouverte — seul formulaire de la page sans toast d'erreur.
class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog({required this.name, required this.onConfirm});

  final String name;
  final Future<void> Function(String password) onConfirm;

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Mot de passe requis.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final message = ApiClient.messageFromError(e);
        setState(() => _error = message.isNotEmpty ? message : 'Erreur lors de la suppression.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_loading && _password.text.isNotEmpty;

    return PopScope(
      // `handleOpenChange` : fermeture bloquée tant que la requête est en cours.
      canPop: !_loading,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gpp_maybe_outlined, size: 20, color: _red600),
            SizedBox(width: 8),
            Expanded(
              child: Text('Supprimer cet utilisateur', style: TextStyle(color: _red600)),
            ),
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
                        text: widget.name,
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
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) {
                    if (!_loading) _submit();
                  },
                  decoration: const InputDecoration(labelText: 'Votre mot de passe', hintText: '••••••••'),
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
          OutlinedButton(
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
