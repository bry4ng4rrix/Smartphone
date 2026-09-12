import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/expenses_repository.dart';
import '../models/expense.dart';
import 'realtime_provider.dart';

final expensesRepositoryProvider = Provider((ref) => ExpensesRepository());

// ---------------------------------------------------------------------------
// Types de dépense — Paramètres > « Dépenses des livreurs » (gérant) et
// formulaire de déclaration du livreur.
// ---------------------------------------------------------------------------

/// Catalogue des types de dépense de la société (`djangoClient.expenseTypes`).
/// Lecture pour tous ; création/modification/suppression réservées au
/// gérant (403 sinon). Chaque action recharge la liste silencieusement.
class ExpenseTypesNotifier extends AsyncNotifier<List<ExpenseType>> {
  late final _repo = ref.read(expensesRepositoryProvider);

  @override
  Future<List<ExpenseType>> build() => _repo.listTypes();

  /// Rechargement NON silencieux (réaffiche l'état de chargement).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.listTypes);
  }

  Future<void> _refreshSilencieux() async {
    state = await AsyncValue.guard(_repo.listTypes);
  }

  Future<ExpenseType> create({required String nom, required double prixUnitaire, bool parUnite = false}) async {
    final type = await _repo.createType(nom: nom, prixUnitaire: prixUnitaire, parUnite: parUnite);
    await _refreshSilencieux();
    return type;
  }

  Future<ExpenseType> updateType(int id, {String? nom, double? prixUnitaire, bool? parUnite, bool? actif}) async {
    final type = await _repo.updateType(id, nom: nom, prixUnitaire: prixUnitaire, parUnite: parUnite, actif: actif);
    await _refreshSilencieux();
    return type;
  }

  /// Interrupteur « Type actif » de la liste (web : `basculerActif`).
  Future<ExpenseType> toggleActif(ExpenseType type) => updateType(type.id, actif: !type.actif);

  /// Renvoie le type DÉSACTIVÉ s'il était déjà utilisé par une dépense (le
  /// serveur ne le supprime pas), `null` s'il a réellement été supprimé.
  Future<ExpenseType?> delete(int id) async {
    final desactive = await _repo.deleteType(id);
    await _refreshSilencieux();
    return desactive;
  }
}

final expenseTypesProvider = AsyncNotifierProvider<ExpenseTypesNotifier, List<ExpenseType>>(ExpenseTypesNotifier.new);

/// Types proposés à la saisie du livreur : uniquement les actifs
/// (`l.filter((t) => t.actif)` de la page /bilan du web).
final activeExpenseTypesProvider = Provider<AsyncValue<List<ExpenseType>>>((ref) {
  return ref.watch(expenseTypesProvider).whenData((types) => types.where((t) => t.actif).toList());
});

// ---------------------------------------------------------------------------
// Dépenses déclarées
// ---------------------------------------------------------------------------

/// Filtres de `GET /orders/expenses/` (`djangoClient.expenses.list`). Sert
/// de clé de famille : deux filtres égaux partagent le même cache.
/// [dateDebut]/[dateFin] sont des jours calendaires (le champ `date` de la
/// dépense) ; [statut] une valeur ou plusieurs séparées par une virgule ;
/// [livreurId] réservé au gérant (le livreur ne reçoit que les siennes).
class ExpensesFilter {
  const ExpensesFilter({this.statut, this.dateDebut, this.dateFin, this.livreurId});

  /// Dépenses d'une seule journée — le cas du bilan du jour (livreur et
  /// gérant : `date_debut = date_fin = jour`).
  factory ExpensesFilter.jour(DateTime jour, {int? livreurId, String? statut}) =>
      ExpensesFilter(dateDebut: jour, dateFin: jour, livreurId: livreurId, statut: statut);

  final String? statut;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final int? livreurId;

  ExpensesFilter copyWith({
    String? statut,
    bool clearStatut = false,
    DateTime? dateDebut,
    DateTime? dateFin,
    int? livreurId,
    bool clearLivreurId = false,
  }) {
    return ExpensesFilter(
      statut: clearStatut ? null : (statut ?? this.statut),
      dateDebut: dateDebut ?? this.dateDebut,
      dateFin: dateFin ?? this.dateFin,
      livreurId: clearLivreurId ? null : (livreurId ?? this.livreurId),
    );
  }

