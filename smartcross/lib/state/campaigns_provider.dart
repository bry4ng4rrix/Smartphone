import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/campaigns_repository.dart';
import '../models/campaign.dart';
import 'reports_provider.dart';

final campaignsRepositoryProvider = Provider((ref) => CampaignsRepository());

/// Campagnes marketing ACTIVES (`djangoClient.campaigns.list({ actif: true })`)
/// — proposées par le formulaire de commande comme campagne d'origine. Les
/// écritures (gérant) rechargent la liste silencieusement et invalident le
/// cache des rapports (le rapport Marketing en dépend). Les erreurs remontent
/// à l'appelant (`ApiClient.messageFromError`).
class CampaignsNotifier extends AsyncNotifier<List<MarketingCampaign>> {
  late final _repo = ref.read(campaignsRepositoryProvider);

  @override
  Future<List<MarketingCampaign>> build() => _repo.list(actif: true);

  /// Rechargement NON silencieux (réaffiche l'état de chargement).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.list(actif: true));
  }

  Future<void> _refreshSilencieux() async {
    state = await AsyncValue.guard(() => _repo.list(actif: true));
    invalidateReports(ref);
  }

  /// `campaigns.create(data)` — payload : `nom`, `plateforme`, `montant`,
  /// `date_debut`, `date_fin?`, `note?`, `actif?`, `magasin_id?`.
  Future<MarketingCampaign> create(Map<String, dynamic> payload) async {
    final c = await _repo.create(payload);
    await _refreshSilencieux();
    return c;
  }

  /// `campaigns.update(id, data)` (PATCH partiel) — `updateCampaign` car
  /// `update` est réservé par AsyncNotifier.
  Future<MarketingCampaign> updateCampaign(int id, Map<String, dynamic> payload) async {
    final c = await _repo.update(id, payload);
    await _refreshSilencieux();
    return c;
  }

  /// `campaigns.delete(id)`.
  Future<void> delete(int id) async {
    await _repo.delete(id);
    await _refreshSilencieux();
  }

  /// `campaigns.setOrderCampaign(orderId, campagne)` — rattache (ou détache
  /// avec `null`) une commande à une campagne, puis invalide les rapports.
  Future<void> setOrderCampaign(int orderId, int? campagne) async {
    await _repo.setOrderCampaign(orderId, campagne);
    invalidateReports(ref);
  }
}

/// Invalidé à la déconnexion (orchestrateur, lib/state/auth_provider.dart).
final campaignsProvider = AsyncNotifierProvider<CampaignsNotifier, List<MarketingCampaign>>(
  CampaignsNotifier.new,
  retry: (_, _) => null,
);
