import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/permissions.dart';
import '../../data/repositories/auth_repository.dart';
import '../../models/delivery_zone.dart';
import '../../models/json_utils.dart';
import '../../models/user.dart';
import '../../state/auth_provider.dart';
import '../../state/expenses_provider.dart';
import '../../state/orders_provider.dart';
import '../../widgets/order_confirm_dialog.dart' show arFmt;
import 'expense_types_crud.dart';

/// Page « Paramètres » — réplique de `/settings` (app/(app)/settings/page.tsx).
///
/// Quatre onglets au plus : « Mon profil » et « Sécurité » (toujours),
/// « Dépenses » et « Zones de livraison » (gérant uniquement). Aucun écran
/// 403 : un non-gérant (préparateur / livreur) voit la page dégradée en
/// lecture seule — champs désactivés, bouton Enregistrer et formulaire de
/// mot de passe non rendus, textes explicatifs dans les descriptions — et le
/// serveur ré-applique la règle (PATCH /users/me/ et /users/change-password/
/// répondent 403 hors admin/magasin, écriture zones/catégories = IsGerant).
///
/// L'onglet actif n'est pas persisté (ni URL, ni stockage), comme sur le web.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    // `if (userLoading)` du web : 3 blocs squelette, pas de spinner.
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Paramètres')),
        body: const _SkeletonList(),
      );
    }

    final isGerant = user.isGerant;
    final tabs = <Widget>[
      const _IconTab(icon: Icons.person_outline, label: 'Mon profil'),
      const _IconTab(icon: Icons.lock_outline, label: 'Sécurité'),
      if (isGerant) const _IconTab(icon: Icons.account_balance_wallet_outlined, label: 'Dépenses'),
      if (isGerant) const _IconTab(icon: Icons.location_on_outlined, label: 'Zones de livraison'),
    ];
    final views = <Widget>[
      const _ProfileTab(),
      const _SecurityTab(),
      if (isGerant) const _DepensesTab(),
      if (isGerant) const _ZonesTab(),
    ];

    return DefaultTabController(
      // Le nombre d'onglets dépend du rôle : un changement de compte sur le
      // même appareil recrée le contrôleur.
      key: ValueKey(isGerant),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paramètres'),
              Text(
                'Gérez votre profil et vos préférences',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

/// Onglet icône + libellé (`<TabsTrigger><Icon/>Libellé</TabsTrigger>`).
class _IconTab extends StatelessWidget {
  const _IconTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      ),
    );
  }
}

/// `<Skeleton className="h-24 w-full" />` × 3.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 96,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          ),
      ],
    );
  }
}

/// `roleLabel` du web : libellé FR du rôle Django brut, repli sur la valeur
/// brute.
String _roleLabel(AppUser user) {
  switch (user.rawRole) {
    case 'admin':
      return 'Administrateur';
    case 'magasin':
      return 'Gérant de magasin';
    case 'employer':
      return 'Commercial';
    default:
      return user.rawRole ?? '';
  }
}

/// Sélecteur d'image (`<input type="file" accept="image/*">`) : galerie ou
/// appareil photo.
Future<XFile?> _pickImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);
}

// =============================================================================
// Société / magasin — nom + logo (`handleUpdateDetails` du web)
// =============================================================================

/// Bloc édité par le Dialog « Modifier l'entreprise » / « Modifier le
/// magasin » : `company_name` + `logo` pour un admin, `shop_name` +
/// `shop_logo` pour un gérant de magasin (users/views.py::Myprofile.patch).
enum _CompanyKind { entreprise, magasin }

extension _CompanyKindX on _CompanyKind {
  String get dialogTitle => this == _CompanyKind.entreprise ? "Modifier l'entreprise" : 'Modifier le magasin';
  String get dialogDescription => this == _CompanyKind.entreprise
      ? 'Mettez à jour le nom et le logo de votre entreprise'
      : 'Mettez à jour le nom et le logo de votre magasin';
  String get nameLabel => this == _CompanyKind.entreprise ? "Nom de l'entreprise" : 'Nom du magasin';
  String get logoLabel => this == _CompanyKind.entreprise ? "Logo de l'entreprise" : 'Logo du magasin';
  String get nameField => this == _CompanyKind.entreprise ? 'company_name' : 'shop_name';
  String get logoField => this == _CompanyKind.entreprise ? 'logo' : 'shop_logo';
}

