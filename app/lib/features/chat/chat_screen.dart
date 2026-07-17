import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repos.dart';
import '../../domain/chat.dart';
import '../../domain/chat_session.dart';
import '../../domain/chat_time.dart';
import '../../domain/image_pick.dart';
import '../client/request_status_screen.dart' show fmtRD;
import 'widgets/bubbles.dart';
import 'widgets/composer.dart';

const _pageSize = 50;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _session = ChatSession();
  Map<String, dynamic>? _conv;
  bool _error = false;
  bool _loadingOlder = false;
  String? _peerAvatarUrl;
  // ignore: unused_field
  String? _peerName;
  int _tempSeq = 0;
  bool _sending = false;
  bool _uploadingImage = false;
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;
  final _scroll = ScrollController();

  String get _uid => supa.auth.currentUser!.id;
  bool get _isProvider => _conv?['provider_user_id'] == _uid;
  bool get _isOpen => _conv?['status'] == 'abierto';

  @override
  void initState() {
    super.initState();
    _load();
    _lifecycle = AppLifecycleListener(
      onPause: _teardownRealtime,
      onResume: _resume,
    );
    _scroll.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    _teardownRealtime();
    _lifecycle?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final results = await Future.wait([
        fetchConversation(widget.conversationId),
        messagesPage(widget.conversationId, limit: _pageSize),
        conversationsList(), // para peer name/avatar (fila de esta conv)
      ]);
      final conv = results[0] as Map<String, dynamic>?;
      if (conv == null) throw StateError('not found');
      final page = results[1] as List<Map<String, dynamic>>;
      final listRow = (results[2] as List<Map<String, dynamic>>)
          .where((c) => c['id'] == widget.conversationId).toList();
      _session.seedFirstPage(page, _pageSize);
      if (!mounted) return;
      setState(() {
        _conv = conv;
        if (listRow.isNotEmpty) {
          _peerName = listRow.first['peer_name'] as String?;
          _peerAvatarUrl = listRow.first['peer_avatar_url'] as String?;
        }
      });
      _setupRealtime();
      _afterLoad();
      // Notificaciones leídas — best-effort, no bloquea la UI.
      markChatNotificationsRead(widget.conversationId).catchError((_) {});
      _jumpToBottom();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  /// Hook para Tasks 8-9 (auto-saludo, auditoría, welcome). Task 7: vacío.
  // ignore: unused_element
  Future<void> _afterLoad() async {}

  // ignore: unused_element
  Future<void> _reload() async {
    final conv = await fetchConversation(widget.conversationId);
    if (mounted && conv != null) setState(() => _conv = conv);
  }

  void _setupRealtime() {
    _teardownRealtime();
    _channel = supa
        .channel('conv-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'conversation_messages',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: widget.conversationId),
          callback: (payload) {
            if (_session.mergeServer(payload.newRecord)) {
              if (mounted) setState(() {});
              _jumpToBottom();
              markChatNotificationsRead(widget.conversationId).catchError((_) {});
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversation_messages',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: widget.conversationId),
          callback: (payload) {
            _session.applyUpdate(payload.newRecord);
            if (mounted) setState(() {});
          },
        )
        .subscribe();
  }

  void _teardownRealtime() {
    final ch = _channel;
    _channel = null;
    if (ch != null) supa.removeChannel(ch);
  }

  /// Resolución del coordinador (review Task 4): en vez del gap query
  /// (`messagesSince` + `mergeGap`), re-fetch de la primera página. El gap
  /// query no recupera UPDATEs de mensajes viejos (ej. un `quick` respondido
  /// mientras la app estaba en background se perdería); `seedFirstPage` ya
  /// preserva los optimistas en vuelo (fix c2deb40).
  Future<void> _resume() async {
    try {
      final rows = await messagesPage(widget.conversationId, limit: _pageSize);
      _session.seedFirstPage(rows, _pageSize);
      if (mounted) {
        setState(() {});
        _jumpToBottom();
      }
    } catch (_) {/* reintenta el realtime igual */}
    if (mounted) _setupRealtime();
  }

  void _maybeLoadOlder() {
    // Lista reversed: el "final" del scroll es el tope visual (mensajes viejos).
    if (!_session.hasMore || _loadingOlder) return;
    if (_scroll.position.extentAfter > 200) return;
    _loadOlder();
  }

  Future<void> _loadOlder() async {
    final cursor = _session.oldestCursor();
    if (cursor == null) return;
    setState(() => _loadingOlder = true);
    try {
      final rows = await messagesPage(widget.conversationId,
          beforeCreatedAt: cursor.$1, beforeId: cursor.$2, limit: _pageSize);
      _session.prependOlder(rows, _pageSize);
    } catch (_) {/* silencioso: el usuario puede reintentar scrolleando */} finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0); // reversed: 0 = abajo
    });
  }

  /// Envío optimista genérico (texto/dirección/imagen/quick/system/audit).
  // ignore: unused_element
  Future<bool> _sendRaw(String kind, String body, {String? senderIdOverride}) async {
    final sender = senderIdOverride ?? _uid;
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}-${_tempSeq++}';
    _session.addOptimistic(
        tempId: tempId, senderId: sender, kind: kind, body: body, now: DateTime.now());
    setState(() {});
    _jumpToBottom();
    try {
      final row = await insertChatMessage(
          convId: widget.conversationId, senderId: sender, kind: kind, body: body);
      _session.confirmOptimistic(tempId, row);
      if (mounted) setState(() {});
      return true;
    } catch (_) {
      _session.removeOptimistic(tempId);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo enviar. Intenta de nuevo.')));
      }
      return false;
    }
  }

  Future<void> _answerQuick(ChatMessage m, String option) async {
    final p = parseQuick(m.body);
    if (p == null || p.selected != null) return;
    final prevBody = m.body;
    final nextBody = answerQuickBody(p, option, _uid);
    setState(() => m.body = nextBody); // optimista
    try {
      await updateQuickBody(m.id, nextBody);
      await _sendRaw('text', quickConfirmation(p.question, option));
    } catch (_) {
      setState(() => m.body = prevBody); // rollback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo responder. Intenta de nuevo.')));
      }
    }
  }

  Future<bool> _sendText(String raw) async {
    final body = sanitizeChatText(raw);
    if (body.isEmpty) return true;
    setState(() => _sending = true);
    final ok = await _sendRaw('text', body);
    if (mounted) setState(() => _sending = false);
    return ok;
  }

  Future<void> _handlePlus(PlusAction action) async {
    switch (action) {
      case PlusAction.sendAddress:
        final body = await myBusinessAddressBody();
        if (!mounted) return;
        if (body == null) {
          _snack('Configura la dirección de tu local en tu perfil de proveedor.');
          return;
        }
        await _sendRaw('address', body);
      case PlusAction.sendContact:
        final body = await myContactBody();
        if (!mounted) return;
        if (body == null) {
          _snack('Completa tus datos en tu perfil primero.');
          return;
        }
        await _sendRaw('text', body);
      case PlusAction.sendLocation:
        final body = await myLocationBody();
        if (!mounted) return;
        if (body == null) {
          _snack('Agrega tu dirección en tu perfil primero.');
          return;
        }
        await _sendRaw('address', body);
      case PlusAction.sendPhoto:
        await _pickAndSendPhoto();
      case PlusAction.improveOffer:
        _openImproveOffer(); // Task 10
    }
  }

  Future<void> _pickAndSendPhoto() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;
    final size = await picked.length();
    if (!mounted) return;
    final check = validatePickedImage(
        sizeBytes: size, path: picked.path, currentCount: 0, maxCount: 1);
    if (check is ImagePickError) {
      _snack(check.message);
      return;
    }
    setState(() => _uploadingImage = true);
    try {
      final url = await uploadChatImage(picked.path);
      await _sendRaw('image', url);
    } catch (_) {
      _snack('No se pudo enviar la imagen.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _sendQuickItem(QuickItem item) async {
    if (item.options.isEmpty) {
      await _sendRaw('text', item.question);
      return;
    }
    final payload = jsonEncode({
      'question': item.question,
      'options': item.options,
      'selected': null,
      'answered_by': null,
    });
    await _sendRaw('quick', payload);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Task 10 implementa la hoja de "mejorar oferta" (bajar precio).
  void _openImproveOffer() {}

  void _openLightbox(String src) {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(children: [
              Center(child: InteractiveViewer(child: Image.network(src))),
              Positioned(
                  top: 8, right: 8,
                  child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(dialogContext).pop())),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final conv = _conv;
    if (_error) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('No pudimos cargar esta conversación.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Reintentar')),
          ])));
    }
    if (conv == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final ms = _session.messages;
    return Scaffold(
      appBar: _buildHeader(conv),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: ms.length + (_loadingOlder ? 1 : 0),
            itemBuilder: (context, j) {
              if (j >= ms.length) {
                return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))));
              }
              final i = ms.length - 1 - j;
              final m = ms[i];
              final own = m.senderId == _uid;
              final bubble = buildBubble(context, m,
                  own: own,
                  groupEnd: isGroupEnd(ms, i),
                  peerAvatarUrl: _peerAvatarUrl,
                  onImageTap: _openLightbox,
                  onQuickAnswer: _answerQuick,
                  canAnswerQuick: _isOpen);
              if (!needsDaySep(ms, i)) return bubble;
              return Column(children: [
                Center(
                    child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(formatDayLabel(m.createdAt),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                )),
                bubble,
              ]);
            },
          ),
        ),
        _buildBottom(conv),
      ]),
    );
  }

  PreferredSizeWidget _buildHeader(Map<String, dynamic> conv) {
    final price = conv['agreed_price'] != null
        ? 'Precio acordado: ${fmtRD(conv['agreed_price'] as num)}'
        : conv['agreed_hourly_rate'] != null
            ? 'Tarifa acordada: ${fmtRD(conv['agreed_hourly_rate'] as num)}/h'
            : 'Acuerdo sin precio fijo';
    return AppBar(
      titleSpacing: 0,
      title: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: conv['product_image_url'] != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(conv['product_image_url'] as String,
                    width: 40, height: 40, fit: BoxFit.cover))
            : const CircleAvatar(child: Icon(Icons.check, size: 16)),
        title: Text(conv['product_name'] as String? ?? 'Acuerdo',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        subtitle: Text(price, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
      ),
      // Tasks 9: actions (⋮ y tap → detalles) se añaden aquí.
    );
  }

  /// Banner de cerrado, o composer si la conversación sigue abierta.
  Widget _buildBottom(Map<String, dynamic> conv) {
    if (!_isOpen) {
      final txt = conv['status'] == 'cerrado'
          ? 'Pedido marcado como completado. El chat queda cerrado y ya no es posible enviar mensajes.'
          : 'Conversación marcada como no concretada. No puede reabrirse.';
      return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(txt, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey)));
    }
    return ChatComposer(
      isProvider: _isProvider,
      sending: _sending || _uploadingImage,
      onSendText: _sendText,
      onPlusAction: _handlePlus,
      onQuickItem: _sendQuickItem,
    );
  }
}
