import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/permissions.dart';
import '../../models/caisse.dart';
import '../../models/magasin.dart';
import '../../state/auth_provider.dart';
import '../../state/caisse_provider.dart';
import '../../state/finance_provider.dart';
import '../../state/stores_provider.dart';
import '../../widgets/async_state_widgets.dart';
import 'tresorerie_sections.dart';

/// `money(v)` du web : `toLocaleString('fr-FR', {min 0, max 2 décimales})`
/// + « Ar » — différent du bilan qui arrondit à l'entier.
final _moneyFmt = NumberFormat.decimalPattern('fr_FR')
  ..minimumFractionDigits = 0
  ..maximumFractionDigits = 2;
String _money(num? v) => '${_moneyFmt.format(v ?? 0)} Ar';

/// `formatDateTime` du web : `format(v, 'dd MMM yyyy HH:mm', {locale: fr})`
/// → « 10 sept. 2026 14:30 », « - » si null. Affiché en heure
/// d'Antananarivo (core/app_time.dart) — le web utilise le fuseau de
/// l'appareil, l'app tranche pour le fuseau métier comme le bilan.
const _moisAbr = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  final d = appLocal(value);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)} ${_moisAbr[d.month - 1]} ${d.year} ${two(d.hour)}:${two(d.minute)}';
}

final _dayFmt = DateFormat('dd/MM/yyyy');
final _apiDayFmt = DateFormat('yyyy-MM-dd');
final _wallClockFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Code couleur systématique du web : entrées/positif vert (green-600),
/// sorties/négatif rouge (red-600), coût orange (orange-600), bénéfice
/// green-700, écart nul vert / non nul orange-700.
const _green = Color(0xFF16A34A);
const _green700 = Color(0xFF15803D);
const _red = Color(0xFFDC2626);
const _orange = Color(0xFFEA580C);
const _orange700 = Color(0xFFC2410C);
const _blue = Color(0xFF2563EB);