/// Champs de `GET /users/me/` que le modèle [AppUser] ne porte pas
/// (`company_name`, `logo`, `shop_logo`) — nécessaires au bloc
/// « Entreprise » et au Dialog de modification.
class _ProfileDetails {
  const _ProfileDetails({this.companyName, this.logo, this.shopName, this.shopLogo});

  final String? companyName;
  final String? logo;
  final String? shopName;
  final String? shopLogo;

  factory _ProfileDetails.fromJson(Map<String, dynamic> json) => _ProfileDetails(
    companyName: asStringOrNull(json['company_name']),
    logo: asStringOrNull(json['logo']),
    shopName: asStringOrNull(json['shop_name']),
    shopLogo: asStringOrNull(json['shop_logo']),
  );
}

/// Accès `/users/me/` propres à cette page — le portage ne pouvant créer que
/// les fichiers listés, ils étendent [AuthRepository] ici, sur le même
/// client HTTP.
extension _SettingsAuthRepository on AuthRepository {
  Future<_ProfileDetails> profileDetails() async {
    final response = await ApiClient.instance.dio.get('users/me/');
    return _ProfileDetails.fromJson(response.data as Map<String, dynamic>);
  }

  /// `djangoClient.patchFormData('/users/me/', formData)` : nom + logo
  /// facultatif, en multipart.
  Future<void> updateCompanyDetails({required _CompanyKind kind, required String name, String? logoPath}) async {
    final formData = FormData.fromMap({
      kind.nameField: name,
      if (logoPath != null) kind.logoField: await MultipartFile.fromFile(logoPath),
    });
    await ApiClient.instance.dio.patch('users/me/', data: formData);
  }
}

final _profileDetailsProvider = FutureProvider.autoDispose<_ProfileDetails>((ref) {
  ref.watch(authProvider.select((a) => a.user?.id));
  return ref.read(authRepositoryProvider).profileDetails();
});

// =============================================================================
// Onglet « Mon profil »
// =============================================================================

