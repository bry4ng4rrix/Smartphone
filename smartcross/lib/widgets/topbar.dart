import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/nav_items.dart';
import '../core/permissions.dart';
import '../features/notifications/notifications_screen.dart'
    show
        NotificationTypeChip,
        formatNotificationDate,
        notificationTypeIcon,
        realtimeStatusFrom,
        RealtimeStatusX;
import '../models/app_notification.dart';
import '../models/user.dart';
import '../state/auth_provider.dart';
import '../state/theme_provider.dart';
import '../state/chat_unread_provider.dart';
import '../state/notifications_provider.dart';
import '../state/realtime_provider.dart';

/// Barre supérieure (frontend/components/layout/topbar.tsx) : cloche de
/// notifications avec menu déroulant et compteur, état du temps réel, menu
/// utilisateur (identité, « Mon profil », « Déconnexion »).
///
/// C'est aussi ELLE qui émet le toast global de l'application pour chaque
/// notification poussée par WebSocket (`useNotificationsWebSocket({showToast:
/// true})` de la cloche web) — elle est montée sur toutes les pages du shell.
class TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const TopBar({super.key, this.onMenuTap, this.menuBadgeCount = 0});

  final VoidCallback? onMenuTap;

  /// Nombre affiché sur le bouton du tiroir (mobile) — messages non lus,
  /// pour que le badge « Discussions » du menu soit visible tiroir fermé.
  final int menuBadgeCount;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  /// Table de libellés de rôle du web (rôle Django brut) — le sous-rôle
  /// commande, que le web n'affiche pas, est ajouté ici pour lever
  /// l'ambiguïté « Commercial » d'un préparateur / livreur.
  static String roleLabel(AppUser user) {
    const labels = {'admin': 'Administrateur', 'magasin': 'Gérant de magasin', 'employer': 'Commercial'};
    final raw = user.rawRole;
    final base = raw == null || raw.isEmpty ? null : (labels[raw] ?? raw);
    final sousRole = user.isPreparateur
        ? 'Préparateur'
        : user.isLivreur
            ? 'Livreur'
            : null;
    return [base, sousRole].whereType<String>().join(' · ');
  }

  /// Initiales : premières lettres des mots du nom complet, 2 au plus,
  /// « U » à défaut.
  static String initials(AppUser? user) {
    final parts = (user?.fullName ?? '').split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    return parts.map((p) => p[0]).join().toUpperCase().substring(0, math.min(2, parts.length));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final status = realtimeStatusFrom(ref.watch(wsConnectionStatusProvider));

    // Toast temps réel — `toast.info(message, {description: 'Type : …',
    // duration: 5000})`, pour toute l'application.
    ref.listen<AsyncValue<AppNotification>>(incomingNotificationProvider, (previous, next) {
      // Une trame = un AsyncData ; un état d'erreur/chargement peut encore
      // porter la valeur précédente, qu'il ne faut pas ré-annoncer.
      if (next is! AsyncData<AppNotification>) return;
      final n = next.value;
      final canSeeAll = user != null && canAccessPath(user, '/notifications');
      // Un message privé mène directement à la messagerie ; le reste à la
      // page Notifications. (En arrière-plan, la même trame devient une
      // notification système — voir state/push_notifications_provider.dart.)
      final cible = n.type == 'chat' ? '/chats' : (canSeeAll ? '/notifications' : null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.message, maxLines: 3, overflow: TextOverflow.ellipsis),
                Text('Type : ${n.typeLabel}', style: const TextStyle(fontSize: 12)),
              ],
            ),
            action: cible != null ? SnackBarAction(label: 'Voir', onPressed: () => context.go(cible)) : null,
          ),
        );
    });

    return AppBar(
      leading: onMenuTap != null
          ? IconButton(
              tooltip: 'Menu',
              icon: Badge(
                label: Text(chatUnreadBadgeLabel(menuBadgeCount)),
                isLabelVisible: menuBadgeCount > 0,
                child: const Icon(Icons.menu),
              ),
              onPressed: onMenuTap,
            )
          : null,
      automaticallyImplyLeading: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.phone_iphone, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Smartphone.Mg', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: status.label,
            child: Icon(Icons.circle, size: 10, color: status.color),
          ),
        ),
        const NotificationsBell(),
        const _ThemeToggleButton(),
        PopupMenuButton<String>(
          tooltip: 'Compte',
          onSelected: (value) async {
            if (value == 'logout') {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            } else if (value == 'profile') {
              context.go('/settings');
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.fullName.isNotEmpty == true ? user!.fullName : 'Utilisateur',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user != null && user.email.isNotEmpty)
                    Text(user.email, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                  if (user != null && roleLabel(user).isNotEmpty)
                    Text(
                      roleLabel(user),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            // « Mon profil » -> /settings : proposé seulement à ceux que le
            // routeur laisse passer (core/nav_items.dart::canAccessPath).
            if (user != null && canAccessPath(user, '/settings'))
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_outline, size: 20),
                  title: Text('Mon profil'),
                ),
              ),
            PopupMenuItem(
              value: 'logout',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, size: 20, color: Theme.of(context).colorScheme.error),
                title: Text('Déconnexion', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF2563EB),
              child: Text(
                initials(user),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cloche de notifications (frontend/components/notifications.tsx) :
/// compteur de non-lues (« 9+ » au-delà de 9), menu déroulant avec les 8
/// dernières notifications, « Tout marquer lu », « Tout effacer » (local),
/// « Marquer lu » unitaire, lien vers la page complète — et, en plus,
/// l'ouverture de la commande citée par une notification.
class NotificationsBell extends ConsumerStatefulWidget {
  const NotificationsBell({super.key});

  @override
  ConsumerState<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends ConsumerState<NotificationsBell> {
  final _menuController = MenuController();
  bool _resolvingOrder = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _seeAll() {
    _menuController.close();
    context.go('/notifications');
  }

  /// Deep-link « Voir la commande » depuis le menu : ferme le menu, marque
  /// la notification lue (silencieusement, comme `markAsRead` du web) et
  /// ouvre la fiche.
  Future<void> _openOrder(AppNotification n) async {
    if (_resolvingOrder || n.orderNumero == null) return;
    _menuController.close();
    setState(() => _resolvingOrder = true);
    if (!n.isRead && n.isPersisted) {
      // Échec silencieux (`console.error('Mark read error:')`).
      ref.read(notificationsProvider.notifier).markRead(n.id).catchError((_) {});
    }
    try {
      final id = await ref.read(notificationsProvider.notifier).resolveOrderId(n);
      if (!mounted) return;
      if (id == null) {
        _snack('Commande ${n.orderNumero} introuvable — ou pas accessible avec votre rôle.');
        return;
      }
      context.push('/orders/$id');
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _resolvingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationsCountProvider);
    final user = ref.watch(authProvider.select((a) => a.user));
    final canSeeAll = user != null && canAccessPath(user, '/notifications');
    // `w-96` (384 px), sans jamais déborder de l'écran.
    final panelWidth = math.min(384.0, MediaQuery.sizeOf(context).width - 16);

    return MenuAnchor(
      controller: _menuController,
      alignmentOffset: const Offset(0, 4),
      style: const MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        alignment: AlignmentDirectional.bottomEnd,
      ),
      menuChildren: [
        SizedBox(
          width: panelWidth,
          child: _NotificationsPanel(
            canSeeAll: canSeeAll,
            onSeeAll: _seeAll,
            onOpenOrder: _openOrder,
          ),
        ),
      ],
      builder: (context, controller, child) {
        return IconButton(
          tooltip: 'Notifications',
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: _resolvingOrder
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Badge(
                  label: Text(notificationsBadgeLabel(unread)),
                  isLabelVisible: unread > 0,
                  child: const Icon(Icons.notifications_outlined),
                ),
        );
      },
    );
  }
}

/// Contenu du menu déroulant de la cloche.
class _NotificationsPanel extends ConsumerStatefulWidget {
  const _NotificationsPanel({required this.canSeeAll, required this.onSeeAll, required this.onOpenOrder});

  final bool canSeeAll;
  final VoidCallback onSeeAll;
  final ValueChanged<AppNotification> onOpenOrder;

  @override
  ConsumerState<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends ConsumerState<_NotificationsPanel> {
  /// Les 8 premières seulement (`notifications.slice(0, 8)`).
  static const int _maxItems = 8;

  /// `actionLoading` : désactive « Tout marquer lu » pendant l'appel.
  bool _actionLoading = false;

  /// `markAsRead(id)` — mise à jour optimiste, échec silencieux
  /// (`console.error('Mark read error:')`).
  Future<void> _markRead(AppNotification n) async {
    try {
      await ref.read(notificationsProvider.notifier).markRead(n.id);
    } catch (_) {
      // silencieux, comme sur le web
    }
  }

  /// `markAllAsRead()` — garde `unreadCount === 0 || actionLoading`.
  Future<void> _markAllRead(int unread) async {
    if (unread == 0 || _actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await ref.read(notificationsProvider.notifier).markAllRead();
    } catch (_) {
      // silencieux, comme sur le web (`console.error('Mark all read error:')`)
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  /// `clearAll()` — PUREMENT LOCAL : rien n'est supprimé en base, les
  /// identifiants sont mémorisés sur l'appareil et la liste se vide.
  void _clearAll(List<AppNotification> visible) {
    if (visible.isEmpty) return;
    ref.read(dismissedNotificationIdsProvider.notifier).dismiss(visible.map((n) => n.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(notificationsProvider);
    final visible = ref.watch(bellNotificationsProvider);
    final unread = ref.watch(unreadNotificationsCountProvider);
    // `loading` : seulement tant que rien n'a jamais été chargé (pas de
    // bouton actualiser dans la cloche).
    final loading = !async.hasValue && !async.hasError;

    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (visible.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_outlined, size: 32, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text('Aucune notification', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    } else {
      final items = visible.take(_maxItems).toList();
      body = ConstrainedBox(
        // `max-h-96` (384 px) : la liste défile dans le menu.
        constraints: const BoxConstraints(maxHeight: 384),
        child: ListView.separated(
          shrinkWrap: true,
          // Le panneau du MenuAnchor a déjà son propre PrimaryScrollController
          // (attaché à sa Scrollbar) : cette liste ne doit pas l'hériter.
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (context, i) => const Divider(height: 1),
          itemBuilder: (context, i) => _PanelItem(
            notification: items[i],
            onMarkRead: () => _markRead(items[i]),
            onOpenOrder: items[i].orderNumero == null ? null : () => widget.onOpenOrder(items[i]),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$unread non lue${unread > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
                  ),
                ),
            ],
          ),
        ),
        if (visible.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.onSurfaceVariant,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: unread == 0 || _actionLoading ? null : () => _markAllRead(unread),
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Tout marquer lu'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.onSurfaceVariant,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _clearAll(visible),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Tout effacer'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        body,
        const Divider(height: 1),
        // Toujours affiché sur le web, même liste vide — ici seulement si le
        // routeur laisse cet utilisateur atteindre la page.
        if (widget.canSeeAll)
          TextButton(
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            onPressed: widget.onSeeAll,
            child: const Text('Voir toutes les notifications'),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Les $_maxItems dernières notifications',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Élément du menu : pastille d'icône (atténuée si lue), message tronqué à 2
/// lignes, point de non-lu, badge de type, date, « Marquer lu » si non lue,
/// « Voir la commande » si le message en cite une. Aucune navigation au
/// simple appui — le menu reste ouvert.
class _PanelItem extends StatelessWidget {
  const _PanelItem({required this.notification, required this.onMarkRead, required this.onOpenOrder});

  final AppNotification notification;
  final VoidCallback onMarkRead;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = notification;
    final unread = !n.isRead;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: unread ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHighest,
            child: Icon(notificationTypeIcon(n), size: 16, color: unread ? scheme.primary : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        n.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          color: unread ? null : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (unread)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 4),
                        child: Icon(Icons.circle, size: 8, color: scheme.primary),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NotificationTypeChip(notification: n),
                    if (n.createdAt != null)
                      Text(
                        formatNotificationDate(n.createdAt!),
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    if (onOpenOrder != null)
                      _LinkButton(label: 'Voir la commande', onPressed: onOpenOrder!),
                    if (unread && n.isPersisted) _LinkButton(label: 'Marquer lu', onPressed: onMarkRead),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Petit lien texte (« Marquer lu », « Voir la commande »).
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}


/// Bouton Soleil / Lune de la TopBar web : Lune tant que l'affichage est
/// clair, Soleil quand il est sombre ; un appui bascule (et mémorise).
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Thème clair' : 'Thème sombre',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(MediaQuery.platformBrightnessOf(context)),
    );
  }
}
