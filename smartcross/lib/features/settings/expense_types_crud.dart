import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../data/repositories/caisse_repository.dart';
import '../../models/caisse.dart';
import '../../models/expense.dart';
import '../../state/auth_provider.dart';
import '../../state/caisse_provider.dart';
import '../../state/expenses_provider.dart';
import '../../widgets/async_state_widgets.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;

/// Onglet « Dépenses » de la page /settings (app/(app)/settings/page.tsx) :
///
/// * [ExpenseCategoriesCrudCard] — carte « Catégories de dépenses »
///   (`ExpenseCategoriesCrudList` du web) : classification comptable des
///   sorties de caisse (Salaire, Pub, Commande stock…).
/// * [LivreurExpenseTypesCrudCard] — carte « Dépenses des livreurs »
///   (`LivreurExpenseTypesCrudList` du web) : types proposés au livreur
///   quand il déclare une dépense depuis son bilan du jour (nom, montant
///   par défaut, « à l'unité », actif).
///
/// Les deux listes sont des listes de lignes (pas de tableau), à édition
/// EN PLACE (la ligne se transforme en champs + OK / Annuler) et à
/// suppression IMMÉDIATE (aucune boîte de confirmation), comme sur le web.
/// Aucune recherche, aucun tri, aucun filtre, aucune pagination.

// =============================================================================
// Catégories de dépenses (caisse) — écriture + provider
// =============================================================================

/// `djangoClient.caisse.categories.create / update / delete`
/// (`/users/caisse/categories/`, écriture réservée au gérant — voir
/// users/views.py::CaisseCategoryViewSet). La lecture (`categories()`) vit
/// déjà dans [CaisseRepository] ; le portage ne pouvant créer que les
/// fichiers listés, l'écriture est ajoutée ici par extension, sur le même
/// client HTTP.
extension CaisseCategoriesCrud on CaisseRepository {
  Future<CaisseCategory> createCaisseCategory(String nom) async {
    final response = await ApiClient.instance.dio.post('users/caisse/categories/', data: {'nom': nom});
    return CaisseCategory.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CaisseCategory> renameCaisseCategory(int id, String nom) async {
    final response = await ApiClient.instance.dio.patch('users/caisse/categories/$id/', data: {'nom': nom});
    return CaisseCategory.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCaisseCategory(int id) async {
    await ApiClient.instance.dio.delete('users/caisse/categories/$id/');
  }
}

/// Liste des catégories de dépense de caisse, avec le CRUD de Paramètres.
/// Chaque action recharge la liste silencieusement (`onChanged()` du web).
class ExpenseCategoriesCrudNotifier extends AsyncNotifier<List<CaisseCategory>> {
  late final _repo = ref.read(caisseRepositoryProvider);

  @override
  Future<List<CaisseCategory>> build() {
    // Les catégories appartiennent à la société : un changement de compte
    // sur le même appareil repart du serveur plutôt que du cache.
    ref.watch(authProvider.select((a) => a.user?.id));
    return _repo.categories();
  }

  /// Rechargement NON silencieux (tirer-pour-rafraîchir, « Réessayer »).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.categories);
  }

  Future<void> _refreshSilencieux() async {
    state = await AsyncValue.guard(_repo.categories);
  }

  Future<CaisseCategory> create(String nom) async {
    final category = await _repo.createCaisseCategory(nom);
    await _refreshSilencieux();
    return category;
  }

  Future<CaisseCategory> rename(int id, String nom) async {
    final category = await _repo.renameCaisseCategory(id, nom);
    await _refreshSilencieux();
    return category;
  }

  Future<void> delete(int id) async {
    await _repo.deleteCaisseCategory(id);
    await _refreshSilencieux();
  }
}

final expenseCategoriesCrudProvider = AsyncNotifierProvider<ExpenseCategoriesCrudNotifier, List<CaisseCategory>>(
  ExpenseCategoriesCrudNotifier.new,
);

// =============================================================================
// Helpers partagés par les deux cartes — et par la carte « Zones de
// livraison » de settings_screen.dart, qui a exactement la même anatomie.
// =============================================================================

/// Toast `sonner` du web : SnackBar éphémère, sans état persistant.
void crudToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// `err.message || 'Erreur…'` du web : le message serveur s'il existe,
/// sinon le libellé générique de l'action.
String crudErrorMessage(Object error, String fallback) {
  final message = ApiClient.messageFromError(error);
  return message.trim().isEmpty ? fallback : message;
}

/// `Number(prix) || 0` du web : vide ou non numérique -> 0. La virgule
/// décimale des claviers FR est acceptée.
double parseMontantOuZero(String raw) {
  final value = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (value == null || value.isNaN || value.isInfinite) return 0;
  return value;
}

/// `String(t.prix_unitaire)` du web pour pré-remplir un champ de saisie :
/// « 5000 » plutôt que « 5000.0 » pour un montant entier.
String montantEnSaisie(double value) => value == value.roundToDouble() ? value.round().toString() : value.toString();

/// Filtre de saisie d'un montant (`<input type="number" min={0}>`) : chiffres
/// et séparateur décimal uniquement — pas de signe.
final List<TextInputFormatter> montantInputFormatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

/// Hauteur maximale d'une liste (`max-h-72` / `max-h-96` du web) : au-delà,
/// la liste défile dans la carte.
const double kCrudCategoriesMaxHeight = 288; // max-h-72
const double kCrudTypesMaxHeight = 384; // max-h-96

/// Liste défilante bornée en hauteur — les états loading / erreur / vide
/// remplacent la liste (le web laisse simplement la liste vide).
class CrudBoundedList extends StatelessWidget {
  const CrudBoundedList({
    super.key,
    required this.maxHeight,
    required this.async,
    required this.itemCount,
    required this.itemBuilder,
    required this.emptyMessage,
    required this.onRetry,
  });

