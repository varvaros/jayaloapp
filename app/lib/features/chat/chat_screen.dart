import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repos.dart';
import '../../domain/chat.dart';
import '../../domain/chat_session.dart';
import '../../domain/chat_time.dart';
import '../../domain/image_pick.dart';
import '../client/request_status_screen.dart' show fmtRD;
import 'widgets/bubbles.dart';
import 'widgets/chat_dialogs.dart';
import 'widgets/composer.dart';
import 'widgets/rating_form.dart';

const _pageSize = 50;

class ChatScreen extends StatefulWidget {
  const ChatScreen(
      {super.key, required this.conversationId, this.peerName, this.peerAvatarUrl});
  final String conversationId;
  // Pasados por la lista de conversaciones (Task I-2): si vienen presentes,
  // evitan volver a llamar al RPC agregado `conversationsList()` solo para
  // resolver el nombre/avatar del peer — ahorro de batería/red al entrar
  // desde la lista. Si son null (deep-link/push futuro sin `extra`), se
  // mantiene el fallback con `conversationsList()`.
  final String? peerName;
  final String? peerAvatarUrl;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _session = ChatSession();
  Map<String, dynamic>? _conv;
  bool _error = false;
  bool _loadingOlder = false;
  String? _peerAvatarUrl;
  String? _peerName;
  int _tempSeq = 0;
  bool _greeted = false;
  bool _sending = false;
  bool _uploadingImage = false;
  bool _hasRating = false;
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
      // Task I-2: si la lista de conversaciones ya nos pasó peer_name/avatar
      // (extra del push), no hace falta el RPC agregado `conversationsList()`
      // solo para resolverlos — ahorro de batería/red al entrar desde la lista.
      final needsPeerFetch = widget.peerName == null;
      final results = await Future.wait([
        fetchConversation(widget.conversationId),
        messagesPage(widget.conversationId, limit: _pageSize),
        if (needsPeerFetch) conversationsList() else Future.value(const <Map<String, dynamic>>[]),
        hasConversationRating(widget.conversationId),
      ]);
      final conv = results[0] as Map<String, dynamic>?;
      if (conv == null) throw StateError('not found');
      final page = results[1] as List<Map<String, dynamic>>;
      final hasRating = results[3] as bool;
      _session.seedFirstPage(page, _pageSize);
      if (!mounted) return;
      setState(() {
        _conv = conv;
        _hasRating = hasRating;
        if (!needsPeerFetch) {
          _peerName = widget.peerName;
          _peerAvatarUrl = widget.peerAvatarUrl;
        } else {
          final listRow = (results[2] as List<Map<String, dynamic>>)
              .where((c) => c['id'] == widget.conversationId).toList();
          if (listRow.isNotEmpty) {
            _peerName = listRow.first['peer_name'] as String?;
            _peerAvatarUrl = listRow.first['peer_avatar_url'] as String?;
          }
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

  /// Hook post-carga: welcome disclaimer, auto-saludo del proveedor y
  /// auditoría 72h. Cada paso guarda `mounted` tras su(s) await(s) porque
  /// el usuario puede salir del chat mientras cualquiera de estas llamadas
  /// de red o el diálogo está en vuelo.
  Future<void> _afterLoad() async {
    final conv = _conv;
    if (conv == null) return;
    // 1) Welcome disclaimer, 1 vez por conversación.
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final key = 'chat_welcome_${conv['id']}';
    if (!(prefs.getBool(key) ?? false)) {
      final cfg = await chatWelcomeConfig();
      if (!mounted) return;
      await showWelcomeDialog(context,
          title: (_isProvider ? cfg['provider_title'] : cfg['customer_title']) as String,
          body: (_isProvider ? cfg['provider_body'] : cfg['customer_body']) as String,
          buttonLabel: cfg['button_label'] as String);
      await prefs.setBool(key, true);
    }
    // 2) Auto-saludo del proveedor en chat vacío.
    if (_isProvider && _isOpen && _session.messages.isEmpty && !_greeted) {
      _greeted = true;
      final results = await Future.wait([
        conversationCustomerFirstName(conv['id'] as String),
        myBusinessName(),
        chatWelcomeConfig(),
      ]);
      if (!mounted) return;
      final customer = results[0] as String?;
      final biz = results[1] as String?;
      final cfg = results[2] as Map<String, dynamic>;
      final priceTxt = conv['agreed_price'] != null
          ? ' por ${fmtRD(conv['agreed_price'] as num)}'
          : conv['agreed_hourly_rate'] != null
              ? ' por ${fmtRD(conv['agreed_hourly_rate'] as num)}/hora'
              : '';
      final body = buildGreeting(cfg['auto_greeting_template'] as String,
          firstName: customer?.split(' ').first ?? 'cliente',
          business: biz ?? 'nuestro negocio',
          product: conv['product_name'] as String? ?? 'el producto acordado',
          priceTxt: priceTxt);
      // Re-chequeo: los 3 awaits de arriba (Future.wait) dejan una ventana
      // donde un mensaje puede llegar por realtime. Si ya no está vacío, no
      // enviar el saludo (pero _greeted queda en true, no reintentar).
      if (_session.messages.isEmpty) {
        await _sendRaw('text', body);
      }
    }
    // 3) Auditoría 72h. Solo el CLIENTE la dispara: es el destinatario del
    // "¿Ya recibiste tu producto?" y así hay un solo actor, sin carrera
    // cross-device entre cliente y proveedor abriendo el chat a la vez.
    // `_session.messages` solo trae los últimos 50 — en conversaciones largas
    // eso no basta para saber si la auditoría ya existe (podría estar más
    // atrás), así que primero evaluamos la parte barata (status/72h con los
    // datos ya cargados de `conv`) y solo si puede hacer falta consultamos.
    if (!_isProvider &&
        needsAudit(
            status: conv['status'] as String,
            createdAt: DateTime.parse(conv['created_at'] as String),
            hasAudit: false,
            now: DateTime.now())) {
      final already = await hasAuditMessage(conv['id'] as String);
      if (!mounted) return;
      if (!already) {
        await _sendRaw('audit', '¿Ya recibiste tu producto?', systemSender: true);
      }
    }
  }

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
  /// `systemSender: true` fuerza sender NULL — gana sobre `senderIdOverride`.
  /// RLS de prod: solo `kind 'audit'` acepta sender NULL; `kind 'system'`
  /// exige sender_id = auth.uid(), así que va sin `systemSender`.
  Future<bool> _sendRaw(String kind, String body,
      {String? senderIdOverride, bool systemSender = false}) async {
    final sender = systemSender ? null : (senderIdOverride ?? _uid);
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

  /// Mejorar oferta: el proveedor baja el precio acordado en un chat abierto
  /// y se lo notifica al cliente con un mensaje system en el chat. El
  /// mensaje va SIN `systemSender` (sender = _uid): la RLS de prod exige
  /// `sender_id = auth.uid()` para `kind 'system'` (solo `audit` acepta
  /// sender NULL). Como el update y el mensaje ocurren en chat abierto, no
  /// hay problema de status (a diferencia de "completado", donde el RLS
  /// bloquea inserts post-cierre).
  void _openImproveOffer() {
    final current = _conv?['agreed_price'] as num?;
    final ctrl = TextEditingController(text: current?.toString() ?? '');
    showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Mejorar oferta'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Reduce el precio acordado. Se notificará al cliente en el chat con el ahorro.',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Text('Precio actual: ${current != null ? fmtRD(current) : '—'}'),
                TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nuevo precio (RD\$)')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () async {
                      final next = num.tryParse(ctrl.text.replaceAll(',', '').trim());
                      if (next == null || next <= 0) {
                        _snack('Ingresa un precio válido.');
                        return;
                      }
                      if (current != null && next >= current) {
                        _snack('El nuevo precio debe ser menor al actual.');
                        return;
                      }
                      Navigator.of(ctx).pop();
                      try {
                        await improveOfferPrice(widget.conversationId, next);
                        if (!mounted) return;
                        final body = current != null
                            ? '🎉 El proveedor mejoró la oferta a ${fmtRD(next)} — ahorro de ${fmtRD(current - next)}.'
                            : '🎉 El proveedor estableció un nuevo precio: ${fmtRD(next)}.';
                        await _sendRaw('system', body);
                        if (!mounted) return;
                        _snack('Oferta mejorada.');
                        await _reload();
                      } catch (_) {
                        if (!mounted) return;
                        _snack('No se pudo mejorar la oferta.');
                      }
                    },
                    child: const Text('Mejorar oferta')),
              ],
            ));
  }

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
      title: GestureDetector(
        onTap: () => showAgreementDetails(context, conv, peerName: _peerName, isProvider: _isProvider),
        child: ListTile(
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
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999)),
          child: Text(
              conv['status'] == 'abierto'
                  ? 'Abierto'
                  : conv['status'] == 'cerrado'
                      ? 'Completado'
                      : 'No concretado',
              style: const TextStyle(fontSize: 11)),
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'complete':
                if (await showCompleteDialog(context)) {
                  if (!mounted) return;
                  try {
                    await markConversationCompleted(widget.conversationId);
                    if (!mounted) return;
                    // El mensaje system lo inserta la RPC (la RLS bloquea inserts post-cierre).
                    _snack('Marcado como completado.');
                    await _reload();
                  } catch (_) {
                    _snack('No se pudo marcar. Intenta de nuevo.');
                  }
                }
              case 'lost':
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                          title: const Text('¿Marcar como no concretado?'),
                          content: const Text(
                              'Esta acción es definitiva, la conversación no se puede reabrir.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancelar')),
                            FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Sí, marcar')),
                          ],
                        ));
                if (!mounted) return;
                if (ok == true) {
                  try {
                    await markConversationLost(widget.conversationId);
                    if (!mounted) return;
                    _snack('Marcado como no concretado.');
                    await _reload();
                  } catch (_) {
                    _snack('No se pudo marcar. Intenta de nuevo.');
                  }
                }
              case 'report':
                final r = await showReportDialog(context, reportedName: _peerName);
                if (!mounted) return;
                if (r != null) {
                  try {
                    await reportAccount(
                        reporterId: _uid,
                        reportedUserId: (_isProvider
                            ? _conv!['customer_id']
                            : _conv!['provider_user_id']) as String,
                        convId: widget.conversationId,
                        reason: r.$1,
                        details: r.$2);
                    if (!mounted) return;
                    _snack('Denuncia enviada. Gracias por avisarnos.');
                  } catch (_) {
                    _snack('No se pudo enviar la denuncia.');
                  }
                }
            }
          },
          itemBuilder: (_) => [
            if (_isProvider && _isOpen) ...[
              const PopupMenuItem(value: 'complete', child: Text('Marcar como completado')),
              const PopupMenuItem(value: 'lost', child: Text('Marcar como perdido')),
            ],
            const PopupMenuItem(value: 'report', child: Text('Denunciar cuenta')),
          ],
        ),
      ],
    );
  }

  /// Banner de cerrado, o composer si la conversación sigue abierta.
  Widget _buildBottom(Map<String, dynamic> conv) {
    if (!_isProvider && conv['status'] == 'cerrado' && !_hasRating) {
      return RatingPanel(
          convId: widget.conversationId,
          customerId: conv['customer_id'] as String,
          providerUserId: conv['provider_user_id'] as String,
          onDone: () => setState(() => _hasRating = true));
    }
    if (!_isOpen) {
      final txt = conv['status'] == 'cerrado'
          ? 'Pedido marcado como completado. El chat queda cerrado y ya no es posible enviar mensajes.'
          : 'Conversación marcada como no concretada. No puede reabrirse.';
      return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(txt, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            if (_hasRating && !_isProvider)
              const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Ya enviaste tu calificación.',
                      style: TextStyle(fontSize: 12))),
          ]));
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
