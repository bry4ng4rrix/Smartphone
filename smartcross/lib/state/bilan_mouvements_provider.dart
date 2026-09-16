import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_time.dart';
import '../core/constants.dart';
import '../core/permissions.dart';
import '../data/repositories/orders_repository.dart';
import '../models/order.dart';
import 'auth_provider.dart';
import 'chat_unread_provider.dart' show kChatUnreadRefreshInterval;
import 'realtime_provider.dart';

/// Badge « Bilan du jour » du menu du gérant (§ demande, sur le modèle du
/// badge « Chats » — miroir de frontend/lib/hooks/useBilanMouvements.ts) :
/// nombre de MOUVEMENTS faits sur le bilan par les livreurs depuis la
/// dernière ouverture de l'écran — chaque passage « Livré » ou « Retour »
/// d'une commande du jour compte pour un.
///
/// Pas de compteur serveur : on relit les commandes du jour (même requête
/// que l'écran Bilan, `date_debut = date_fin = aujourd'hui`) et l'on compte
/// les entrées d'historique LIVRE / RETOUR postérieures au dernier « vu »,
/// mémorisé sur l'appareil (SharedPreferences, par compte). Ouvrir /bilan
/// remet le compteur à 0 ([marquerVu]).
///
/// Relu toutes les 30 s, à chaque changement d'écran (shell) et à chaque
/// événement temps réel.
const Set<OrderStatus> kStatutsMouvementBilan = {OrderStatus.livre, OrderStatus.retour};

String _cleVu(int userId) => 'bilan_vu_at_$userId';

/// Mouvements LIVRE / RETOUR strictement postérieurs à [depuis].
int compterMouvementsBilan(Iterable<Order> orders, DateTime depuis) {
  var n = 0;
  for (final o in orders) {
    for (final h in o.statusHistory) {
      if (!kStatutsMouvementBilan.contains(h.nouveauStatut)) continue;
      final t = h.timestamp;
      if (t != null && t.isAfter(depuis)) n++;
    }
  }
  return n;
}

class BilanMouvementsNotifier extends AsyncNotifier<int> {
  final _repo = OrdersRepository();
  Timer? _timer;

  /// Vrai tant que l'écran Bilan est affiché : tout ce qui arrive est vu.
  bool _surLaPage = false;

  @override
  Future<int> build() async {
    _timer?.cancel();
    ref.onDispose(() => _timer?.cancel());

    final user = ref.watch(
      authProvider.select((a) => a.status == AuthStatus.authenticated ? a.user : null),
    );
    if (user == null || !user.isGerant) return 0;

    ref.listen(realtimeTickProvider, (previous, next) => refresh());
    _timer = Timer.periodic(kChatUnreadRefreshInterval, (_) => refresh());
    return _compter(user.id);
  }

  Future<DateTime> _lireVu(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_cleVu(userId));
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    } catch (_) {
      // Préférence illisible : comme « jamais vu ».
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<void> _ecrireVu(int userId, DateTime instant) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cleVu(userId), instant.toUtc().millisecondsSinceEpoch);
    } catch (_) {
      // Non bloquant.
    }
  }

  Future<int> _compter(int userId) async {
    final jour = appToday();
    final orders = await _repo.list(dateDebut: jour, dateFin: jour);
    if (_surLaPage) {
      await _ecrireVu(userId, DateTime.now().toUtc());
      return 0;
    }
    return compterMouvementsBilan(orders, await _lireVu(userId));
  }

  /// Relit le compteur immédiatement. Silencieux : en cas d'échec, la
  /// dernière valeur connue reste affichée.
  Future<void> refresh() async {
    final auth = ref.read(authProvider);
    final user = auth.user;
    if (auth.status != AuthStatus.authenticated || user == null || !user.isGerant) return;
    final result = await AsyncValue.guard(() => _compter(user.id));
    if (result.hasValue) state = result;
  }

  /// L'écran Bilan est affiché ([affiche] = true) ou vient d'être quitté :
  /// à l'ouverture le badge retombe à 0 sur-le-champ et le « vu » est
  /// mémorisé.
  Future<void> setSurLaPage(bool affiche) async {
    _surLaPage = affiche;
    if (!affiche) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;
    state = const AsyncData(0);
    await _ecrireVu(user.id, DateTime.now().toUtc());
  }
}

final bilanMouvementsProvider = AsyncNotifierProvider<BilanMouvementsNotifier, int>(BilanMouvementsNotifier.new);

/// Valeur prête pour le badge : 0 tant que rien n'est chargé ou en erreur.
final bilanMouvementsCountProvider = Provider<int>((ref) => ref.watch(bilanMouvementsProvider).value ?? 0);
