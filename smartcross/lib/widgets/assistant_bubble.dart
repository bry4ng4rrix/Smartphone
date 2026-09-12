import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/permissions.dart';
import '../data/repositories/assistant_repository.dart';
import '../state/auth_provider.dart';

/// Assistant de l'application — bulle flottante en bas à droite, portage de
/// `frontend/components/assistant-bubble.tsx` (montée sur TOUTES les pages
/// de l'app par le layout web, `app/(app)/layout.tsx`).
///
/// Usages, identiques au web :
///
///  * répondre aux questions sur le fonctionnement de l'app, à partir du
///    mode d'emploi tenu dans `frontend/app/api/ai/assistant/route.ts` ;
///  * créer une commande dictée en une phrase (gérant, préparateur) ;
///  * mettre à jour les stocks depuis un fichier Excel joint (gérant) ;
///  * rédiger un rapport commenté des 30 derniers jours (gérant).
///
/// Toute action est d'abord présentée sous forme de récapitulatif : rien
/// n'est écrit avant que l'utilisateur ne touche « Confirmer ». Le modèle
/// tourne en local sur le VPS (Ollama) : rien ne part vers un service tiers.
///
/// Le réseau passe par [AssistantRepository] (qui documente la dépendance au
/// site web Next.js, seul hébergeur de la route) via [assistantProvider] —
/// le widget ne fait aucun appel HTTP.
///
/// ## Montage
///
/// À poser PAR-DESSUS le contenu du shell, dans un `Stack` :
///
/// ```dart
/// Stack(fit: StackFit.expand, children: [child, const AssistantBubble()])
/// ```
///
/// Le widget se cale lui-même en bas à droite ([Align]) et laisse passer
/// les touches en dehors de la bulle. Plusieurs écrans ont déjà un
/// `FloatingActionButton` en bas à droite (Commandes, Produits, Alertes,
/// Fournisseurs, Dépôt) : le bouton d'ouverture est donc décalé au-dessus
/// de la hauteur d'un FAB par défaut ([launcherMargin]) ; le panneau ouvert,
/// lui, recouvre la page depuis le coin ([panelMargin]), comme sur le web.
class AssistantBubble extends ConsumerStatefulWidget {
  const AssistantBubble({
    super.key,
    this.launcherMargin = const EdgeInsets.only(right: 16, bottom: 84),
    this.panelMargin = const EdgeInsets.all(16),
  });

  /// Marge du bouton rond d'ouverture (bulle fermée).
  final EdgeInsets launcherMargin;

  /// Marge du panneau (bulle ouverte).
  final EdgeInsets panelMargin;

  @override
  ConsumerState<AssistantBubble> createState() => _AssistantBubbleState();
}

// -----------------------------------------------------------------------------
// Conversation (état + actions) — `useState` de la bulle web, tenu dans un
// provider pour survivre aux reconstructions du shell et pour que les appels
// réseau vivent hors du widget.
// -----------------------------------------------------------------------------

final assistantRepositoryProvider = Provider((ref) => AssistantRepository());

/// `SUGGESTIONS` du web — questions proposées tant que la conversation est
/// vide ; un appui envoie la question telle quelle.
const List<String> kAssistantSuggestions = [
  'Comment créer une commande ?',
  'À quelle heure le livreur peut-il livrer ?',
  'Comment valider une dépense de livreur ?',
  'Que se passe-t-il si le client refuse un article ?',
];

/// `EXEMPLE_COMMANDE` du web — un appui pré-remplit la saisie (sans envoyer).
const String kAssistantExempleCommande =
    'Crée une commande pour Rakoto 034 12 345 67, 2 coques iPhone 13 noires, zone 2, lot II B 45 Ivandry, paiement à la livraison';

/// Nombre de jours couverts par « Générer le rapport du mois » (J−29 … J).
const int kAssistantJoursRapport = 30;

enum AssistantRole { user, assistant }

/// Décision prise sur une proposition jointe à un message de l'assistant.
enum AssistantDecision { confirmee, annulee }

/// `Message` du web.
class AssistantMessage {
  const AssistantMessage({required this.role, required this.texte, this.proposition, this.decision});

  final AssistantRole role;
  final String texte;

  /// Action à confirmer, jointe à un message de l'assistant.
  final AssistantProposition? proposition;
  final AssistantDecision? decision;

