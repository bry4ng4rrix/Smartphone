import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/orders_provider.dart';
import '../../widgets/assign_staff_dialog.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/status_badge.dart';
import 'orders_list_screen.dart' show EditOrderDialog;

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');
String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

/// `fmtAppDateTime` du web : JJ/MM/AAAA HH:mm à l'heure d'Antananarivo, quel
/// que soit le fuseau de l'appareil — « — » si la valeur est absente.
String _fmtAppDateTime(DateTime? d) => d == null ? '—' : _dateTimeFmt.format(appLocal(d));

enum _ActionKind { status, assign }

/// Une action proposée depuis la fiche — miroir de `gerantActionOptions` /
/// `nextAction` de page.tsx : soit une transition de statut ([kind] =
/// status), soit la désignation d'une personne ([kind] = assign, [role]).
class _ActionOption {
  const _ActionOption({
    required this.label,
    required this.target,
    required this.icon,
    this.kind = _ActionKind.status,
    this.role,
  });
  final String label;
  final OrderStatus target;
  final IconData icon;
  final _ActionKind kind;

  /// 'PREPARATEUR' | 'LIVREUR' — pour une assignation.
  final String? role;

  bool get isAssign => kind == _ActionKind.assign;
}

const _assignerPreparateur = _ActionOption(
  label: 'Assigner un préparateur',
  target: OrderStatus.enPreparation,
  kind: _ActionKind.assign,
  role: 'PREPARATEUR',
  icon: Icons.person_add_alt_outlined,
);
const _assignerLivreur = _ActionOption(
  label: 'Assigner un livreur',
  target: OrderStatus.enLivraison,
  kind: _ActionKind.assign,
  role: 'LIVREUR',
  icon: Icons.person_add_alt_outlined,
);

/// Actions proposées au GÉRANT : uniquement les transitions réellement
/// possibles depuis le statut courant — le workflow ne revient jamais en
/// arrière, et une commande terminée (Livrée / Retour / Annulée) n'en propose
/// aucune. Mêmes règles que orders/services.py::TRANSITIONS.
///
/// Les boutons d'assignation ne sont proposés que tant que le poste est
/// vacant (§ demande) : une fois quelqu'un désigné, le bouton disparaît —
/// pour changer de personne, on passe par « Modifier ». Le livreur peut être
/// désigné à l'avance, dès que le préparateur l'est, sans attendre que la
/// commande soit prête. Un retrait sur place n'a jamais de livreur.
List<_ActionOption> _gerantActionOptions(Order order) {
  final sansPreparateur = order.preparateurId == null;
  final sansLivreur = order.livreurId == null && !order.estRecuperation;

  switch (order.statutCourant) {
    case OrderStatus.nouvelle:
      return [
        if (sansPreparateur) _assignerPreparateur,
        // Préparateur déjà en place : c'est le tour du livreur.
        if (!sansPreparateur && sansLivreur) _assignerLivreur,
        const _ActionOption(
          label: 'Commencer la préparation',
          target: OrderStatus.enPreparation,
          icon: Icons.inventory_2_outlined,
        ),
      ];
    case OrderStatus.enPreparation:
      return [
        if (sansLivreur) _assignerLivreur,
        const _ActionOption(label: 'Commande prête', target: OrderStatus.prete, icon: Icons.inventory_2_outlined),
      ];
    case OrderStatus.prete:
      // Retrait sur place : pas de livreur, le gérant clôture directement au
      // comptoir (voir services.py::change_order_status).
      if (order.estRecuperation) {
        return const [
          _ActionOption(label: 'Récupérée par le client', target: OrderStatus.livre, icon: Icons.inventory_2_outlined),
        ];
      }
      return [
        if (sansLivreur) _assignerLivreur,
        const _ActionOption(
          label: 'Récupérer / En livraison',
          target: OrderStatus.enLivraison,
          icon: Icons.local_shipping_outlined,
        ),
      ];
    case OrderStatus.enLivraison:
      return const [
        _ActionOption(label: 'Livrée', target: OrderStatus.livre, icon: Icons.local_shipping_outlined),
        _ActionOption(label: 'Retour', target: OrderStatus.retour, icon: Icons.undo),
      ];
    case OrderStatus.livre:
    case OrderStatus.retour:
    case OrderStatus.annulee:
      return const [];
  }
}

