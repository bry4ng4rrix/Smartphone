import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Écran `/verify-email` du web (`frontend/app/verify-email/page.tsx`) :
/// page d'information 100% STATIQUE — aucun guard, aucun state, aucun appel
/// API, aucun bouton « Renvoyer l'email ».
///
/// Note métier reprise de la doc de migration : le produit ne vérifie PAS les
/// emails (aucun backend mail n'est configuré), il fonctionne par approbation
/// manuelle de l'administrateur — cette route est orpheline côté web
/// (l'inscription renvoie sur la page d'attente d'approbation). Elle est
/// portée à l'identique pour ne rien perdre, et reste atteignable directement.
class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    // Pastille ronde `bg-primary/10` + icône Mail.
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.email_outlined,
                            size: 32, color: theme.colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Vérifiez votre email',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Un lien de confirmation vous a été envoyé.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Veuillez cliquer sur le lien dans l\'email pour activer votre compte. '
                      'Si vous ne le voyez pas, vérifiez vos courriers indésirables.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Retour à la connexion'),
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