  String? get _debutKey => dateDebut == null ? null : formatExpenseDate(dateDebut!);
  String? get _finKey => dateFin == null ? null : formatExpenseDate(dateFin!);

  @override
  bool operator ==(Object other) =>
      other is ExpensesFilter &&
      other.statut == statut &&
      other._debutKey == _debutKey &&
      other._finKey == _finKey &&
      other.livreurId == livreurId;

  @override
  int get hashCode => Object.hash(statut, _debutKey, _finKey, livreurId);
}

/// Dépenses correspondant à un filtre — une journée le plus souvent
/// (`expensesProvider(ExpensesFilter.jour(jour))`). Le serveur limite déjà
/// le livreur à ses propres dépenses ; le gérant reçoit celles de tous ses
/// magasins et affine par livreur côté client ou via [ExpensesFilter.livreurId].
///
/// Se recharge à chaque événement temps réel (une déclaration ou une
/// décision du gérant crée une notification, donc un événement). Après une
/// action, TOUTES les vues de dépenses ouvertes (vue d'ensemble et détail
/// d'un livreur, par exemple) sont invalidées, pas seulement celle-ci.
class ExpensesNotifier extends AsyncNotifier<List<LivreurExpense>> {
  ExpensesNotifier(this.filter);

  final ExpensesFilter filter;
  late final _repo = ref.read(expensesRepositoryProvider);

  Future<List<LivreurExpense>> _fetch() => _repo.list(
        statut: filter.statut,
        dateDebut: filter.dateDebut,
        dateFin: filter.dateFin,
        livreurId: filter.livreurId,
      );

  @override
  Future<List<LivreurExpense>> build() {
    ref.watch(realtimeTickProvider);
    return _fetch();
  }

  /// Rechargement NON silencieux de cette vue.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Après une action : toutes les vues de dépenses repartent du serveur,
  /// celle-ci comprise, et l'appelant attend son nouvel état.
  Future<void> _invaliderTout() async {
    ref.invalidate(expensesProvider);
    await future;
  }

  /// Déclaration par le livreur (« Nouvelle dépense » du bilan). Toast web :
  /// « Dépense envoyée au gérant pour validation ».
  Future<LivreurExpense> declarer({
    int? typeDepenseId,
    required String libelle,
    required double prixUnitaire,
    int quantite = 1,
    String motif = '',
    DateTime? date,
  }) async {
    final expense = await _repo.create(
      typeDepenseId: typeDepenseId,
      libelle: libelle,
      prixUnitaire: prixUnitaire,
      quantite: quantite,
      motif: motif,
      date: date,
    );
    await _invaliderTout();
    return expense;
  }

  /// « Retirer » — tant que la dépense est en attente.
  Future<void> retirer(int id) async {
    await _repo.delete(id);
    await _invaliderTout();
  }

  /// Gérant : « Accepter » / « Rejeter ». [statut] = 'ACCEPTE' | 'REJETE'.
  Future<LivreurExpense> resoudre(int id, String statut, {String motifRejet = ''}) async {
    final expense = await _repo.resoudre(id, statut, motifRejet: motifRejet);
    await _invaliderTout();
    return expense;
  }

  Future<LivreurExpense> accepter(int id) => resoudre(id, ExpenseStatus.accepte.apiValue);

  Future<LivreurExpense> rejeter(int id, {String motifRejet = ''}) =>
      resoudre(id, ExpenseStatus.rejete.apiValue, motifRejet: motifRejet);
}

final expensesProvider =
    AsyncNotifierProvider.autoDispose.family<ExpensesNotifier, List<LivreurExpense>, ExpensesFilter>(
  ExpensesNotifier.new,
);

/// Somme des dépenses ACCEPTÉES d'une liste — seules celles-ci sont
/// déduites du bilan (« DÉPENSES VALIDÉES » / « NET À REMETTRE »).
double totalDepensesAcceptees(Iterable<LivreurExpense> depenses) =>
    depenses.where((d) => d.estAcceptee).fold<double>(0, (s, d) => s + d.montant);

/// Nombre de dépenses encore à trancher (« n à valider » de la vue
/// d'ensemble du gérant).
int nbDepensesEnAttente(Iterable<LivreurExpense> depenses) => depenses.where((d) => d.estEnAttente).length;