/// Action du moment pour le préparateur / le livreur (`nextAction` du web).
_ActionOption? _nextAction(Order order, {required bool isPreparateur, required bool isLivreur}) {
  if (isPreparateur) {
    switch (order.statutCourant) {
      case OrderStatus.nouvelle:
        return const _ActionOption(
          label: 'Commencer la préparation',
          target: OrderStatus.enPreparation,
          icon: Icons.inventory_2_outlined,
        );
      case OrderStatus.enPreparation:
        return const _ActionOption(
          label: 'Commande prête',
          target: OrderStatus.prete,
          icon: Icons.inventory_2_outlined,
        );
      default:
        return null;
    }
  }
  if (isLivreur) {
    switch (order.statutCourant) {
      case OrderStatus.prete:
        return const _ActionOption(
          label: 'Récupérer (en livraison)',
          target: OrderStatus.enLivraison,
          icon: Icons.local_shipping_outlined,
        );
      case OrderStatus.enLivraison:
        return const _ActionOption(label: 'Livré', target: OrderStatus.livre, icon: Icons.local_shipping_outlined);
      default:
        return null;
    }
  }
  return null;
}

/// Fiche d'une commande — pendant Flutter du Dialog « Détail commande » de
/// page.tsx, pour les trois rôles. Ordre des blocs identique au web :
/// en-tête (numéro + Modifier), Information, notes, partage au chat,
/// Chronologie, Historique détaillé, puis EN BAS les boutons de statut, qui
/// se remplacent au fil du workflow sans quitter l'écran.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  /// « Modifier » reste proposé tant que la commande n'est pas terminée
  /// (§ demande) : au-delà de "En préparation" le formulaire se limite aux
  /// données de livraison (zone, adresse, paiement, note du livreur).
  Future<void> _edit(BuildContext context, WidgetRef ref, Order order) async {
    if (order.modificationComplete) {
      await showDialog<void>(
        context: context,
        builder: (_) => EditOrderDialog(order: order),
      );
    } else if (order.modificationLivraisonSeule) {
      await showDialog<void>(
        context: context,
        builder: (_) => _EditLivraisonDialog(order: order),
      );
    } else {
      return;
    }
    ref.invalidate(orderDetailProvider(orderId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));
    // Charge les zones configurables : alimente le cache utilisé pour
    // afficher un nom de zone à partir du code (DeliveryZoneCatalog).
    ref.watch(deliveryZonesProvider);
    final user = ref.watch(authProvider).user;
    final isGerant = user?.isGerant ?? false;

    // Dernière commande connue, y compris pendant un rechargement silencieux.
    final order = async.value;
    final canEdit = isGerant && order != null && !order.estTerminee;

    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'Détail commande' : 'Commande ${order.numero}'),
        actions: [
          if (canEdit)
            TextButton.icon(
              onPressed: () => _edit(context, ref, order),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Modifier'),
            ),
        ],
      ),
      // Après une action, la commande est rechargée SANS repasser par l'état
      // de chargement : la fiche reste affichée et ses boutons se remplacent
      // (`refreshDetail` du web).
      body: async.when(
        skipLoadingOnReload: true,
        data: (value) => _OrderDetailBody(order: value),
        error: (error, _) => ErrorState(
          message: ApiClient.messageFromError(error),
          onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        ),
        loading: () => const LoadingState(),
      ),
    );
  }
}

/// Confirmation intégrée en cours : elle remplace les boutons de statut, en
/// bas de la fiche (`detailInline` du web).
class _InlineConfirm {
  const _InlineConfirm({required this.target, required this.label});
  final OrderStatus target;
  final String label;
  bool get showPhoto => photoPourStatut(target);
}

class _OrderDetailBody extends ConsumerStatefulWidget {
  const _OrderDetailBody({required this.order});
  final Order order;

  @override
  ConsumerState<_OrderDetailBody> createState() => _OrderDetailBodyState();
}

class _OrderDetailBodyState extends ConsumerState<_OrderDetailBody> {
  /// Une action (transition, assignation, correction, annulation…) est en
  /// cours : tous les boutons sont désactivés en attendant.
  bool _busy = false;
  bool _sharing = false;
  _InlineConfirm? _inline;

