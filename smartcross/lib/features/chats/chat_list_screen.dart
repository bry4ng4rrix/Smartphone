import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../data/repositories/chat_repository.dart';
import '../../models/chat.dart';
import '../../widgets/async_state_widgets.dart';
import 'chat_conversation_screen.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository());

/// Cadence du rafraîchissement silencieux de la liste des contacts —
/// `setInterval(() => fetchUsers(true), 20000)` de chats/page.tsx.
const Duration kChatUsersRefreshInterval = Duration(seconds: 20);

/// Contacts de la messagerie, DÉJÀ classés comme sur le web (non-lus d'abord,
/// puis la conversation la plus récente, puis l'alphabet — voir
/// `ChatRepository.users`).
///
/// Se rafraîchit tout seul toutes les 20 s tant qu'un écran l'observe (la
/// liste, ou une conversation ouverte qui en tire la présence de son
/// interlocuteur) : « En ligne » / « Vu à… » et les badges de non-lus sont
/// recalculés côté serveur à chaque appel, rien n'est poussé. Pendant un
/// rafraîchissement `.value` garde la dernière liste connue — pas de spinner,
/// et une erreur réseau ne vide pas la liste (le web ne signale pas non plus
/// l'échec d'un fetch silencieux).
final chatUsersProvider = FutureProvider.autoDispose<List<ChatUser>>((ref) async {
  final timer = Timer(kChatUsersRefreshInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.read(chatRepositoryProvider).users();
});

/// "En ligne" / "Vu à l'instant" / "Vu il y a X min" / "Vu à HH:mm" / "Hors
/// ligne" — même formulation que `formatLastSeen()` côté web
/// (chats/page.tsx). Public pour l'en-tête de chat_conversation_screen.dart.
String presenceLabel(ChatUser user) {
  if (user.isOnline) return 'En ligne';
  final seen = lastSeenLabel(user.lastSeenAt);
  return seen != null ? 'Vu $seen' : 'Hors ligne';
}

/// `formatLastSeen()` du web : < 1 min -> "à l'instant" ; < 60 min -> "il y a
/// N min" ; sinon "à HH:mm" (heure du magasin, cf. core/app_time.dart).
String? lastSeenLabel(DateTime? date) {
  if (date == null) return null;
  final diffMin = DateTime.now().toUtc().difference(date.toUtc()).inMinutes;
  if (diffMin < 1) return "à l'instant";
  if (diffMin < 60) return 'il y a $diffMin min';
  final local = appLocal(date);
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return 'à $hh:$mm';
}

/// Couleur du badge de rôle — `getRoleBadgeColor()` du web : admin = rose,
/// magasin = bleu, employer = émeraude, inconnu = gris.
Color chatRoleColor(BuildContext context, String role) {
  switch (role) {
    case 'admin':
      return const Color(0xFFE11D48);
    case 'magasin':
      return const Color(0xFF2563EB);
    case 'employer':
      return const Color(0xFF059669);
    default:
      return Theme.of(context).colorScheme.outline;
  }
}

/// Petit badge de rôle en capitales (« ADMIN » / « GÉRANT » / « EMPLOYÉ »).
class ChatRoleBadge extends StatelessWidget {
  const ChatRoleBadge({super.key, required this.role, this.compact = true});

  final String role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = chatRoleColor(context, role);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: compact ? 1 : 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        chatRoleLabel(role).toUpperCase(),
        style: TextStyle(fontSize: compact ? 9 : 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.3),
      ),
    );
  }
}