  bool get estUtilisateur => role == AssistantRole.user;

  AssistantMessage copyWith({AssistantDecision? decision}) => AssistantMessage(
        role: role,
        texte: texte,
        proposition: proposition,
        decision: decision ?? this.decision,
      );
}

/// `messages` + `enCours` de la bulle web.
class AssistantConversation {
  const AssistantConversation({this.messages = const [], this.enCours = false});

  final List<AssistantMessage> messages;

  /// Une requête est en cours : saisie, envoi, suggestions, Confirmer /
  /// Annuler et « Générer le rapport du mois » sont désactivés.
  final bool enCours;

  AssistantConversation copyWith({List<AssistantMessage>? messages, bool? enCours}) =>
      AssistantConversation(messages: messages ?? this.messages, enCours: enCours ?? this.enCours);
}

/// Les trois actions de la bulle web : `envoyer`, `decider`, `genererRapport`.
/// Les textes d'échec sont ceux du web ; quand la cause est le site web
/// (Next.js) injoignable, l'explication de [AssistantIndisponibleException]
/// est ajoutée à la suite pour que le gérant sache quoi déployer.
class AssistantNotifier extends Notifier<AssistantConversation> {
  late final AssistantRepository _repo = ref.read(assistantRepositoryProvider);

  /// Incrémenté à chaque remise à zéro : une requête partie sous l'ancien
  /// compte n'écrit plus dans la conversation du nouveau.
  int _generation = 0;

  @override
  AssistantConversation build() {
    // Changement de compte (ou déconnexion) : conversation vierge — le web
    // repart aussi de zéro, sa bulle étant démontée avec le layout.
    ref.listen(
      authProvider.select((a) => a.status == AuthStatus.authenticated ? a.user?.id : null),
      (previous, next) {
        if (previous != next) _reinitialiser();
      },
    );
    return const AssistantConversation();
  }

  void _reinitialiser() {
    _generation++;
    state = const AssistantConversation();
  }

  bool _actif(int generation) => ref.mounted && generation == _generation;

  void _ajouter(AssistantMessage message) => state = state.copyWith(messages: [...state.messages, message]);

  void _ajouterAssistant(String texte, {AssistantProposition? proposition}) =>
      _ajouter(AssistantMessage(role: AssistantRole.assistant, texte: texte, proposition: proposition));

  String _messageEchec(String base, Object error) =>
      error is AssistantIndisponibleException ? '$base\n\n${error.message}' : base;

  /// `envoyer(texte, piece)` : question, commande dictée ou fichier Excel.
  /// Sans texte ni fichier, ou pendant une requête : rien.
  Future<void> envoyer(String texte, {PlatformFile? fichier}) async {
    final propre = texte.trim();
    if ((propre.isEmpty && fichier == null) || state.enCours) return;
    final generation = _generation;
    _ajouter(AssistantMessage(
      role: AssistantRole.user,
      texte: fichier != null ? '${propre.isNotEmpty ? '$propre\n' : ''}📎 ${fichier.name}' : texte,
    ));
    state = state.copyWith(enCours: true);
    try {
      final AssistantReply reponse;
      if (fichier != null) {
        final bytes = await fichier.readAsBytes();
        reponse = await _repo.fichierStocks(bytes: bytes, filename: fichier.name, question: texte);
      } else {
        reponse = await _repo.question(texte);
      }
      if (!_actif(generation)) return;
      _ajouterAssistant(reponse.reponse, proposition: reponse.proposition);
    } catch (e) {
      if (!_actif(generation)) return;
      _ajouterAssistant(_messageEchec("Je n'ai pas pu répondre. Réessayez.", e));
    } finally {
      if (_actif(generation)) state = state.copyWith(enCours: false);
    }
  }

