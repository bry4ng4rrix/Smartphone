import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_time.dart';
import '../../core/chat_socket_service.dart';
import '../../models/chat.dart';
import '../../state/auth_provider.dart';
import '../../state/chat_unread_provider.dart';
import '../../widgets/async_state_widgets.dart';
import 'chat_list_screen.dart';

final _timeFmt = DateFormat('HH:mm');
final _dayFmt = DateFormat('dd/MM/yyyy');

/// Réponses rapides proposées tant que la conversation est vide
/// (`quickSuggestions` du web) — le tap remplit le champ, il n'envoie pas.
const List<String> kChatQuickSuggestions = [
  'Bonjour !',
  'Est-ce que le stock est à jour ?',
  'La commande est en cours.',
  'Merci pour votre aide !',
  "Je m'en occupe tout de suite.",
];

/// URL d'image telle que CE device peut la charger.
///
/// Le serveur construit l'URL absolue à partir de l'hôte de la requête qui a
/// créé le message : un message poussé en direct par le socket porte donc
/// l'hôte de l'EXPÉDITEUR — `localhost` si le collègue est sur le web de la
/// même machine, injoignable depuis un téléphone ou l'émulateur. On rebase
/// alors sur l'URL serveur configurée dans l'app ; une URL relative est
/// simplement préfixée ; tout autre hôte (CDN, IP du LAN) est laissé tel quel.
String chatImageUrl(String url) {
  final base = ApiClient.instance.baseUrl;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (!uri.hasScheme) {
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }
  const loopback = {'localhost', '127.0.0.1', '0.0.0.0', '::1', '[::1]'};
  if (loopback.contains(uri.host)) {
    final origin = Uri.parse(base);
    return Uri(
      scheme: origin.scheme,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }
  return url;
}

/// Conversation DIRECTE avec [recipientId] — `/chats/dm/:id`.
///
/// Historique REST puis WebSocket `ws/chat/` (envoi, édition, suppression,
/// accusés de lecture, heartbeat de présence et reconnexion sont portés par
/// `ChatSocketService`) ; l'image passe par HTTP (`ChatRepository.sendImage`)
/// et revient par le socket. [embedded] : affichée dans le volet de droite de
/// la liste (écran large) — pas de bouton retour.
///
/// Sans [recipientId] (ancienne route `/chats/room/general`) : le salon
/// Général n'existe plus, l'écran l'explique et renvoie vers la liste.
class ChatConversationScreen extends ConsumerStatefulWidget {
  const ChatConversationScreen({super.key, this.recipientId, this.title = 'Discussion', this.embedded = false});

  final int? recipientId;
  final String title;
  final bool embedded;

  @override
  ConsumerState<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends ConsumerState<ChatConversationScreen> {
  final _socket = ChatSocketService();
  final _messageController = TextEditingController();
  final _editingController = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _loadingHistory = true;
  String? _historyError;
  ChatSocketStatus _status = ChatSocketStatus.disconnected;
  int? _editingId;
  bool _sendingImage = false;

  // Trames reçues pendant le chargement de l'historique : elles portent sur
  // des messages que l'on ne connaît pas encore, on les rejoue une fois
  // l'historique posé (l'accusé « read » part dès la connexion, il arrive
  // typiquement AVANT la réponse REST).
  final List<ChatSocketEvent> _pendingEvents = [];

  StreamSubscription<ChatSocketEvent>? _eventsSub;
  StreamSubscription<ChatSocketStatus>? _statusSub;
  late final ProviderContainer _container;

  int? get _myId => ref.read(authProvider).user?.id;
  bool get _isDirect => widget.recipientId != null;
  bool get _connected => _status == ChatSocketStatus.connected;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    if (!_isDirect) {
      _loadingHistory = false;
      return;
    }
    _eventsSub = _socket.events.listen(_onEvent);
    _statusSub = _socket.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _socket.connectToConversation(recipientId: widget.recipientId);
    _loadHistory();
    // Ouvrir une conversation la marque comme lue côté serveur (action
    // « read » à la connexion) : relire la liste des contacts tout de suite
    // pour que le badge de non-lus retombe sans attendre le prochain
    // rafraîchissement périodique (miroir web : fetchUsers(true) quand
    // activeRecipient change). Hors du cycle de build, cf. Riverpod.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(chatUsersProvider);
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _statusSub?.cancel();
    _socket.disposeService();
    _messageController.dispose();
    _editingController.dispose();
    _scrollController.dispose();
    // En quittant : la liste des contacts (ordre « plus récente en tête »,
    // non-lus) et le badge du menu sont relus — le web relit à chaque
    // changement de page. Le widget est démonté, on passe par le conteneur.
    if (_isDirect) {
      final container = _container;
      Future.microtask(() {
        container.invalidate(chatUsersProvider);
        container.read(chatUnreadProvider.notifier).refresh();
      });
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Historique + temps réel
  // ---------------------------------------------------------------------------

  Future<void> _loadHistory() async {
    // Premier chargement : l'état initial est déjà « en cours » (pas de
    // setState pendant initState) ; « Réessayer » repasse par ici.
    if (!_loadingHistory || _historyError != null) {
      setState(() {
        _loadingHistory = true;
        _historyError = null;
      });
    }
    try {
      final history = await ref.read(chatRepositoryProvider).history(recipientId: widget.recipientId);
      if (!mounted) return;
      final pending = List<ChatSocketEvent>.of(_pendingEvents);
      _pendingEvents.clear();
      setState(() {
        // Messages arrivés par le socket pendant la requête : conservés s'ils
        // ne figurent pas déjà dans l'historique (dédoublonnage par id).
        final known = history.map((m) => m.id).toSet();
        final live = _messages.where((m) => !known.contains(m.id)).toList();
        _messages
          ..clear()
          ..addAll(history)
          ..addAll(live);
        _sortMessages();
        _loadingHistory = false;
        for (final event in pending) {
          _applyEvent(event);
        }
      });
      for (final event in pending.whereType<ChatMessagesRead>()) {
        _afterRead(event);
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = ApiClient.messageFromError(e);
        _loadingHistory = false;
      });
    }
  }

  void _sortMessages() {
    _messages.sort((a, b) {
      final ta = a.timestamp?.millisecondsSinceEpoch ?? 0;
      final tb = b.timestamp?.millisecondsSinceEpoch ?? 0;
      return ta != tb ? ta.compareTo(tb) : a.id.compareTo(b.id);
    });
  }

  void _onEvent(ChatSocketEvent event) {
    if (!mounted) return;
    if (_loadingHistory && event is! ChatMessageReceived) {
      _pendingEvents.add(event);
      return;
    }
    setState(() => _applyEvent(event));
    if (event is ChatMessageReceived) _scrollToBottom();
    if (event is ChatMessagesRead) _afterRead(event);
  }

  /// Met [_messages] à jour pour [event] — à appeler dans un setState.
  void _applyEvent(ChatSocketEvent event) {
    switch (event) {
      case ChatMessageReceived(:final message):
        // Le serveur renvoie aussi NOS messages (pas d'ajout optimiste) ; les
        // doublons sont ignorés comme sur le web.
        if (_messages.any((m) => m.id == message.id)) return;
        _messages.add(message);
        _sortMessages();
      case ChatMessageEdited(:final id, :final content, :final isEdited, :final editedAt):
        final i = _messages.indexWhere((m) => m.id == id);
        if (i != -1) _messages[i] = _messages[i].copyWith(content: content, isEdited: isEdited, editedAt: editedAt);
      case ChatMessageDeleted(:final id):
        final i = _messages.indexWhere((m) => m.id == id);
        if (i != -1) _messages[i] = _messages[i].copyWith(isDeleted: true, content: '');
        if (_editingId == id) _editingId = null;
      case ChatMessagesRead(:final ids, :final readAt):
        for (var i = 0; i < _messages.length; i++) {
          if (ids.contains(_messages[i].id)) _messages[i] = _messages[i].copyWith(readAt: readAt);
        }
    }
  }

  /// Accusé de lecture diffusé sur le salon — le nôtre (messages reçus que
  /// l'on vient de consulter) ou celui de l'interlocuteur (nos messages,
  /// coches bleues). Dans le premier cas le badge du menu et celui du contact
  /// retombent tout de suite ; on confirme ensuite auprès du serveur.
  void _afterRead(ChatMessagesRead event) {
    final myId = _myId;
    final mine = event.ids.where((id) => _messages.any((m) => m.id == id && m.senderId != myId)).length;
    final unread = ref.read(chatUnreadProvider.notifier);
    if (mine > 0) unread.decrement(mine);
    unread.refresh();
    ref.invalidate(chatUsersProvider);
  }

  void _scrollToBottom() {
    // Liste inversée : l'offset 0 est le bas de la conversation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// `handleSendMessage` : rien n'est envoyé (silencieusement) si le texte
  /// est vide ou si le socket n'est pas connecté ; aucun ajout optimiste, la
  /// bulle apparaît quand le serveur renvoie le message.
  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty || !_connected) return;
    if (_socket.sendMessage(text)) _messageController.clear();
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _editingId = message.id;
      _editingController.text = message.content;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _editingController.clear();
    });
  }

  /// `saveEditMessage` : ne fait rien si le texte est vide ou hors ligne ;
  /// le nouveau contenu s'affiche à l'arrivée de `message_edited`.
  void _saveEdit() {
    final id = _editingId;
    final text = _editingController.text.trim();
    if (id == null || text.isEmpty || !_connected) return;
    if (_socket.editMessage(id, text)) _cancelEdit();
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    if (!_connected) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce message ?'),
        content: const Text('Le message sera remplacé par « Message supprimé » pour tout le monde.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) _socket.deleteMessage(message.id);
  }

  /// Menu d'actions d'un message (appui long, ou bouton « ⋮ » sur les
  /// miens) : « Copier le texte », et pour MES messages non supprimés
  /// « Modifier » / « Supprimer » — le DropdownMenu du web.
  void _showActions(ChatMessage message) {
    final mine = message.senderId == _myId && !message.isDeleted;
    final hasText = message.content.isNotEmpty && !message.isDeleted;
    if (!mine && !hasText) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (hasText)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copier le texte'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: message.content));
                  if (mounted) _snack('Message copié.');
                },
              ),
            if (mine) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Modifier'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startEdit(message);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text('Supprimer', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete(message);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bouton « + » : « Envoyer une image » (fichiers) / « Prendre une photo »
  /// (appareil) — le Popover du web.
  void _showAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const _AttachIcon(Icons.image_outlined),
              title: const Text('Envoyer une image'),
              subtitle: const Text('Depuis vos fichiers'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const _AttachIcon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              subtitle: const Text("Avec l'appareil photo"),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAndSendImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// `handleImageSelected` : POST multipart, la légende est le texte déjà
  /// saisi ; le message revient par le socket (pas d'ajout ici).
  Future<void> _pickAndSendImage(ImageSource source) async {
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);
    } catch (e) {
      if (mounted) _snack("Impossible d'ouvrir l'image : ${ApiClient.messageFromError(e)}");
      return;
    }
    if (picked == null || !mounted) return;
    setState(() => _sendingImage = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendImage(File(picked.path), content: _messageController.text, recipientId: widget.recipientId);
      if (mounted) _messageController.clear();
    } catch (e) {
      // Web : `err?.message || "Impossible d'envoyer l'image."` — le message
      // serveur (« Aucune image reçue. », « Destinataire introuvable »,
      // « Permission refusée »...) est repris tel quel.
      if (mounted) _snack(ApiClient.messageFromError(e));
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openImage(String url) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _ImageViewerScreen(url: url)));
  }

  // ---------------------------------------------------------------------------
  // Rendu
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_isDirect) return _RoomRemovedScreen(embedded: widget.embedded);

    final myId = ref.watch(authProvider).user?.id;
    // Présence de l'interlocuteur toujours à jour : dérivée de la liste
    // rafraîchie toutes les 20 s (`liveActiveRecipient` du web), pas de
    // l'objet figé au moment du tap.
    final activeUser = ref.watch(chatUsersProvider).value?.firstWhereOrNull((u) => u.id == widget.recipientId);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: _Header(user: activeUser, fallbackTitle: widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SocketStatusBadge(status: _status),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages(myId)),
          _Composer(
            controller: _messageController,
            connected: _connected,
            sendingImage: _sendingImage,
            showSendLabel: wide,
            showSuggestions: !_loadingHistory && _historyError == null && _messages.isEmpty,
            onSend: _send,
            onAttach: _showAttachMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(int? myId) {
    if (_loadingHistory) return const _CenteredLoader(label: 'Chargement des messages...');
    if (_historyError != null) {
      return ErrorState(message: "Erreur lors du chargement de l'historique.\n$_historyError", onRetry: _loadHistory);
    }
    if (_messages.isEmpty) return const _EmptyConversation();

    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: _messages.length,
        itemBuilder: (context, i) {
          // Liste inversée : l'index 0 est le message le plus récent.
          final index = _messages.length - 1 - i;
          final m = _messages[index];
          final previous = index == 0 ? null : _messages[index - 1];
          final isMine = m.senderId == myId;
          // Groupement par expéditeur (web) : nom + rôle uniquement sur un
          // message reçu, quand l'expéditeur change.
          final showSender = !isMine && (previous == null || previous.senderId != m.senderId);
          final newDay =
              m.timestamp != null &&
              (previous?.timestamp == null || appDay(previous!.timestamp!) != appDay(m.timestamp!));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (newDay) _DaySeparator(day: m.timestamp!),
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 3, top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        m.senderName ?? '',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                      ),
                      if (m.senderRole != null) ...[const SizedBox(width: 5), ChatRoleBadge(role: m.senderRole!)],
                    ],
                  ),
                ),
              _MessageRow(
                message: m,
                isMine: isMine,
                // Largeur max des bulles : 78 % du volet (85 % / 75 % / 65 %
                // selon la taille d'écran sur le web).
                maxWidth: constraints.maxWidth * 0.78,
                editing: _editingId == m.id,
                editingController: _editingController,
                onSaveEdit: _saveEdit,
                onCancelEdit: _cancelEdit,
                onMore: isMine && !m.isDeleted && _editingId != m.id ? () => _showActions(m) : null,
                onLongPress: !m.isDeleted && _editingId != m.id ? () => _showActions(m) : null,
                onOpenImage: _openImage,
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// Sous-widgets
// =============================================================================

/// Avatar + nom + « En ligne / Vu … • Rôle » de l'interlocuteur.
class _Header extends StatelessWidget {
  const _Header({required this.user, required this.fallbackTitle});

  final ChatUser? user;
  final String fallbackTitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final u = user;
    if (u == null) {
      return Text(fallbackTitle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Row(
      children: [
        PresenceAvatar(user: u, radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                u.fullName.isNotEmpty ? u.fullName : fallbackTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      presenceLabel(u),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: u.isOnline ? const Color(0xFF059669) : scheme.onSurfaceVariant,
                        fontWeight: u.isOnline ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(' • ', style: TextStyle(fontSize: 11, color: scheme.outlineVariant)),
                  Text(
                    u.roleLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Badge d'état du socket — « En ligne » (vert, pastille pulsante),
/// « Connexion... » (ambre, spinner), « Hors ligne » (rose).
class _SocketStatusBadge extends StatelessWidget {
  const _SocketStatusBadge({required this.status});
  final ChatSocketStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label, leading) = switch (status) {
      ChatSocketStatus.connected => (const Color(0xFF059669), 'En ligne', const _PulsingDot(color: Color(0xFF10B981))),
      ChatSocketStatus.connecting => (
        const Color(0xFFD97706),
        'Connexion...',
        const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFD97706)),
        ),
      ),
      ChatSocketStatus.disconnected => (
        const Color(0xFFE11D48),
        'Hors ligne',
        const Icon(Icons.circle, size: 8, color: Color(0xFFE11D48)),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Pastille avec halo pulsant (`animate-ping` du badge « En ligne »).
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.75,
                child: Transform.scale(
                  scale: 1 + t,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// « Aucun message pour le moment » — icône dans un rond + sous-titre.
class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.06), shape: BoxShape.circle),
              child: Icon(Icons.chat_bubble_outline, size: 40, color: scheme.primary.withValues(alpha: 0.35)),
            ),
            const SizedBox(height: 12),
            const Text('Aucun message pour le moment', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            SizedBox(
              width: 280,
              child: Text(
                'Envoyez un message pour commencer la conversation en temps réel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Séparateur de journée (« Aujourd'hui », « Hier », dd/MM/yyyy) — l'heure
/// seule du web est ambiguë sur un historique de 100 messages.
class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = appDay(day);
    final today = appToday();
    final label = d == today
        ? "Aujourd'hui"
        : d == today.subtract(const Duration(days: 1))
        ? 'Hier'
        : _dayFmt.format(d);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Une ligne de conversation : bulle (ou éditeur inline), bouton d'actions
/// pour mes messages, horodatage + « modifié » + coches de lecture.
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.isMine,
    required this.maxWidth,
    required this.editing,
    required this.editingController,
    required this.onSaveEdit,
    required this.onCancelEdit,
    required this.onMore,
    required this.onLongPress,
    required this.onOpenImage,
  });

  final ChatMessage message;
  final bool isMine;
  final double maxWidth;
  final bool editing;
  final TextEditingController editingController;
  final VoidCallback onSaveEdit;
  final VoidCallback onCancelEdit;

  /// Bouton « ⋮ » à gauche de la bulle — mes messages non supprimés.
  final VoidCallback? onMore;

  /// Appui long sur la bulle — tout message non supprimé.
  final VoidCallback? onLongPress;
  final ValueChanged<String> onOpenImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = message;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (onMore != null)
                IconButton(
                  tooltip: 'Actions',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  iconSize: 16,
                  color: scheme.onSurfaceVariant,
                  icon: const Icon(Icons.more_vert),
                  onPressed: onMore,
                ),
              if (editing)
                SizedBox(
                  width: maxWidth,
                  child: _InlineEditor(controller: editingController, onSave: onSaveEdit, onCancel: onCancelEdit),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: GestureDetector(
                    onLongPress: onLongPress,
                    child: _Bubble(message: m, isMine: isMine, onOpenImage: onOpenImage),
                  ),
                ),
            ],
          ),
          if (!editing)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    [
                      if (m.timestamp != null) _timeFmt.format(appLocal(m.timestamp!)),
                      if (m.isEdited && !m.isDeleted) 'modifié',
                    ].join(' · '),
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                  ),
                  // Coches façon WhatsApp — uniquement sur MES messages non
                  // supprimés (conversation directe).
                  if (isMine && !m.isDeleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      m.readAt != null ? Icons.done_all : Icons.done,
                      size: 13,
                      color: m.readAt != null ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Édition inline d'un message : champ pré-rempli (focus), valider (Entrée
/// ou ✓), annuler (Échap ou ✕).
class _InlineEditor extends StatelessWidget {
  const _InlineEditor({required this.controller, required this.onSave, required this.onCancel});

  final TextEditingController controller;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSave(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Modifier le message…',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Enregistrer',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(Icons.check),
            onPressed: onSave,
          ),
          IconButton(
            tooltip: 'Annuler',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(Icons.close),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// La bulle : « Message supprimé » (bordure, italique), sinon image
/// (ouvrable) puis texte (retours à la ligne conservés).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMine, required this.onOpenImage});

  final ChatMessage message;
  final bool isMine;
  final ValueChanged<String> onOpenImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = message;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMine ? 16 : 4),
      topRight: Radius.circular(isMine ? 4 : 16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    if (m.isDeleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              'Message supprimé',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final fg = isMine ? scheme.onPrimary : scheme.onSurface;
    final url = m.hasImage ? chatImageUrl(m.image!) : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: isMine ? scheme.primary : scheme.surfaceContainerHighest, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (url != null)
            Padding(
              padding: EdgeInsets.only(bottom: m.content.isNotEmpty ? 6 : 0),
              child: GestureDetector(
                onTap: () => onOpenImage(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240, minWidth: 80, minHeight: 40),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      semanticLabel: 'Image envoyée',
                      loadingBuilder: (context, child, progress) => progress == null
                          ? child
                          : SizedBox(
                              width: 160,
                              height: 120,
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                            ),
                      errorBuilder: (context, error, stack) => Container(
                        width: 160,
                        height: 90,
                        alignment: Alignment.center,
                        color: fg.withValues(alpha: 0.08),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 18, color: fg.withValues(alpha: 0.7)),
                            const SizedBox(width: 6),
                            Text(
                              'Image indisponible',
                              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Retours à la ligne conservés (`whitespace-pre-wrap`) ; la copie
          // passe par l'appui long (« Copier le texte »).
          if (m.content.isNotEmpty) Text(m.content, style: TextStyle(color: fg, fontSize: 14, height: 1.35)),
        ],
      ),
    );
  }
}

/// Suggestions rapides (conversation vide) + bouton « + » + champ + Envoyer.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.connected,
    required this.sendingImage,
    required this.showSendLabel,
    required this.showSuggestions,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool connected;
  final bool sendingImage;
  final bool showSendLabel;
  final bool showSuggestions;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 4,
      shadowColor: Colors.black12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSuggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in kChatQuickSuggestions)
                        ActionChip(
                          label: Text(s, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onPressed: () {
                            controller
                              ..text = s
                              ..selection = TextSelection.collapsed(offset: s.length);
                          },
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: connected && !sendingImage ? onAttach : null,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: sendingImage
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: connected,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => onSend(),
                      decoration: const InputDecoration(
                        hintText: 'Rédiger votre message...',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final enabled = connected && controller.text.trim().isNotEmpty;
                      return SizedBox(
                        height: 44,
                        child: showSendLabel
                            ? FilledButton.icon(
                                onPressed: enabled ? onSend : null,
                                icon: const Icon(Icons.send, size: 18),
                                label: const Text('Envoyer'),
                              )
                            : FilledButton(
                                onPressed: enabled ? onSend : null,
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
                                child: const Icon(Icons.send, size: 18),
                              ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachIcon extends StatelessWidget {
  const _AttachIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: scheme.primary),
    );
  }
}

/// Visionneuse plein écran (l'image du web s'ouvre dans un nouvel onglet) :
/// zoom/pincement, et ouverture dans le navigateur.
class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Image envoyée'),
        actions: [
          IconButton(
            tooltip: 'Ouvrir dans le navigateur',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const CircularProgressIndicator(color: Colors.white),
            errorBuilder: (context, error, stack) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Image indisponible', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ancienne route `/chats/room/general` : le salon Général n'existe plus
/// (conversations directes uniquement, comme sur le web).
class _RoomRemovedScreen extends StatelessWidget {
  const _RoomRemovedScreen({required this.embedded});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !embedded, title: const Text('Discussion')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EmptyState(
                message: "Le salon Général n'existe plus : la messagerie ne comporte que des conversations directes.",
                icon: Icons.forum_outlined,
              ),
              FilledButton.icon(
                onPressed: () => context.go('/chats'),
                icon: const Icon(Icons.group_outlined, size: 18),
                label: const Text('Voir les conversations'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