  Order get _order => widget.order;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Referme la fiche (retour à la liste si elle a été ouverte directement).
  ///
  /// Le routeur est résolu AVANT tout `await` : si le provider est passé en
  /// erreur entre-temps, l'écran parent a déjà remplacé ce corps par
  /// l'état d'erreur et `context` n'est plus utilisable.
  void _fermer(GoRouter router) {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/orders');
    }
  }

  /// Recharge la commande affichée, sans fermer la fiche.
  ///
  /// Le détail doit suivre le workflow : après « Commande prête », la fiche
  /// montre le statut Prête, la chronologie complétée et le bouton suivant
  /// (§ demande). Si le rechargement échoue — ou si le rôle courant n'a plus
  /// le droit de voir la commande à son nouveau statut (préparateur après
  /// « Prête », livreur après « Livré ») — on referme, faute de quoi la
  /// fiche resterait figée sur un état périmé (`refreshDetail` du web).
  Future<void> _recharger() async {
    final router = GoRouter.of(context);
    final provider = orderDetailProvider(_order.id);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      _fermer(router);
    }
  }

  /// Ouvre la confirmation intégrée pour une transition.
  void _ouvrir(OrderStatus target, String label) {
    setState(() => _inline = _InlineConfirm(target: target, label: label));
  }

  Future<void> _changeStatus(OrderStatus target, OrderConfirmResult result) async {
    final order = _order;
    setState(() => _busy = true);
    try {
      await ref
          .read(ordersProvider.notifier)
          .changeStatus(
            order.id,
            target.apiValue,
            note: result.note,
            photoPath: result.photoPath,
            itemsLivres: result.itemsLivres,
          );
      // Rien de remis au pointage : le serveur a enregistré un Retour.
      final effectif = target == OrderStatus.livre && result.rienRemis ? OrderStatus.retour : target;
      _snack('Commande ${order.numero} → ${effectif.label}');
      if (!mounted) return;
      setState(() => _inline = null);
      // On NE ferme PAS : on recharge la commande pour que la fiche affiche
      // le nouveau statut, la chronologie à jour et l'action suivante.
      await _recharger();
    } catch (e) {
      // En cas d'échec on reste sur le formulaire : la note et la photo
      // saisies ne sont pas perdues.
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Assigne un préparateur ou un livreur SANS faire avancer la commande
  /// (§ demande) : le statut reste "Nouvelle" ou "Prête" jusqu'à ce que
  /// quelqu'un clique explicitement sur l'étape suivante, qui réutilise alors
  /// l'affectation sans la redemander. Seule action qui garde sa propre
  /// boîte : elle doit charger la liste du personnel.
  Future<void> _assign(String role) async {
    final order = _order;
    final notifier = ref.read(ordersProvider.notifier);
    final result = await showAssignStaffDialog(
      context,
      role: role,
      orderNumero: order.numero,
      loadStaff: () => notifier.availableStaff(
        role,
        magasinId: order.magasinId,
        dateCommande: role == 'LIVREUR' ? order.dateCommande : null,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (role == 'PREPARATEUR') {
        await notifier.assignPreparateur(order.id, result.staffId);
      } else {
        await notifier.assignLivreur(order.id, result.staffId);
      }
      _snack('Commande ${order.numero} — ${role == 'PREPARATEUR' ? 'préparateur' : 'livreur'} assigné');
      await _recharger();
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Corrige un état final saisi par erreur — un « Retour » touché par
  /// accident alors que la livraison était faite, et l'inverse. Le serveur
  /// rétablit le stock : les articles ressortent (ou rentrent) selon le sens.
  Future<void> _corriger(OrderStatus cible) async {
    final order = _order;
    final result = await showDialog<OrderConfirmResult>(
      context: context,
      builder: (_) => _CorrectionDialog(order: order, cible: cible),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(ordersProvider.notifier).corrigerStatut(order.id, cible.apiValue, note: result.note);
      _snack('Commande ${order.numero} corrigée → ${cible.label}');
      await _recharger();
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Annulation (gérant) — restitue le stock si déjà déduit. Irréversible :
  /// le mot ANNULER est à retaper dans la boîte (§ demande).
  Future<void> _cancel() async {
    final order = _order;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CancelOrderDialog(order: order, onConfirm: () => ref.read(ordersProvider.notifier).cancel(order.id)),
    );
    if (done != true || !mounted) return;
    _snack('Commande ${order.numero} annulée');
    await _recharger();
  }

  /// Suppression (gérant, uniquement tant que "Nouvelle").
  Future<void> _delete() async {
    final order = _order;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _DeleteOrderDialog(order: order, onConfirm: () => ref.read(ordersProvider.notifier).delete(order.id)),
    );
    if (done != true || !mounted) return;
    _snack('Commande ${order.numero} supprimée');
    _fermer(GoRouter.of(context));
  }

  /// Partage la commande dans la messagerie (§ demande) : résumé + photo de
  /// préparation, envoyés au livreur assigné. Tout est composé côté serveur.
  Future<void> _share() async {
    final order = _order;
    setState(() => _sharing = true);
    try {
      await ref.read(ordersProvider.notifier).shareToChat(order.id);
      _snack(order.livreurName == null ? 'Commande envoyée au livreur' : 'Commande envoyée à ${order.livreurName}');
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authProvider).user;
    final isGerant = user?.isGerant ?? false;
    final isPreparateur = user?.isPreparateur ?? false;
    final isLivreur = user?.isLivreur ?? false;

    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final actions = _buildActions(context, isGerant: isGerant, isPreparateur: isPreparateur, isLivreur: isLivreur);
    final canCancel = isGerant && order.annulationPossible;
    final canDelete = isGerant && order.suppressionPossible;

    return RefreshIndicator(
      onRefresh: () async {
        final provider = orderDetailProvider(order.id);
        ref.invalidate(provider);
        try {
          await ref.read(provider.future);
        } catch (_) {
          // L'état d'erreur est déjà porté par le provider (ErrorState).
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // ------------------------------------------------------------ En-tête
          Row(
            children: [
              Expanded(child: Text(order.numero, style: theme.textTheme.headlineSmall)),
              OrderStatusBadge(status: order.statutCourant),
            ],
          ),
          if (order.livraisonPartielle)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.undo, size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Livraison partielle — ${order.itemsRapportes.length} article(s) rapporté(s) en stock',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // -------------------------------------------------------- Information
          _SectionLabel('Information'),
          const SizedBox(height: 8),
          if (order.items.isNotEmpty) ...[_ArticlesCard(order: order), const SizedBox(height: 10)],
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  // Tant que la commande n'est pas Livrée, on affiche la date
                  // de livraison prévue — une fois Livrée, l'heure réellement
                  // atteinte (§ demande).
                  _KeyValueRow(
                    label: order.statutCourant == OrderStatus.livre ? 'Livrée le' : 'Livraison prévue le',
                    value: _fmtAppDateTime(
                      order.statutCourant == OrderStatus.livre
                          ? (order.historyAt(OrderStatus.livre) ?? order.dateCommande)
                          : order.dateCommande,
                    ),
                  ),
                  _KeyValueRow(label: 'Nom client', value: order.clientNom.isEmpty ? '-' : order.clientNom),
                  _KeyValueRow(
                    label: 'Numéro client',
                    value: order.telephone ?? '-',
                    onTap: order.telephone == null ? null : () => launchUrl(Uri.parse('tel:${order.telephone}')),
                  ),
                  // Le livreur appelle le second numéro quand le premier ne
                  // répond pas (§ demande).
                  if (order.telephone2 != null)
                    _KeyValueRow(
                      label: 'Autre numéro',
                      value: order.telephone2!,
                      onTap: () => launchUrl(Uri.parse('tel:${order.telephone2}')),
                    ),
                  _KeyValueRow(
                    label: 'Adresse client',
                    value: (order.adresseLivraison == null || order.adresseLivraison!.isEmpty)
                        ? '-'
                        : order.adresseLivraison!,
                  ),
                  _KeyValueRow(label: 'Zone', value: DeliveryZoneCatalog.labelFor(order.livraisonZone)),
                  _KeyValueRow(label: 'Mode de paiement', value: order.modePaiement.label),
                  if (!order.estRecuperation && order.fraisLivraison != null)
                    _KeyValueRow(label: 'Frais de livraison', value: _ar(order.fraisLivraison!)),
                  // Rien ne reste à encaisser quand le client a déjà payé
                  // d'avance : afficher un "Total à payer" ferait croire au
                  // livreur qu'il doit encore réclamer la somme (§ demande).
                  if (!order.estPrepayee)
                    _KeyValueRow(
                      label: 'Total à payer',
                      value: order.totalAPayer == null ? '-' : _ar(order.totalAPayer!),
                      bold: true,
                    ),
                  if (order.preparateurName != null) _KeyValueRow(label: 'Préparateur', value: order.preparateurName!),
                  if (order.livreurName != null) _KeyValueRow(label: 'Livreur', value: order.livreurName!),
                  if (order.createdAt != null)
                    _KeyValueRow(label: 'Commande créée le', value: _fmtAppDateTime(order.createdAt)),
                ],
              ),
            ),
          ),

          // -------------------------------------------------------------- Notes
          if (order.notePreparateur != null && order.notePreparateur!.isNotEmpty)
            _NoteBlock(label: 'Note pour le préparateur', text: order.notePreparateur!),
          if (order.noteLivreur != null && order.noteLivreur!.isNotEmpty)
            _NoteBlock(label: 'Note pour le livreur', text: order.noteLivreur!),

          // ----------------------------------------------------- Envoyer au chat
          // Proposé dès qu'une photo de préparation existe, au gérant comme au
          // préparateur, pour prévenir le livreur avec la preuve du colis
          // (§ demande). Une seule destination : le salon Général a été retiré
          // de la messagerie.
          if ((isGerant || isPreparateur) && order.aPhotoPreparation) ...[
            const Divider(height: 28),
            Text('Envoyer au chat (avec la photo)', style: muted),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (order.livreurId == null || _sharing) ? null : _share,
                icon: _sharing
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chat_bubble_outline),
                label: Text(
                  _sharing
                      ? 'Envoi…'
                      : order.livreurName != null
                      ? 'Au livreur (${order.livreurName})'
                      : 'Aucun livreur assigné',
                ),
              ),
            ),
          ],

          // -------------------------------------------- Chronologie / Historique
          if (order.statusHistory.isNotEmpty) ...[
            const Divider(height: 28),
            Text('Chronologie', style: muted),
            const SizedBox(height: 8),
            _OrderTimelineCard(order: order),
            const SizedBox(height: 16),
            Text('Historique détaillé', style: muted),
            const SizedBox(height: 4),
            for (final h in order.statusHistory) _HistoriqueEntry(entry: h),
          ],

          // ------------------------------------------------------------ Actions
          // Les actions de statut sont placées tout en bas, après l'historique
          // détaillé (§ demande). Seul « Modifier » reste dans l'en-tête.
          if (actions != null || canCancel || canDelete) ...[
            const Divider(height: 28),
            if (_busy)
              const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 2)),
            ?actions,
            if (canCancel || canDelete) ...[
              if (actions != null) const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (canCancel)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _cancel,
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Annuler la commande'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  if (canDelete)
                    TextButton.icon(
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Zone d'actions du bas de la fiche, jouées SANS quitter l'écran : le
  /// bouton laisse place, au même endroit, au formulaire de confirmation
  /// (note, photo de preuve pour « Prête », pointage pour « Livré », mot à
  /// retaper pour « Retour »). Retourne `null` s'il n'y a rien à proposer.
  Widget? _buildActions(
    BuildContext context, {
    required bool isGerant,
    required bool isPreparateur,
    required bool isLivreur,
  }) {
    final order = _order;

    // Confirmation en cours : elle remplace les boutons.
    final inline = _inline;
    if (inline != null) {
      return _InlineConfirmCard(
        label: inline.label,
        showPhoto: inline.showPhoto,
        child: OrderConfirmForm(
          // Nouveau formulaire vierge à chaque cible.
          key: ValueKey(inline.target),
          showPhoto: inline.showPhoto,
          confirmWord: kMotsConfirmation[inline.target],
          // Pointage des articles au moment de livrer.
          items: pointagePourStatut(inline.target) ? order.items : null,
          submitting: _busy,
          onCancel: () => setState(() => _inline = null),
          onSubmit: (result) => _changeStatus(inline.target, result),
        ),
      );
    }

    // Commande close : plus de transition possible, mais le gérant peut
    // CORRIGER un état saisi par erreur — le livreur touche vite « Retour »
    // alors que la livraison est faite (§ demande).
    if (isGerant && order.estClose) {
      final cible = order.correctionCible!;
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _corriger(cible),
          icon: const Icon(Icons.undo),
          label: Text("Corriger l'état → ${cible.label}"),
        ),
      );
    }

    // GÉRANT : toutes les actions du statut courant, en boutons. Elles se
    // remplacent au fil du workflow, la fiche restant ouverte jusqu'au
    // statut terminal.
    if (isGerant) {
      final options = _gerantActionOptions(order);
      if (options.isEmpty) return null;
      return Column(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: _actionButton(
                  option,
                  onPressed: _busy
                      ? null
                      : () {
                          if (option.isAssign) {
                            _assign(option.role!);
                          } else {
                            _ouvrir(option.target, option.label);
                          }
                        },
                ),
              ),
            ),
        ],
      );
    }

    // LIVREUR en cours de livraison : "Livré" et "Retour" sont deux issues
    // possibles, pas une succession.
    if (isLivreur && order.statutCourant == OrderStatus.enLivraison && isJourJ(order.dateCommande, UserRole.livreur)) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _ouvrir(OrderStatus.livre, 'Livré'),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Livré'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _ouvrir(OrderStatus.retour, 'Retour'),
              icon: const Icon(Icons.undo),
              label: const Text('Retour'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      );
    }

    // Préparateur et livreur : leur action du moment, jouée elle aussi sans
    // quitter la fiche. Un employé sans sous-rôle ne voit aucun bouton.
    final action = _nextAction(order, isPreparateur: isPreparateur, isLivreur: isLivreur);
    if (action == null) return null;
    final roleCommande = isPreparateur ? UserRole.preparateur : UserRole.livreur;
    final bloque = !isJourJ(order.dateCommande, roleCommande);
    // Livreur hors jour J : aucun bouton, pas même grisé.
    if (isLivreur && bloque) return null;
    // Ce que le bouton doit annoncer, c'est le moment où il se débloquera —
    // pas la date de livraison.
    final label = bloque && order.dateCommande != null
        ? 'Disponible le ${dueDateLabel(order.dateCommande!, roleCommande)}'
        : action.label;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: (bloque || _busy) ? null : () => _ouvrir(action.target, action.label),
        icon: Icon(action.icon),
        label: Text(label),
      ),
    );
  }

  Widget _actionButton(_ActionOption option, {required VoidCallback? onPressed}) {
    if (option.isAssign) {
      return OutlinedButton.icon(onPressed: onPressed, icon: Icon(option.icon), label: Text(option.label));
    }
    if (option.target == OrderStatus.retour) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(option.icon),
        label: Text(option.label),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
      );
    }
    return FilledButton.icon(onPressed: onPressed, icon: Icon(option.icon), label: Text(option.label));
  }
}

