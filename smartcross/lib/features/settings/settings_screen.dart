import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../data/repositories/auth_repository.dart';
import '../../models/catalog.dart';
import '../../state/auth_provider.dart';
import '../../state/catalog_provider.dart';

/// Marques courantes malgaches/internationales — même liste que le web
/// (`app/(app)/settings/page.tsx`), pour ajouter une marque en un clic
/// plutôt que de retaper son nom depuis le module Catalogue.
const _kSuggestedBrands = [
  'Samsung', 'iPhone', 'Huawei', 'Redmi', 'Xiaomi', 'Tecno', 'Infinix',
  'Itel', 'Oppo', 'Realme', 'Google Pixel', 'Poco', 'Vivo', 'Honor',
];

/// Profil et sécurité du compte connecté — infrastructure conservée du
/// backend générique (indépendante du cahier des charges Smartphone.Mg).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _savingProfile = false;
  String? _profileError;

  final _oldPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();
  bool _savingPassword = false;
  String? _passwordError;
  String? _passwordSuccess;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameController.text = user?.fullName ?? '';
    _phoneController.text = user?.phone ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _oldPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      await AuthRepository().updateProfile(fullName: _nameController.text.trim(), phone: _phoneController.text.trim());
      await ref.read(authProvider.notifier).refreshUser();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
    } catch (e) {
      setState(() => _profileError = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPwController.text.length < 6) {
      setState(() => _passwordError = '6 caractères minimum');
      return;
    }
    if (_newPwController.text != _confirmPwController.text) {
      setState(() => _passwordError = 'Les mots de passe ne correspondent pas');
      return;
    }
    setState(() {
      _savingPassword = true;
      _passwordError = null;
      _passwordSuccess = null;
    });
    try {
      await AuthRepository().changePassword(oldPassword: _oldPwController.text, newPassword: _newPwController.text);
      _oldPwController.clear();
      _newPwController.clear();
      _confirmPwController.clear();
      setState(() => _passwordSuccess = 'Mot de passe changé avec succès');
    } catch (e) {
      setState(() => _passwordError = ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mon profil', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(controller: TextEditingController(text: user?.email), decoration: const InputDecoration(labelText: 'Email'), enabled: false),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: InputDecoration(labelText: 'Rôle'),
                    controller: TextEditingController(text: user?.role.label ?? ''),
                    enabled: false,
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nom complet')),
                  const SizedBox(height: 10),
                  TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Téléphone')),
                  if (_profileError != null) ...[
                    const SizedBox(height: 8),
                    Text(_profileError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _savingProfile ? null : _saveProfile, child: Text(_savingProfile ? 'Enregistrement…' : 'Enregistrer')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Changer le mot de passe', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(controller: _oldPwController, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel')),
                  const SizedBox(height: 10),
                  TextField(controller: _newPwController, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe')),
                  const SizedBox(height: 10),
                  TextField(controller: _confirmPwController, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le nouveau mot de passe')),
                  if (_passwordError != null) ...[
                    const SizedBox(height: 8),
                    Text(_passwordError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_passwordSuccess != null) ...[
                    const SizedBox(height: 8),
                    Text(_passwordSuccess!, style: const TextStyle(color: Colors.green)),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _savingPassword ? null : _changePassword, child: Text(_savingPassword ? 'Enregistrement…' : 'Changer')),
                  ),
                ],
              ),
            ),
          ),
          if (user?.role == UserRole.gerant) ...[
            const SizedBox(height: 16),
            const _CatalogueBrandsCard(),
            const SizedBox(height: 16),
            const _CatalogueTypesCard(),
            const SizedBox(height: 16),
            const _CatalogueColorsCard(),
          ],
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Déconnexion'),
              onTap: () => ref.read(authProvider.notifier).logout(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Onglet "Catalogue" (gérant uniquement) : ajout rapide d'une marque
/// courante en un clic, en plus du CRUD complet déjà disponible dans le
/// module Produits (`ManageBrandsDialog`/`BrandsNotifier`).
class _CatalogueBrandsCard extends ConsumerStatefulWidget {
  const _CatalogueBrandsCard();

  @override
  ConsumerState<_CatalogueBrandsCard> createState() => _CatalogueBrandsCardState();
}

class _CatalogueBrandsCardState extends ConsumerState<_CatalogueBrandsCard> {
  String? _adding;

  Future<void> _addBrand(String nom) async {
    setState(() => _adding = nom);
    try {
      await ref.read(brandsProvider.notifier).create(nom);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marque "$nom" ajoutée')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  Future<void> _rename(Brand b) async {
    final controller = TextEditingController(text: b.nom);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer la marque'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == b.nom) return;
    try {
      await ref.read(brandsProvider.notifier).rename(b.id, name);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _delete(Brand b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la marque'),
        content: Text('Supprimer "${b.nom}" ? Impossible si des références l\'utilisent déjà.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(brandsProvider.notifier).delete(b.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brands = ref.watch(brandsProvider).value ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Marques', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Ajoutez une marque courante en un clic, ou gérez la liste complète ci-dessous.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final nom in _kSuggestedBrands)
                  _BrandChip(
                    nom: nom,
                    already: brands.any((b) => b.nom.toLowerCase() == nom.toLowerCase()),
                    loading: _adding == nom,
                    onTap: () => _addBrand(nom),
                  ),
              ],
            ),
            const Divider(height: 24),
            Text('Toutes les marques (${brands.length})', style: Theme.of(context).textTheme.labelLarge),
            for (final b in brands)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(b.nom),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _rename(b)),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _delete(b)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip({required this.nom, required this.already, required this.loading, required this.onTap});
  final String nom;
  final bool already;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: already
          ? const Icon(Icons.check, size: 16)
          : (loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add, size: 16)),
      label: Text(nom),
      onPressed: already || loading ? null : onTap,
    );
  }
}

