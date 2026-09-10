import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/secure_storage.dart';
import '../../state/auth_provider.dart';

/// Palette « attente » du web (classes Tailwind amber), variantes sombres
/// incluses — ce sont des couleurs de STATUT, pas des couleurs de thème.
const _amber50 = Color(0xFFFFFBEB);
const _amber100 = Color(0xFFFEF3C7);
const _amber200 = Color(0xFFFDE68A);
const _amber400 = Color(0xFFFBBF24);
const _amber600 = Color(0xFFD97706);
const _amber800 = Color(0xFF92400E);
const _amber900 = Color(0xFF78350F);
const _amber950 = Color(0xFF451A03);

/// Écran d'attente d'approbation — UNIFIE les deux pages web qui font double
/// emploi (recommandation explicite de la doc de migration) :
///
/// - `frontend/app/auth/pending-approval/page.tsx` : version détaillée, page
///   d'arrivée RÉELLE après une inscription réussie — encadré ambre
///   « Qu'est-ce qui se passe maintenant? » + liste numérotée en 3 étapes +
///   délai indicatif + bouton « Retour à la connexion ».
/// - `frontend/app/pending-approval/page.tsx` : version courte — paragraphe
///   « Merci de votre patience… », bouton « Actualiser la page » et bouton
///   « Se déconnecter » (SEUL endroit du web qui pointe vers /logout).
///
/// Tout le contenu et TOUTES les actions des deux pages sont ici : rien n'est
/// perdu à la fusion. Le web n'a aucun polling du statut — on garde ce
/// principe, mais le bouton « Actualiser la page » du web était un simple
/// lien vers /login (libellé trompeur signalé par la doc) : ici il fait une
/// VRAIE re-vérification quand une session existe encore, et retombe sur
/// l'écran de connexion sinon (un compte non approuvé ne peut de toute façon
/// pas obtenir de token : `CustomTokenObtainPairSerializer` refuse la
/// connexion tant que `is_confirmed` est faux).
class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  bool _busy = false;

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// « Actualiser la page » : relit le profil si une session existe (compte
  /// approuvé entre-temps -> `authProvider` repasse en `authenticated` et
  /// `core/router.dart` renvoie l'utilisateur sur son accueil), sinon renvoie
  /// vers la connexion, exactement comme le lien du web.
  Future<void> _refreshStatus() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final token = await TokenStorage.instance.accessToken;
      if (token != null && token.isNotEmpty) {
        await ref.read(authProvider.notifier).refreshUser();
        if (!mounted) return;
        if (ref.read(authProvider).status == AuthStatus.authenticated) {
          _snack('Compte approuvé — accès ouvert.');
          return;
        }
      }
      if (!mounted) return;
      _snack("Toujours en attente d'approbation. Réessayez de vous connecter plus tard.");
      context.go('/login');
    } catch (e) {
      if (mounted) _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Équivalent du lien `/logout` du web : purge la session locale puis
  /// renvoie sur la connexion.
  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).logout();
    } catch (e) {
      if (mounted) _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Pastille ronde ambre + icône horloge (= attente).
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: isDark ? _amber950 : _amber100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.schedule,
                          size: 32,
                          color: isDark ? _amber400 : _amber600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "En attente d'approbation",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Votre compte doit être approuvé par un administrateur.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 20),
                    _buildInfoBox(theme, isDark),
                    const SizedBox(height: 16),
                    Text(
                      "Le processus d'approbation peut prendre quelques minutes à quelques "
                      "heures selon la disponibilité de l'administrateur.",
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 10),
                    // Paragraphe de la version courte de la page web.
                    Text(
                      'Merci de votre patience. Un administrateur examine actuellement votre '
                      'demande. Vous recevrez un accès complet dès que votre compte sera approuvé.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _refreshStatus,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Actualiser la page'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : () => context.go('/login'),
                      child: const Text('Retour à la connexion'),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _busy ? null : _logout,
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Se déconnecter'),
                      style: TextButton.styleFrom(foregroundColor: muted),
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

  /// Encadré ambre « Qu'est-ce qui se passe maintenant? » + les 3 étapes du
  /// processus, numérotées comme sur le web.
  Widget _buildInfoBox(ThemeData theme, bool isDark) {
    final titleColor = isDark ? _amber100 : _amber900;
    final bodyColor = isDark ? _amber200 : _amber800;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? _amber950.withValues(alpha: 0.4) : _amber50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? _amber800 : _amber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.email_outlined, size: 16, color: titleColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "Qu'est-ce qui se passe maintenant?",
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: titleColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _step(theme, bodyColor, '1.', "Un administrateur examinera votre demande d'inscription"),
          const SizedBox(height: 8),
          _step(theme, bodyColor, '2.', 'Vous recevrez une notification par email une fois approuvé'),
          const SizedBox(height: 8),
          _step(theme, bodyColor, '3.', 'Vous pourrez vous connecter avec vos identifiants'),
        ],
      ),
    );
  }

  Widget _step(ThemeData theme, Color color, String number, String label) {
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(number, style: style?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: style)),
      ],
    );
  }
}