// ---------------------------------------------------------------------------
// Blocs d'affichage
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(letterSpacing: 2, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// Articles de la commande, avec leurs métadonnées étiquetées — Type
/// (catégorie), Sous-type, Marque, Quantité (§ demande). Un article rapporté
/// lors d'une livraison partielle est barré et signalé.
class _ArticlesCard extends StatelessWidget {
  const _ArticlesCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Articles'),
            for (final item in order.items) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.libelle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: item.retourne ? TextDecoration.lineThrough : null,
                        color: item.retourne ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                  ),
                  if (item.retourne) ...[
                    const SizedBox(width: 8),
                    const StatusChip(label: 'Rapporté', color: Color(0xFFEF4444)),
                  ],
                ],
              ),
              Text(_meta(item), style: small),
              // Prix unitaire : exposé au gérant seulement (serializer complet).
              if (item.prixUnitaire != null)
                Text(
                  '${item.quantite} × ${_ar(item.prixUnitaire!)} = ${_ar(item.prixUnitaire! * item.quantite)}',
                  style: small,
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _meta(OrderItem item) {
    final parts = [
      if (item.categoryName != null && item.categoryName!.isNotEmpty) 'Type : ${item.categoryName}',
      if (item.typeName != null && item.typeName!.isNotEmpty) 'Sous-type : ${item.typeName}',
      if (item.brandName != null && item.brandName!.isNotEmpty) 'Marque : ${item.brandName}',
      if (item.quantite > 0) 'Quantité : ${item.quantite}',
    ];
    return parts.isEmpty ? 'Sans métadonnées' : parts.join(' • ');
  }
}

