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
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/status_badge.dart';

/// File d'attente des retraits au comptoir — équivalent exact de
/// `GET /orders/?statut=PRETE&livraison_zone=RECUPERATION` (le seul appel de
/// liste de `frontend/app/(app)/pickup/page.tsx`).
///
/// Le filtre `livraison_zone` existe côté serveur (orders/views.py::
/// get_queryset, branche gérant) mais n'est pas exposé par
/// `OrdersRepository.list()` — et le portage n'a pas le droit de modifier un
/// fichier existant. On filtre donc la zone côté client sur le résultat de
/// `statut=PRETE` : le prédicat serveur est `livraison_zone == 'RECUPERATION'`,
/// strictement le même que celui appliqué ici, donc la liste obtenue est
/// identique (seul l'ensemble transféré est un peu plus large, et il reste
/// petit puisque limité aux commandes déjà prêtes).
///
/// `realtimeTickProvider` remplace `useRealtimeRefresh(['order',
/// 'order_status_history'], ...)` du web : une commande passée « Prête » par
/// un préparateur apparaît ici sans action de l'utilisateur (§9 README).
final pickupOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  ref.watch(realtimeTickProvider);
  final orders = await ref.read(ordersRepositoryProvider).list(statut: OrderStatus.prete.apiValue);
  return orders.where((o) => o.livraisonZone == kRecuperationCode).toList();
});

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
class PickupScreen extends ConsumerStatefulWidget {
  const PickupScreen({super.key});

  @override
  ConsumerState<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends ConsumerState<PickupScreen> {
  /// `confirming` du web : id de la commande en cours de validation (une
  /// seule à la fois) — désactive son bouton et affiche « Confirmation... ».
  int? _confirming;

  /// Rechargement NON silencieux déclenché par le bouton « Rafraîchir » :
  /// le web réaffiche ses skeletons (`fetchOrders()` sans `silent`).
  bool _reloading = false;

  /// Dernière erreur déjà signalée par un toast, pour ne pas répéter le même
  /// SnackBar à chaque reconstruction.
  Object? _reportedError;

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

  /// Bouton « Marquer comme récupérée » : ouvre la confirmation, puis
  /// `POST /orders/{id}/status/ {statut: 'LIVRE'}` — exactement
  /// `confirmPickup(order)` du web.
  Future<void> _confirmPickup(Order order) async {
    // Dialogue partagé du projet (widgets/order_confirm_dialog.dart) : il
    // porte le titre dynamique du web et, en plus, le récapitulatif complet
    // (client, téléphone, zone, articles, total) ainsi qu'une note
    // optionnelle envoyée avec le changement de statut. Aucune photo n'est
    // demandée pour un retrait sur place (`showPhoto` reste false), comme le
    // web. « Annuler » (ou Échap / clic extérieur) renvoie null : aucune API
    // appelée.
    final result = await showOrderConfirmDialog(
      context,
      title: 'Confirmer la récupération de ${order.numero} ?',
      order: order,
    );
    if (result == null) return;

    setState(() => _confirming = order.id);
    try {
      await ref.read(ordersRepositoryProvider).changeStatus(
            order.id,
            OrderStatus.livre.apiValue,
            note: result.note,
          );
      _snack('Commande ${order.numero} récupérée');
      // Refetch silencieux : la carte disparaît de la liste puisque la
      // commande n'est plus PRETE. `ordersProvider` est invalidé pour que la
      // page Commandes reflète le changement si elle est ouverte.
      ref.invalidate(pickupOrdersProvider);
      ref.invalidate(ordersProvider);
    } catch (e) {
      // Web : toast.error(err.message || 'Action impossible').
      _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _confirming = null);
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
      _snack(ApiClient.messageFromError(error));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Récupération sur place'),
        actions: [
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
    // projet (widgets/async_state_widgets.dart).
    if (_reloading || (!async.hasValue && async.isLoading)) return const LoadingState();
    if (!async.hasValue) {
      return ErrorState(message: ApiClient.messageFromError(async.error!), onRetry: _refresh);
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
                            order: order,
                            confirming: _confirming == order.id,
                            onConfirm: () => _confirmPickup(order),
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
  const _PickupCard({required this.order, required this.confirming, required this.onConfirm});

  final Order order;
  final bool confirming;
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
              // Web : <a href="tel:..."> — ici l'appel natif via url_launcher.
              InkWell(
                onTap: () => launchUrl(Uri.parse('tel:$phone')),
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
                Text(
                  arFmt(order.totalAPayer ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                FilledButton.icon(
                  // Ouvre la modale de confirmation — jamais l'API
                  // directement (comme le web). Désactivé pendant l'envoi de
                  // CETTE commande, avec le libellé « Confirmation... ».
                  onPressed: confirming ? null : onConfirm,
                  icon: confirming
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(confirming ? 'Confirmation...' : 'Marquer comme récupérée'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
