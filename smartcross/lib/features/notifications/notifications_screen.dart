import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/notifications_socket_service.dart';
import '../../models/app_notification.dart';
import '../../state/notifications_provider.dart';
import '../../state/realtime_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/status_badge.dart';

// ---------------------------------------------------------------------------
// Helpers visuels partagés par la page et par la cloche de la barre
// supérieure (widgets/topbar.dart) — équivalents de
// frontend/lib/notifications-utils.tsx.
// ---------------------------------------------------------------------------

final _notificationDateFmt = DateFormat('dd/MM/yyyy HH:mm');

/// `formatNotificationDate` du web (`10/09/2026 14:32`, ni secondes ni
/// « il y a X minutes »), à l'heure d'Antananarivo (core/app_time.dart).
String formatNotificationDate(DateTime value) => _notificationDateFmt.format(appLocal(value));

/// `typeIcon()` du web (sale=Package, user=User, product=Mail,
/// chat=MessageSquare, transfer=ArrowLeftRight, movement=ArrowUpDown, défaut
/// Bell), complété par les types réellement émis par le serveur — dont les
/// deux sous-types « commande » du §9 README.
IconData notificationTypeIcon(AppNotification notification) {
  switch (notification.type) {
    case 'sale':
      return Icons.inventory_2_outlined;
    case 'user':
      return Icons.person_outline;
    case 'product':
      return Icons.mail_outline;
    case 'chat':
      return Icons.chat_bubble_outline;
    case 'transfer':
      return Icons.compare_arrows_outlined;
    case 'movement':
      return Icons.swap_vert_outlined;
    case 'order':
      return notification.notifType == NotifType.commandePrete
          ? Icons.local_shipping_outlined
          : Icons.receipt_long_outlined;
    case 'supplier_order':
      return Icons.local_shipping_outlined;
    case 'caisse':
      return Icons.point_of_sale_outlined;
    default:
      return Icons.notifications_outlined;
  }
}

/// `getTypeBadgeClass()` du web — couleurs de TYPE (comme celles de
/// widgets/status_badge.dart), pas des couleurs de thème : sale=vert,
/// product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange ;
/// plus les types serveur.
Color notificationTypeColor(String type) {
  switch (type) {
    case 'sale':
      return const Color(0xFF16A34A);
    case 'product':
      return const Color(0xFF2563EB);
    case 'user':
      return const Color(0xFF7C3AED);
    case 'chat':
      return const Color(0xFFD97706);
    case 'transfer':
      return const Color(0xFF0891B2);
    case 'movement':
      return const Color(0xFFEA580C);
    case 'order':
      return const Color(0xFF2563EB);
    case 'supplier_order':
      return const Color(0xFF0D9488);
    case 'caisse':
      return const Color(0xFF10B981);
    default:
      return const Color(0xFF64748B);
  }
}

/// Badge de type (`typeLabel` + `getTypeBadgeClass` du web).
class NotificationTypeChip extends StatelessWidget {
  const NotificationTypeChip({super.key, required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    return StatusChip(label: notification.typeLabel, color: notificationTypeColor(notification.type));
  }
}

/// Ligne de métadonnées de la carte web : `Utilisateur : X` (si présent),
/// puis ` · Magasin : Y` (si présent), puis ` · date` (si présente).
String notificationMetaLine(AppNotification notification) {
  final magasin = notification.magasinName?.trim();
  return [
    notification.subjectLabel,
    if (magasin != null && magasin.isNotEmpty) 'Magasin : $magasin',
    if (notification.createdAt != null) formatNotificationDate(notification.createdAt!),
  ].whereType<String>().join(' · ');
}

/// Les 3 états du socket temps réel du web (`useNotificationsWebSocket`).
enum RealtimeStatus { connected, connecting, disconnected }

/// État courant dérivé de `wsConnectionStatusProvider`. Ce flux ne rejoue
/// pas la dernière valeur à un nouvel abonné : tant qu'aucun changement
/// n'est arrivé, on lit directement l'état de la connexion.
RealtimeStatus realtimeStatusFrom(AsyncValue<bool> status) {
  if (status.hasValue) return status.value! ? RealtimeStatus.connected : RealtimeStatus.disconnected;
  return NotificationsSocketService.instance.isConnected ? RealtimeStatus.connected : RealtimeStatus.connecting;
}

extension RealtimeStatusX on RealtimeStatus {
  String get label {
    switch (this) {
      case RealtimeStatus.connected:
        return 'Temps réel';
      case RealtimeStatus.connecting:
        return 'Connexion...';
      case RealtimeStatus.disconnected:
        return 'Déconnecté';
    }
  }