/// Ligne « libellé à gauche / valeur à droite » de la grille d'informations.
class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value, this.onTap, this.bold = false});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: onTap != null ? scheme.primary : null,
                  decoration: onTap != null ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(text),
        ],
      ),
    );
  }
}

/// Encadré de la confirmation intégrée : « Confirmer : {label} » + aide pour
/// la photo, puis le formulaire.
class _InlineConfirmCard extends StatelessWidget {
  const _InlineConfirmCard({required this.label, required this.showPhoto, required this.child});
  final String label;
  final bool showPhoto;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('Confirmer : $label'),
          if (showPhoto) ...[
            const SizedBox(height: 6),
            Text(
              'Ajoutez si besoin une note et une photo prouvant que la préparation est faite — le livreur les verra.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Une ligne de l'historique détaillé : « {statut} — {auteur ou Système} —
/// {date} (note) », plus la vignette de la photo de préparation et le lien
/// « Voir / télécharger la photo » quand elle existe.
class _HistoriqueEntry extends StatelessWidget {
  const _HistoriqueEntry({required this.entry});
  final OrderStatusHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = entry;
    final statut = h.ancienStatut == null
        ? h.nouveauStatut.label
        : '${h.ancienStatut!.label} → ${h.nouveauStatut.label}';
    final note = (h.note != null && h.note!.isNotEmpty) ? ' (${h.note})' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$statut — ${h.changedByName ?? 'Système'} — ${_fmtAppDateTime(h.timestamp)}$note',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (h.aPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => launchUrl(Uri.parse(h.photo!), mode: LaunchMode.externalApplication),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        h.photo!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 64,
                          height: 64,
                          color: scheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Voir / télécharger la photo',
                      style: TextStyle(color: scheme.primary, decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Résumé "Prête le / En livraison depuis le / Livrée le" — une ligne par
/// statut effectivement atteint, dérivée de l'historique complet, pour une
/// lecture immédiate sans avoir à parcourir la liste détaillée en dessous.
class _OrderTimelineCard extends StatelessWidget {
  const _OrderTimelineCard({required this.order});
  final Order order;

  static const _milestones = [
    (OrderStatus.enPreparation, Icons.build_outlined, 'Préparation commencée le'),
    (OrderStatus.prete, Icons.inventory_2_outlined, 'Prête le'),
    (OrderStatus.enLivraison, Icons.local_shipping_outlined, 'En livraison depuis le'),
    (OrderStatus.livre, Icons.check_circle_outline, 'Livrée le'),
    (OrderStatus.retour, Icons.undo, 'Retour le'),
  ];

  @override
  Widget build(BuildContext context) {
    // Chaque jalon prend le PREMIER horodatage de l'historique pour ce statut.
    final timestamps = <OrderStatus, DateTime?>{};
    for (final h in order.statusHistory) {
      timestamps.putIfAbsent(h.nouveauStatut, () => h.timestamp);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La création vient de createdAt (horodatage automatique), pas de
            // dateCommande qui porte désormais la livraison prévue — sinon une
            // livraison planifiée pour demain s'affichait "avant" la préparation.
            _TimelineRow(
              icon: Icons.add_shopping_cart_outlined,
              label: 'Commande créée le',
              date: order.createdAt,
              reached: order.createdAt != null,
            ),
            _TimelineRow(
              icon: Icons.event_outlined,
              label: 'Livraison prévue le',
              date: order.dateCommande,
              reached: order.dateCommande != null,
            ),
            for (final (status, icon, label) in _milestones)
              _TimelineRow(icon: icon, label: label, date: timestamps[status], reached: timestamps.containsKey(status)),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.icon, required this.label, required this.date, required this.reached});
  final IconData icon;
  final String label;
  final DateTime? date;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    if (!reached) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label ', style: Theme.of(context).textTheme.bodyMedium),
                  TextSpan(
                    text: _fmtAppDateTime(date),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Boîtes de dialogue
// ---------------------------------------------------------------------------

/// Correction d'un état final saisi par erreur (gérant) : LIVRE <-> RETOUR,
/// avec le mot cible à retaper.
class _CorrectionDialog extends StatelessWidget {
  const _CorrectionDialog({required this.order, required this.cible});
  final Order order;
  final OrderStatus cible;

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return AlertDialog(
      title: Text('Corriger la commande ${order.numero}'),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'Son état passera de '),
                    TextSpan(text: order.statutCourant.label, style: bold),
                    const TextSpan(text: ' à '),
                    TextSpan(text: cible.label, style: bold),
                    TextSpan(
                      text:
                          '. Le stock est rétabli en conséquence : ${cible == OrderStatus.livre ? "les articles ressortent du stock, puisqu'ils n'ont jamais été rapportés." : 'les articles rentrent en stock, puisque le colis est revenu.'}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OrderConfirmForm(
                confirmWord: cible == OrderStatus.retour ? 'RETOUR' : 'LIVRE',
                onCancel: () => Navigator.of(context).pop(),
                onSubmit: (result) => Navigator.of(context).pop(result),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Annulation (gérant) — irréversible : on fait retaper le mot ANNULER pour
/// rendre le geste délibéré (§ demande). L'appel serveur est joué dans la
/// boîte (libellé « Annulation... »), qui se ferme sur `true` en cas de succès.
class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog({required this.order, required this.onConfirm});
  final Order order;
  final Future<void> Function() onConfirm;

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  final _saisie = TextEditingController();
  bool _cancelling = false;
  String? _error;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final motValide = motConfirmationValide(kMotConfirmationAnnulation, _saisie.text);
    return AlertDialog(
      title: Text('Annuler la commande ${order.numero} ?'),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.annulationRestitueStock
                  ? 'La commande de ${order.clientNom} sera annulée. Le stock déjà déduit pour cette commande sera automatiquement restitué.'
                  : 'La commande de ${order.clientNom} sera annulée.',
            ),
            const SizedBox(height: 12),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Pour confirmer, tapez '),
                  TextSpan(
                    text: kMotConfirmationAnnulation,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _saisie,
              decoration: const InputDecoration(hintText: kMotConfirmationAnnulation),
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              enabled: !_cancelling,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _cancelling ? null : () => Navigator.of(context).pop(false), child: const Text('Retour')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: (_cancelling || !motValide) ? null : _confirm,
          child: Text(_cancelling ? 'Annulation...' : 'Annuler la commande'),
        ),
      ],
    );
  }
}

/// Suppression définitive (gérant, commande « Nouvelle » uniquement).
class _DeleteOrderDialog extends StatefulWidget {
  const _DeleteOrderDialog({required this.order, required this.onConfirm});
  final Order order;
  final Future<void> Function() onConfirm;

  @override
  State<_DeleteOrderDialog> createState() => _DeleteOrderDialogState();
}

class _DeleteOrderDialogState extends State<_DeleteOrderDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return AlertDialog(
      title: Text('Supprimer la commande ${order.numero} ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cette action est définitive — la commande de ${order.clientNom} sera supprimée.'),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _deleting ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _deleting ? null : _confirm,
          child: Text(_deleting ? 'Suppression...' : 'Supprimer'),
        ),
      ],
    );
  }
}

/// « Modifier » au-delà de "En préparation" (`livraisonSeule` du web) : la
/// commande est trop engagée pour tout modifier, mais les données de
/// LIVRAISON doivent rester ajustables — le client peut régler d'avance, ou
/// dicter une autre adresse pendant que le livreur roule. Changer la zone met
/// à jour les frais et le total, donc le bilan du livreur (§ demande). Même
/// règle que le serveur (orders/services.py::update_order), qui refuserait le
/// reste de toute façon. Un retrait sur place ne garde que le paiement.
class _EditLivraisonDialog extends ConsumerStatefulWidget {
  const _EditLivraisonDialog({required this.order});
  final Order order;