/// `Number(text)` du web, tolérant à la virgule décimale et aux espaces.
double? _parseAmount(String text) {
  final cleaned = text.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Valeur pré-remplie dans un champ montant : entier si possible.
String _amountText(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Heure « au mur » d'Antananarivo, maintenant, à la minute — objet naïf
/// (sans drapeau UTC) pour que les bornes des sélecteurs de date se
/// comparent champ à champ.
DateTime _wallNow() {
  final n = appNow();
  return DateTime(n.year, n.month, n.day, n.hour, n.minute);
}

/// Page `/caisse` du web (frontend/app/(app)/caisse/page.tsx).
///
/// Gestion complète de la caisse d'un magasin : ouvrir une session avec un
/// fond de départ (montant + heure), enregistrer les mouvements d'espèces
/// (entrée/sortie avec catégorie de dépense), fermer la session avec le
/// montant compté (+ heure) et l'écart, résumé financier de période
/// (entrées/sorties/solde + CA/coût/bénéfice des produits vendus, sorties par
/// catégorie, mouvements de la période) et historique des sessions fermées.
///
/// Gating : réservé au gérant (`admin` ou `magasin`, [UserPermissions
/// .isGerant]) — le backend est `IsGerant` sur tous les endpoints ; un
/// préparateur/livreur voit un écran « Accès refusé » explicite (le web le
/// laisse tomber sur des toasts 403). Règle centrale du web :
/// `magasinId = isAdmin ? selectedMagasinId : user.magasin_id` — l'admin
/// n'a pas de magasin propre et DOIT en choisir un dans la barre
/// « Magasin : ».
class CaisseScreen extends ConsumerStatefulWidget {
  const CaisseScreen({super.key});

  @override
  ConsumerState<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends ConsumerState<CaisseScreen> with SingleTickerProviderStateMixin {
  /// Onglets de la caisse — mêmes sections que le web : Trésorerie, Journal,
  /// Ventes, Épargne, Boost, Sessions (ouverture / mouvements / fermeture).
  late final TabController _tabs = TabController(length: 6, vsync: this);

  /// Plage du résumé : `summaryFrom` = premier jour du mois courant,
  /// `summaryTo` = aujourd'hui — jours d'Antananarivo (le backend compare
  /// `created_at__date` dans ce fuseau).
  late DateTime _summaryFrom;
  late DateTime _summaryTo;

  /// `loading` du web pendant `fetchCaisse()` : rechargement NON silencieux
  /// (bouton « Actualiser »), les cartes sont remplacées par le chargement.
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    final today = appToday();
    _summaryFrom = DateTime(today.year, today.month, 1);
    _summaryTo = today;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  CaissePeriodQuery _periodQuery(int magasinId) => (
        magasinId: magasinId,
        dateFrom: _apiDayFmt.format(_summaryFrom),
        dateTo: _apiDayFmt.format(_summaryTo),
      );

  /// Même période pour la trésorerie (`/api/finance/*`).
  FinanceQuery _financeQuery(int magasinId) => (
        magasinId: magasinId,
        dateFrom: _apiDayFmt.format(_summaryFrom),
        dateTo: _apiDayFmt.format(_summaryTo),
      );

  /// Recharge tout ce qui dépend de la trésorerie (après remise, retrait,
  /// boost, session…).
  void _rechargerTresorerie(int magasinId) {
    ref.invalidate(financeDashboardProvider(_financeQuery(magasinId)));
    ref.invalidate(financeJournalProvider(_financeQuery(magasinId)));
    ref.invalidate(financeVentesProvider(_financeQuery(magasinId)));
    ref.invalidate(financeEpargneProvider(magasinId));
    ref.invalidate(caisseHistoryProvider(magasinId));
    ref.invalidate(caissePeriodProvider(_periodQuery(magasinId)));
    ref.read(currentCaisseProvider(magasinId).notifier).refreshSilencieux();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// `fetchCaisse()` du web : session courante + sessions (historique),
  /// NON silencieux. Ne recharge PAS le résumé de période (asymétrie du
  /// web, reproduite).
  Future<void> _fetchCaisse() async {
    final magasinId = ref.read(caisseMagasinIdProvider);
    if (magasinId == null || _refreshing) return;
    setState(() => _refreshing = true);
    Object? failure;
    try {
      await ref.read(currentCaisseProvider(magasinId).notifier).refresh();
      ref.invalidate(caisseHistoryProvider(magasinId));
      await ref.read(caisseHistoryProvider(magasinId).future);
    } catch (e) {
      failure = e;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    if (!mounted) return;
    // `refresh()` du notifier ne lève jamais (AsyncValue.guard) : on relit
    // l'état pour signaler une erreur de la session courante.
    final after = ref.read(currentCaisseProvider(magasinId));
    failure ??= after.hasError ? after.error : null;
    if (failure != null) _snack('Erreur de chargement de la caisse: ${ApiClient.messageFromError(failure)}');
  }

  /// Tirer-pour-rafraîchir : tout recharger silencieusement (session,
  /// historique, résumé de période).
  Future<void> _refreshSilencieux(int magasinId) async {
    ref.invalidate(caisseHistoryProvider(magasinId));
    ref.invalidate(caissePeriodProvider(_periodQuery(magasinId)));
    ref.invalidate(financeDashboardProvider(_financeQuery(magasinId)));
    ref.invalidate(financeJournalProvider(_financeQuery(magasinId)));
    ref.invalidate(financeVentesProvider(_financeQuery(magasinId)));
    ref.invalidate(financeEpargneProvider(magasinId));
    await ref.read(currentCaisseProvider(magasinId).notifier).refreshSilencieux();
  }

  Future<void> _pickSummaryDate({required bool from}) async {
    final initial = from ? _summaryFrom : _summaryTo;
    final today = appToday();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(today.year + 1, 12, 31),
      helpText: from ? 'Début de la période' : 'Fin de la période',
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (from) {
        _summaryFrom = day;
      } else {
        _summaryTo = day;
      }
    });
  }

  Future<void> _openOpenDialog(int magasinId) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _OpenDialog(magasinId: magasinId));
    if (ok == true) _snack('Caisse ouverte');
  }

  Future<void> _openCloseDialog(int magasinId, CaisseSession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _CloseDialog(magasinId: magasinId, session: session),
    );
    if (ok == true) _snack('Caisse fermée');
  }

  Future<void> _openMovementDialog(int magasinId) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _MovementDialog(magasinId: magasinId));
    if (ok == true) _snack('Mouvement ajouté');
  }

  /// Correction d'un mouvement de la session ouverte (§ demande).
  Future<void> _editMovement(int magasinId, CaisseMovement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _MovementDialog(magasinId: magasinId, existing: m),
    );
    if (ok == true) _snack('Mouvement modifié');
  }

  /// Suppression après confirmation — le solde attendu est recalculé.
  Future<void> _deleteMovement(int magasinId, CaisseMovement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce mouvement ?'),
        content: Text(
          '${m.isIn ? 'Entrée' : 'Sortie'} de ${_money(m.amount)} — « ${m.reason} » (${_formatDateTime(m.createdAt)}).\n'
          'Le solde attendu de la session est recalculé. Cette action est irréversible.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(currentCaisseProvider(magasinId).notifier).deleteMovement(m.id);
      _snack('Mouvement supprimé');
    } catch (e) {
      _snack(ApiClient.messageFromError(e));
    }
  }

  /// Toasts d'erreur de chargement (sonner du web) — les données
  /// précédentes restent affichées.
  void _toastOnError<T>(AsyncValue<T>? previous, AsyncValue<T> next, String prefix) {
    if (!next.hasError || next.isLoading) return;
    if (previous != null && previous.hasError && identical(previous.error, next.error)) return;
    _snack('$prefix: ${ApiClient.messageFromError(next.error!)}');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final scheme = Theme.of(context).colorScheme;

    // `userLoading` du web.
    if (auth.status == AuthStatus.loading || user == null) {
      return Scaffold(appBar: AppBar(title: const Text('Caisse')), body: const LoadingState());
    }
    if (!user.isGerant) return const _AccesRefuse();

    final isAdmin = user.isAdmin;
    final magasinId = ref.watch(caisseMagasinIdProvider);

    if (isAdmin) {
      ref.listen(storesProvider, (previous, next) => _toastOnError(previous, next, 'Erreur de chargement des magasins'));
    }
    if (magasinId != null) {
      ref.listen(
        currentCaisseProvider(magasinId),
        (previous, next) => _toastOnError(previous, next, 'Erreur de chargement de la caisse'),
      );
      ref.listen(
        caissePeriodProvider(_periodQuery(magasinId)),
        (previous, next) => _toastOnError(previous, next, 'Erreur de chargement du résumé'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: _blue),
            SizedBox(width: 8),
            Text('Caisse'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: (magasinId == null || _refreshing) ? null : _fetchCaisse,
              icon: _refreshing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Actualiser'),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isAdmin)
            _StoreSelector(
              selectedId: magasinId,
              onSelect: (id) => ref.read(caisseSelectedMagasinProvider.notifier).select(id),
            ),
          // Période partagée par toutes les sections (jours d'Antananarivo).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(child: _DateButton(label: _dayFmt.format(_summaryFrom), onTap: () => _pickSummaryDate(from: true))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
                Expanded(child: _DateButton(label: _dayFmt.format(_summaryTo), onTap: () => _pickSummaryDate(from: false))),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Trésorerie'),
              Tab(text: 'Journal'),
              Tab(text: 'Ventes'),
              Tab(text: 'Épargne'),
              Tab(text: 'Boost'),
              Tab(text: 'Sessions'),
            ],
          ),
          Expanded(
            child: magasinId == null
                ? _NoMagasin(isAdmin: isAdmin)
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _tresorerie(magasinId),
                      _journal(magasinId),
                      _ventes(magasinId),
                      _epargne(magasinId),
                      _boost(magasinId),
                      _buildCaisse(magasinId),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _refreshable(int magasinId, Widget child) => RefreshIndicator(
        onRefresh: () => _refreshSilencieux(magasinId),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [child],
        ),
      );

  Widget _tresorerie(int magasinId) {
    final async = ref.watch(financeDashboardProvider(_financeQuery(magasinId)));
    final session = ref.watch(currentCaisseProvider(magasinId)).value;
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(message: ApiClient.messageFromError(e), onRetry: () => _rechargerTresorerie(magasinId)),
      data: (d) => _refreshable(
        magasinId,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TresorerieIndicateurs(ind: d.indicateurs),
            const SizedBox(height: 12),
            SectionGain(d: d),
            const SizedBox(height: 12),
            SectionEncaissements(
              enc: d.encaissements,
              magasinId: magasinId,
              sessionOuverte: session != null && session.isOpen,
              onChanged: () => _rechargerTresorerie(magasinId),
            ),
            const SizedBox(height: 12),
            SectionLivraison(d: d),
          ],
        ),
      ),
    );
  }

  Widget _journal(int magasinId) => _refreshable(
        magasinId,
        SectionJournal(
          async: ref.watch(financeJournalProvider(_financeQuery(magasinId))),
          onRetry: () => ref.invalidate(financeJournalProvider(_financeQuery(magasinId))),
        ),
      );

  Widget _ventes(int magasinId) => _refreshable(
        magasinId,
        SectionVentes(
          async: ref.watch(financeVentesProvider(_financeQuery(magasinId))),
          onRetry: () => ref.invalidate(financeVentesProvider(_financeQuery(magasinId))),
        ),
      );

  Widget _epargne(int magasinId) {
    final d = ref.watch(financeDashboardProvider(_financeQuery(magasinId))).value;
    return _refreshable(
      magasinId,
      SectionEpargne(
        magasinId: magasinId,
        async: ref.watch(financeEpargneProvider(magasinId)),
        versePeriode: d?.epargneVersePeriode ?? 0,
        retirePeriode: d?.epargneRetirePeriode ?? 0,
        onChanged: () => _rechargerTresorerie(magasinId),
      ),
    );
  }

  Widget _boost(int magasinId) {
    final async = ref.watch(financeDashboardProvider(_financeQuery(magasinId)));
    final session = ref.watch(currentCaisseProvider(magasinId)).value;
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(message: ApiClient.messageFromError(e), onRetry: () => _rechargerTresorerie(magasinId)),
      data: (d) => _refreshable(
        magasinId,
        SectionBoost(
          boosts: d.boosts,
          magasinId: magasinId,
          sessionOuverte: session != null && session.isOpen,
          onChanged: () => _rechargerTresorerie(magasinId),
        ),
      ),
    );
  }

  Widget _buildCaisse(int magasinId) {
    final sessionAsync = ref.watch(currentCaisseProvider(magasinId));
    final historyAsync = ref.watch(caisseHistoryProvider(magasinId));
    final periodAsync = ref.watch(caissePeriodProvider(_periodQuery(magasinId)));

    // `loading` du web : les 3 cartes remplacées par le chargement.
    if (_refreshing || (!sessionAsync.hasValue && !sessionAsync.hasError)) {
      return const LoadingState();
    }
    if (sessionAsync.hasError && !sessionAsync.hasValue) {
      return ErrorState(
        message: 'Erreur de chargement de la caisse: ${ApiClient.messageFromError(sessionAsync.error!)}',
        onRetry: _fetchCaisse,
      );
    }

    final session = sessionAsync.value;
    return RefreshIndicator(
      onRefresh: () => _refreshSilencieux(magasinId),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _SessionCard(
            session: session,
            onOpen: () => _openOpenDialog(magasinId),
            onMovement: () => _openMovementDialog(magasinId),
            onClose: session == null ? null : () => _openCloseDialog(magasinId, session),
            // Modifier / supprimer : session ouverte uniquement (§ demande).
            onEditMovement: session != null && session.isOpen ? (m) => _editMovement(magasinId, m) : null,
            onDeleteMovement: session != null && session.isOpen ? (m) => _deleteMovement(magasinId, m) : null,
          ),
          const SizedBox(height: 16),
          _SummaryCard(
            periodAsync: periodAsync,
            from: _summaryFrom,
            to: _summaryTo,
            onRetry: () => ref.invalidate(caissePeriodProvider(_periodQuery(magasinId))),
          ),
          const SizedBox(height: 16),
          _HistoryCard(
            historyAsync: historyAsync,
            onRetry: () => ref.invalidate(caisseHistoryProvider(magasinId)),
          ),
        ],
      ),
    );
  }
}