class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab();

  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> with AutomaticKeepAliveClientMixin {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _adresseController = TextEditingController();
  XFile? _avatarFile;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // `useEffect(() => { setFullName(user.full_name || '') … }, [user])`.
    final user = ref.read(authProvider).user;
    _nameController.text = user?.fullName ?? '';
    _phoneController.text = user?.phone ?? '';
    _adresseController.text = user?.adresse ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _adresseController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final file = await _pickImage(context);
    if (file != null && mounted) setState(() => _avatarFile = file);
  }

  /// `handleUpdateProfile` : PATCH JSON {full_name, phone, adresse} puis, si
  /// une photo a été choisie, second PATCH multipart {photo}. Aucune
  /// validation client. Le formulaire n'est pas réinitialisé.
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.updateProfile(
        fullName: _nameController.text,
        phone: _phoneController.text,
        adresse: _adresseController.text,
      );
      final avatar = _avatarFile;
      if (avatar != null) {
        await repo.uploadProfilePhoto(avatar.path);
        if (mounted) setState(() => _avatarFile = null);
      }
      // Le web garde l'aperçu local ; l'app recharge l'utilisateur pour que
      // la barre du haut et l'aperçu reflètent la photo enregistrée.
      await ref.read(authProvider.notifier).refreshUser();
      if (mounted) crudToast(context, 'Profil mis à jour');
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur lors de la mise à jour'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCompanyDialog(_CompanyKind kind, String initialName) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _CompanyDetailsDialog(kind: kind, initialName: initialName),
    );
    if (updated != true || !mounted) return;
    crudToast(context, 'Informations mises à jour avec succès');
    // `window.location.reload()` du web : on recharge l'utilisateur courant
    // et les détails société/magasin.
    ref.invalidate(_profileDetailsProvider);
    await ref.read(authProvider.notifier).refreshUser();
  }

  Future<void> _refresh() async {
    ref.invalidate(_profileDetailsProvider);
    await ref.read(authProvider.notifier).refreshUser();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authProvider).user;
    if (user == null) return const _SkeletonList();
    final isGerant = user.isGerant;
    final details = ref.watch(_profileDetailsProvider).value;
    final companyName = details?.companyName ?? '';
    final shopName = user.shopName ?? details?.shopName ?? '';

    final avatar = _avatarFile;
    final ImageProvider? avatarImage = avatar != null
        ? FileImage(File(avatar.path))
        : (user.photo != null && user.photo!.isNotEmpty ? NetworkImage(user.photo!) : null);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Informations personnelles', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    isGerant
                        ? 'Mettez à jour vos informations'
                        : 'Seul le gérant peut modifier ces informations. Contactez votre gérant pour toute correction.',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Text('Photo de profil', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.surfaceContainerHighest,
                          border: Border.all(color: scheme.outlineVariant),
                          image: avatarImage == null ? null : DecorationImage(image: avatarImage, fit: BoxFit.cover),
                        ),
                        child: avatarImage == null ? Icon(Icons.person_outline, color: scheme.onSurfaceVariant) : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: isGerant ? _pickAvatar : null,
                              icon: const Icon(Icons.upload_file_outlined, size: 18),
                              label: const Text('Choisir une image'),
                            ),
                            if (avatar != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  avatar.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: ValueKey('email-${user.email}'),
                    initialValue: user.email,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      helperText: "L'email ne peut pas être modifié",
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Rôle', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerLeft, child: _OutlineBadge(_roleLabel(user))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    enabled: isGerant,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nom complet', hintText: 'Votre nom'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    enabled: isGerant,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+261 XX XXX XX XX'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _adresseController,
                    enabled: isGerant,
                    decoration: const InputDecoration(
                      labelText: 'Adresse',
                      hintText: 'Ex: Lot II A 45, Antanimena, Antananarivo',
                    ),
                  ),
                  if (user.isMagasin && shopName.isNotEmpty) ...[
                    const Divider(height: 32),
                    Text('Magasin', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _CompanyBlock(name: shopName, onEdit: () => _openCompanyDialog(_CompanyKind.magasin, shopName)),
                  ],
                  if (user.isAdmin && companyName.isNotEmpty) ...[
                    const Divider(height: 32),
                    Text('Entreprise', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _CompanyBlock(
                      name: companyName,
                      // Le serveur n'applique le nom/logo société qu'au
                      // propriétaire (AdminProfile) : un co-administrateur
                      // partage les données, pas cette action de propriété.
                      onEdit: user.canManageCompany
                          ? () => _openCompanyDialog(_CompanyKind.entreprise, companyName)
                          : null,
                      lockedHint: user.canManageCompany
                          ? null
                          : 'Seul le propriétaire de la société peut modifier ces informations.',
                    ),
                  ],
                  if (isGerant) ...[
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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

/// `<Badge variant="outline">` (rôle).
class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Encadré « Magasin » / « Entreprise » : icône Building2 + nom en gras +
/// bouton « Modifier » (outline, small).
class _CompanyBlock extends StatelessWidget {
  const _CompanyBlock({required this.name, required this.onEdit, this.lockedHint});

  final String name;
  final VoidCallback? onEdit;
  final String? lockedHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_outlined, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Modifier'),
                ),
              ],
            ],
          ),
          if (lockedHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(lockedHint!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// Dialog « Modifier l'entreprise » / « Modifier le magasin » : nom (requis)
/// + logo facultatif avec aperçu 80×80 après sélection. Renvoie `true`
/// après enregistrement.
class _CompanyDetailsDialog extends ConsumerStatefulWidget {
  const _CompanyDetailsDialog({required this.kind, required this.initialName});

  final _CompanyKind kind;
  final String initialName;

  @override
  ConsumerState<_CompanyDetailsDialog> createState() => _CompanyDetailsDialogState();
}

class _CompanyDetailsDialogState extends ConsumerState<_CompanyDetailsDialog> {
  late final _nameController = TextEditingController(text: widget.initialName);
  XFile? _logoFile;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await _pickImage(context);
    if (file != null && mounted) setState(() => _logoFile = file);
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    // Attribut `required` de l'input web.
    if (name.isEmpty) {
      crudToast(context, '${widget.kind.nameLabel} : champ requis');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .updateCompanyDetails(kind: widget.kind, name: name, logoPath: _logoFile?.path);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        crudToast(context, crudErrorMessage(e, 'Erreur lors de la mise à jour'));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = widget.kind;
    final logo = _logoFile;

    return AlertDialog(
      title: Text(kind.dialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kind.dialogDescription, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: kind.nameLabel, hintText: kind.nameLabel),
            ),
            const SizedBox(height: 16),
            Text(kind.logoLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickLogo,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(logo == null ? 'Choisir une image' : logo.name, overflow: TextOverflow.ellipsis),
            ),
            if (logo != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(File(logo.path), fit: BoxFit.contain),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Enregistrement...'),
                  ],
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// =============================================================================
// Onglet « Sécurité »
// =============================================================================

class _SecurityTab extends ConsumerStatefulWidget {
  const _SecurityTab();

  @override
  ConsumerState<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends ConsumerState<_SecurityTab> with AutomaticKeepAliveClientMixin {
  final _oldPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();
  bool _changing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _oldPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  /// `handleChangePassword` : correspondance puis longueur ≥ 6, tout en
  /// toasts (aucun message sous les champs) ; succès = toast + champs vidés,
  /// sans déconnexion.
  Future<void> _changePassword() async {
    final oldPw = _oldPwController.text;
    final newPw = _newPwController.text;
    final confirmPw = _confirmPwController.text;
    // Attributs `required` des trois inputs web.
    if (oldPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
      crudToast(context, 'Veuillez remplir tous les champs');
      return;
    }
    if (newPw != confirmPw) {
      crudToast(context, 'Les mots de passe ne correspondent pas');
      return;
    }
    if (newPw.length < 6) {
      crudToast(context, 'Le mot de passe doit contenir au moins 6 caractères');
      return;
    }
    setState(() => _changing = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(oldPassword: oldPw, newPassword: newPw);
      if (!mounted) return;
      crudToast(context, 'Mot de passe changé avec succès');
      _oldPwController.clear();
      _newPwController.clear();
      _confirmPwController.clear();
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur lors du changement de mot de passe'));
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isGerant = ref.watch(authProvider.select((a) => a.user?.isGerant ?? false));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Changer le mot de passe', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  isGerant
                      ? 'Sécurisez votre compte'
                      : 'Seul le gérant peut modifier le mot de passe. Contactez votre gérant.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                // Le formulaire entier n'est rendu que pour un gérant.
                if (isGerant) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _oldPwController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Mot de passe actuel', hintText: '••••••••'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPwController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Nouveau mot de passe', hintText: '••••••••'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPwController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', hintText: '••••••••'),
                    onSubmitted: (_) => _changing ? null : _changePassword(),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _changing ? null : _changePassword,
                      child: Text(_changing ? 'Changement...' : 'Changer le mot de passe'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Onglet « Dépenses » (gérant)
// =============================================================================

class _DepensesTab extends ConsumerWidget {
  const _DepensesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => Future.wait<void>([
        ref.read(expenseCategoriesCrudProvider.notifier).refresh(),
        ref.read(expenseTypesProvider.notifier).refresh(),
      ]),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [ExpenseCategoriesCrudCard(), SizedBox(height: 16), LivreurExpenseTypesCrudCard()],
      ),
    );
  }
}

// =============================================================================
// Onglet « Zones de livraison » (gérant)
// =============================================================================

class _ZonesTab extends ConsumerWidget {
  const _ZonesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => ref.read(deliveryZonesProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Zones de livraison', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    "Zones proposées à la création d'une commande (nom + frais de livraison). "
                    'Le retrait sur place ("Récupération") reste toujours disponible séparément et n\'est pas géré ici. '
                    'Ajoutez-en, renommez ou changez le prix selon vos besoins — pensez à garder au moins une zone gratuite (0 Ar).',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  const _DeliveryZonesCrudList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `DeliveryZonesCrudList` du web : compteur « Toutes les zones (N) »,
/// lignes nom (barré si inactive) + badge prix + interrupteur « Zone
/// active » + crayon + corbeille, édition en place (nom + prix, OK /
/// Annuler), barre d'ajout (nom + prix + Ajouter).
class _DeliveryZonesCrudList extends ConsumerStatefulWidget {
  const _DeliveryZonesCrudList();

  @override
  ConsumerState<_DeliveryZonesCrudList> createState() => _DeliveryZonesCrudListState();
}

class _DeliveryZonesCrudListState extends ConsumerState<_DeliveryZonesCrudList> {
  int? _editingId;
  final _editingNameController = TextEditingController();
  final _editingPrixController = TextEditingController();
  final _newNameController = TextEditingController();
  final _newPrixController = TextEditingController();

  @override
  void dispose() {
    _editingNameController.dispose();
    _editingPrixController.dispose();
    _newNameController.dispose();
    _newPrixController.dispose();
    super.dispose();
  }

  DeliveryZonesNotifier get _notifier => ref.read(deliveryZonesProvider.notifier);

  void _startEdit(DeliveryZoneOption z) {
    setState(() {
      _editingId = z.id;
      _editingNameController.text = z.nom;
      _editingPrixController.text = montantEnSaisie(z.prix);
    });
  }

  /// `saveEdit` : nom trimmé non vide sinon abandon silencieux ; prix
  /// `Number(prix) || 0` ; PATCH {nom, prix} (sans `actif`).
  Future<void> _saveEdit() async {
    final id = _editingId;
    final name = _editingNameController.text.trim();
    if (id == null || name.isEmpty) return;
    try {
      await _notifier.updateZone(id, nom: name, prix: parseMontantOuZero(_editingPrixController.text));
      if (!mounted) return;
      crudToast(context, 'Zone mise à jour');
      setState(() => _editingId = null);
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  /// `toggleActive` : PATCH {actif: !actif}, rechargement, SANS toast.
  Future<void> _toggleActive(DeliveryZoneOption z) async {
    try {
      await _notifier.toggleActif(z);
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  /// `removeZone` : DELETE immédiat, sans confirmation. Une zone déjà
  /// utilisée par des commandes est seulement désactivée par le serveur :
  /// elle réapparaît alors barrée dans la liste.
  Future<void> _remove(DeliveryZoneOption z) async {
    try {
      final desactivee = await _notifier.delete(z.id);
      if (!mounted) return;
      crudToast(context, desactivee == null ? 'Zone supprimée' : 'Zone désactivée (déjà utilisée par des commandes)');
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur lors de la suppression'));
    }
  }

  /// `addZone` : nom trimmé non vide sinon abandon silencieux ; prix
  /// `Number(prix) || 0` ; les deux champs sont vidés après succès.
  Future<void> _add() async {
    final name = _newNameController.text.trim();
    if (name.isEmpty) return;
    try {
      await _notifier.create(nom: name, prix: parseMontantOuZero(_newPrixController.text));
      if (!mounted) return;
      crudToast(context, 'Zone ajoutée');
      _newNameController.clear();
      _newPrixController.clear();
    } catch (e) {
      if (mounted) crudToast(context, crudErrorMessage(e, 'Erreur'));
    }
  }

  Widget _prixField(TextEditingController controller, {required VoidCallback onSubmitted}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: montantInputFormatters,
      decoration: const InputDecoration(isDense: true, hintText: 'Prix (Ar)'),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(deliveryZonesProvider);
    final zones = async.value ?? const <DeliveryZoneOption>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Toutes les zones (${zones.length})', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        CrudBoundedList(
          maxHeight: kCrudTypesMaxHeight,
          async: async,
          itemCount: zones.length,
          emptyMessage: 'Aucune zone.',
          onRetry: () => _notifier.refresh(),
          itemBuilder: (context, index) {
            final z = zones[index];
            if (_editingId == z.id) {
              return CrudRowFrame(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    TextField(
                      controller: _editingNameController,
                      autofocus: true,
                      decoration: const InputDecoration(isDense: true, hintText: 'Nom de la zone'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    _prixField(_editingPrixController, onSubmitted: _saveEdit),
                    CrudEditActions(onOk: _saveEdit, onCancel: () => setState(() => _editingId = null)),
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
                          z.nom,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: z.actif ? null : theme.colorScheme.onSurfaceVariant,
                            decoration: z.actif ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(alignment: Alignment.centerLeft, child: CrudPriceBadge(arFmt(z.prix))),
                      ],
                    ),
                  ),
                  CrudRowActions(
                    leading: Tooltip(
                      message: 'Zone active',
                      child: Switch(value: z.actif, onChanged: (_) => _toggleActive(z)),
                    ),
                    onEdit: () => _startEdit(z),
                    onDelete: () => _remove(z),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newNameController,
          decoration: const InputDecoration(isDense: true, hintText: 'Nouvelle zone (ex: Zone 4)'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _prixField(_newPrixController, onSubmitted: _add)),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Ajouter')),
          ],
        ),
      ],
    );
  }
}