  /// `decider(index, decision)` : Confirmer / Annuler la proposition jointe
  /// au message [index]. Annuler n'appelle personne ; Confirmer renvoie la
  /// proposition telle quelle au mode « executer ».
  Future<void> decider(int index, AssistantDecision decision) async {
    if (state.enCours) return;
    if (index < 0 || index >= state.messages.length) return;
    final message = state.messages[index];
    final proposition = message.proposition;
    if (proposition == null || message.decision != null) return;
    final generation = _generation;

    final messages = [...state.messages];
    messages[index] = message.copyWith(decision: decision);
    state = state.copyWith(messages: messages);

    if (decision == AssistantDecision.annulee) {
      _ajouterAssistant("D'accord, j'annule. Rien n'a été modifié.");
      return;
    }
    state = state.copyWith(enCours: true);
    try {
      final reponse = await _repo.executer(proposition);
      if (!_actif(generation)) return;
      _ajouterAssistant(reponse.reponse);
    } catch (e) {
      if (!_actif(generation)) return;
      _ajouterAssistant(
        _messageEchec("Je n'ai pas pu exécuter l'action. Vérifiez dans l'application avant de réessayer.", e),
      );
    } finally {
      if (_actif(generation)) state = state.copyWith(enCours: false);
    }
  }

  /// `genererRapport()` : les chiffres des 30 derniers jours sont d'abord
  /// demandés à l'API (`GET orders/reports/`, gérant uniquement), puis
  /// donnés au modèle en mode « rapport ». C'est le serveur qui agrège —
  /// l'app ne fait que transmettre.
  Future<void> genererRapport() async {
    if (state.enCours) return;
    final generation = _generation;
    _ajouter(AssistantMessage(
      role: AssistantRole.user,
      texte: 'Génère le rapport des $kAssistantJoursRapport derniers jours.',
    ));
    state = state.copyWith(enCours: true);
    try {
      final rapport = await _repo.chiffresDerniersJours(kAssistantJoursRapport);
      final reponse = await _repo.rapport(rapport);
      if (!_actif(generation)) return;
      _ajouterAssistant(reponse.reponse);
    } catch (e) {
      if (!_actif(generation)) return;
      _ajouterAssistant(_messageEchec("Je n'ai pas pu récupérer les chiffres de la période.", e));
    } finally {
      if (_actif(generation)) state = state.copyWith(enCours: false);
    }
  }
}

/// Conversation de la bulle — conservée tant que l'app tourne (comme la
/// bulle web, qui survit aux changements de page), remise à zéro au
/// changement de compte.
final assistantProvider = NotifierProvider<AssistantNotifier, AssistantConversation>(AssistantNotifier.new);

// -----------------------------------------------------------------------------
// Widget
// -----------------------------------------------------------------------------

/// Largeur et hauteur maximales du panneau — `w-[min(380px,…)]`,
/// `max-h-[min(600px,…)]` du web.
const double _kPanelMaxWidth = 380;
const double _kPanelMaxHeight = 600;

/// `flex-1 overflow-auto` du web : la bulle vit dans la zone de contenu.
class _AssistantBubbleState extends ConsumerState<AssistantBubble> {
  bool _ouvert = false;
  final TextEditingController _question = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Fichier Excel choisi via le trombone, en attente d'envoi (gérant).
  PlatformFile? _fichier;

  @override
  void initState() {
    super.initState();
    // Le bouton Envoyer dépend du contenu de la saisie.
    _question.addListener(_onQuestionChanged);
  }

  void _onQuestionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _question.removeListener(_onQuestionChanged);
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// `finRef.current?.scrollIntoView({behavior: 'smooth'})` à chaque
  /// nouveau message et à chaque changement d'« en cours ».
  void _defilerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _ouvrir() {
    setState(() => _ouvert = true);
    _defilerEnBas();
  }

  void _fermer() => setState(() => _ouvert = false);

  /// Envoi de la saisie courante (avec le fichier joint le cas échéant), ou
  /// d'une suggestion [texte]. Comme le web, la saisie et le fichier sont
  /// vidés dès l'envoi, quelle que soit l'issue.
  void _envoyer([String? texte]) {
    final conversation = ref.read(assistantProvider);
    final question = texte ?? _question.text;
    final fichier = texte == null ? _fichier : null;
    if ((question.trim().isEmpty && fichier == null) || conversation.enCours) return;
    ref.read(assistantProvider.notifier).envoyer(question, fichier: fichier);
    _question.clear();
    setState(() => _fichier = null);
  }

