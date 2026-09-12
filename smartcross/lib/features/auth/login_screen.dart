import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../state/auth_provider.dart';

/// Table de traduction des erreurs du web (`ERRORS` + `friendlyError()` dans
/// `frontend/components/auth/login-form.tsx`) : matching par `includes`, la
/// PREMIÈRE clé qui matche gagne, sinon le message brut du backend est
/// affiché tel quel. Les deux messages réellement produits par Django sont
/// « No active account found with the given credentials » (identifiants
/// invalides ou compte désactivé) et « Compte non approuvé. Contactez votre
/// administrateur. » (jeton refusé tant que `is_confirmed` est faux) ; les
/// autres clés sont héritées de l'ancien backend et conservées à l'identique.
const Map<String, String> _errorTranslations = {
  'Invalid login credentials': 'Email ou mot de passe incorrect.',
  'No active account found': 'Email ou mot de passe incorrect.',
  'Email not confirmed': "Compte non confirmé. Contactez l'administrateur.",
  'Compte non approuvé': "Compte en attente d'approbation. Contactez votre administrateur.",
  'User not found': 'Aucun compte avec cet email.',
  'Too many requests': 'Trop de tentatives. Attendez quelques minutes.',
  'Account pending approval': AccountNotApprovedException.message,
  'Account rejected': 'Compte rejeté. Contactez votre manager.',
  'Authentication failed': 'Email ou mot de passe incorrect.',
};

