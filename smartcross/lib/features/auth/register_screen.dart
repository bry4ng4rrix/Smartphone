import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../data/repositories/account_repository.dart';

/// Table de traduction des erreurs du web (`ERRORS` + `friendlyError()` dans
/// `frontend/components/auth/register-form.tsx`) : matching par `includes`,
/// dans l'ordre de déclaration. Ce sont des messages hérités de l'ancien
/// backend (anglais) ; s'ils ne matchent pas, on affiche le message brut du
/// backend Django, souvent de la forme
/// « admin_email: Administrateur introuvable avec cet email. ».
const Map<String, String> _errorTranslations = {
  'User already registered': 'Un compte existe déjà avec cet email.',
  'Password should be at least': 'Le mot de passe doit contenir au moins 6 caractères.',
  'Unable to validate email': 'Adresse email invalide.',
  'Too many requests': 'Trop de tentatives. Attendez quelques minutes.',
};

String _friendlyError(String message) {
  for (final entry in _errorTranslations.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  return message;
}

/// Couleurs de sélection du RadioGroup, reprises telles quelles des classes
/// Tailwind de la page web — ce sont des couleurs d'IDENTITÉ de rôle
/// (bleu = admin, cyan = gérant, vert = employé), pas des couleurs de thème.
const _blue500 = Color(0xFF3B82F6);
const _blue50 = Color(0xFFEFF6FF);
const _cyan500 = Color(0xFF06B6D4);
const _cyan50 = Color(0xFFECFEFF);
const _green500 = Color(0xFF22C55E);
const _green50 = Color(0xFFF0FDF4);
const _green600 = Color(0xFF16A34A); // toast de succès

/// Écran `/register` du web (`frontend/app/register/page.tsx` +
/// `frontend/components/auth/register-form.tsx`) : auto-inscription PUBLIQUE.
///
/// L'utilisateur choisit lui-même son type de compte (Admin / Manager /
/// Employé) et le formulaire change de champs en conséquence. Aucune
/// connexion automatique, aucun token stocké : le compte part en attente
/// d'approbation (`is_confirmed=False`) — sauf `admin`, confirmé d'office par
/// le serializer Django — et l'écran renvoie vers `/pending-approval`.
///
/// Fidélité au web assumée sur deux points « bizarres » :
/// - l'email du compte n'est JAMAIS validé côté client (ni présence ni
///   format) : c'est le backend qui rejette (400 `email: ...`) ;
/// - les validations sont SÉQUENTIELLES et s'arrêtent au premier problème,
///   affiché en toast (ici SnackBar) — aucun message d'erreur sous les champs.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  // Un contrôleur par champ, jamais recréé : comme les `useState` du web, la
  // valeur saisie survit à un changement de type de compte (c'est notamment
  // le MÊME state `adminEmail` qui sert au Manager et à l'Employé).
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _positionController = TextEditingController();

  /// Défaut du web : 'employee'.
  RegisterAccountType _type = RegisterAccountType.employee;
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _companyNameController.dispose();
    _shopNameController.dispose();
    _adminEmailController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  /// Validations client du web, dans l'ORDRE EXACT : la première qui échoue
  /// arrête tout et produit un seul message.
  String? _firstValidationError() {
    if (_fullNameController.text.trim().isEmpty) {
      return 'Le nom complet est requis.';
    }
    if (_passwordController.text.length < 6) {
      return 'Le mot de passe doit contenir au moins 6 caractères.';
    }
    if (_type == RegisterAccountType.admin && _companyNameController.text.trim().isEmpty) {
      return "Le nom de l'entreprise est requis.";
    }
    if (_type == RegisterAccountType.storeManager) {
      if (_shopNameController.text.trim().isEmpty) return 'Le nom du magasin est requis.';
      if (_adminEmailController.text.trim().isEmpty) {
        return "L'email de l'administrateur est requis.";
      }
    }
    if (_type == RegisterAccountType.employee) {
      if (_adminEmailController.text.trim().isEmpty) {
        return "L'email du responsable est requis.";
      }
      if (_positionController.text.trim().isEmpty) return 'Le poste / fonction est requis.';
    }
    return null;
  }

  void _toast(String message, {required bool isError}) {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isError ? scheme.onError : Colors.white),
        ),
        backgroundColor: isError ? scheme.error : _green600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit() async {
    if (_loading) return;
    final validationError = _firstValidationError();
    if (validationError != null) {
      _toast(validationError, isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(accountRepositoryProvider).register(
            type: _type,
            fullName: _fullNameController.text,
            email: _emailController.text,
            password: _passwordController.text,
            username: _usernameController.text,
            companyName: _companyNameController.text,
            shopName: _shopNameController.text,
            adminEmail: _adminEmailController.text,
            position: _positionController.text,
          );
      if (!mounted) return;
      _toast(_type.successMessage, isError: false);
      // Web : `router.push('/auth/pending-approval')`. Le formulaire n'est
      // volontairement PAS réinitialisé et aucun token n'est posé.
      context.go('/pending-approval');
    } catch (e) {
      if (!mounted) return;
      // On reste sur le formulaire, les valeurs saisies sont conservées.
      _toast(_friendlyError(ApiClient.messageFromError(e)), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _backToLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Retour à la connexion',
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : _backToLogin,
        ),
        title: const Text('Inscription'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // `border-t-4 border-t-primary` : liseré coloré en haut de la
                  // carte, ce qui distingue l'inscription de la connexion.
                  Container(height: 4, color: theme.colorScheme.primary),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Créer un compte', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          'Rejoignez E-kajy Entana',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        _buildTypeSelector(theme),
                        const SizedBox(height: 16),
                        _buildField(
                          label: 'Nom complet',
                          isRequired: true,
                          controller: _fullNameController,
                          icon: Icons.person_outline,
                          hint: 'Jean Dupont',
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                        ),
                        // Champs dynamiques selon le type de compte
                        // (`animate-in fade-in duration-200` côté web).
                        ..._buildDynamicFields(),
                        const SizedBox(height: 14),
                        _buildField(
                          label: "Nom d'utilisateur",
                          isRequired: false,
                          optionalSuffix: '(Optionnel)',
                          controller: _usernameController,
                          icon: Icons.person_outline,
                          hint: 'jean_dupont',
                          autofillHints: const [AutofillHints.username],
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          label: 'Email',
                          isRequired: true,
                          controller: _emailController,
                          icon: Icons.email_outlined,
                          hint: 'vous@example.com',
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          label: 'Mot de passe',
                          isRequired: true,
                          controller: _passwordController,
                          icon: Icons.lock_outline,
                          hint: '••••••••',
                          obscure: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          helper: 'Minimum 6 caractères',
                          suffix: IconButton(
                            tooltip: _obscure
                                ? 'Afficher le mot de passe'
                                : 'Masquer le mot de passe',
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed:
                                _loading ? null : () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Création du compte…'),
                                  ],
                                )
                              : const Text("S'inscrire"),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Déjà un compte?',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            TextButton(
                              onPressed: _loading ? null : _backToLogin,
                              child: const Text('Se connecter'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// RadioGroup « Type de compte » : 3 cartes cliquables côte à côte, chacune
  /// bordée/teintée de sa couleur quand elle est sélectionnée.
  Widget _buildTypeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Type de compte',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        RadioGroup<RegisterAccountType>(
          groupValue: _type,
          onChanged: (value) {
            if (_loading || value == null) return;
            setState(() => _type = value);
          },
          child: Row(
            children: [
              Expanded(child: _typeOption(theme, RegisterAccountType.admin)),
              const SizedBox(width: 8),
              Expanded(child: _typeOption(theme, RegisterAccountType.storeManager)),
              const SizedBox(width: 8),
              Expanded(child: _typeOption(theme, RegisterAccountType.employee)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typeOption(ThemeData theme, RegisterAccountType type) {
    final isDark = theme.brightness == Brightness.dark;
    final selected = _type == type;
    final accent = switch (type) {
      RegisterAccountType.admin => _blue500,
      RegisterAccountType.storeManager => _cyan500,
      RegisterAccountType.employee => _green500,
    };
    // `bg-blue-50` en clair, `dark:bg-blue-950/30` en sombre : une teinte très
    // légère de la couleur d'accent dans les deux cas.
    final background = selected
        ? (isDark
            ? accent.withValues(alpha: 0.16)
            : switch (type) {
                RegisterAccountType.admin => _blue50,
                RegisterAccountType.storeManager => _cyan50,
                RegisterAccountType.employee => _green50,
              })
        : Colors.transparent;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _loading ? null : () => setState(() => _type = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<RegisterAccountType>(
              value: type,
              enabled: !_loading,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: accent,
            ),
            Flexible(
              child: Text(
                type.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected && !isDark ? accent : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Champs supplémentaires selon le type de compte choisi.
  List<Widget> _buildDynamicFields() {
    switch (_type) {
      case RegisterAccountType.admin:
        return [
          const SizedBox(height: 14),
          _buildField(
            label: "Nom de l'entreprise",
            isRequired: true,
            controller: _companyNameController,
            icon: Icons.business_outlined,
            hint: 'Ma Super Entreprise',
            textCapitalization: TextCapitalization.words,
          ),
        ];
      case RegisterAccountType.storeManager:
        return [
          const SizedBox(height: 14),
          _buildField(
            label: 'Nom du magasin',
            isRequired: true,
            controller: _shopNameController,
            icon: Icons.business_outlined,
            hint: 'Boutique Centre-Ville',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          _buildField(
            label: "Email de l'administrateur",
            isRequired: true,
            controller: _adminEmailController,
            icon: Icons.email_outlined,
            hint: 'admin@boutique.com',
            keyboardType: TextInputType.emailAddress,
          ),
        ];
      case RegisterAccountType.employee:
        return [
          const SizedBox(height: 14),
          _buildField(
            label: 'Email du responsable (Admin ou Gérant)',
            isRequired: true,
            controller: _adminEmailController,
            icon: Icons.email_outlined,
            hint: 'gerant@boutique.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _buildField(
            label: 'Poste / Fonction',
            isRequired: true,
            controller: _positionController,
            icon: Icons.person_outline,
            hint: 'Caissier, Vendeur...',
            textCapitalization: TextCapitalization.sentences,
          ),
        ];
    }
  }

  /// Champ « label au-dessus + input à icône », comme le web. L'astérisque
  /// rouge marque les champs obligatoires, `(Optionnel)` en gris les autres.
  Widget _buildField({
    required String label,
    required bool isRequired,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    String? optionalSuffix,
    String? helper,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            children: [
              if (isRequired)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (optionalSuffix != null)
                TextSpan(
                  text: ' $optionalSuffix',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          // `disabled={loading}` sur TOUS les inputs du web.
          enabled: !_loading,
          obscureText: obscure,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            suffixIcon: suffix,
            helperText: helper,
            isDense: true,
          ),
        ),
      ],
    );
  }
}
