import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../data/repositories/password_repository.dart';
import '../../widgets/async_state_widgets.dart';

/// Couleurs de STATUT reprises des classes Tailwind de la page web
/// (`text-green-700` / `text-orange-700` / `text-red-700`), comme le fait
/// déjà `features/alerts/alerts_screen.dart` — ce ne sont pas des couleurs de
/// thème.
const _green = Color(0xFF15803D);
const _orange = Color(0xFFC2410C);
const _red = Color(0xFFB91C1C);

final _timeFmt = DateFormat('HH:mm:ss');

/// Les 2 écrans de la même carte côté web (`step` = 'request' | 'check').
enum _Step { request, check }

/// Page `/forgot-password` du web
/// (`frontend/app/forgot-password/page.tsx` +
/// `frontend/components/auth/forgot-password-form.tsx`).
///
/// PUBLIC (les 3 endpoints sont `AllowAny`), à câbler HORS du `ShellRoute` et
/// à ajouter aux préfixes publics du routeur.
///
/// Flux en 3 temps SANS aucun email (le projet n'a pas de backend mail) :
/// 1. l'utilisateur envoie une demande, routée vers l'ADMIN de sa société ;
/// 2. il revient vérifier si l'admin l'a approuvée ;
/// 3. une fois approuvée, il définit lui-même son nouveau mot de passe.
///
/// Gating métier appliqué par le backend, pas par l'UI : seuls les comptes
/// `magasin` et `employer` peuvent utiliser ce flux ; un compte `admin`
/// reçoit un 400 « La réinitialisation automatique n'est pas disponible pour
/// les comptes administrateur. Contactez le support technique directement. »
/// que l'on affiche brut, exactement comme le web.
///
/// AJOUT MOBILE (demandé) : le web n'a QUE le bouton manuel « Vérifier le
/// statut » ; ici la vérification est aussi relancée automatiquement toutes
/// les 12 s tant que la demande est `pending`, parce qu'un utilisateur mobile
/// laisse l'écran ouvert en attendant la validation de son admin. Le bouton
/// manuel reste présent et fait toujours exactement la même chose.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const Duration _pollInterval = Duration(seconds: 12);

  final _requestFormKey = GlobalKey<FormState>();
  final _checkFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _Step _step = _Step.request;

  /// Un seul drapeau de chargement partagé par les 3 formulaires — comme le
  /// `loading` unique du composant web (tous les champs et boutons sont
  /// désactivés pendant l'appel).
  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  /// `null` = aucune vérification faite (état initial de l'écran 'check') ;
  /// le bandeau coloré n'est rendu que pour pending/approved/rejected.
  PasswordResetStatus? _status;
  DateTime? _lastCheckedAt;

  Timer? _pollTimer;
  bool _pollInFlight = false;

  bool get _isPolling => _pollTimer != null;

  PasswordRepository get _repo => ref.read(passwordRepositoryProvider);

  @override
  void dispose() {
    _pollTimer?.cancel();
    _emailCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

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

  /// Web : `err.message || '<message par défaut>'`. `messageFromError` sait
  /// déjà extraire la clé `error` utilisée par ces 3 endpoints.
  String _errorMessage(Object error, String fallback) {
    final message = ApiClient.messageFromError(error).trim();
    return message.isEmpty ? fallback : message;
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email requis';
    if (!v.contains('@')) return 'Email invalide';
    return null;
  }

  // -------------------------------------------------------------- polling

  /// Le polling ne tourne QUE sur l'écran 'check' et QUE tant que la demande
  /// est en attente : approuvée ou rejetée, il n'y a plus rien à surveiller.
  void _syncPolling() {
    final shouldPoll = _step == _Step.check &&
        _status == PasswordResetStatus.pending &&
        _emailCtrl.text.trim().isNotEmpty;
    if (shouldPoll) {
      if (_pollTimer == null) {
        _pollTimer = Timer.periodic(_pollInterval, (_) => _pollStatus());
        setState(() {});
      }
    } else if (_pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
      setState(() {});
    }
  }

  void _stopPolling() {
    if (_pollTimer == null) return;
    _pollTimer!.cancel();
    _pollTimer = null;
  }

  /// Vérification SILENCIEUSE : pas de spinner bloquant, et une erreur réseau
  /// ne déclenche aucun message (le bouton manuel reste là pour ça).
  Future<void> _pollStatus() async {
    if (_loading || _pollInFlight) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    _pollInFlight = true;
    try {
      final status = await _repo.forgotPasswordStatus(email);
      if (!mounted) return;
      final previous = _status;
      setState(() {
        _status = status;
        _lastCheckedAt = appNow();
      });
      if (status != previous) {
        if (status == PasswordResetStatus.approved) {
          _snack('Demande validée : vous pouvez définir votre nouveau mot de passe.');
        } else if (status == PasswordResetStatus.rejected) {
          _snack('Votre demande a été rejetée. Contactez votre administrateur.', error: true);
        }
      }
      _syncPolling();
    } catch (_) {
      // Silencieux : voir ci-dessus.
    } finally {
      _pollInFlight = false;
    }
  }

  // ------------------------------------------------------------- actions

  /// FORMULAIRE 1 — `POST users/public/forgot-password/`.
  Future<void> _handleRequest() async {
    if (!_requestFormKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await _repo.forgotPasswordRequest(_emailCtrl.text.trim());
      if (!mounted) return;
      // Web : le statut est forcé à 'pending' localement, sans relire le
      // serveur, et l'écran bascule sur 'check'.
      setState(() {
        _status = PasswordResetStatus.pending;
        _step = _Step.check;
        _lastCheckedAt = null;
      });
      _snack(result.message); // message DU SERVEUR, jamais une constante
      _syncPolling();
    } catch (e) {
      _snack(_errorMessage(e, "Erreur lors de l'envoi de la demande"), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// FORMULAIRE 2 — `GET users/public/forgot-password/status/`.
  Future<void> _handleCheckStatus() async {
    if (!_checkFormKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final status = await _repo.forgotPasswordStatus(_emailCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _status = status;
        _lastCheckedAt = appNow();
      });
      if (status == PasswordResetStatus.none) {
        _snack('Aucune demande trouvée pour cet email.', error: true);
      }
      _syncPolling();
    } catch (e) {
      _snack(_errorMessage(e, 'Erreur lors de la vérification'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// FORMULAIRE 3 — `POST users/public/forgot-password/confirm/`.
  Future<void> _handleSetPassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    // Web : contrôle JS AVANT l'appel, message affiché en toast (aucune
    // erreur inline sur cette page).
    if (_newPasswordCtrl.text != _confirmCtrl.text) {
      _snack('Les mots de passe ne correspondent pas', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await _repo.forgotPasswordConfirm(
        email: _emailCtrl.text.trim(),
        newPassword: _newPasswordCtrl.text,
      );
      if (!mounted) return;
      _stopPolling();
      _snack('Mot de passe défini avec succès. Vous pouvez vous connecter.');
      context.go('/login');
    } catch (e) {
      _snack(_errorMessage(e, 'Erreur lors de la définition du mot de passe'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// « Faire une nouvelle demande » : remet `step` et `status` à zéro mais
  /// CONSERVE l'email saisi (comportement web).
  void _newRequest() {
    _stopPolling();
    setState(() {
      _step = _Step.request;
      _status = null;
      _lastCheckedAt = null;
    });
  }

  /// « Demande déjà envoyée ? Vérifier le statut » : simple bascule d'écran,
  /// AUCUN appel API.
  void _goToCheckStep() {
    setState(() => _step = _Step.check);
    _syncPolling();
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
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
                        Icon(Icons.vpn_key_outlined, size: 22, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mot de passe oublié',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // Description dynamique de la carte (web).
                      _step == _Step.request
                          ? 'Entrez votre email : votre demande sera transmise pour validation.'
                          : 'Vérifiez si votre demande a été validée.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_step == _Step.request) ..._buildRequestStep(theme) else ..._buildCheckStep(theme),
                    const SizedBox(height: 8),
                    const Divider(height: 24),
                    // Lien permanent en bas de carte (web).
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : () => context.go('/login'),
                        child: const Text('Retour à la connexion'),
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

  List<Widget> _buildRequestStep(ThemeData theme) {
    return [
      // Détail UX imposé par la doc de migration : expliquer clairement qu'il
      // n'y a AUCUN email — la validation est manuelle, côté administrateur.
      _InfoNote(
        icon: Icons.info_outline,
        text: "Aucun email n'est envoyé : votre demande est validée manuellement par "
            "votre administrateur. Revenez ensuite ici pour vérifier son statut et "
            "définir votre nouveau mot de passe.",
      ),
      const SizedBox(height: 16),
      Form(
        key: _requestFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtrl,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'vous@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: _validateEmail,
              onFieldSubmitted: (_) => _loading ? null : _handleRequest(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _handleRequest,
              child: _loading
                  ? const _ButtonSpinnerLabel(label: 'Envoyer la demande')
                  : const Text('Envoyer la demande'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Demande déjà envoyée ?',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          TextButton(
            onPressed: _loading ? null : _goToCheckStep,
            child: const Text('Vérifier le statut'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildCheckStep(ThemeData theme) {
    final status = _status;
    return [
      Form(
        key: _checkFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtrl,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'vous@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: _validateEmail,
              onFieldSubmitted: (_) => _loading ? null : _handleCheckStatus(),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loading ? null : _handleCheckStatus,
              child: _loading
                  ? const _ButtonSpinnerLabel(label: 'Vérifier le statut')
                  : const Text('Vérifier le statut'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // Bandeau de statut : rendu UNIQUEMENT pour pending/approved/rejected
      // (le web masque volontairement le bandeau quand le statut vaut 'none').
      if (status != null && status != PasswordResetStatus.none)
        _StatusBanner(status: status)
      else if (status == PasswordResetStatus.none)
        // 'none' : pas de bandeau coloré côté web, seulement un toast. Sur
        // mobile un toast se rate facilement — on garde donc l'état vide
        // partagé du projet, avec le message exact.
        const EmptyState(
          message: 'Aucune demande trouvée pour cet email.',
          icon: Icons.search_off,
        )
      else
        const EmptyState(
          message: 'Aucune vérification effectuée pour le moment. Renseignez votre email '
              'puis touchez « Vérifier le statut ».',
          icon: Icons.help_outline,
        ),
      if (_isPolling || _lastCheckedAt != null) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            if (_isPolling) ...[
              const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                [
                  if (_isPolling) 'Vérification automatique toutes les 12 s',
                  if (_lastCheckedAt != null) 'Dernière vérification à ${_timeFmt.format(_lastCheckedAt!)}',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
      // Sous-formulaire visible UNIQUEMENT si la demande est approuvée.
      if (status == PasswordResetStatus.approved) ...[
        const Divider(height: 28),
        Form(
          key: _passwordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _newPasswordCtrl,
                enabled: !_loading,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  // Ajout mobile (le web n'a pas de bouton œil ici) : saisir
                  // un mot de passe à l'aveugle au clavier tactile est une
                  // source d'erreurs. Aucune information ni action perdue.
                  suffixIcon: IconButton(
                    tooltip: _obscureNew ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                    icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Mot de passe requis';
                  // `minLength={6}` côté web + contrôle backend.
                  if (v.length < 6) return 'Le mot de passe doit contenir au moins 6 caractères';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmCtrl,
                enabled: !_loading,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmer',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirm ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                    icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                // Pas de longueur minimale ici (web), juste `required` : la
                // non-correspondance est signalée par un message, pas inline.
                validator: (v) => (v == null || v.isEmpty) ? 'Confirmation requise' : null,
                onFieldSubmitted: (_) => _loading ? null : _handleSetPassword(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _handleSetPassword,
                child: _loading
                    ? const _ButtonSpinnerLabel(label: 'Définir le mot de passe')
                    : const Text('Définir le mot de passe'),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _loading ? null : _newRequest,
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Faire une nouvelle demande'),
        ),
      ),
    ];
  }
}

/// Bouton en cours d'envoi : spinner à gauche, libellé INCHANGÉ (web).
class _ButtonSpinnerLabel extends StatelessWidget {
  const _ButtonSpinnerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Bandeau coloré des 3 statuts, avec les textes et les icônes exacts du web.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final PasswordResetStatus status;

  Color get _color => switch (status) {
        PasswordResetStatus.approved => _green,
        PasswordResetStatus.rejected => _red,
        _ => _orange,
      };

  IconData get _icon => switch (status) {
        PasswordResetStatus.approved => Icons.check_circle_outline,
        PasswordResetStatus.rejected => Icons.cancel_outlined,
        _ => Icons.schedule,
      };

  String get _text => switch (status) {
        PasswordResetStatus.approved =>
          'Demande validée : vous pouvez définir votre nouveau mot de passe.',
        PasswordResetStatus.rejected =>
          'Votre demande a été rejetée. Contactez votre administrateur.',
        _ => 'En attente de validation par votre administrateur.',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.10),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 18, color: _color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _text,
              style: TextStyle(color: _color, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encart d'explication neutre (fond `surfaceContainerHighest`).
class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
