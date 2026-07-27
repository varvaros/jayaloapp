import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repos.dart';
import '../../domain/chat.dart';
import '../../domain/chat_session.dart';
import '../../domain/chat_time.dart';
import '../../core/safe_image_picker.dart';
import '../../domain/image_pick.dart';
import '../../domain/money.dart';
import 'widgets/bubbles.dart';
import 'widgets/chat_dialogs.dart';
import 'funnel_status_store.dart';
import 'opened_conversations.dart';
import '../shared/brand_kit.dart';
import 'widgets/composer.dart';
import 'widgets/rating_form.dart';
import '../shared/jayalo_loader.dart';
import '../shared/violet_header.dart';
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';

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
  // Calificación bilateral: ¿el proveedor ya calificó al cliente? + el
  // business_id con el que la escribe (dueño → pasa la RLS de customer_reviews).
  bool _customerReviewed = false;
  String? _reviewBusinessId;
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;
  final _scroll = ScrollController();

  String get _uid => supa.auth.currentUser!.id;
  bool get _isProvider => _conv?['provider_user_id'] == _uid;
  bool get _isOpen => _conv?['status'] == 'abierto';

  @override
  void initState() {
    super.initState();
    // "Nueva" en la lista se quita al ENTRAR (pedido PO 2026-07-23): marcar la
    // conversación como abierta AQUÍ (no en _load) — se registra al abrir el
    // chat aunque la carga de mensajes tarde o falle. El store notifica y la
    // lista se repinta al instante.
    openedConversationsStore.markOpened(widget.conversationId);
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
      _maybeLoadProviderReview(conv);
      // Notificaciones leídas — best-effort, no bloquea la UI. Al leer este
      // chat, el badge de "Mensajes" de la barra debe bajar (pedido PO
      // 2026-07-21): se recuenta tras marcar leído.
      markChatNotificationsRead(widget.conversationId)
          .then((_) => messagesBadge.refresh())
          .catchError((_) {});
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
    if (mounted && conv != null) {
      setState(() => _conv = conv);
      _maybeLoadProviderReview(conv);
    }
  }

  /// Carga, para el PROVEEDOR en un chat de oferta, si ya calificó al cliente y
  /// con qué business_id — para poder mostrar el panel de calificación al
  /// cerrarse el chat. Best-effort: si falla, el panel simplemente no aparece.
  Future<void> _maybeLoadProviderReview(Map<String, dynamic> conv) async {
    final isProvider = conv['provider_user_id'] == _uid;
    final offerId = conv['source_id'] as String?;
    if (!isProvider || conv['kind'] != 'offer' || offerId == null) return;
    try {
      final results =
          await Future.wait([hasCustomerReview(offerId), offerBusinessId(offerId)]);
      if (!mounted) return;
      setState(() {
        _customerReviewed = results[0] as bool;
        _reviewBusinessId = results[1] as String?;
      });
    } catch (_) {
      // El panel no se muestra; no rompe el chat.
    }
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
      // La confirmación honra el texto personalizado que viajó en el payload
      // (p.replies); si no vino, se cae al lookup por defaults.
      final confirm = p.replies[option] ?? quickConfirmation(p.question, option);
      await _sendRaw('text', confirm);
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
      case PlusAction.sendStoreItem:
        await _pickAndSendStoreItem();
      case PlusAction.improveOffer:
        _openImproveOffer(); // Task 10
    }
  }

  Future<void> _pickAndSendPhoto() async {
    // Cámara o galería (pedido PO 2026-07-21: "imágenes del dispositivo").
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await guardedPick(
        (p) => p.pickImage(source: source, maxWidth: 1200, imageQuality: 85));
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

  /// "De mi tienda" (pedido PO 2026-07-21): el proveedor elige un producto o
  /// servicio de su tienda y lo comparte en el chat — foto (`kind 'image'`,
  /// body = URL, mismo formato que la web) + un texto con los detalles
  /// ([storeItemChatCaption]). Las fotos ya viven en Storage (public read):
  /// no hay que subir nada.
  Future<void> _pickAndSendStoreItem() async {
    List<Map<String, dynamic>> items = const [];
    try {
      final bid = await myBusinessId();
      if (bid != null) items = await myStoreProducts(bid);
    } catch (_) {}
    if (!mounted) return;
    if (items.isEmpty) {
      _snack('Aún no tienes productos o servicios en tu tienda.');
      return;
    }
    final (productos, servicios) = partitionStoreItems(items);
    final it = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget row(Map<String, dynamic> p) {
          final urls =
              (p['image_urls'] as List?)?.cast<String>() ?? const <String>[];
          final price = catalogPriceLabel(
              price: p['price'] as num?,
              priceMin: p['price_min'] as num?,
              priceMax: p['price_max'] as num?);
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: urls.isEmpty
                  ? Container(
                      width: 44,
                      height: 44,
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.storefront_outlined,
                          size: 20, color: cs.primary))
                  : JayaloNetworkImage(urls.first,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                          width: 44,
                          height: 44,
                          color: cs.surfaceContainerHighest)),
            ),
            title: Text(p['name'] as String? ?? 'Sin nombre',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(price, style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, p),
          );
        }

        Widget header(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(t,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
            );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .7),
            child: ListView(shrinkWrap: true, children: [
              if (productos.isNotEmpty) header('PRODUCTOS'),
              ...productos.map(row),
              if (servicios.isNotEmpty) header('SERVICIOS'),
              ...servicios.map(row),
            ]),
          ),
        );
      },
    );
    if (it == null || !mounted) return;
    setState(() => _uploadingImage = true);
    try {
      final urls =
          (it['image_urls'] as List?)?.cast<String>() ?? const <String>[];
      if (urls.isNotEmpty) await _sendRaw('image', urls.first);
      final price = catalogPriceLabel(
          price: it['price'] as num?,
          priceMin: it['price_min'] as num?,
          priceMax: it['price_max'] as num?);
      await _sendRaw('text', storeItemChatCaption(it, priceLabel: price));
    } catch (_) {
      _snack('No se pudo enviar el artículo.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  /// Selector del estado de embudo (privado del proveedor, pedido PO
  /// 2026-07-22): hoja con los chips; local, no toca la BD.
  Future<void> _pickFunnelStatus() async {
    await funnelStatusStore.ensureLoaded();
    if (!mounted) return;
    final current = funnelStatusStore.statusKey(widget.conversationId);
    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Estado del cliente',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Solo para ti — el cliente no lo ve.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in funnelStatuses)
                    ChoiceChip(
                      selected: current == s.key,
                      onSelected: (_) => Navigator.pop(ctx, s.key),
                      avatar: Text(s.emoji, style: const TextStyle(fontSize: 14)),
                      label: Text(s.label),
                      selectedColor: s.color.withValues(alpha: .22),
                      side: BorderSide(
                          color: current == s.key ? s.color : cs.outlineVariant),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (current != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, ''),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Quitar estado'),
                ),
            ]),
          ),
        );
      },
    );
    if (picked == null || !mounted) return; // cerró sin elegir
    await funnelStatusStore.setStatus(
        widget.conversationId, picked.isEmpty ? null : picked);
  }

  Future<void> _sendQuickItem(QuickItem item) async {
    if (item.options.isEmpty) {
      await _sendRaw('text', item.question);
      return;
    }
    // `quickSendBody` incluye el mapa de confirmaciones del emisor para que una
    // respuesta rápida EDITADA se confirme con su texto aunque el que contesta
    // no la tenga en sus defaults.
    await _sendRaw('quick', quickSendBody(item));
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
              Center(child: InteractiveViewer(child: JayaloNetworkImage(src))),
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
          body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
              icon: Icons.arrow_back_ios_new,
              tooltip: 'Atrás',
              // A la LISTA de conversaciones (pedido PO 2026-07-21), no al
              // home ni a lo que hubiera debajo en la pila.
              onTap: () => context.go('/messages')),
        ),
        Expanded(
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('No pudimos cargar esta conversación.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Reintentar')),
          ])),
        ),
      ]));
    }
    if (conv == null) {
      return Scaffold(
          body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
              icon: Icons.arrow_back_ios_new,
              tooltip: 'Atrás',
              // A la LISTA de conversaciones (pedido PO 2026-07-21), no al
              // home ni a lo que hubiera debajo en la pila.
              onTap: () => context.go('/messages')),
        ),
        const Expanded(child: JayaloLoaderBlock()),
      ]));
    }
    final ms = _session.messages;
    final pal = chatPalette(context);
    // Guía de bienvenida al chat, por rol: el proveedor y el cliente ven
    // consignas distintas. `_conv` ya está garantizado no-nulo en este punto
    // (los `if (conv == null)`/`_error` de arriba retornan antes), así que
    // `_isProvider` ya refleja el rol real — pero se gatea igual por
    // claridad/robustez ante refactors futuros.
    final chatGuideKey =
        _isProvider ? 'provider.chat_reveal.v1' : 'client.chat_reveal.v1';
    return Scaffold(
      body: OnboardingGuide(
        key: ValueKey(chatGuideKey),
        guideKey: chatGuideKey,
        mode: OnboardingMode.welcome,
        steps: onboardingCopy[chatGuideKey]!,
        enabled: _conv != null,
        child: Column(children: [
        _buildHeader(conv),
        // El panel lila ES la pantalla del chat (doctrina: un solo fondo lila,
        // inconfundible). La lista y el composer viven dentro.
        Expanded(
          child: Container(
            color: pal.panel,
            child: Column(children: [
              Expanded(
                // Fondo de doodles Jáyalo detrás de los mensajes (el composer
                // de abajo conserva el lila pleno). Base pal.panel por debajo
                // como fallback mientras carga el asset.
                child: Container(
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/chat-bg.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: ms.length + (_loadingOlder ? 1 : 0),
                  itemBuilder: (context, j) {
                    if (j >= ms.length) {
                      return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: JayaloSpinner(size: 18)));
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: pal.sys,
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(formatDayLabel(m.createdAt),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: pal.ink.withValues(alpha: .9))),
                      )),
                      bubble,
                    ]);
                  },
                  ),
                ),
              ),
              _buildBottom(conv),
            ]),
          ),
        ),
        ]),
      ),
    );
  }

  /// Header violeta del chat: atrás + nombre del peer (con el pedido de
  /// subtítulo) centrado + menú. Sin redondeo inferior: el panel lila calza
  /// justo debajo. Tocar el título abre el detalle del acuerdo.
  Widget _buildHeader(Map<String, dynamic> conv) {
    return VioletHeader(
      bottomRadius: 0,
      leading: HeaderCircleButton(
          icon: Icons.arrow_back_ios_new,
          tooltip: 'Atrás',
          // A la LISTA de conversaciones (pedido PO 2026-07-21).
          onTap: () => context.go('/messages')),
      title: _peerName ?? (conv['product_name'] as String? ?? 'Acuerdo'),
      subtitle: conv['product_name'] as String?,
      titleAlign: HeaderTitleAlign.center,
      onTitleTap: () => showAgreementDetails(context, conv,
          peerName: _peerName, isProvider: _isProvider),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
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
                                style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(ctx).colorScheme.error),
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
              case 'funnel':
                await _pickFunnelStatus();
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
            // Estado de embudo (privado del proveedor, pedido PO 2026-07-22).
            if (_isProvider)
              const PopupMenuItem(value: 'funnel', child: Text('Estado del cliente')),
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
    // Lado del PROVEEDOR de la calificación bilateral (pedido PO): al cerrarse
    // un chat de oferta, el proveedor califica al cliente.
    if (_isProvider &&
        conv['status'] == 'cerrado' &&
        conv['kind'] == 'offer' &&
        _reviewBusinessId != null &&
        !_customerReviewed) {
      return CustomerRatingPanel(
        offerId: conv['source_id'] as String,
        businessId: _reviewBusinessId!,
        customerId: conv['customer_id'] as String,
        onDone: () => setState(() => _customerReviewed = true),
      );
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
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
