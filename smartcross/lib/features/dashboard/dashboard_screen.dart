import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/dashboard.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/kpi_card.dart';

final _moneyFmt = NumberFormat.decimalPattern('fr_FR');

String _ar(num value) => '${_moneyFmt.format(value.round())} Ar';

/// Dashboard Gérant (§7.7 README) : KPIs, suivi temps réel, analyse
/// financière, TOP produits, stock rapide — filtrable par période.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final filter = ref.watch(dashboardFilterProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Tableau de bord', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in DashboardPeriodPreset.values)
                  ChoiceChip(
                    label: Text(_presetLabel(preset)),
                    selected: filter.preset == preset,
                    onSelected: (_) => ref.read(dashboardFilterProvider.notifier).set(filter.copyWith(preset: preset)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            switch (async) {
              AsyncData(:final value) => _DashboardBody(data: value),
              AsyncError(:final error) => ErrorState(
                  message: ApiClient.messageFromError(error),
                  onRetry: () => ref.read(dashboardProvider.notifier).refresh(),
                ),
              _ => const Padding(padding: EdgeInsets.only(top: 60), child: LoadingState()),
            },
          ],
        ),
      ),
    );
  }

  String _presetLabel(DashboardPeriodPreset preset) {
    switch (preset) {
      case DashboardPeriodPreset.jour:
        return "Aujourd'hui";
      case DashboardPeriodPreset.semaine:
        return 'Cette semaine';
      case DashboardPeriodPreset.mois:
        return 'Ce mois';
      case DashboardPeriodPreset.personnalise:
        return 'Personnalisé';
    }
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    final fin = data.financiere;
    final stock = data.stockRapide;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KpiGrid(
          children: [
            KpiCard(label: 'Ventes (période)', value: '${k.nbVentes}', icon: Icons.shopping_bag_outlined),
            KpiCard(label: 'CA période', value: _ar(k.caPeriode), icon: Icons.payments_outlined, accentColor: Colors.green),
            KpiCard(label: 'CA mois en cours', value: _ar(k.caMoisEnCours), icon: Icons.calendar_month_outlined),
            KpiCard(
              label: 'Taux livraison réussie',
              value: k.tauxLivraisonReussiePct != null ? '${k.tauxLivraisonReussiePct}%' : '—',
              icon: Icons.local_shipping_outlined,
            ),
            KpiCard(label: 'Retours', value: '${k.nbRetours}', icon: Icons.assignment_return_outlined, accentColor: Colors.orange),
          ],
        ),
        const SizedBox(height: 20),
        Text('Suivi commandes en temps réel', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final entry in data.suiviCommandesTempsReel.entries) _StatusCountChip(statut: entry.key, count: entry.value),
          ],
        ),
        const SizedBox(height: 20),
        Text('Analyse financière', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _FinanceRow('CA produits vendus', fin.caProduitsVendus),
                _FinanceRow('Frais de livraison encaissés', fin.fraisLivraisonEncaisses),
                _FinanceRow('Total investi fournisseurs', -fin.totalInvestiFournisseurs, negative: true),
                _FinanceRow('Total pub Meta Ads', -fin.totalPubMetaAds, negative: true),
                const Divider(height: 24),
                _FinanceRow('Bénéfice estimé', fin.beneficeEstime, emphasize: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Stock rapide', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        KpiGrid(
          children: [
            KpiCard(label: 'Total en stock', value: '${stock.totalEnStock}', icon: Icons.inventory_2_outlined),
            KpiCard(label: 'Ruptures', value: '${stock.ruptures}', icon: Icons.remove_shopping_cart_outlined, accentColor: Colors.red),
            KpiCard(label: 'Stock bas', value: '${stock.stockBas}', icon: Icons.trending_down, accentColor: Colors.orange),
          ],
        ),
        const SizedBox(height: 20),
        Text('TOP 20 produits (période)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;
          final blocks = [
            _TopList(title: 'Par sous-type', entries: data.topParSousType),
            _TopList(title: 'Marques', entries: data.topMarques),
            _TopList(title: 'Références', entries: data.topReferences),
            _TopList(title: 'Couleurs', entries: data.topCouleurs),
          ];
          if (isWide) {
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: blocks,
            );
          }
          return Column(children: [for (final b in blocks) Padding(padding: const EdgeInsets.only(bottom: 12), child: b)]);
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow(this.label, this.value, {this.negative = false, this.emphasize = false});
  final String label;
  final double value;
  final bool negative;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    final color = negative ? Colors.red : (emphasize ? (value >= 0 ? Colors.green : Colors.red) : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('${negative ? '-' : ''}${_ar(value.abs())}', style: style?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _StatusCountChip extends StatelessWidget {
  const _StatusCountChip({required this.statut, required this.count});
  final String statut;
  final int count;

  static const _labels = {
    'NOUVELLE': 'Nouvelle',
    'EN_PREPARATION': 'En préparation',
    'PRETE': 'Prête',
    'EN_LIVRAISON': 'En livraison',
    'LIVRE': 'Livrée',
    'RETOUR': 'Retour',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('${_labels[statut] ?? statut} : $count', style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _TopList extends StatelessWidget {
  const _TopList({required this.title, required this.entries});
  final String title;
  final List<TopEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucune donnée', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length > 5 ? 5 : entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(e.label, overflow: TextOverflow.ellipsis)),
                          Text('${e.quantiteVendue}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