  final double maxHeight;
  final AsyncValue<List<Object>> async;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final String emptyMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (async.hasError && !async.hasValue) {
      return ErrorState(message: ApiClient.messageFromError(async.error!), onRetry: onRetry);
    }
    if (async.isLoading && !async.hasValue) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator());
    }
    if (itemCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Ligne encadrée (`border rounded-md px-3 py-2` du web).
class CrudRowFrame extends StatelessWidget {
  const CrudRowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Boutons icône compacts (`size="icon" variant="ghost"` du web) : crayon
/// neutre, corbeille rouge.
class CrudRowActions extends StatelessWidget {
  const CrudRowActions({super.key, required this.onEdit, required this.onDelete, this.leading});

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?leading,
        IconButton(
          tooltip: 'Modifier',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: onEdit,
        ),
        IconButton(
          tooltip: 'Supprimer',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          onPressed: onDelete,
        ),
      ],
    );
  }
}

/// Boutons « OK » / « Annuler » d'une ligne en édition.
class CrudEditActions extends StatelessWidget {
  const CrudEditActions({super.key, required this.onOk, required this.onCancel});

  final VoidCallback onOk;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(onPressed: onCancel, child: const Text('Annuler')),
        const SizedBox(width: 4),
        FilledButton(onPressed: onOk, child: const Text('OK')),
      ],
    );
  }
}

/// Badge `variant="secondary"` (prix formaté).
class CrudPriceBadge extends StatelessWidget {
  const CrudPriceBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
      ),
    );
  }
}

// =============================================================================
// Carte « Catégories de dépenses »
// =============================================================================

/// Carte « Catégories de dépenses » — `ExpenseCategoriesCrudList` du web :
/// compteur « Toutes les catégories (N) », lignes nom + crayon + corbeille,
/// édition en place (OK / Annuler), barre d'ajout en bas.
class ExpenseCategoriesCrudCard extends ConsumerStatefulWidget {
  const ExpenseCategoriesCrudCard({super.key});

  @override
  ConsumerState<ExpenseCategoriesCrudCard> createState() => _ExpenseCategoriesCrudCardState();
}

class _ExpenseCategoriesCrudCardState extends ConsumerState<ExpenseCategoriesCrudCard> {
  int? _editingId;
  final _editingController = TextEditingController();
  final _newController = TextEditingController();

  @override
  void dispose() {
    _editingController.dispose();
    _newController.dispose();
    super.dispose();
  }

  void _startEdit(CaisseCategory c) {
    setState(() {
      _editingId = c.id;
      _editingController.text = c.nom;
    });
  }