/// CRUD des sous-types (le niveau entre la catégorie — ex. Housse, Cache
/// écran — et la marque, ex. Flip cover, Privacy, Chargeur, Écouteur).
/// Reflète le catalogue réellement en base (`catalog/categories`/`types`) —
/// mêmes endpoints que le module Produits → Configuration, dupliqué ici
/// pour un accès rapide depuis Paramètres (parité avec le web).
class _CatalogueTypesCard extends ConsumerStatefulWidget {
  const _CatalogueTypesCard();

  @override
  ConsumerState<_CatalogueTypesCard> createState() => _CatalogueTypesCardState();
}

class _CatalogueTypesCardState extends ConsumerState<_CatalogueTypesCard> {
  final _newCategoryController = TextEditingController();
  final Map<int, TextEditingController> _newTypeControllers = {};

  @override
  void dispose() {
    _newCategoryController.dispose();
    for (final c in _newTypeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int categoryId) {
    return _newTypeControllers.putIfAbsent(categoryId, () => TextEditingController());
  }

  Future<void> _renameCategory(ProductCategory c) async {
    final controller = TextEditingController(text: c.nom);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer la catégorie'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == c.nom) return;
    try {
      await ref.read(categoriesProvider.notifier).rename(c.id, name);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _deleteCategory(ProductCategory c) async {
    final confirmed = await _confirmDialog(context, 'Supprimer la catégorie "${c.nom}" ? Impossible si des sous-types en dépendent.');
    if (!confirmed) return;
    try {
      await ref.read(categoriesProvider.notifier).delete(c.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _addCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(categoriesProvider.notifier).create(name, ref.read(categoriesProvider).value?.length ?? 0);
      _newCategoryController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _renameType(ProductType t) async {
    final controller = TextEditingController(text: t.nom);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer le sous-type'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == t.nom) return;
    try {
      await ref.read(typesProvider.notifier).rename(t.id, name);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _deleteType(ProductType t) async {
    final confirmed = await _confirmDialog(context, 'Supprimer le sous-type "${t.nom}" ? Impossible si des références en dépendent.');
    if (!confirmed) return;
    try {
      await ref.read(typesProvider.notifier).delete(t.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _addType(int categoryId) async {
    final controller = _controllerFor(categoryId);
    final name = controller.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(typesProvider.notifier).create(categoryId, name);
      controller.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? [];
    final types = ref.watch(typesProvider).value ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sous-types (catégories produit)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Le niveau entre la catégorie (ex. Housse, Cache écran) et la marque — ex. Flip cover, '
              'Privacy, Chargeur, Écouteur. Analysé depuis le catalogue actuel : renommez, supprimez ou '
              'ajoutez-en de nouveaux.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final c in categories) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sell_outlined, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(c.nom, style: Theme.of(context).textTheme.titleSmall)),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _renameCategory(c)),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _deleteCategory(c)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final t in types.where((t) => t.categoryId == c.id))
                            Row(
                              children: [
                                Expanded(child: Text(t.nom, style: Theme.of(context).textTheme.bodySmall)),
                                IconButton(icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _renameType(t)),
                                IconButton(icon: const Icon(Icons.delete_outline, size: 16), onPressed: () => _deleteType(t)),
                              ],
                            ),
                          if (!types.any((t) => t.categoryId == c.id))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text('Aucun sous-type.', style: Theme.of(context).textTheme.bodySmall),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _controllerFor(c.id),
                                    decoration: const InputDecoration(isDense: true, hintText: 'Nouveau sous-type (ex. Chargeur)'),
                                    onSubmitted: (_) => _addType(c.id),
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.add_circle_outline, size: 20), onPressed: () => _addType(c.id)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (categories.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Aucune catégorie.', style: Theme.of(context).textTheme.bodySmall)),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCategoryController,
                    decoration: const InputDecoration(isDense: true, labelText: 'Nouvelle catégorie (ex. Accessoires)'),
                    onSubmitted: (_) => _addCategory(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _addCategory, child: const Text('Ajouter')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDialog(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirmer'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// CRUD des couleurs (§8 README) — alimente le Select du module Produits
/// (création de référence/variante), analysé depuis les couleurs déjà
/// utilisées dans le catalogue actuel.
class _CatalogueColorsCard extends ConsumerStatefulWidget {
  const _CatalogueColorsCard();

  @override
  ConsumerState<_CatalogueColorsCard> createState() => _CatalogueColorsCardState();
}

class _CatalogueColorsCardState extends ConsumerState<_CatalogueColorsCard> {
  final _newColorController = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _newColorController.dispose();
    super.dispose();
  }

  Future<void> _addColor() async {
    if (_newColorController.text.trim().isEmpty) return;
    setState(() => _adding = true);
    try {
      await ref.read(colorsProvider.notifier).create(_newColorController.text.trim());
      _newColorController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _rename(ProductColor c) async {
    final controller = TextEditingController(text: c.nom);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer la couleur'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == c.nom) return;
    try {
      await ref.read(colorsProvider.notifier).rename(c.id, name);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  Future<void> _delete(ProductColor c) async {
    final confirmed = await _confirmDialog(context, 'Supprimer la couleur "${c.nom}" ?');
    if (!confirmed) return;
    try {
      await ref.read(colorsProvider.notifier).delete(c.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.messageFromError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(colorsProvider).value ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Couleurs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Liste des couleurs proposées dans le sélecteur de variante (module Produits).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final c in colors)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(c.nom),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _rename(c)),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _delete(c)),
                  ],
                ),
              ),
            if (colors.isEmpty) Text('Aucune couleur.', style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newColorController,
                    decoration: const InputDecoration(isDense: true, labelText: 'Nouvelle couleur (ex: Bleu)'),
                    onSubmitted: (_) => _addColor(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _adding ? null : _addColor, child: const Text('Ajouter')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