  /// Trombone : fichier Excel de stocks (`accept=".xlsx,.xls"`).
  Future<void> _choisirFichier() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir le sélecteur de fichiers.")),
        );
      }
      return;
    }
    if (picked == null || !mounted) return; // Annulé par l'utilisateur.
    setState(() => _fichier = picked);
  }

  void _retirerFichier() => setState(() => _fichier = null);

  /// Bouton « Exemple : … » : pré-remplit la saisie, curseur à la fin.
  void _remplirExemple() {
    _question.value = const TextEditingValue(
      text: kAssistantExempleCommande,
      selection: TextSelection.collapsed(offset: kAssistantExempleCommande.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    // Pas d'assistant pour un visiteur non connecté : il n'a ni page ni
    // données.
    if (auth.status != AuthStatus.authenticated || user == null) return const SizedBox.shrink();

    ref.listen<AssistantConversation>(assistantProvider, (previous, next) {
      if (previous == null || previous.messages.length != next.messages.length || previous.enCours != next.enCours) {
        _defilerEnBas();
      }
    });

    if (!_ouvert) {
      return Align(
        alignment: Alignment.bottomRight,
        child: SafeArea(
          top: false,
          left: false,
          child: Padding(
            padding: widget.launcherMargin,
            child: FloatingActionButton(
              // Tag distinct : plusieurs écrans ont leur propre FAB (tag par
              // défaut) dans le même sous-arbre.
              heroTag: 'assistant_bubble_launcher',
              shape: const CircleBorder(),
              tooltip: "Ouvrir l'assistant",
              onPressed: _ouvrir,
              child: const Icon(Icons.smart_toy_outlined),
            ),
          ),
        ),
      );
    }

    final conversation = ref.watch(assistantProvider);
    final isGerant = user.isGerant;
    final peutCommander = isGerant || user.isPreparateur;

    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        top: false,
        left: false,
        child: Padding(
          padding: widget.panelMargin,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? math.min(_kPanelMaxWidth, constraints.maxWidth)
                  : _kPanelMaxWidth;
              final maxHeight = constraints.maxHeight.isFinite
                  ? math.min(_kPanelMaxHeight, constraints.maxHeight)
                  : _kPanelMaxHeight;
              return _panneau(
                context,
                conversation: conversation,
                isGerant: isGerant,
                peutCommander: peutCommander,
                width: width,
                maxHeight: maxHeight,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _panneau(
    BuildContext context, {
    required AssistantConversation conversation,
    required bool isGerant,
    required bool peutCommander,
    required double width,
    required double maxHeight,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _entete(context, peutCommander: peutCommander),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(12),
                  children: _corps(
                    context,
                    conversation: conversation,
                    isGerant: isGerant,
                    peutCommander: peutCommander,
                    largeurMessage: (width - 24) * 0.85,
                  ),
                ),
              ),
              const Divider(height: 1),
              _pied(context, conversation: conversation, isGerant: isGerant, peutCommander: peutCommander),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entete(BuildContext context, {required bool peutCommander}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.smart_toy_outlined, size: 16, color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Assistant', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  peutCommander ? 'Guide et actions' : "Guide de l'application",
                  style: text.bodySmall?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Fermer l'assistant",
            icon: const Icon(Icons.close, size: 18),
            onPressed: _fermer,
          ),
        ],
      ),
    );
  }

  List<Widget> _corps(
    BuildContext context, {
    required AssistantConversation conversation,
    required bool isGerant,
    required bool peutCommander,
    required double largeurMessage,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final messages = conversation.messages;
    return [
      if (messages.isEmpty) ...[
        Text(
          "Posez-moi une question sur l'application — les rôles, le parcours d'une commande, les dépenses, les bilans…",
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final suggestion in kAssistantSuggestions) ...[
          _SuggestionButton(
            label: suggestion,
            onTap: conversation.enCours ? null : () => _envoyer(suggestion),
          ),
          const SizedBox(height: 6),
        ],
        if (peutCommander) ...[
          const SizedBox(height: 6),
          Text(
            'Je peux aussi créer une commande que vous me dictez'
            '${isGerant ? ', ou mettre à jour les stocks depuis un fichier Excel (trombone)' : ''}. '
            'Je vous montre toujours un récapitulatif avant d\'agir.',
            style: muted,
          ),
          const SizedBox(height: 6),
          _SuggestionButton(
            label: 'Exemple : $kAssistantExempleCommande',
            muted: true,
            onTap: _remplirExemple,
          ),
        ],
      ],
      for (var i = 0; i < messages.length; i++) ...[
        _MessageBubble(
          message: messages[i],
          maxWidth: largeurMessage,
          enCours: conversation.enCours,
          onDecider: (decision) => ref.read(assistantProvider.notifier).decider(i, decision),
        ),
        const SizedBox(height: 10),
      ],
      if (conversation.enCours)
        Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('Un instant…', style: muted),
          ],
        ),
    ];
  }

  Widget _pied(
    BuildContext context, {
    required AssistantConversation conversation,
    required bool isGerant,
    required bool peutCommander,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final enCours = conversation.enCours;
    final fichier = _fichier;
    final peutEnvoyer = !enCours && (_question.text.trim().isNotEmpty || fichier != null);
    final String placeholder;
    if (fichier != null) {
      placeholder = 'Message (facultatif)…';
    } else if (peutCommander) {
      placeholder = 'Question ou commande à créer…';
    } else {
      placeholder = 'Votre question…';
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isGerant) ...[
            OutlinedButton.icon(
              onPressed: enCours ? null : () => ref.read(assistantProvider.notifier).genererRapport(),
              icon: const Icon(Icons.summarize_outlined, size: 18),
              label: const Text('Générer le rapport du mois'),
            ),
            const SizedBox(height: 8),
          ],
          if (fichier != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.table_chart_outlined, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fichier.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _retirerFichier,
                    child: const Tooltip(
                      message: 'Retirer le fichier',
                      child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 14)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isGerant) ...[
                IconButton.outlined(
                  tooltip: 'Joindre un fichier Excel de stocks',
                  icon: const Icon(Icons.attach_file, size: 18),
                  onPressed: enCours ? null : _choisirFichier,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: TextField(
                  controller: _question,
                  enabled: !enCours,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _envoyer(),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Envoyer',
                onPressed: peutEnvoyer ? () => _envoyer() : null,
                icon: enCours
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bouton de suggestion (bordure, texte à gauche, xs) ; [muted] pour le
/// bouton « Exemple : … » (bordure pointillée grise sur le web).
class _SuggestionButton extends StatelessWidget {
  const _SuggestionButton({required this.label, required this.onTap, this.muted = false});

  final String label;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: muted ? scheme.outline.withValues(alpha: 0.5) : scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: muted ? scheme.onSurfaceVariant : scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

/// Une bulle de message : à droite (fond primaire) pour l'utilisateur, à
/// gauche (fond neutre) pour l'assistant, avec la carte de proposition le
/// cas échéant.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.maxWidth,
    required this.enCours,
    required this.onDecider,
  });

  final AssistantMessage message;
  final double maxWidth;
  final bool enCours;
  final void Function(AssistantDecision decision) onDecider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final utilisateur = message.estUtilisateur;
    final texteStyle = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: utilisateur ? scheme.onPrimary : scheme.onSurface,
    );
    final proposition = message.proposition;
    return Align(
      alignment: utilisateur ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: utilisateur ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (utilisateur)
                Text(message.texte, style: texteStyle)
              else
                SelectableText(message.texte, style: texteStyle),
              if (proposition != null)
                _PropositionCard(
                  proposition: proposition,
                  decision: message.decision,
                  enCours: enCours,
                  onDecider: onDecider,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Récapitulatif d'une action proposée, avec Confirmer / Annuler tant
/// qu'aucune décision n'est prise, puis « Confirmé » / « Annulé ».
class _PropositionCard extends StatelessWidget {
  const _PropositionCard({
    required this.proposition,
    required this.decision,
    required this.enCours,
    required this.onDecider,
  });

  final AssistantProposition proposition;
  final AssistantDecision? decision;
  final bool enCours;
  final void Function(AssistantDecision decision) onDecider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final petit = ButtonStyle(
      visualDensity: VisualDensity.compact,
      minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                proposition.estCommande ? Icons.check : Icons.table_chart_outlined,
                size: 14,
                color: scheme.onSurface,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  proposition.titre,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final ligne in proposition.resume)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(ligne, style: TextStyle(fontSize: 12, color: scheme.onSurface)),
            ),
          if (decision != null)
            Text(
              decision == AssistantDecision.confirmee ? 'Confirmé' : 'Annulé',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  FilledButton(
                    style: petit,
                    onPressed: enCours ? null : () => onDecider(AssistantDecision.confirmee),
                    child: const Text('Confirmer'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: petit,
                    onPressed: enCours ? null : () => onDecider(AssistantDecision.annulee),
                    child: const Text('Annuler'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
