import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../models/delivery_zone.dart';
import '../../models/order.dart';
import '../../state/auth_provider.dart';
import '../../state/orders_provider.dart';
import '../../state/realtime_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;
import '../../widgets/status_badge.dart';

/// Délai de regroupement des événements temps réel avant refetch —
/// `useRealtimeRefresh(..., { debounceMs: 400 })` du web.
const Duration _kRealtimeDebounce = Duration(milliseconds: 400);

/// File d'attente des retraits au comptoir — équivalent exact de
/// `GET /orders/?statut=PRETE&livraison_zone=RECUPERATION` (le seul appel de
/// liste de `frontend/app/(app)/pickup/page.tsx`) : le filtrage est figé côté
/// requête, aucun filtre/tri/pagination côté client, l'ordre est celui de
/// l'API.
///
/// Temps réel : `useRealtimeRefresh(['order', 'order_status_history'], () =>
/// fetchOrders(true))` du web = refetch SILENCIEUX (la liste reste affichée)
/// à chaque événement WebSocket, regroupés sur 400 ms. Ici `ref.listen` sur
/// [realtimeTickProvider] (chaque notification poussée sur /ws/notifications/
/// — dont « Commande {numero} prête à récupérer sur place », créée au
/// passage PRETE d'une commande RECUPERATION) puis `invalidateSelf()`, qui
/// conserve la valeur précédente pendant le rechargement. Une commande passée
/// « Prête » par un préparateur apparaît donc sans action de l'utilisateur.
final pickupOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  Timer? debounce;
  ref.onDispose(() => debounce?.cancel());
  ref.listen(realtimeTickProvider, (previous, next) {
    debounce?.cancel();
    debounce = Timer(_kRealtimeDebounce, () {
      if (ref.mounted) ref.invalidateSelf();
    });
  });
  return ref.read(ordersRepositoryProvider).list(
        statut: OrderStatus.prete.apiValue,
        livraisonZone: kRecuperationCode,
      );
});

/// `err.message || fallback` du web : le message serveur s'il existe, sinon
/// le libellé générique de la page.
String _messageOr(Object error, String fallback) {
  final message = ApiClient.messageFromError(error).trim();
  return message.isEmpty ? fallback : message;
}

/// Compose le numéro (`<a href="tel:…">` du web). Sans application capable
/// de téléphoner (tablette, émulateur), on le dit plutôt que d'échouer en
/// silence.
Future<void> _appeler(BuildContext context, String numero) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ok = await launchUrl(Uri.parse('tel:$numero'));
    if (!ok) messenger.showSnackBar(SnackBar(content: Text("Impossible d'appeler le $numero sur cet appareil.")));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text("Impossible d'appeler le $numero sur cet appareil.")));
  }
}

/// Page `/pickup` du web (`frontend/app/(app)/pickup/page.tsx`) : commandes
/// prêtes à retirer au comptoir (zone « Récupération », donc sans livreur).
/// Le gérant confirme le retrait client, ce qui bascule PRETE -> LIVRE.
///
/// Gating GERANT explicite, comme le web (`useCurrentUser().isGerant`,
/// c'est-à-dire `role === 'admin' || role === 'magasin'` — voir
/// core/permissions.dart) : écran « Accès refusé » et AUCUN chargement de
/// données tant que l'utilisateur n'est pas gérant. Le serveur applique la
/// même règle (orders/services.py : « Seul le gérant peut valider une
/// récupération sur place. »).
///
/// Aucun bouton d'annulation, aucun détail/expansion, aucun lien vers la
/// fiche commande, aucun menu contextuel, aucune sélection multiple, aucun
/// onglet/switch/toggle — comme le web.
class PickupScreen extends ConsumerStatefulWidget {
  const PickupScreen({super.key});

