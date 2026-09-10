import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/permissions.dart';
import '../../data/repositories/password_repository.dart';
import '../../state/auth_provider.dart';
import '../../widgets/async_state_widgets.dart';

/// Couleur de STATUT reprise de Tailwind (`text-orange-700`) pour l'avis de
/// restriction, comme dans `features/alerts/alerts_screen.dart`.
const _orange = Color(0xFFC2410C);
const _green = Color(0xFF15803D);

/// Page `/reset-password` du web (`frontend/app/reset-password/page.tsx` +
/// `frontend/components/auth/reset-password-form.tsx`).
///
/// Malgré son nom, ce n'est PAS une réinitialisation par lien/token : c'est
/// le changement de mot de passe d'un compte CONNECTÉ qui connaît son
/// ancien mot de passe (le vrai « mot de passe oublié » est
/// `ForgotPasswordScreen`).
///
/// Gating : le web n'a aucun garde côté page, mais le backend réserve
/// `POST /users/change-password/` aux rôles `admin` et `magasin`
/// (`isGerant` de `core/permissions.dart`) et répond 403
/// [kChangePasswordForbiddenMessage] aux autres. On prévient donc
/// l'utilisateur AVANT l'appel avec un bandeau — sans jamais bloquer le
/// bouton, pour ne pas transformer un rôle mal rafraîchi en refus définitif :
/// c'est le serveur qui tranche, et son message est affiché tel quel.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Équivalent des `toast.success` / `toast.error` de `sonner` côté web.
  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : _green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Web : seule validation JS de la page, en toast, avant tout appel.
    if (_newCtrl.text != _confirmCtrl.text) {
      _snack('Les mots de passe ne correspondent pas', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(passwordRepositoryProvider).changePassword(
            oldPassword: _oldCtrl.text,
            newPassword: _newCtrl.text,
          );
      if (!mounted) return;
      _oldCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
      _snack('Mot de passe changé avec succès');
      // Le web fait `router.push('/login')` SANS purger les jetons : sur
      // mobile, un utilisateur encore authentifié serait immédiatement
      // renvoyé sur son accueil par la garde de `core/router.dart`, et la
      // redirection ne se verrait jamais. On ferme donc la session pour
      // obtenir le MÊME résultat visible (retour à l'écran de connexion),
      // avec en prime un vrai contrôle du nouveau mot de passe. Le message
      // sous le bouton prévient l'utilisateur avant qu'il ne valide.
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      final message = ApiClient.messageFromError(e).trim();
      _snack(message.isEmpty ? 'Erreur lors du changement' : message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    // Équivalent du `<Suspense fallback={...}>` de la page web (carte
    // « Chargement... » avec spinner) : ici, la session en cours de
    // restauration.
    if (auth.status == AuthStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Changer le mot de passe')),
        body: const LoadingState(),
      );
    }

    // Le web ne garde pas la page : l'appel part sans en-tête Authorization
    // et finit en 401 puis en redirection dure vers /login. On rend l'état
    // explicite plutôt que de laisser un formulaire condamné à échouer.
    if (auth.status != AuthStatus.authenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Changer le mot de passe')),
        body: Column(
          children: [
            const Expanded(
              child: ErrorState(
                message: 'Vous devez être connecté pour changer votre mot de passe.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: () => context.go('/login'),
                child: const Text('Se connecter'),
              ),
            ),
          ],
        ),
      );
    }

    final user = auth.user;
    // `isGerant` = role admin || magasin — exactement le test du backend.
    final isGerant = user != null && user.isGerant;

    return Scaffold(
      appBar: AppBar(title: const Text('Changer le mot de passe')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_outline, size: 22, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Changer le mot de passe',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Entrez votre mot de passe actuel et votre nouveau mot de passe',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!isGerant) ...[
                      const SizedBox(height: 16),
                      _WarningNote(text: kChangePasswordForbiddenMessage),
                    ],
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _oldCtrl,
                            obscureText: _obscureOld,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Mot de passe actuel',
                              prefixIcon: const Icon(Icons.lock_outline),
                              // Ajout mobile : le web n'a aucun bouton œil sur
                              // cette page, mais saisir 3 mots de passe à
                              // l'aveugle au clavier tactile est une source
                              // d'erreurs. Rien n'est retiré par ailleurs.
                              suffixIcon: IconButton(
                                tooltip: _obscureOld ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                                icon: Icon(_obscureOld
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscureOld = !_obscureOld),
                              ),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Mot de passe actuel requis' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _newCtrl,
                            obscureText: _obscureNew,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: 'Nouveau mot de passe',
                              prefixIcon: const Icon(Icons.lock_reset),
                              suffixIcon: IconButton(
                                tooltip: _obscureNew ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                                icon: Icon(_obscureNew
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscureNew = !_obscureNew),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Nouveau mot de passe requis';
                              // `minLength={6}` côté web + contrôle backend
                              // (400 « Le mot de passe doit contenir au moins
                              // 6 caractères »).
                              if (v.length < 6) {
                                return 'Le mot de passe doit contenir au moins 6 caractères';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscureConfirm,
                            decoration: InputDecoration(
                              labelText: 'Confirmer',
                              prefixIcon: const Icon(Icons.lock_reset),
                              suffixIcon: IconButton(
                                tooltip: _obscureConfirm
                                    ? 'Afficher le mot de passe'
                                    : 'Masquer le mot de passe',
                                icon: Icon(_obscureConfirm
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                              ),
                            ),
                            // Pas de longueur minimale sur la confirmation
                            // (web) : la non-correspondance est signalée par
                            // un message, pas par une erreur inline.
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Confirmation requise' : null,
                            onFieldSubmitted: (_) => _loading ? null : _submit(),
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            // Web : le libellé devient 'Changement...' et le
                            // bouton est désactivé — PAS de spinner ici.
                            child: Text(_loading ? 'Changement...' : 'Changer le mot de passe'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Après le changement, vous serez déconnecté et devrez vous reconnecter '
                      'avec votre nouveau mot de passe.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bandeau d'avertissement (restriction de rôle), aux couleurs de statut du
/// web plutôt qu'à celles du thème.
class _WarningNote extends StatelessWidget {
  const _WarningNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.10),
        border: Border.all(color: _orange.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: _orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _orange, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