/// Avatar à initiales (`getInitials()` du web) + pastille verte en bas à
/// droite si le contact est en ligne — réutilisé par l'en-tête de
/// conversation.
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({super.key, required this.user, this.radius = 20});

  final ChatUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          foregroundColor: scheme.primary,
          child: Text(
            user.initials,
            style: TextStyle(fontSize: radius * 0.65, fontWeight: FontWeight.w700),
          ),
        ),
        if (user.isOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Largeur à partir de laquelle la liste et la conversation s'affichent côte
/// à côte (colonnes `md:` du web) — au-delà du sidebar du shell.
const double _kSplitBreakpoint = 1000;

/// Délai du filtre local — `useDebouncedValue(searchQuery, 250)` du web.
const Duration _kSearchDebounce = Duration(milliseconds: 250);

/// Page `/chats` du web (chats/page.tsx) : la messagerie ne comporte plus que
/// des conversations DIRECTES (le salon « Général » a été retiré). Colonne
/// « Conversations » : recherche, contacts triés (non-lus d'abord, puis la
/// plus récente), badge de non-lus par contact, présence « En ligne » /
/// « Vu à… », rafraîchie toutes les 20 s et à chaque ouverture de
/// conversation.
///
/// Sur un écran étroit, ouvrir un contact pousse la conversation
/// (`/chats/dm/:id`) ; sur un écran large, elle s'affiche à côté de la liste
/// comme sur le web.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  /// Interlocuteur affiché dans le volet de droite (écran large uniquement).
  ChatUser? _selected;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_kSearchDebounce, () {
      if (mounted) setState(() => _query = value);
    });
  }

  /// Tirer pour rafraîchir — refetch NON silencieux : l'échec est signalé
  /// (« Impossible de charger la liste des collaborateurs. »).
  Future<void> _refresh() async {
    try {
      ref.invalidate(chatUsersProvider);
      await ref.read(chatUsersProvider.future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de charger la liste des collaborateurs. ${ApiClient.messageFromError(e)}')),
      );
    }
  }

  /// `handleSelectUser` : ouvre la conversation (volet de droite sur écran
  /// large, route poussée sinon). L'ouverture relit la liste tout de suite
  /// (côté conversation) pour que le badge de non-lus retombe sans attendre
  /// le prochain rafraîchissement périodique.
  void _open(ChatUser user, bool split) {
    if (split) {
      setState(() => _selected = user);
    } else {
      context.push('/chats/dm/${user.id}', extra: user.fullName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final split = MediaQuery.sizeOf(context).width >= _kSplitBreakpoint;
    final async = ref.watch(chatUsersProvider);
    // `.value` garde la dernière liste pendant un rafraîchissement (silencieux
    // ou tiré) au lieu de tout remplacer par un spinner toutes les 20 s.
    final users = async.value;

    final list = Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.group_outlined, size: 20), SizedBox(width: 8), Text('Conversations')],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher un collaborateur...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: users != null
          ? _UsersList(
              users: users,
              query: _query,
              selectedId: split ? _selected?.id : null,
              onRefresh: _refresh,
              onTap: (u) => _open(u, split),
            )
          : switch (async) {
              AsyncError(:final error) => ErrorState(
                message: 'Impossible de charger la liste des collaborateurs.\n${ApiClient.messageFromError(error)}',
                onRetry: () => ref.invalidate(chatUsersProvider),
              ),
              _ => const _CenteredLoader(label: 'Chargement des collaborateurs...'),
            },
    );

    if (!split) return list;

    // Écran large : liste à gauche (largeur fixe, comme la colonne `md:w-80`
    // du web) et conversation active à droite.
    final selected = _selected;
    return Row(
      children: [
        SizedBox(width: 340, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Scaffold(
                  body: EmptyState(
                    message: 'Choisissez un collaborateur pour ouvrir la conversation.',
                    icon: Icons.chat_bubble_outline,
                  ),
                )
              : ChatConversationScreen(
                  key: ValueKey('dm-${selected.id}'),
                  recipientId: selected.id,
                  title: selected.fullName,
                  embedded: true,
                ),
        ),
      ],
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Liste filtrée des contacts (l'ordre vient du repository) avec tirer pour
/// rafraîchir ; « Aucun collaborateur trouvé » si le filtre ne laisse rien.
class _UsersList extends StatelessWidget {
  const _UsersList({
    required this.users,
    required this.query,
    required this.selectedId,
    required this.onRefresh,
    required this.onTap,
  });

  final List<ChatUser> users;
  final String query;
  final int? selectedId;
  final Future<void> Function() onRefresh;
  final ValueChanged<ChatUser> onTap;

  @override
  Widget build(BuildContext context) {
    final filtered = users.where((u) => u.matchesSearch(query)).toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: filtered.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                EmptyState(message: 'Aucun collaborateur trouvé', icon: Icons.person_search_outlined),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final u = filtered[i];
                return _UserTile(user: u, selected: selectedId == u.id, onTap: () => onTap(u));
              },
            ),
    );
  }
}

/// Une ligne de contact : avatar + pastille de présence, nom, badge de
/// non-lus, badge de rôle, magasin (ou « Administration »), présence.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.selected, required this.onTap});

  final ChatUser user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final unread = user.hasUnread;
    final presenceColor = user.isOnline ? const Color(0xFF059669) : muted.withValues(alpha: 0.8);

    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: PresenceAvatar(user: user),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14),
            ),
          ),
          if (unread) ...[
            const SizedBox(width: 6),
            Semantics(
              label:
                  '${user.unreadCount} message${user.unreadCount > 1 ? 's' : ''} non lu${user.unreadCount > 1 ? 's' : ''}',
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(9)),
                child: Text(
                  user.unreadBadgeLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          ChatRoleBadge(role: user.role),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(user.shopName != null ? Icons.storefront_outlined : Icons.shield_outlined, size: 12, color: muted),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  user.shopName ?? 'Administration',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            presenceLabel(user),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: presenceColor,
              fontWeight: user.isOnline ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
