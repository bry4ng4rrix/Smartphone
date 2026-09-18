import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../models/supplier.dart';
import '../../state/suppliers_provider.dart';
import '../../widgets/async_state_widgets.dart';
import 'supplier_form_dialog.dart';
import 'supplier_order_card.dart';
import 'supplier_status.dart';

/// Page Fournisseurs (`/suppliers`) — miroir de frontend/app/(app)/suppliers :
/// indicateurs, onglet « Approvisionnements » (cartes § 16, filtres statut /
/// fournisseur / recherche) et onglet « Fournisseurs » (fiches).
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _searchController = TextEditingController();
  String _search = '';
  SupplierOrderStatus? _statut;
  int? _supplierId;

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<SupplierOrder> _filtrer(List<SupplierOrder> orders) {
    final q = _search.trim().toLowerCase();
    return orders.where((o) {
      if (_statut != null && o.statut != _statut) return false;
      if (_supplierId != null && o.supplierId != _supplierId) return false;
      if (q.isNotEmpty) {
        final texte = [o.numero, o.supplierNom, o.produitLibelle, o.tracking, o.numeroColis, o.description ?? ''].join(' ').toLowerCase();
        if (!texte.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _nouvelAppro([Supplier? supplier]) async {
    final id = await context.push<int>('/suppliers/new', extra: supplier);
    if (id != null && mounted) context.push('/suppliers/$id');
  }

  Future<void> _formFournisseur([Supplier? supplier]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => SupplierFormDialog(supplier: supplier));
    if (ok == true) {
      ref.invalidate(suppliersListProvider);
      ref.invalidate(supplierKpisProvider);
    }
  }

  Future<void> _supprimerFournisseur(Supplier s) async {
    final utilise = s.nbApprovisionnements > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(utilise ? 'Désactiver « ${s.nom} » ?' : 'Supprimer « ${s.nom} » ?'),
        content: Text(utilise
            ? 'Ce fournisseur a ${s.nbApprovisionnements} approvisionnement(s) : il sera désactivé, l\'historique est conservé.'
            : 'Suppression définitive de la fiche.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(utilise ? 'Désactiver' : 'Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(suppliersRepositoryProvider).supplierDelete(s.id);
      ref.invalidate(suppliersListProvider);
      ref.invalidate(supplierKpisProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(utilise ? 'Fournisseur désactivé' : 'Fournisseur supprimé')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ordersAsync = ref.watch(supplierOrdersProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);
    final kpisAsync = ref.watch(supplierKpisProvider);
    final suppliers = suppliersAsync.value ?? const <Supplier>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fournisseurs'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(supplierOrdersProvider.notifier).refresh();
              ref.invalidate(suppliersListProvider);
              ref.invalidate(supplierKpisProvider);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'appro' ? _nouvelAppro() : _formFournisseur(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'appro', child: ListTile(leading: Icon(Icons.add_box_outlined), title: Text('Nouvel approvisionnement'))),
              PopupMenuItem(value: 'fournisseur', child: ListTile(leading: Icon(Icons.factory_outlined), title: Text('Nouveau fournisseur'))),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Approvisionnements'), Tab(text: 'Fournisseurs')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nouvelAppro(),
        icon: const Icon(Icons.add),
        label: const Text('Approvisionnement'),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ------------------------------------------------ Approvisionnements
          RefreshIndicator(
            onRefresh: () async {
              await ref.read(supplierOrdersProvider.notifier).refreshSilencieux();
              ref.invalidate(supplierKpisProvider);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _Kpis(kpis: kpisAsync.value)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _search = v),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'N°, sous-type, fournisseur, tracking, colis…',
                            suffixIcon: _search.isEmpty
                                ? null
                                : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _searchController.clear(); _search = ''; })),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<SupplierOrderStatus?>(
                                key: ValueKey('statut-$_statut'),
                                initialValue: _statut,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Statut', isDense: true),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Tous les statuts')),
                                  for (final s in SupplierOrderStatus.values) DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() => _statut = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                key: ValueKey('supplier-$_supplierId'),
                                initialValue: _supplierId,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Fournisseur', isDense: true),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Tous')),
                                  for (final s in suppliers) DropdownMenuItem(value: s.id, child: Text(s.nom, overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() => _supplierId = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                ...ordersAsync.when(
                  data: (orders) {
                    final list = _filtrer(orders);
                    if (list.isEmpty) {
                      return [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            message: orders.isEmpty ? 'Aucun approvisionnement. Créez-en un : un fournisseur, un sous-type, une quantité.' : 'Aucun approvisionnement pour ces filtres.',
                            icon: Icons.local_shipping_outlined,
                          ),
                        ),
                      ];
                    }
                    return [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                        sliver: SliverList.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => SupplierOrderCard(
                            order: list[i],
                            compact: true,
                            onTap: () => context.push('/suppliers/${list[i].id}'),
                          ),
                        ),
                      ),
                    ];
                  },
                  loading: () => const [SliverFillRemaining(hasScrollBody: false, child: LoadingState())],
                  error: (e, _) => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorState(message: ApiClient.messageFromError(e), onRetry: () => ref.read(supplierOrdersProvider.notifier).refresh()),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ------------------------------------------------ Fournisseurs
          suppliersAsync.when(
            data: (list) => list.isEmpty
                ? const EmptyState(message: 'Aucun fournisseur. Créez une fiche pour y rattacher vos approvisionnements.', icon: Icons.factory_outlined)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.nom, style: TextStyle(fontWeight: FontWeight.w700, decoration: s.actif ? null : TextDecoration.lineThrough)),
                                        Text([s.pays, s.contact, s.telephone].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined), onPressed: () => _formFournisseur(s)),
                                  IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _supprimerFournisseur(s)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                runSpacing: 2,
                                children: [
                                  Text('${s.nbApprovisionnements} appro(s) · ${s.nbEnCours} en cours', style: const TextStyle(fontSize: 12)),
                                  Text('Payé ${fmtAr(s.totalPayeMga)}', style: const TextStyle(fontSize: 12)),
                                  Text('Reste ${fmtDevise(s.resteAPayerDevise, s.devise)}', style: const TextStyle(fontSize: 12)),
                                  if (s.dernierNumero != null) Text('Dernier : ${s.dernierNumero}', style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _nouvelAppro(s),
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Approvisionnement'),
                                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () => setState(() { _supplierId = s.id; _tabs.animateTo(0); }),
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                    child: const Text('Historique'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(message: ApiClient.messageFromError(e), onRetry: () => ref.invalidate(suppliersListProvider)),
          ),
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.kpis});
  final SupplierKpis? kpis;

  @override
  Widget build(BuildContext context) {
    final k = kpis;
    if (k == null) return const SizedBox(height: 8);
    final scheme = Theme.of(context).colorScheme;
    Widget tuile(String titre, String valeur, String detail) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(valeur, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(detail, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Row(children: [
            tuile('En cours', '${k.nbEnCours}', '${k.nbApprovisionnements} au total · ${k.nbFinalises} finalisé(s)'),
            const SizedBox(width: 8),
            tuile('En transit', '${k.enTransitNb}', '${fmtAr(k.enTransitValeurMga)} · ${k.aFinaliser} à finaliser'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            tuile('Total payé', fmtAr(k.totalPayeMga), 'Frais + Douane ${fmtAr(k.totalFraisDouaneMga)}'),
            const SizedBox(width: 8),
            tuile('Coût moyen / pièce', k.coutMoyenParPieceMga == null ? '—' : fmtAr(k.coutMoyenParPieceMga!), '${k.nbFournisseursActifs} fournisseur(s) actif(s)'),
          ]),
        ],
      ),
    );
  }
}
