import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/chat_socket_service.dart';
import '../../models/chat.dart';
import '../../models/json_utils.dart';
import '../../state/auth_provider.dart';
import 'chat_list_screen.dart';

final _timeFmt = DateFormat('HH:mm');

/// Conversation (salon général ou message privé). [recipientId] null =
/// salon général de la société.
class ChatConversationScreen extends ConsumerStatefulWidget {
  const ChatConversationScreen({super.key, this.recipientId, this.title = 'Général'});

  final int? recipientId;
  final String title;

  @override
  ConsumerState<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends ConsumerState<ChatConversationScreen> {
  final _socket = ChatSocketService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  String? _error;
  int? _editingId;
  StreamSubscription<bool>? _statusSub;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _socket.connectToConversation(recipientId: widget.recipientId);
    _socket.incoming.listen(_handleIncoming);
    // (1) Juste après connexion (et toute reconnexion) à une conversation
    // DIRECTE : marquer "vu" les messages déjà reçus non lus (no-op serveur
    // pour "Général", voir ChatConsumer.mark_read()).
    _statusSub = _socket.connectionStatus.listen((connected) {
      if (connected && widget.recipientId != null) _socket.markRead();
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _socket.disposeService();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      final history = await repo.history(recipientId: widget.recipientId);
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _error = ApiClient.messageFromError(e);
        _loading = false;
      });
    }
  }

  void _handleIncoming(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    setState(() {
      switch (type) {
        case 'message':
          _messages.add(ChatMessage.fromJson(data));
        case 'message_edited':
          final id = (data['id'] as num?)?.toInt();
          final index = _messages.indexWhere((m) => m.id == id);
          if (index != -1) _messages[index] = _messages[index].copyWith(content: data['content'] as String?, isEdited: true);
        case 'message_deleted':
          final id = (data['id'] as num?)?.toInt();
          final index = _messages.indexWhere((m) => m.id == id);
          if (index != -1) _messages[index] = _messages[index].copyWith(isDeleted: true, content: '');
        case 'message_read':
          // Broadcast serveur suite à une action "read" (la nôtre ou celle
          // de l'autre partie) : {"ids": [...], "read_at": ...}.
          final ids = (data['ids'] as List?)?.map((e) => (e as num).toInt()).toSet() ?? const <int>{};
          final readAt = asDateOrNull(data['read_at']);
          for (var i = 0; i < _messages.length; i++) {
            if (ids.contains(_messages[i].id)) _messages[i] = _messages[i].copyWith(readAt: readAt);
          }
      }
    });
    if (type == 'message') {
      _scrollToBottom();
      // (2) Message reçu (pas le mien) pendant que la conversation DIRECTE
      // est affichée -> le marquer "vu" tout de suite (miroir web :
      // ws.onmessage). "Général" n'a pas de statut "vu" : rien à envoyer.
      final senderId = (data['sender'] as num?)?.toInt();
      final myId = ref.read(authProvider).user?.id;
      if (widget.recipientId != null && senderId != myId) _socket.markRead();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (_editingId != null) {
      _socket.editMessage(_editingId!, text);
      setState(() => _editingId = null);
    } else {
      _socket.sendMessage(text);
    }
    _messageController.clear();
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _editingId = message.id;
      _messageController.text = message.content;
    });
  }

  void _showActions(ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Modifier'), onTap: () { Navigator.pop(context); _startEdit(message); }),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () { Navigator.pop(context); _socket.deleteMessage(message.id); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authProvider).user?.id;
    // Présence du contact actif (DM uniquement) — dérivée de la même liste
    // périodiquement rafraîchie que chat_list_screen.dart (pas de push
    // serveur), voir chatUsersProvider.
    final activeUser = widget.recipientId == null
        ? null
        : ref.watch(chatUsersProvider).value?.where((u) => u.id == widget.recipientId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: activeUser == null
            ? Text(widget.title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(activeUser.fullName.isNotEmpty ? activeUser.fullName : widget.title),
                  Text(
                    presenceLabel(activeUser),
                    style: TextStyle(fontSize: 12, color: activeUser.isOnline ? Colors.greenAccent.shade400 : null),
                  ),
                ],
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final isMine = m.senderId == myId;
                          return _MessageBubble(
                            message: m,
                            isMine: isMine,
                            showSender: widget.recipientId == null && !isMine,
                            showReadReceipt: isMine && widget.recipientId != null,
                            onLongPress: isMine && !m.isDeleted ? () => _showActions(m) : null,
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  if (_editingId != null)
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _editingId = null; _messageController.clear(); })),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(hintText: _editingId != null ? 'Modifier le message…' : 'Message…', border: const OutlineInputBorder()),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showSender,
    this.showReadReceipt = false,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showSender;
  // Coche(s) façon WhatsApp — uniquement sur SES PROPRES messages dans une
  // conversation DIRECTE (le salon "Général" n'a pas de "vu" unique par
  // message, voir ChatConsumer.mark_read()).
  final bool showReadReceipt;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
          decoration: BoxDecoration(
            color: isMine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSender && message.senderName != null)
                Text(message.senderName!, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                message.isDeleted ? 'Message supprimé' : message.content,
                style: message.isDeleted ? TextStyle(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant) : null,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.timestamp != null) Text(_timeFmt.format(message.timestamp!.toLocal()), style: Theme.of(context).textTheme.labelSmall),
                  if (message.isEdited && !message.isDeleted) Text('  (modifié)', style: Theme.of(context).textTheme.labelSmall),
                  if (showReadReceipt && !message.isDeleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.readAt != null ? Icons.done_all : Icons.done,
                      size: 14,
                      color: message.readAt != null ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