  /// `saveEdit` : nom trimmé non vide, sinon abandon silencieux.
  Future<void> _saveEdit() async {
    final id = _editingId;
    final name = _editingController.text.trim();
    if (id == null || name.isEmpty) return;
    try {
      await ref.read(expenseCategoriesCrudProvider.notifier).rename(id, name);
      if (!mounted) return;
      crudToast(context, 'Catégorie renommée');
      setState(() => _editingId = null);
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  /// `removeCategory` : suppression IMMÉDIATE, sans confirmation (web).
  Future<void> _remove(CaisseCategory c) async {
    try {
      await ref.read(expenseCategoriesCrudProvider.notifier).delete(c.id);
      if (mounted) crudToast(context, 'Catégorie supprimée');
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur lors de la suppression'));
    }
  }

  /// `addCategory` : nom trimmé non vide, sinon abandon silencieux.
  Future<void> _add() async {
    final name = _newController.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(expenseCategoriesCrudProvider.notifier).create(name);
      if (!mounted) return;
      crudToast(context, 'Catégorie ajoutée');
      _newController.clear();
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(expenseCategoriesCrudProvider);
    final categories = async.value ?? const <CaisseCategory>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catégories de dépenses', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Catégories proposées lors d'une saisie de sortie de caisse (Salaire, Pub, Commande stock...). "
              'Ajoutez-en, renommez ou supprimez-les selon vos besoins.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('Toutes les catégories (${categories.length})', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            CrudBoundedList(
              maxHeight: kCrudCategoriesMaxHeight,
              async: async,
              itemCount: categories.length,
              emptyMessage: 'Aucune catégorie.',
              onRetry: () => ref.read(expenseCategoriesCrudProvider.notifier).refresh(),
              itemBuilder: (context, index) {
                final c = categories[index];
                if (_editingId == c.id) {
                  return CrudRowFrame(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _editingController,
                            autofocus: true,
                            decoration: const InputDecoration(isDense: true),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _saveEdit(),
                          ),
                        ),
                        const SizedBox(width: 4),
                        CrudEditActions(onOk: _saveEdit, onCancel: () => setState(() => _editingId = null)),
                      ],
                    ),
                  );
                }
                return CrudRowFrame(
                  child: Row(
                    children: [
                      Expanded(child: Text(c.nom, style: theme.textTheme.bodyMedium)),
                      CrudRowActions(onEdit: () => _startEdit(c), onDelete: () => _remove(c)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newController,
                    decoration: const InputDecoration(isDense: true, hintText: 'Nouvelle catégorie (ex: Transport)'),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Ajouter')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Carte « Dépenses des livreurs »
// =============================================================================

/// Carte « Dépenses des livreurs » — `LivreurExpenseTypesCrudList` du web :
/// compteur « Types (N) », lignes nom (barré si inactif) + badge montant
/// (« / unité » si à l'unité) + interrupteur « Type actif » + crayon +
/// corbeille, édition en place (nom, montant, à l'unité, OK / Annuler),
/// barre d'ajout (nom, montant, à l'unité, Ajouter).
class LivreurExpenseTypesCrudCard extends ConsumerStatefulWidget {
  const LivreurExpenseTypesCrudCard({super.key});

  @override
  ConsumerState<LivreurExpenseTypesCrudCard> createState() => _LivreurExpenseTypesCrudCardState();
}

class _LivreurExpenseTypesCrudCardState extends ConsumerState<LivreurExpenseTypesCrudCard> {
  // Barre d'ajout.
  final _nomController = TextEditingController();
  final _prixController = TextEditingController();
  bool _parUnite = false;

  // Édition en place, même schéma que les zones de livraison.
  int? _editionId;
  final _editionNomController = TextEditingController();
  final _editionPrixController = TextEditingController();
  bool _editionParUnite = false;

  @override
  void dispose() {
    _nomController.dispose();
    _prixController.dispose();
    _editionNomController.dispose();
    _editionPrixController.dispose();
    super.dispose();
  }

  ExpenseTypesNotifier get _notifier => ref.read(expenseTypesProvider.notifier);

  void _ouvrirEdition(ExpenseType t) {
    setState(() {
      _editionId = t.id;
      _editionNomController.text = t.nom;
      _editionPrixController.text = montantEnSaisie(t.prixUnitaire);
      _editionParUnite = t.parUnite;
    });
  }

  /// `enregistrerEdition` : nom trimmé non vide sinon abandon silencieux ;
  /// montant `Number(prix) || 0`.
  Future<void> _enregistrerEdition() async {
    final id = _editionId;
    final nom = _editionNomController.text.trim();
    if (id == null || nom.isEmpty) return;
    try {
      await _notifier.updateType(
        id,
        nom: nom,
        prixUnitaire: parseMontantOuZero(_editionPrixController.text),
        parUnite: _editionParUnite,
      );
      if (!mounted) return;
      crudToast(context, 'Type mis à jour');
      setState(() => _editionId = null);
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  /// `ajouter` : nom trimmé non vide sinon abandon silencieux ; montant
  /// `Number(prix) || 0` ; les trois champs sont vidés après succès.
  Future<void> _ajouter() async {
    final nom = _nomController.text.trim();
    if (nom.isEmpty) return;
    try {
      await _notifier.create(nom: nom, prixUnitaire: parseMontantOuZero(_prixController.text), parUnite: _parUnite);
      if (!mounted) return;
      crudToast(context, 'Type de dépense ajouté');
      setState(() {
        _nomController.clear();
        _prixController.clear();
        _parUnite = false;
      });
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  /// `basculerActif` : PATCH immédiat, rechargement, SANS toast de succès.
  Future<void> _basculerActif(ExpenseType t) async {
    try {
      await _notifier.toggleActif(t);
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  /// `supprimer` : DELETE immédiat, sans confirmation. Un type déjà utilisé
  /// par une dépense est seulement désactivé par le serveur : il réapparaît
  /// alors barré dans la liste.
  Future<void> _supprimer(ExpenseType t) async {
    try {
      final desactive = await _notifier.delete(t.id);
      if (!mounted) return;
      crudToast(context, desactive == null ? 'Type supprimé' : 'Type désactivé (déjà utilisé par des dépenses)');
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur lors de la suppression'));
    }
  }

  Widget _parUniteSwitch({required bool value, required ValueChanged<bool> onChanged}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged),
        const SizedBox(width: 4),
        const Text("à l'unité", style: TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _montantField(TextEditingController controller, {VoidCallback? onSubmitted}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: montantInputFormatters,
      decoration: const InputDecoration(isDense: true, hintText: 'Montant (Ar)'),
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(expenseTypesProvider);
    final types = async.value ?? const <ExpenseType>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dépenses des livreurs', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Types proposés au livreur quand il déclare une dépense depuis son bilan du jour. '
              "Le prix sert de valeur par défaut ; cochez « à l'unité » pour une dépense qui se compte "
              '(enveloppes, sacs…), le livreur saisira alors une quantité.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('Types (${types.length})', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            CrudBoundedList(
              maxHeight: kCrudTypesMaxHeight,
              async: async,
              itemCount: types.length,
              emptyMessage: 'Aucun type de dépense.',
              onRetry: () => _notifier.refresh(),
              itemBuilder: (context, index) {
                final t = types[index];
                if (_editionId == t.id) {
                  return CrudRowFrame(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        TextField(
                          controller: _editionNomController,
                          autofocus: true,
                          decoration: const InputDecoration(isDense: true, hintText: 'Nom du type'),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _montantField(_editionPrixController, onSubmitted: _enregistrerEdition)),
                            const SizedBox(width: 8),
                            _parUniteSwitch(
                              value: _editionParUnite,
                              onChanged: (v) => setState(() => _editionParUnite = v),
                            ),
                          ],
                        ),
                        CrudEditActions(onOk: _enregistrerEdition, onCancel: () => setState(() => _editionId = null)),
                      ],
                    ),
                  );
                }
                return CrudRowFrame(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.nom,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: t.actif ? null : theme.colorScheme.onSurfaceVariant,
                                decoration: t.actif ? null : TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: CrudPriceBadge('${arFmt(t.prixUnitaire)}${t.parUnite ? ' / unité' : ''}'),
                            ),
                          ],
                        ),
                      ),
                      CrudRowActions(
                        leading: Tooltip(
                          message: 'Type actif',
                          child: Switch(value: t.actif, onChanged: (_) => _basculerActif(t)),
                        ),
                        onEdit: () => _ouvrirEdition(t),
                        onDelete: () => _supprimer(t),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nomController,
              decoration: const InputDecoration(isDense: true, hintText: 'Nouveau type (ex: Repas)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _montantField(_prixController, onSubmitted: _ajouter)),
                const SizedBox(width: 8),
                _parUniteSwitch(value: _parUnite, onChanged: (v) => setState(() => _parUnite = v)),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _ajouter,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