/// Écran « Accès refusé » — un préparateur/livreur (ou un employé sans
/// sous-rôle) n'a aucun droit sur la caisse (backend `IsGerant`).
class _AccesRefuse extends StatelessWidget {
  const _AccesRefuse();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caisse')),
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
                    'Cette page est réservée aux gérants.',
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

/// Barre « Magasin : » (admin uniquement) — un bouton par magasin de
/// `GET /users/magasins/users/` (logo rond ou icône Store + nom), aucune
/// présélection ; « Aucun magasin » si la liste est vide.
class _StoreSelector extends ConsumerWidget {
  const _StoreSelector({required this.selectedId, required this.onSelect});

  final int? selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final storesAsync = ref.watch(storesProvider);

    Widget content;
    if (!storesAsync.hasValue && !storesAsync.hasError) {
      content = const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (storesAsync.hasError && !storesAsync.hasValue) {
      content = Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => ref.read(storesProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Réessayer'),
        ),
      );
    } else {
      final stores = storesAsync.value ?? const <Magasin>[];
      content = stores.isEmpty
          ? Text('Aucun magasin', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final store in stores) ...[
                    ChoiceChip(
                      avatar: _StoreLogo(url: store.shopLogo),
                      label: Text(store.shopName),
                      selected: selectedId == store.magasinId,
                      onSelected: (_) => onSelect(store.magasinId),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Text(
            'Magasin :',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Logo rond du magasin (`shop_logo`), icône Store grise en repli.
class _StoreLogo extends StatelessWidget {
  const _StoreLogo({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.storefront_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url!,
        width: 16,
        height: 16,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }
}

/// `!magasinId` du web : aucun magasin résolu.
class _NoMagasin extends StatelessWidget {
  const _NoMagasin({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
            child: Text(
              isAdmin ? 'Sélectionnez un magasin pour gérer sa caisse.' : 'Aucun magasin associé à votre compte.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Tuiles KPI (grilles 2/4 et 2/3/6 du web)
// -----------------------------------------------------------------------------

class _Kpi {
  const _Kpi(this.label, this.value, {this.color, this.icon});
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.tiles, required this.mdColumns, required this.lgColumns});

  final List<_Kpi> tiles;
  final int mdColumns;
  final int lgColumns;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1000
            ? lgColumns
            : width >= 600
                ? mdColumns
                : 2;
        const spacing = 12.0;
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: [
            for (final t in tiles)
              SizedBox(
                width: tileWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (t.icon != null) ...[
                          Icon(t.icon, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            t.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t.value,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: t.color,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Listes de mouvements (session en cours / période)
// -----------------------------------------------------------------------------

/// Conteneur `border rounded-lg divide-y max-h-* overflow-y-auto` du web :
/// liste bornée en hauteur qui défile en interne.
class _MovementList extends StatelessWidget {
  const _MovementList({
    required this.movements,
    required this.maxHeight,
    required this.emptyText,
    this.showCategory = false,
    this.onEdit,
    this.onDelete,
  });

  final List<CaisseMovement> movements;
  final double maxHeight;
  final String emptyText;

  /// Titre `{reason} · {category_name}` (liste de la période uniquement).
  final bool showCategory;

  /// Modifier / supprimer un mouvement (session ouverte uniquement, § demande).
  final ValueChanged<CaisseMovement>? onEdit;
  final ValueChanged<CaisseMovement>? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: movements.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView.separated(
                shrinkWrap: true,
                primary: false,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: movements.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant),
                itemBuilder: (context, i) =>
                    _MovementRow(movement: movements[i], showCategory: showCategory, onEdit: onEdit, onDelete: onDelete),
              ),
            ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement, required this.showCategory, this.onEdit, this.onDelete});

  final CaisseMovement movement;
  final bool showCategory;
  final ValueChanged<CaisseMovement>? onEdit;
  final ValueChanged<CaisseMovement>? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = movement;
    final color = m.isIn ? _green : _red;
    final category = m.categoryName;
    final title = showCategory && category != null && category.isNotEmpty ? '${m.reason} · $category' : m.reason;
    final by = m.createdByName;
    final subtitle = '${_formatDateTime(m.createdAt)}${by != null && by.isNotEmpty ? ' · $by' : ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(m.isIn ? Icons.arrow_circle_up_outlined : Icons.arrow_circle_down_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${m.isIn ? '+' : '-'}${_money(m.amount)}',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color),
          ),
          // Crayon / corbeille (session ouverte uniquement), comme sur le web.
          if (onEdit != null)
            IconButton(
              tooltip: 'Modifier le mouvement',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: () => onEdit!(m),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Supprimer le mouvement',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: scheme.error,
              onPressed: () => onDelete!(m),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CARTE 1 — statut de session
// -----------------------------------------------------------------------------

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onOpen,
    required this.onMovement,
    required this.onClose,
    this.onEditMovement,
    this.onDeleteMovement,
  });

  final CaisseSession? session;
  final VoidCallback onOpen;
  final VoidCallback onMovement;
  final VoidCallback? onClose;
  final ValueChanged<CaisseMovement>? onEditMovement;
  final ValueChanged<CaisseMovement>? onDeleteMovement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = session;
    final openedBy = s?.openedByName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  s != null ? Icons.lock_open_outlined : Icons.lock_outline,
                  size: 20,
                  color: s != null ? _green : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s != null ? 'Caisse ouverte' : 'Caisse fermée',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (s != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Ouverte le ${_formatDateTime(s.openedAt)}${openedBy != null && openedBy.isNotEmpty ? ' par $openedBy' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: s != null
                  ? [
                      OutlinedButton.icon(
                        onPressed: onMovement,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Mouvement'),
                      ),
                      FilledButton.icon(
                        onPressed: onClose,
                        style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('Fermer la caisse'),
                      ),
                    ]
                  : [
                      FilledButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.lock_open_outlined, size: 18),
                        label: const Text('Ouvrir la caisse'),
                      ),
                    ],
            ),
            if (s != null) ...[
              const SizedBox(height: 16),
              _KpiGrid(
                mdColumns: 4,
                lgColumns: 4,
                tiles: [
                  _Kpi('Fond d\'ouverture', _money(s.openingBalance)),
                  _Kpi('Entrées', '+${_money(s.totalEntrees)}', color: _green),
                  _Kpi('Sorties', '-${_money(s.totalSorties)}', color: _red),
                  _Kpi('Solde attendu', _money(s.soldeCourant)),
                ],
              ),
              const SizedBox(height: 16),
              Text('Mouvements de la session', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              // `[...session.movements].reverse()` : ordre chronologique
              // croissant (l'API renvoie `-created_at`).
              _MovementList(
                movements: s.movements.reversed.toList(),
                maxHeight: 256,
                emptyText: 'Aucun mouvement pour l\'instant',
                onEdit: onEditMovement,
                onDelete: onDeleteMovement,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CARTE 2 — résumé de la caisse (période)
// -----------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.periodAsync,
    required this.from,
    required this.to,
    required this.onRetry,
  });

  final AsyncValue<CaissePeriodData> periodAsync;
  final DateTime from;
  final DateTime to;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = periodAsync.value;

    Widget content;
    if (!periodAsync.hasValue && !periodAsync.hasError) {
      // `summaryLoading` du web : Skeleton h-40.
      content = const SizedBox(height: 160, child: LoadingState());
    } else if (periodAsync.hasError && data == null) {
      content = ErrorState(
        message: 'Erreur de chargement du résumé: ${ApiClient.messageFromError(periodAsync.error!)}',
        onRetry: onRetry,
      );
    } else {
      final summary = data!.summary;
      final movements = data.movements;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KpiGrid(
            mdColumns: 3,
            lgColumns: 6,
            tiles: [
              _Kpi('Entrées', '+${_money(summary.totalEntrees)}', color: _green),
              _Kpi('Sorties', '-${_money(summary.totalSorties)}', color: _red),
              _Kpi('Solde', _money(summary.solde)),
              _Kpi('CA produits vendus', _money(summary.caProduitsVendus)),
              _Kpi('Coût des produits vendus', _money(summary.coutProduitsVendus), color: _orange),
              _Kpi(
                'Bénéfice produits vendus',
                _money(summary.beneficeProduitsVendus),
                color: _green700,
                icon: Icons.savings_outlined,
              ),
            ],
          ),
          if (summary.sortiesParCategorie.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Sorties par catégorie', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final row in summary.sortiesParCategorie)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${row.categorie} : ${_money(row.total)}', style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('Mouvements de la période (${movements.length})', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          // Filtres locaux sur les mouvements déjà chargés (miroir du journal
          // de caisse web, § demande) : date, sens, type (catégorie), montant
          // min / max, recherche.
          _MovementFilters(movements: movements, from: from, to: to),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Résumé de la caisse',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Tous les mouvements et les ventes de la période, quelle que soit la session.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text('Période ${_dayFmt.format(from)} → ${_dayFmt.format(to)} (choisie en haut de la page).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }
}

/// Filtres locaux de la liste « Mouvements de la période » (journal de
/// caisse) : une seule date (jour de Madagascar), sens (entrées / sorties),
/// type = catégorie, montant min / max et recherche libre (libellé,
/// catégorie, auteur). Le récapitulatif suit la sélection.
class _MovementFilters extends StatefulWidget {
  const _MovementFilters({required this.movements, required this.from, required this.to});

  final List<CaisseMovement> movements;
  final DateTime from;
  final DateTime to;

  @override
  State<_MovementFilters> createState() => _MovementFiltersState();
}

enum _Sens { tous, entrees, sorties }

class _MovementFiltersState extends State<_MovementFilters> {
  DateTime? _date;
  _Sens _sens = _Sens.tous;
  String? _categorie; // null = toutes ; '' = sans catégorie
  bool _categorieFiltre = false;
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  final _rechercheController = TextEditingController();

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    _rechercheController.dispose();
    super.dispose();
  }

  bool get _actif =>
      _date != null ||
      _sens != _Sens.tous ||
      _categorieFiltre ||
      _minController.text.isNotEmpty ||
      _maxController.text.isNotEmpty ||
      _rechercheController.text.trim().isNotEmpty;

  void _reset() => setState(() {
        _date = null;
        _sens = _Sens.tous;
        _categorie = null;
        _categorieFiltre = false;
        _minController.clear();
        _maxController.clear();
        _rechercheController.clear();
      });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? appToday(),
      firstDate: DateTime(widget.from.year, widget.from.month, widget.from.day),
      lastDate: DateTime(widget.to.year, widget.to.month, widget.to.day),
    );
    if (d != null) setState(() => _date = d);
  }

  List<CaisseMovement> get _filtres {
    final q = _rechercheController.text.trim().toLowerCase();
    final min = double.tryParse(_minController.text.replaceAll(' ', ''));
    final max = double.tryParse(_maxController.text.replaceAll(' ', ''));
    return widget.movements.where((m) {
      if (_date != null) {
        final c = m.createdAt;
        if (c == null) return false;
        final jour = appDay(c);
        if (!(jour.year == _date!.year && jour.month == _date!.month && jour.day == _date!.day)) return false;
      }
      if (_sens == _Sens.entrees && !m.isIn) return false;
      if (_sens == _Sens.sorties && m.isIn) return false;
      if (_categorieFiltre && (m.categoryName ?? '') != (_categorie ?? '')) return false;
      if (min != null && m.amount < min) return false;
      if (max != null && m.amount > max) return false;
      if (q.isNotEmpty) {
        final texte = [m.reason, m.categoryName ?? '', m.createdByName ?? '', m.amount.toStringAsFixed(0)].join(' ').toLowerCase();
        if (!texte.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = <String>{for (final m in widget.movements) m.categoryName ?? ''}.toList()..sort();
    final lignes = _filtres;
    final entrees = lignes.where((m) => m.isIn).fold<double>(0, (a, m) => a + m.amount);
    final sorties = lignes.where((m) => !m.isIn).fold<double>(0, (a, m) => a + m.amount);

    Widget champ(Widget child, {double width = 150}) => SizedBox(width: width, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            champ(
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(_date == null ? 'Date' : _dayFmt.format(_date!), overflow: TextOverflow.ellipsis),
              ),
            ),
            champ(
              DropdownButtonFormField<_Sens>(
                // Clé = valeur : « Réinitialiser » remet bien le champ à zéro.
                key: ValueKey('sens-$_sens'),
                initialValue: _sens,
                decoration: const InputDecoration(labelText: 'Sens', isDense: true),
                items: const [
                  DropdownMenuItem(value: _Sens.tous, child: Text('Entrées + sorties')),
                  DropdownMenuItem(value: _Sens.entrees, child: Text('Entrées')),
                  DropdownMenuItem(value: _Sens.sorties, child: Text('Sorties')),
                ],
                onChanged: (v) => setState(() => _sens = v ?? _Sens.tous),
              ),
            ),
            champ(
              DropdownButtonFormField<String>(
                key: ValueKey('type-${_categorieFiltre ? (_categorie ?? '') : '__TOUTES__'}'),
                initialValue: _categorieFiltre ? (_categorie ?? '') : '__TOUTES__',
                decoration: const InputDecoration(labelText: 'Type', isDense: true),
                items: [
                  const DropdownMenuItem(value: '__TOUTES__', child: Text('Tous les types')),
                  for (final c in categories) DropdownMenuItem(value: c, child: Text(c.isEmpty ? 'Sans catégorie' : c)),
                ],
                onChanged: (v) => setState(() {
                  _categorieFiltre = v != null && v != '__TOUTES__';
                  _categorie = _categorieFiltre ? v : null;
                }),
              ),
              width: 190,
            ),
            champ(
              TextField(
                controller: _minController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant min (Ar)', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              width: 140,
            ),
            champ(
              TextField(
                controller: _maxController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant max (Ar)', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              width: 140,
            ),
            champ(
              TextField(
                controller: _rechercheController,
                decoration: InputDecoration(
                  labelText: 'Recherche',
                  hintText: 'Nom, libellé, catégorie, auteur…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _rechercheController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _rechercheController.clear()),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              width: 260,
            ),
            if (_actif)
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Réinitialiser'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${lignes.length} mouvement(s)${_actif ? ' sur ${widget.movements.length}' : ''} · entrées +${_money(entrees)} · sorties -${_money(sorties)}',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        // Ordre API (`-created_at`, plus récent en premier).
        _MovementList(
          movements: lignes,
          maxHeight: 288,
          emptyText: _actif ? 'Aucun mouvement ne correspond à ces filtres' : 'Aucun mouvement pour cette période',
          showCategory: true,
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(label),
    );
  }
}

// -----------------------------------------------------------------------------
// CARTE 3 — historique des sessions fermées
// -----------------------------------------------------------------------------

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.historyAsync, required this.onRetry});

  final AsyncValue<List<CaisseSession>> historyAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sessions = historyAsync.value ?? const <CaisseSession>[];

    Widget content;
    if (!historyAsync.hasValue && !historyAsync.hasError) {
      content = const SizedBox(height: 80, child: LoadingState());
    } else if (historyAsync.hasError && !historyAsync.hasValue) {
      content = ErrorState(
        message: 'Erreur de chargement de la caisse: ${ApiClient.messageFromError(historyAsync.error!)}',
        onRetry: onRetry,
      );
    } else if (sessions.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune session fermée', style: TextStyle(color: scheme.onSurfaceVariant))),
      );
    } else {
      content = Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: sessions.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant),
          itemBuilder: (context, i) => _HistoryTile(session: sessions[i]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historique des sessions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${sessions.length} session(s) fermée(s)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }
}

/// Une ligne du tableau « Historique » (6 colonnes du web : Ouverte le,
/// Fermée le, Fond, Compté, Écart, Ouvert / Fermé par).
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.session});
  final CaisseSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = session;
    final diff = s.difference ?? 0;
    final ecartColor = diff == 0 ? _green700 : _orange700;
    final openedBy = (s.openedByName == null || s.openedByName!.isEmpty) ? '-' : s.openedByName!;
    final closedBy = (s.closedByName == null || s.closedByName!.isEmpty) ? '-' : s.closedByName!;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ouverte le ${_formatDateTime(s.openedAt)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: ecartColor.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Écart ${diff > 0 ? '+' : ''}${_money(diff)}',
                  style: TextStyle(color: ecartColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('Fermée le ${_formatDateTime(s.closedAt)}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            children: [
              Text('Fond : ${_money(s.openingBalance)}', style: const TextStyle(fontSize: 13)),
              Text('Compté : ${_money(s.closingBalance)}', style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Ouvert / Fermé par : $openedBy / $closedBy', style: muted),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Champ date + heure (DateTimeInput du web : date et heure séparées)
// -----------------------------------------------------------------------------

/// Heure « au mur » d'Antananarivo saisie par l'utilisateur ; les bornes
/// [firstDate]/[lastDate] ne portent que sur la partie DATE (comme le
/// composant web), le serveur restant l'autorité sur l'instant exact.
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.helperText,
    this.enabled = true,
  });

  final String label;
  final DateTime value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onChanged;
  final String? helperText;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final first = firstDate.isAfter(lastDate) ? lastDate : firstDate;
    var initial = value;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: lastDate,
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value));
    if (time == null) return;
    onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          helperMaxLines: 2,
          suffixIcon: const Icon(Icons.event_outlined),
        ),
        child: Text(_wallClockFmt.format(value)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dialog « Ouvrir la caisse »
// -----------------------------------------------------------------------------

class _OpenDialog extends ConsumerStatefulWidget {
  const _OpenDialog({required this.magasinId});
  final int magasinId;

  @override
  ConsumerState<_OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends ConsumerState<_OpenDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  /// Heure au mur d'Antananarivo (initialisée à maintenant).
  late DateTime _openedAt = _wallNow();
  bool _amountTouched = false;
  bool _prefilled = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pré-remplissage avec la valeur de stock actuelle du magasin — arrive
    // APRÈS l'ouverture du dialog (asynchrone), sans jamais écraser une
    // saisie déjà commencée.
    _applyStockValue(ref.read(caisseStockValueProvider(widget.magasinId)), initial: true);
    ref.listenManual(caisseStockValueProvider(widget.magasinId), (previous, next) => _applyStockValue(next));
  }

  void _applyStockValue(AsyncValue<double?> async, {bool initial = false}) {
    if (_prefilled || _amountTouched || async.isLoading || !async.hasValue) return;
    _prefilled = true;
    final value = async.value;
    if (value == null) return;
    _amountController.text = _amountText(value);
    if (!initial && mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _amountController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Montant d\'ouverture requis');
      return;
    }
    final amount = _parseAmount(raw);
    if (amount == null || amount < 0) {
      setState(() => _error = 'Montant invalide');
      return;
    }
    final openedAtUtc = appWallClockToUtc(_openedAt);
    if (openedAtUtc.isAfter(DateTime.now().toUtc())) {
      setState(() => _error = 'Heure d\'ouverture ne peut pas être dans le futur.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(currentCaisseProvider(widget.magasinId).notifier).open(
            openingBalance: amount,
            openingNote: _noteController.text.trim(),
            openedAt: openedAtUtc,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = ApiClient.messageFromError(e);
      if (mounted) setState(() => _error = message.isEmpty ? 'Erreur lors de l’ouverture' : message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockAsync = ref.watch(caisseStockValueProvider(widget.magasinId));
    final today = appToday();

    return AlertDialog(
      scrollable: true,
      title: const Text('Ouvrir la caisse'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Renseignez le fond de caisse de départ.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _amountTouched = true,
              decoration: InputDecoration(
                labelText: 'Montant d\'ouverture (Ar) *',
                helperText: 'Pré-rempli avec la valeur de stock actuelle du magasin — modifiable.',
                helperMaxLines: 2,
                suffixIcon: stockAsync.isLoading && !_amountTouched
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            _DateTimeField(
              label: 'Heure d\'ouverture',
              value: _openedAt,
              firstDate: today.subtract(const Duration(days: 365)),
              lastDate: today,
              onChanged: (v) => setState(() => _openedAt = v),
              helperText: 'Modifiable si la caisse a été ouverte plus tôt dans la journée.',
              enabled: !_submitting,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optionnel)', hintText: 'Ex: Fond de caisse du matin'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_open_outlined, size: 18),
          label: const Text('Ouvrir'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dialog « Fermer la caisse »
// -----------------------------------------------------------------------------

class _CloseDialog extends ConsumerStatefulWidget {
  const _CloseDialog({required this.magasinId, required this.session});
  final int magasinId;
  final CaisseSession session;

  @override
  ConsumerState<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends ConsumerState<_CloseDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _closedAt = _wallNow();
  bool _amountTouched = false;
  bool _prefilled = false;
  bool _submitting = false;
  String? _error;

  double get _expected => widget.session.soldeCourant;

  @override
  void initState() {
    super.initState();
    // Même pré-remplissage (valeur de stock) que l'ouverture — recalculé à
    // chaque ouverture du dialog, le stock bougeant pendant la session.
    _applyStockValue(ref.read(caisseStockValueProvider(widget.magasinId)), initial: true);
    ref.listenManual(caisseStockValueProvider(widget.magasinId), (previous, next) => _applyStockValue(next));
  }

  void _applyStockValue(AsyncValue<double?> async, {bool initial = false}) {
    if (_prefilled || _amountTouched || async.isLoading || !async.hasValue) return;
    _prefilled = true;
    final value = async.value;
    if (value == null) return;
    _amountController.text = _amountText(value);
    // Rafraîchit l'indicateur d'écart calculé à partir du champ.
    if (!initial && mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _amountController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Montant compté requis');
      return;
    }
    final amount = _parseAmount(raw);
    if (amount == null || amount < 0) {
      setState(() => _error = 'Montant invalide');
      return;
    }
    final closedAtUtc = appWallClockToUtc(_closedAt);
    if (closedAtUtc.isAfter(DateTime.now().toUtc())) {
      setState(() => _error = 'Heure de fermeture ne peut pas être dans le futur.');
      return;
    }
    final openedAt = widget.session.openedAt;
    if (openedAt != null && closedAtUtc.isBefore(openedAt.toUtc())) {
      setState(() => _error = 'L\'heure de fermeture ne peut pas être avant l\'heure d\'ouverture.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(currentCaisseProvider(widget.magasinId).notifier).close(
            closingBalance: amount,
            closingNote: _noteController.text.trim(),
            closedAt: closedAtUtc,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = ApiClient.messageFromError(e);
      if (mounted) setState(() => _error = message.isEmpty ? 'Erreur lors de la fermeture' : message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockAsync = ref.watch(caisseStockValueProvider(widget.magasinId));
    final today = appToday();
    final openedAt = widget.session.openedAt;
    final firstDate = openedAt != null ? appDay(openedAt) : today.subtract(const Duration(days: 365));

    // Indicateur d'écart en direct dès qu'un montant est saisi.
    final entered = _parseAmount(_amountController.text);
    final ecart = entered != null ? entered - _expected : null;

    return AlertDialog(
      scrollable: true,
      title: const Text('Fermer la caisse'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Solde attendu : '),
                  TextSpan(text: _money(_expected), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(text: ' — comptez la caisse et indiquez le montant réel.'),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _amountTouched = true),
              decoration: InputDecoration(
                labelText: 'Montant compté (Ar) *',
                helperText: 'Pré-rempli avec la valeur de stock actuelle du magasin — modifiable.',
                helperMaxLines: 2,
                suffixIcon: stockAsync.isLoading && !_amountTouched
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            if (ecart != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Écart : ${ecart > 0 ? '+' : ''}${_money(ecart)}',
                  style: TextStyle(fontSize: 12, color: ecart == 0 ? _green : _orange),
                ),
              ),
            const SizedBox(height: 12),
            _DateTimeField(
              label: 'Heure de fermeture',
              value: _closedAt,
              firstDate: firstDate,
              lastDate: today,
              onChanged: (v) => setState(() => _closedAt = v),
              helperText: 'Modifiable si la caisse a été fermée plus tôt.',
              enabled: !_submitting,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optionnel)', hintText: 'Ex: Compte OK'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_outline, size: 18),
          label: const Text('Fermer la caisse'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dialog « Ajouter un mouvement »
// -----------------------------------------------------------------------------

class _MovementDialog extends ConsumerStatefulWidget {
  const _MovementDialog({required this.magasinId, this.existing});
  final int magasinId;

  /// Mouvement à corriger (null = ajout).
  final CaisseMovement? existing;

  @override
  ConsumerState<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends ConsumerState<_MovementDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  /// Reset à l'ouverture : type 'in', montant '', motif '', catégorie ''.
  String _movementType = 'in';
  int? _categoryId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _movementType = e.isIn ? 'in' : 'out';
      _amountController.text = e.amount == e.amount.roundToDouble() ? e.amount.toInt().toString() : e.amount.toString();
      _reasonController.text = e.reason;
      _categoryId = e.categoryId;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _amountController.text.trim();
    final reason = _reasonController.text.trim();
    if (raw.isEmpty || reason.isEmpty) {
      setState(() => _error = 'Montant et motif requis');
      return;
    }
    final amount = _parseAmount(raw);
    if (amount == null || amount < 0) {
      setState(() => _error = 'Montant invalide');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final notifier = ref.read(currentCaisseProvider(widget.magasinId).notifier);
      final existing = widget.existing;
      if (existing != null) {
        await notifier.updateMovement(
          existing.id,
          movementType: _movementType,
          amount: amount,
          reason: reason,
          categoryId: _movementType == 'out' ? _categoryId : null,
        );
      } else {
        await notifier.addMovement(
          movementType: _movementType,
          amount: amount,
          reason: reason,
          categoryId: _movementType == 'out' ? _categoryId : null,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = ApiClient.messageFromError(e);
      if (mounted) {
        setState(() => _error = message.isEmpty
            ? (widget.existing != null ? 'Erreur lors de la modification du mouvement' : 'Erreur lors de l’ajout du mouvement')
            : message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Catégories de dépense : erreur de chargement ignorée silencieusement
    // (`.catch(() => {})` du web) — le select reste vide.
    final categoriesAsync = ref.watch(caisseCategoriesProvider);
    final categories = categoriesAsync.value ?? const <CaisseCategory>[];
    final isOut = _movementType == 'out';

    final edition = widget.existing != null;
    return AlertDialog(
      scrollable: true,
      title: Text(edition ? 'Modifier le mouvement' : 'Ajouter un mouvement'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              edition
                  ? 'Correction du mouvement du ${_formatDateTime(widget.existing!.createdAt)} — le solde attendu est recalculé.'
                  : 'Apport ou retrait d\'espèces dans la caisse.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 8),
            ],
            Text('Type *', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'in',
                  icon: Icon(Icons.arrow_circle_up_outlined, color: _green),
                  label: Text('Entrée'),
                ),
                ButtonSegment(
                  value: 'out',
                  icon: Icon(Icons.arrow_circle_down_outlined, color: _red),
                  label: Text('Sortie'),
                ),
              ],
              selected: {_movementType},
              onSelectionChanged: _submitting
                  ? null
                  : (values) => setState(() {
                        _movementType = values.first;
                        // Une catégorie ne s'applique qu'aux sorties.
                        if (_movementType == 'in') _categoryId = null;
                      }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant (Ar) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'Motif *', hintText: 'Ex: Achat fournitures'),
            ),
            if (isOut) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                decoration: InputDecoration(
                  labelText: 'Catégorie (optionnel)',
                  helperText: categoriesAsync.isLoading && categories.isEmpty
                      ? 'Chargement des catégories…'
                      : 'Gérez les catégories dans Paramètres > Dépenses.',
                  helperMaxLines: 2,
                ),
                hint: const Text('Aucune catégorie'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Aucune catégorie')),
                  for (final c in categories) DropdownMenuItem<int?>(value: c.id, child: Text(c.nom)),
                ],
                onChanged: _submitting ? null : (v) => setState(() => _categoryId = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(edition ? Icons.edit_outlined : Icons.add, size: 18),
          label: Text(edition ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