  @override
  ConsumerState<_EditLivraisonDialog> createState() => _EditLivraisonDialogState();
}

class _EditLivraisonDialogState extends ConsumerState<_EditLivraisonDialog> {
  late String _zone = widget.order.livraisonZone;
  late PaymentMode _modePaiement = widget.order.modePaiement;
  late final _adresseController = TextEditingController(text: widget.order.adresseLivraison ?? '');
  late final _noteLivreurController = TextEditingController(text: widget.order.noteLivreur ?? '');
  bool _submitting = false;
  String? _error;

  bool get _recuperation => _zone == kRecuperationCode;

  @override
  void dispose() {
    _adresseController.dispose();
    _noteLivreurController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(ordersProvider.notifier)
          .updateLivraison(
            widget.order.id,
            modePaiement: _modePaiement.apiValue,
            livraisonZone: _zone,
            adresseLivraison: _recuperation ? '' : _adresseController.text.trim(),
            noteLivreur: _recuperation ? '' : _noteLivreurController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Commande ${widget.order.numero} — livraison mise à jour')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(deliveryZonesProvider).asData?.value ?? const <DeliveryZoneOption>[];
    // Zones actives (+ la zone courante même désactivée), jamais le retrait
    // sur place : en régime restreint on ne change pas le type de commande.
    final zoneItems = [
      for (final z in zones)
        if (z.code != kRecuperationCode && (z.actif || z.code == _zone))
          DropdownMenuItem(value: z.code, child: Text(z.label)),
    ];
    if (!_recuperation && !zoneItems.any((i) => i.value == _zone)) {
      zoneItems.add(DropdownMenuItem(value: _zone, child: Text(DeliveryZoneCatalog.labelFor(_zone))));
    }

    return AlertDialog(
      title: Text('Modifier la commande ${widget.order.numero}'),
      content: SizedBox(
        width: dialogWidth(MediaQuery.sizeOf(context).width, 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Commande déjà engagée : seules la zone, l'adresse, le paiement et la note du livreur restent modifiables. Changer la zone met à jour les frais et le bilan du livreur.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (!_recuperation) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _zone,
                  decoration: const InputDecoration(labelText: 'Zone de livraison'),
                  items: zoneItems,
                  onChanged: _submitting ? null : (v) => setState(() => _zone = v ?? _zone),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _adresseController,
                  decoration: const InputDecoration(labelText: 'Adresse de livraison'),
                  enabled: !_submitting,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMode>(
                initialValue: _modePaiement,
                decoration: const InputDecoration(labelText: 'Paiement'),
                items: [for (final m in PaymentMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                onChanged: _submitting ? null : (v) => setState(() => _modePaiement = v ?? _modePaiement),
              ),
              // La note du livreur reste utile en cours de tournée : c'est par
              // elle qu'on lui transmet une consigne de dernière minute.
              if (!_recuperation) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _noteLivreurController,
                  decoration: const InputDecoration(labelText: 'Note pour le livreur (optionnel)'),
                  maxLines: 2,
                  enabled: !_submitting,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Enregistrement...' : 'Enregistrer'),
        ),
      ],
    );
  }
}