String _friendlyError(String message) {
  for (final entry in _errorTranslations.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  return message;
}

/// `bg-green-600` du toast de succès (richColors de sonner) — couleur de
/// STATUT, pas de thème, comme dans `register_screen.dart`.
const _green600 = Color(0xFF16A34A);

/// Dernier événement d'expiration déjà annoncé à l'utilisateur : le
/// `StreamProvider` conserve la dernière valeur émise, il faut donc se
/// souvenir de celle qu'on a affichée pour ne pas la répéter à chaque retour
/// sur cet écran (chaque émission crée une nouvelle instance).
AuthEvent? _lastAnnouncedExpiry;

/// Écran `/login` du web (`frontend/app/login/page.tsx` +
/// `frontend/components/auth/login-form.tsx`) : connexion par email + mot de
/// passe, point d'entrée unique de l'app (toutes les redirections non
/// authentifiées y mènent — y compris l'expiration de session, gérée par
/// `AuthNotifier` + `core/router.dart`).
///
/// Fidélité au web :
/// - `noValidate` : AUCUNE validation côté client (ni longueur, ni format
///   d'email) — on peut soumettre vide, l'erreur vient du backend ;
/// - retours utilisateur par toasts (ici SnackBar), table de traduction des
///   erreurs identique ; l'encart d'erreur sous le titre est un complément
///   mobile (un toast se rate facilement) ;
/// - pré-remplissage de l'email depuis `?email=` ;
/// - après succès : toast « Connexion réussie ! » puis accueil selon le rôle
///   (gérant -> tableau de bord, préparateur/livreur -> commandes), que
///   `core/router.dart` applique dès que la session est établie.
///
/// « Mémorisation » : les jetons sont persistés dans le stockage sécurisé
/// dès la connexion (comme `django_tokens` en localStorage) et la session
/// est restaurée au démarrage par `AuthNotifier._bootstrap` ; en plus, les
/// champs sont exposés à l'autofill du système (`autoComplete="email"` /
/// `"current-password"` côté web).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  /// Dernier `?email=` appliqué : `/login` -> `/login?email=x` réutilise la
  /// même page (même clé de route), l'écran n'est donc pas recréé et c'est
  /// `didChangeDependencies` qui voit passer la nouvelle valeur.
  String? _appliedPrefill;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announceSessionExpiry());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `useEffect(() => { const prefill = searchParams.get('email'); … },
    // [searchParams])` : `/login?email=…` pré-remplit l'email (inscription,
    // mot de passe défini, écran d'attente…).
    final prefill = GoRouterState.of(context).uri.queryParameters['email']?.trim() ?? '';
    if (prefill == _appliedPrefill) return;
    _appliedPrefill = prefill;
    if (prefill.isNotEmpty) _emailController.text = prefill;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Retour sur cet écran après un 401 non rafraîchissable (`sessionExpired`
  /// émis par `ApiClient`) : le web redirige en dur vers /login sans un mot ;
  /// on explique à l'utilisateur pourquoi il doit se reconnecter.
  void _announceSessionExpiry() {
    if (!mounted) return;
    final event = ref.read(authEventProvider).value;
    if (event == null || event.kind != AuthEventKind.sessionExpired) return;
    if (identical(event, _lastAnnouncedExpiry)) return;
    _lastAnnouncedExpiry = event;
    setState(() => _error = 'Votre session a expiré. Veuillez vous reconnecter.');
    _toast(_error!, isError: true);
  }

  /// Équivalent des `toast.success` / `toast.error` de `sonner` côté web.
  /// Le messenger racine survit à la navigation : le toast de succès reste
  /// visible sur l'écran d'accueil vers lequel le routeur redirige.
  void _toast(
    String message, {
    required bool isError,
    ScaffoldMessengerState? messenger,
    ColorScheme? scheme,
  }) {
    // Messenger et couleurs capturés AVANT l'appel réseau par [_submit] : le
    // routeur peut avoir remplacé cet écran quand la réponse arrive.
    if ((messenger == null || scheme == null) && !mounted) return;
    scheme ??= Theme.of(context).colorScheme;
    final m = messenger ?? ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: isError ? scheme.onError : Colors.white)),
        backgroundColor: isError ? scheme.error : _green600,
        behavior: SnackBarBehavior.floating,
        // `toastOptions.duration = 5000` + `closeButton` du Toaster global.
        duration: const Duration(seconds: 5),
        showCloseIcon: true,
      ),
    );
  }

  Future<void> _submit() async {
    if (_loading) return;
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Deux requêtes s'enchaînent (login puis /users/me/) sous un seul
      // spinner ; le routeur applique ensuite la destination par rôle.
      await ref.read(authProvider.notifier).login(_emailController.text.trim(), _passwordController.text);
      // Propose au système d'enregistrer les identifiants (autofill).
      TextInput.finishAutofillContext();
      _toast('Connexion réussie !', isError: false, messenger: messenger, scheme: scheme);
    } on AccountNotApprovedException catch (e) {
      // `if (!response.user.is_confirmed)` du web : on reste sur la page (et
      // le repository a purgé les jetons, contrairement au web).
      if (mounted) setState(() => _error = e.toString());
      _toast(e.toString(), isError: true, messenger: messenger, scheme: scheme);
    } catch (e) {
      final raw = ApiClient.messageFromError(e).trim();
      final message = _friendlyError(raw.isEmpty ? 'Erreur de connexion' : raw);
      if (mounted) setState(() => _error = message);
      _toast(message, isError: true, messenger: messenger, scheme: scheme);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Un `sessionExpired` qui arrive alors que l'écran de connexion est DÉJÀ
    // affiché (requête en vol d'un écran précédent, jeton résiduel…) n'a
    // rien à expliquer : on le marque comme vu pour qu'il ne soit pas
    // annoncé à tort lors d'un passage ultérieur sur cet écran.
    ref.listen<AsyncValue<AuthEvent?>>(authEventProvider, (_, next) {
      final event = next.value;
      if (event != null) _lastAnnouncedExpiry = event;
    });

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Configurer le serveur',
            icon: const Icon(Icons.dns_outlined),
            onPressed: _loading ? null : () => context.push('/server-setup'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.phone_iphone, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Connexion',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Accédez à votre espace E-kajy Entana',
                            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                          ),
                          const SizedBox(height: 20),
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline, size: 18, color: theme.colorScheme.onErrorContainer),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Email
                          Text(
                            'Email',
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _emailController,
                            enabled: !_loading,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              hintText: 'vous@example.com',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Mot de passe : libellé à gauche, lien « Mot de
                          // passe oublié ? » à droite sur la MÊME ligne (web).
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Mot de passe',
                                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              // Seul point d'entrée du flux « mot de passe
                              // oublié », comme sur le web : sans ce lien la
                              // route serait orpheline sur mobile.
                              TextButton(
                                onPressed: _loading ? null : () => context.push('/forgot-password'),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  textStyle: theme.textTheme.bodySmall,
                                ),
                                child: const Text('Mot de passe oublié ?'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passwordController,
                            enabled: !_loading,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                // aria-label dynamique du bouton œil web.
                                tooltip: _obscure ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Connexion…'),
                                    ],
                                  )
                                : const Text('Se connecter'),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Pas encore de compte?', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                              TextButton(
                                onPressed: _loading ? null : () => context.push('/register'),
                                child: const Text('Créer un compte'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