  /// `getSocketStatusBadgeClass` : émeraude / ambre / rose.
  Color get color {
    switch (this) {
      case RealtimeStatus.connected:
        return const Color(0xFF059669);
      case RealtimeStatus.connecting:
        return const Color(0xFFD97706);
      case RealtimeStatus.disconnected:
        return const Color(0xFFE11D48);
    }
  }
}

/// Pastille d'état du temps réel (en-tête de la page web) : point vert
/// « Temps réel », spinner « Connexion... », icône d'alerte « Déconnecté ».
class RealtimeStatusBadge extends ConsumerWidget {
  const RealtimeStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = realtimeStatusFrom(ref.watch(wsConnectionStatusProvider));
    final color = status.color;
    final Widget indicator = switch (status) {
      RealtimeStatus.connected => Icon(Icons.circle, size: 8, color: color),
      RealtimeStatus.connecting => SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        ),
      RealtimeStatus.disconnected => Icon(Icons.error_outline, size: 12, color: color),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(width: 6),
          Text(status.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Filtre lu / non lu (client — l'API n'a pas de paramètre de filtre).
enum _ReadFilter { toutes, nonLues, lues }

/// Page `/notifications` du web (frontend/app/(app)/notifications/page.tsx)
/// — « Historique des notifications » : liste complète, marquage lu / non lu
/// unitaire et global, suppression unitaire et globale, indicateur temps
/// réel. En plus côté mobile : filtres (lu/non lu, type), sélection multiple
/// (`bulk-read` / `bulk-delete`, exposés par l'API mais inutilisés par la
/// page web) et deep-link vers la commande citée par la notification.
///
/// Gating : la page web n'a AUCUN garde interne — seul le lien de menu est
/// `adminOnly`. Ici le contrôle est fait en amont par `core/router.dart` /
/// `core/nav_items.dart::canAccessPath`. Le contenu est de toute façon
/// cloisonné par le serveur.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Rechargement NON silencieux en cours (« Actualiser », « Réessayer ») —
  /// Riverpod 3 conserve la valeur précédente pendant un `AsyncLoading`,
  /// l'écran s'en souvient donc lui-même pour afficher le chargement.
  bool _refreshing = false;

  /// `actionLoading` du web : désactive les boutons d'en-tête et ceux de
  /// chaque carte pendant une action.
  bool _actionLoading = false;

  /// Notification dont la commande est en cours de résolution (deep-link).
  int? _resolvingId;

  _ReadFilter _readFilter = _ReadFilter.toutes;

  /// `notif_type` retenu, `null` = tous.
  String? _typeFilter;

  bool _selectionMode = false;
  final Set<int> _selected = <int>{};

  // ----- helpers -----------------------------------------------------------

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Message d'échec du web, complété par la raison donnée par le serveur
  /// quand il y en a une (ex : 403 « Permission refusée » sur une
  /// suppression).
  String _failure(String base, Object error) {
    if (error is DioException && error.response?.data is Map) {
      final detail = ApiClient.messageFromError(error);
      if (detail.isNotEmpty) return '$base ($detail)';
    }
    return base;
  }

  /// Exécute une action sous `actionLoading`, avec toast de succès / d'échec.
  Future<bool> _run(Future<void> Function() action, {required String success, required String failure}) async {
    if (_actionLoading) return false;
    setState(() => _actionLoading = true);
    try {
      await action();
      _snack(success);
      return true;
    } catch (e) {
      _snack(_failure(failure, e));
      return false;
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<bool> _confirm({required String title, required String message, required String confirmLabel}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ----- chargement --------------------------------------------------------

  /// Bouton « Actualiser » du web : `fetchNotifications()` NON silencieux
  /// (les skeletons réapparaissent).
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(notificationsProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    _signalLoadError();
  }

  /// Tirer-pour-rafraîchir : la liste reste affichée.
  Future<void> _silentRefresh() async {
    await ref.read(notificationsProvider.notifier).refreshSilencieux();
    _signalLoadError();
  }

  /// Web : `toast.error('Impossible de charger les notifications.')`, la
  /// liste précédente est conservée.
  void _signalLoadError() {
    if (!mounted) return;
    final after = ref.read(notificationsProvider);
    if (after.hasError && after.hasValue) _snack('Impossible de charger les notifications.');
  }

  // ----- actions -----------------------------------------------------------

  Future<void> _toggleRead(AppNotification n) {
    final wasRead = n.isRead;
    return _run(
      () => ref.read(notificationsProvider.notifier).setRead(n.id, !wasRead),
      success: wasRead ? 'Notification marquée non lue' : 'Notification marquée lue',
      failure: 'Impossible de mettre à jour la notification.',
    );
  }

  Future<void> _markAllRead() {
    return _run(
      () => ref.read(notificationsProvider.notifier).markAllRead(),
      success: 'Toutes les notifications ont été marquées comme lues.',
      failure: 'Impossible de marquer toutes les notifications comme lues.',
    );
  }

  /// Suppression unitaire — immédiate, sans confirmation, comme sur le web.
  Future<void> _delete(AppNotification n) {
    return _run(
      () => ref.read(notificationsProvider.notifier).delete(n.id),
      success: 'Notification supprimée.',
      failure: 'Impossible de supprimer la notification.',
    );
  }

  /// « Supprimer tout » : suppression EN BASE de toutes les notifications
  /// visibles (pas seulement celles affichées par les filtres) —
  /// irréversible, d'où une confirmation.
  Future<void> _deleteAll(int total) async {
    final ok = await _confirm(
      title: 'Supprimer tout',
      message: 'Supprimer définitivement les $total notification(s) ? '
          'Toutes les notifications sont concernées, filtres compris. Cette action est irréversible.',
      confirmLabel: 'Supprimer tout',
    );
    if (!ok) return;
    final done = await _run(
      () => ref.read(notificationsProvider.notifier).deleteAll(),
      success: 'Toutes les notifications ont été supprimées.',
      failure: 'Impossible de supprimer les notifications.',
    );
    if (done) _exitSelection();
  }

  // ----- sélection multiple ------------------------------------------------

  void _enterSelection([AppNotification? first]) {
    setState(() {
      _selectionMode = true;
      _selected.clear();
      if (first != null) _selected.add(first.id);
    });
  }

  void _exitSelection() {
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(AppNotification n) {
    setState(() {
      if (!_selected.remove(n.id)) _selected.add(n.id);
    });
  }

  void _selectAll(List<AppNotification> visible) {
    setState(() {
      if (_selected.length == visible.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(visible.map((n) => n.id));
      }
    });
  }

  Future<void> _bulkRead() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final done = await _run(
      () => ref.read(notificationsProvider.notifier).bulkRead(ids),
      success: '${ids.length} notification(s) marquée(s) lue(s).',
      failure: 'Impossible de mettre à jour les notifications sélectionnées.',
    );
    if (done) _exitSelection();
  }

  Future<void> _bulkDelete() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final ok = await _confirm(
      title: 'Supprimer la sélection',
      message: 'Supprimer définitivement ${ids.length} notification(s) ? Cette action est irréversible.',
      confirmLabel: 'Supprimer',
    );
    if (!ok) return;
    final done = await _run(
      () => ref.read(notificationsProvider.notifier).bulkDelete(ids),
      success: '${ids.length} notification(s) supprimée(s).',
      failure: 'Impossible de supprimer les notifications sélectionnées.',
    );
    if (done) _exitSelection();
  }

  // ----- deep-link commande ------------------------------------------------

  /// Ouvre la commande citée par la notification (`CMD-…` dans le message).
  /// La notification passe « lue » au passage, silencieusement.
  Future<void> _openOrder(AppNotification n) async {
    if (_resolvingId != null || n.orderNumero == null) return;
    setState(() => _resolvingId = n.id);
    if (!n.isRead && n.isPersisted) {
      unawaited(ref.read(notificationsProvider.notifier).markRead(n.id).catchError((_) {}));
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
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  /// Appui sur une carte : en mode sélection -> (dé)sélectionne ; sinon la
  /// notification passe lue si elle ne l'était pas, et sa commande s'ouvre
  /// si elle en cite une.
  void _onCardTap(AppNotification n) {
    if (_selectionMode) {
      _toggleSelected(n);
      return;
    }
    if (n.orderNumero != null) {
      _openOrder(n);
      return;
    }
    if (!n.isRead && !_actionLoading) _toggleRead(n);
  }

  // ----- filtres -----------------------------------------------------------

  List<AppNotification> _applyFilters(List<AppNotification> all) {
    return all.where((n) {
      if (_typeFilter != null && n.type != _typeFilter) return false;
      switch (_readFilter) {
        case _ReadFilter.toutes:
          return true;
        case _ReadFilter.nonLues:
          return !n.isRead;
        case _ReadFilter.lues:
          return n.isRead;
      }
    }).toList();
  }

  bool get _hasFilters => _typeFilter != null || _readFilter != _ReadFilter.toutes;

  void _resetFilters() {
    setState(() {
      _typeFilter = null;
      _readFilter = _ReadFilter.toutes;
    });
  }

  // ----- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    // Chargement « bloquant » : premier chargement et « Actualiser »
    // uniquement — un rafraîchissement temps réel garde la liste à l'écran.
    final initialLoading = !async.hasValue && !async.hasError;
    final loading = _refreshing || initialLoading;
    final all = async.value ?? const <AppNotification>[];
    final visible = _applyFilters(all);
    final unread = all.where((n) => !n.isRead).length;
    // Types présents dans la liste, dans l'ordre d'apparition (filtre).
    final types = <String>[];
    for (final n in all) {
      if (!types.contains(n.type)) types.add(n.type);
    }
    // Une sélection ne survit pas aux suppressions / relectures.
    _selected.removeWhere((id) => !all.any((n) => n.id == id));

    final headerDisabled = loading || _actionLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: headerDisabled ? null : _refresh,
              icon: loading
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Actualiser'),
            ),
          ),
        ],
      ),
      body: _buildBody(
        async: async,
        loading: loading,
        all: all,
        visible: visible,
        unread: unread,
        types: types,
        headerDisabled: headerDisabled,
      ),
    );
  }