  @override
  ConsumerState<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends ConsumerState<PickupScreen> {
  /// `confirming` du web : id de la commande en cours de validation (une
  /// seule à la fois, `number | null`). Observé à la fois par le bouton de la
  /// carte et par le bouton « Confirmer » de la modale — tous deux désactivés
  /// avec le libellé « Confirmation... » pendant l'appel.
  final ValueNotifier<int?> _confirming = ValueNotifier<int?>(null);

  /// Rechargement NON silencieux déclenché par le bouton « Rafraîchir » :
  /// le web réaffiche ses skeletons (`fetchOrders()` sans `silent`).
  bool _reloading = false;

  /// Dernière erreur déjà signalée par un toast, pour ne pas répéter le même
  /// SnackBar à chaque reconstruction.
  Object? _reportedError;

  @override
  void dispose() {
    _confirming.dispose();
    super.dispose();
  }

  /// `fetchOrders(silent)` du web. Non silencieux : repasse par l'état de
  /// chargement ; silencieux : la liste courante reste affichée pendant
  /// l'appel (Riverpod conserve la valeur précédente).
  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _reloading = true);
    try {
      ref.invalidate(pickupOrdersProvider);
      await ref.read(pickupOrdersProvider.future);
    } catch (_) {
      // Le web se contente d'un toast et garde la liste précédente : le
      // message est affiché par le listener d'erreur (ou par ErrorState s'il
      // n'y a encore rien à montrer).
    } finally {
      if (mounted && !silent) setState(() => _reloading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Bouton « Marquer comme récupérée » : ouvre la modale de confirmation
  /// (`setPickupTarget(order)`) — jamais l'API directement.
  ///
  /// Comme la `Dialog` du web, elle se ferme par Échap / clic extérieur /
  /// « Annuler » à tout moment, même pendant l'envoi (l'appel en cours se
  /// poursuit et aboutit à son toast + refetch) ; « Annuler » n'appelle
  /// aucune API.
  Future<void> _openPickupDialog(Order order) {
    return showDialog<void>(
      context: context,
      builder: (_) => _PickupConfirmDialog(
        order: order,
        confirming: _confirming,
        onConfirm: () => _confirmPickup(order),
      ),
    );
  }

  /// `confirmPickup(order)` du web : `POST /orders/{id}/status/ {statut:
  /// 'LIVRE'}` — sans note, sans photo, sans `items_livres` (absent = tout
  /// est remis). Renvoie vrai si la récupération est enregistrée (la modale
  /// se ferme), faux sinon (toast d'erreur, la modale RESTE OUVERTE pour
  /// réessayer).
  Future<bool> _confirmPickup(Order order) async {
    _confirming.value = order.id;
    try {
      await ref.read(ordersRepositoryProvider).changeStatus(order.id, OrderStatus.livre.apiValue);
      // Web : toast.success(`Commande ${order.numero} récupérée`).
      _snack('Commande ${order.numero} récupérée');
      if (mounted) {
        // Refetch silencieux (`fetchOrders(true)`) : la carte disparaît de la
        // liste puisque la commande n'est plus PRETE. `ordersProvider` est
        // invalidé pour que la page Commandes reflète le changement si elle
        // est ouverte.
        ref.invalidate(ordersProvider);
        unawaited(_refresh(silent: true));
      }
      return true;
    } catch (e) {
      // Web : toast.error(err.message || 'Action impossible').
      _snack(_messageOr(e, 'Action impossible'));
      return false;
    } finally {
      // Ne relâche que SA propre commande : une autre validation lancée entre
      // temps garde son état.
      if (mounted && _confirming.value == order.id) _confirming.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    // Web : tant que `userLoading` est vrai, le garde ne s'applique pas et la
    // page principale (skeletons) est affichée brièvement.
    if (auth.status == AuthStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Récupération sur place')),
        // Web : 3 skeletons `h-24`. L'app a un état de chargement unique et
        // partagé (widgets/async_state_widgets.dart) — même rôle, présentation
        // maison du projet.
        body: const LoadingState(),
      );
    }
    if (user == null || !user.isGerant) return const _AccesRefuse();

    // Le fetch n'est déclenché qu'une fois le gérant identifié (useEffect du
    // web : `if (!userLoading && isGerant) fetchOrders()`).
    final async = ref.watch(pickupOrdersProvider);

    // Web : `toast.error(err.message || 'Erreur de chargement des commandes')`
    // — la liste conserve son état précédent.
    ref.listen<AsyncValue<List<Order>>>(pickupOrdersProvider, (previous, next) {
      final error = next.error;
      if (error == null || !next.hasValue) return;
      if (identical(error, _reportedError)) return;
      _reportedError = error;
      _snack(_messageOr(error, 'Erreur de chargement des commandes'));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Récupération sur place'),
        actions: [
          // Web : bouton icône seul (RefreshCw), ni désactivé ni animé
          // pendant le chargement — refetch NON silencieux.
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Commandes prêtes à retirer au comptoir (zone "Récupération") — pas de livreur assigné.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(async)),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<Order>> async) {
    // Web : `loading` -> 3 skeletons. Ici l'état de chargement partagé du
    // projet (widgets/async_state_widgets.dart). Un rechargement silencieux
    // (temps réel, après action, tirer-pour-rafraîchir) conserve la valeur
    // précédente : `hasValue` reste vrai et la liste reste affichée.
    if (_reloading || (!async.hasValue && async.isLoading)) return const LoadingState();
    if (!async.hasValue) {
      return ErrorState(
        message: _messageOr(async.error!, 'Erreur de chargement des commandes'),
        onRetry: _refresh,
      );
    }

    final orders = async.value!;
    return RefreshIndicator(
      // Le rafraîchissement par glissement garde la liste visible (le web n'a
      // que le bouton d'en-tête, qui lui repasse par les skeletons).
      onRefresh: () => _refresh(silent: true),
      child: orders.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: const EmptyState(
                    message: 'Aucune commande prête à récupérer pour le moment.',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // Web : `grid gap-3` 1 colonne sur mobile, `sm:grid-cols-2`
                // au-delà. Les cartes n'ayant pas la même hauteur, un Wrap
                // reproduit la grille sans les étirer.
                final twoColumns = constraints.maxWidth >= 700;
                final cardWidth =
                    twoColumns ? (constraints.maxWidth - 24 - 12) / 2 : constraints.maxWidth - 24;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final order in orders)
                        SizedBox(
                          width: cardWidth,
                          child: _PickupCard(
                            key: ValueKey(order.id),
                            order: order,
                            confirming: _confirming,
                            onConfirm: () => _openPickupDialog(order),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Modale de confirmation du retrait — la `Dialog` shadcn du web, à
/// l'identique : titre et description dynamiques, AUCUN champ de saisie
/// (pas de note, pas de photo, pas de mot à retaper), « Annuler » /
/// « Confirmer ».
///
/// « Confirmer » est désactivé (libellé « Confirmation... ») tant que CETTE
/// commande est en cours d'envoi ; « Annuler », Échap et le clic extérieur
/// restent possibles à tout moment. En cas d'échec la modale reste ouverte ;
/// elle ne se ferme que sur succès (`setPickupTarget(null)` n'est appelé que
/// dans le chemin succès côté web).
class _PickupConfirmDialog extends StatelessWidget {
  const _PickupConfirmDialog({required this.order, required this.confirming, required this.onConfirm});

  final Order order;
  final ValueListenable<int?> confirming;

  /// Lance l'appel API ; vrai = récupération enregistrée.
  final Future<bool> Function() onConfirm;

  Future<void> _confirm(BuildContext context) async {
    final ok = await onConfirm();
    // Fermée entre temps (Échap / clic extérieur) : plus rien à fermer.
    if (ok && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: confirming,
      builder: (context, confirmingId, _) {
        final busy = confirmingId == order.id;
        return AlertDialog(
          title: Text('Confirmer la récupération de ${order.numero} ?'),
          content: Text(
            'La commande de ${order.clientNom} sera marquée comme livrée (récupérée sur place).',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          actions: [
            // Web : variant='outline', setPickupTarget(null) — aucune API.
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: busy ? null : () => _confirm(context),
              child: Text(busy ? 'Confirmation...' : 'Confirmer'),
            ),
          ],
        );
      },
    );
  }
}

/// Écran « Accès refusé » du web : rendu à la place de TOUT le reste dès que
/// l'utilisateur n'est pas gérant (aucune donnée n'est chargée).
class _AccesRefuse extends StatelessWidget {
  const _AccesRefuse();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Récupération sur place')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_maybe_outlined, size: 48, color: Color(0xFFEF4444)),
                  const SizedBox(height: 16),
                  Text(
                    'Accès refusé',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cette page est réservée au gérant.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une `Card` de la grille web : numéro + client + badge « Prête », téléphone
/// cliquable, articles, puis pied « total / bouton d'action ».
class _PickupCard extends StatelessWidget {
  const _PickupCard({super.key, required this.order, required this.confirming, required this.onConfirm});

  final Order order;

  /// `confirming` de la page : le bouton est désactivé, avec le libellé
  /// « Confirmation... », tant que c'est CETTE commande qui est en cours.
  final ValueListenable<int?> confirming;

  /// Ouvre la modale de confirmation (jamais l'API directement).
  final VoidCallback onConfirm;

  /// Web : `(order.items || []).map(it => `${it.reference_name}
  /// (${it.couleur}) x${it.quantite}`).join(', ')` — la couleur est toujours
  /// affichée, même quand elle vaut « Standard », et aucun prix unitaire.
  String get _itemsLabel =>
      order.items.map((it) => '${it.referenceName} (${it.couleur}) x${it.quantite}').join(', ');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    final phone = order.telephone;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                      Text(order.numero, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(order.clientNom, style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Toutes les commandes de cette page sont PRETE : le badge
                // vaut donc toujours « Prête », comme le badge statique bleu
                // du web.
                OrderStatusBadge(status: order.statutCourant),
              ],
            ),
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Web : <a href="tel:..."> — ici l'appel natif via url_launcher
              // (rappeler le client qui ne vient pas).
              InkWell(
                onTap: () => _appeler(context, phone),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_outlined, size: 15, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        phone,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(_itemsLabel, style: muted),
            // Pied de carte du web : `border-t pt-3`, total à gauche, bouton
            // d'action à droite. Un Wrap plutôt qu'un Row : sur un écran
            // étroit le bouton (libellé long) passe sous le total au lieu de
            // déborder.
            const Divider(height: 22),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // Web : fmt(order.total_a_payer) — arrondi à l'entier + ' Ar'.
                Text(
                  arFmt(order.totalAPayer ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                ValueListenableBuilder<int?>(
                  valueListenable: confirming,
                  builder: (context, confirmingId, _) {
                    final busy = confirmingId == order.id;
                    return FilledButton.icon(
                      // Ouvre la modale de confirmation — jamais l'API
                      // directement (comme le web). Désactivé pendant l'envoi
                      // de CETTE commande, avec le libellé « Confirmation... ».
                      onPressed: busy ? null : onConfirm,
                      icon: busy
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(busy ? 'Confirmation...' : 'Marquer comme récupérée'),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