  Widget _buildBody({
    required AsyncValue<List<AppNotification>> async,
    required bool loading,
    required List<AppNotification> all,
    required List<AppNotification> visible,
    required int unread,
    required List<String> types,
    required bool headerDisabled,
  }) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text('Toutes les alertes et mouvements enregistrés de l\'application.', style: muted),
              const RealtimeStatusBadge(),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: headerDisabled || all.isEmpty ? null : _markAllRead,
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Marquer tout lu'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: headerDisabled || all.isEmpty ? null : () => _deleteAll(all.length),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Supprimer tout'),
              ),
              OutlinedButton.icon(
                onPressed: loading || all.isEmpty
                    ? null
                    : _selectionMode
                        ? _exitSelection
                        : _enterSelection,
                icon: Icon(_selectionMode ? Icons.close : Icons.checklist_outlined, size: 18),
                label: Text(_selectionMode ? 'Annuler la sélection' : 'Sélectionner'),
              ),
            ],
          ),
        ],
      ),
    );

    if (loading) {
      return ListView(
        children: [header, const SizedBox(height: 160, child: LoadingState())],
      );
    }
    // Le web se contente d'un toast et garde la liste précédente : l'écran
    // d'erreur n'apparaît que s'il n'y a rien à montrer.
    if (async.hasError && !async.hasValue) {
      return ListView(
        children: [
          header,
          SizedBox(
            height: 240,
            child: ErrorState(message: ApiClient.messageFromError(async.error!), onRetry: _refresh),
          ),
        ],
      );
    }

    final filters = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_ReadFilter>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                const ButtonSegment(value: _ReadFilter.toutes, label: Text('Toutes')),
                ButtonSegment(value: _ReadFilter.nonLues, label: Text(unread > 0 ? 'Non lues ($unread)' : 'Non lues')),
                const ButtonSegment(value: _ReadFilter.lues, label: Text('Lues')),
              ],
              selected: {_readFilter},
              onSelectionChanged: (s) => setState(() => _readFilter = s.first),
            ),
          ),
          if (types.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Tous les types'),
                  selected: _typeFilter == null,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _typeFilter = null),
                ),
                for (final type in types)
                  ChoiceChip(
                    label: Text(notificationTypeLabel(type)),
                    selected: _typeFilter == type,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _typeFilter = _typeFilter == type ? null : type),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    final selectionBar = !_selectionMode
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Material(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${_selected.length} sélectionnée(s)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextButton(
                      onPressed: visible.isEmpty ? null : () => _selectAll(visible),
                      child: Text(_selected.length == visible.length && visible.isNotEmpty ? 'Aucune' : 'Tout sélectionner'),
                    ),
                    TextButton.icon(
                      onPressed: _selected.isEmpty || _actionLoading ? null : _bulkRead,
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Marquer lues'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: _selected.isEmpty || _actionLoading ? null : _bulkDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Supprimer'),
                    ),
                  ],
                ),
              ),
            ),
          );

    final listTitle = Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text('Historique des notifications', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(
            _hasFilters ? '${visible.length} / ${all.length}' : '${all.length}',
            style: muted,
          ),
        ],
      ),
    );

    Widget emptyBlock;
    if (all.isEmpty) {
      emptyBlock = const SizedBox(
        height: 200,
        child: EmptyState(message: 'Aucune notification pour le moment.', icon: Icons.notifications_none),
      );
    } else if (visible.isEmpty) {
      emptyBlock = Column(
        children: [
          const SizedBox(
            height: 140,
            child: EmptyState(message: 'Aucune notification ne correspond aux filtres.', icon: Icons.filter_alt_off_outlined),
          ),
          TextButton(onPressed: _resetFilters, child: const Text('Réinitialiser les filtres')),
          const SizedBox(height: 16),
        ],
      );
    } else {
      emptyBlock = const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _silentRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverToBoxAdapter(child: filters),
          if (selectionBar != null) SliverToBoxAdapter(child: selectionBar),
          SliverToBoxAdapter(child: listTitle),
          if (visible.isEmpty) SliverToBoxAdapter(child: emptyBlock),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final n = visible[i];
                return _NotificationCard(
                  notification: n,
                  selectionMode: _selectionMode,
                  selected: _selected.contains(n.id),
                  actionsDisabled: _actionLoading,
                  resolvingOrder: _resolvingId == n.id,
                  onTap: () => _onCardTap(n),
                  onLongPress: _selectionMode ? null : () => _enterSelection(n),
                  onToggleRead: () => _toggleRead(n),
                  onDelete: () => _delete(n),
                  onOpenOrder: n.orderNumero == null ? null : () => _openOrder(n),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'une notification (une par élément, pas de tableau) : pastille
/// d'icône de type, message, badge de type, badge « Nouveau » si non lue,
/// ligne de métadonnées, bouton lu / non lu, bouton de suppression — et le
/// lien vers la commande citée.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.selectionMode,
    required this.selected,
    required this.actionsDisabled,
    required this.resolvingOrder,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleRead,
    required this.onDelete,
    required this.onOpenOrder,
  });

  final AppNotification notification;
  final bool selectionMode;
  final bool selected;
  final bool actionsDisabled;
  final bool resolvingOrder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = notification;
    final unread = !n.isRead;
    final typeColor = notificationTypeColor(n.type);
    final meta = notificationMetaLine(n);

    // `getNotificationCardClass` : non lue = teinte primaire + bordure
    // primaire ; lue = fond atténué.
    final Color cardColor = selected
        ? scheme.secondaryContainer.withValues(alpha: 0.6)
        : unread
            ? scheme.primaryContainer.withValues(alpha: 0.25)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.3);
    final borderColor = selected
        ? scheme.secondary
        : unread
            ? scheme.primary.withValues(alpha: 0.35)
            : scheme.outlineVariant;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: borderColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(value: selected, onChanged: (_) => onTap()),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 10),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: typeColor.withValues(alpha: 0.12),
                    child: Icon(notificationTypeIcon(n), color: typeColor, size: 18),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.message,
                      style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        NotificationTypeChip(notification: n),
                        if (unread) StatusChip(label: 'Nouveau', color: scheme.primary),
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    if (onOpenOrder != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: resolvingOrder || selectionMode ? null : onOpenOrder,
                          icon: resolvingOrder
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.open_in_new, size: 16),
                          label: Text('Voir la commande ${n.orderNumero}'),
                        ),
                      ),
                  ],
                ),
              ),
              if (!selectionMode)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mail = « remettre non lue » (déjà lue), double coche =
                    // « marquer lue » (non lue) — comme les icônes du web.
                    IconButton(
                      tooltip: unread ? 'Marquer lue' : 'Marquer non lue',
                      visualDensity: VisualDensity.compact,
                      onPressed: actionsDisabled || !n.isPersisted ? null : onToggleRead,
                      icon: Icon(unread ? Icons.done_all : Icons.mail_outline, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      visualDensity: VisualDensity.compact,
                      color: scheme.error,
                      onPressed: actionsDisabled || !n.isPersisted ? null : onDelete,
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
