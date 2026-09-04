import 'dart:async';

import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/geocode_client.dart';
import '../../data/location_body.dart';
import '../../data/repos.dart';
import '../../domain/appointment.dart';
import '../../domain/chat.dart';
import '../../domain/chat_session.dart';
import '../../domain/chat_time.dart';
import '../../domain/geo.dart';
import '../../core/error_reporter.dart';
import '../../core/safe_image_picker.dart';
import '../../core/sfx.dart';
import '../../core/motion.dart';
import '../../domain/image_pick.dart';
import '../../domain/improve_offer_error.dart';
import '../../domain/money.dart';
import 'widgets/bubbles.dart';
import 'widgets/calendar_link.dart';
import 'widgets/chat_dialogs.dart';
import 'widgets/conversation_actions.dart';
import 'funnel_status_store.dart';
import 'opened_conversations.dart';
import '../shared/brand_kit.dart';
import 'widgets/composer.dart';
import 'widgets/propose_date_sheet.dart';
import 'widgets/rating_form.dart';
import 'widgets/typing_indicator.dart';
import '../shared/jayalo_loader.dart';
import '../shared/violet_header.dart';
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';
import '../shared/verified_badges.dart';

const _pageSize = 50;

/// Qué opciones ofrece el ⋮ del chat. Pura y pública para poder probar el
/// contrato sin montar la pantalla (su initState toca Supabase).
///
/// "No concretado" es de AMBOS participantes: la RLS y el grant por columna
/// sobre `status` siempre lo permitieron y el gate era solo de UI. "Completado"
/// sigue siendo del proveedor — cierra el trato y dispara la calificación.
List<String> chatMenuValues({required bool isProvider, required bool isOpen}) =>
    [
      // Perfil del cliente (mockup aprobado 2026-08-11): solo el PROVEEDOR —
      // el perfil anónimo/revelado es de clientes; el cliente ya ve la tienda
      // del proveedor por su propia vía.
      if (isProvider) 'profile',
      // Ver el WhatsApp del cliente (PO 2026-09-04). Va justo detrás del
      // perfil: las dos son "cosas del cliente". SIEMPRE presente para el
      // proveedor con el chat abierto — cuando no se puede se pinta gris con
      // el motivo (ver `whatsappMenuReason`), no se esconde. Con el chat
      // cerrado desaparece, como el resto de acciones vivas.
      if (isProvider && isOpen) 'whatsapp',
      if (isProvider && isOpen) 'complete',
      if (isOpen) 'lost',
      if (isProvider) 'funnel',
      'report',
    ];

/// Por qué el ⋮ puede (o no) enseñar el WhatsApp del cliente.
///
/// `unknown` es el estado de ARRANQUE y el de "la consulta falló": por
/// defecto el ítem sale gris, y solo el servidor puede habilitarlo.
enum WhatsappRevealGate { canReveal, optedOut, noPhone, unknown }

/// Motivo que va bajo «Ver WhatsApp del cliente» en el ⋮. `null` = el ítem va
/// habilitado. Pura y pública por el mismo motivo que [chatMenuValues]: se
/// fija en un test sin montar la pantalla (su initState toca Supabase).
String? whatsappMenuReason(WhatsappRevealGate gate) => switch (gate) {
      WhatsappRevealGate.canReveal => null,
      // El interruptor es del CLIENTE (`profiles.whatsapp_reveal_enabled`,
      // false por defecto): no es un fallo nuestro y el copy no debe sonar a
      // error. Es el caso de 9 de cada 10 ofertas reales.
      WhatsappRevealGate.optedOut => 'El cliente prefiere solo el chat de Jayalo',
      WhatsappRevealGate.noPhone => 'El cliente no dejó un teléfono',
      WhatsappRevealGate.unknown => 'No pudimos comprobarlo',
    };

/// ¿Se puede resolver el negocio de esta conversación para escribir en
/// `business_reviews`? Pura y pública para fijar el límite en un test sin
/// montar la pantalla (su `initState` toca Supabase).
///
/// Solo los chats de OFERTA. La política de INSERT de `business_reviews`
/// (migración 20260729210000) exige una `provider_offers` desbloqueada de ese
/// cliente con ese negocio, y un chat de producto no tiene ninguna. Ver el
/// comentario largo en `_loadReviewContext`.
bool canResolveReviewBusiness(String? kind) => kind == 'offer';

/// ¿Va la nota «Ya enviaste tu calificación» en el cartel del chat cerrado, para
/// el rol que lo está mirando?
///
/// Antes la nota era solo del cliente, y al proveedor que YA había calificado le
/// quedaba el aviso de cierre («Puedes calificar la transacción») sin nada
/// debajo que lo explicara: el panel había desaparecido justamente porque su
/// trabajo estaba hecho (bug reportado por el PO el 2026-08-25).
///
/// No es simétrica a propósito: el cliente califica en CUALQUIER chat cerrado,
/// el proveedor solo en los de OFERTA (ver [canResolveReviewBusiness]). En un
/// chat de producto el proveedor nunca tuvo calificador, así que decirle «ya
/// enviaste» sería la misma mentira por la puerta de al lado.
///
/// Pura y pública por el mismo motivo que la de arriba: se fija en un test sin
/// montar la pantalla.
bool showsRatingSentNote({
  required bool isProvider,
  required String? kind,
  required bool hasRating,
  required bool customerReviewed,
}) => isProvider
    ? (canResolveReviewBusiness(kind) && customerReviewed)
    : hasRating;

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
  // Sellos de la contraparte, junto al nombre de la cabecera (PO 2026-07-28,
  // paso 7 — slot `titleTrailing` de `VioletHeader`). Best-effort: null si no
  // hay relación registrada o la RPC falla; la cabecera se pinta igual.
  PeerBadges? _peerBadges;
  int _tempSeq = 0;
  bool _greeted = false;
  bool _sending = false;
  // Guarda de reentrada para _sendCurrentLocation: el GPS puede tardar hasta
  // 15s (timeLimit) y ese metodo no toca _sending, asi que sin esto un
  // segundo toque en "+" durante la espera mandaba dos mensajes de ubicacion.
  bool _capturingLocation = false;
  bool _uploadingImage = false;
  bool _hasRating = false;
  // Calificación bilateral: ¿el proveedor ya calificó al cliente? + el
  // business_id con el que la escribe (dueño → pasa la RLS de customer_reviews).
  bool _customerReviewed = false;
  String? _reviewBusinessId;
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;
  final _scroll = ScrollController();

  // ── "…está escribiendo" ────────────────────────────────────────────────────
  // Viaja por BROADCAST en el canal que el chat ya tiene abierto: no toca la BD
  // (no hay fila que escribir ni RLS que pasar) y no deja rastro — es estado
  // efímero, que es exactamente lo que es "estoy escribiendo".
  //
  // Se apoya en que las DOS puntas corran esta app. Un peer que esté en la web
  // no emite `typing`, así que el indicador simplemente no aparece: el chat se
  // comporta igual que antes, sin degradarse.
  static const _typingEvent = 'typing';

  /// Cada cuánto, como MÁXIMO, se emite mientras el usuario teclea. Sin este
  /// tope se mandaría un frame de websocket por pulsación.
  static const _typingThrottle = Duration(seconds: 2);

  /// Cuánto sobrevive el indicador sin recibir un `typing` nuevo. Tiene que ser
  /// holgadamente mayor que [_typingThrottle], si no titila entre emisiones.
  static const _typingTimeout = Duration(seconds: 5);

  bool _peerTyping = false;
  DateTime? _lastTypingSent;
  Timer? _peerTypingTimer;

  /// URLs firmadas de las fotos del bucket privado, por marcador `chat-media:`.
  /// Se llena tras cada carga o mensaje entrante; mientras falte una, su burbuja
  /// muestra el placeholder en vez de desaparecer.
  final Map<String, String> _signedChatImages = {};

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
    // Para que el push NO duplique el aviso sonoro mientras miras este chat.
    activeConversationId = widget.conversationId;
    _load();
    _lifecycle = AppLifecycleListener(
      onPause: _teardownRealtime,
      onResume: _resume,
    );
    _scroll.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    // ORDEN: bajar el indicador a mano ANTES de `_teardownRealtime`, que
    // también lo baja. Acá el State se está yendo y `setState` ya no es legal,
    // así que se apagan el timer y la bandera en crudo; con `_peerTyping` ya en
    // false, el `_clearPeerTyping` de adentro del teardown no llama a setState.
    _peerTypingTimer?.cancel();
    _peerTypingTimer = null;
    _peerTyping = false;
    _teardownRealtime();
    // Solo si sigue siendo la mía: si ya se abrió otra conversación, el dispose
    // tardío de esta no debe borrar la marca de la que está en pantalla.
    if (activeConversationId == widget.conversationId) activeConversationId = null;
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
      ]);
      final conv = results[0] as Map<String, dynamic>?;
      if (conv == null) throw StateError('not found');
      final page = results[1] as List<Map<String, dynamic>>;
      // `hasConversationRating` sale del `Future.wait` a propósito: desde el
      // 2026-08-29 necesita el `source_id` de la conversación para poder mirar
      // también `business_reviews` (ver su doc), y dentro del wait `conv` todavía
      // no existe. Cuesta un viaje más; a cambio, el cliente que ya calificó
      // desde la web no vuelve a ver el formulario aquí ni pisa su propia nota.
      final hasRating = await hasConversationRating(
        widget.conversationId,
        offerId: conv['kind'] == 'offer' ? conv['source_id'] as String? : null,
      );
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
      _resolveChatImages();
      _loadReviewContext(conv);
      // Sellos de la contraparte — best-effort, no bloquea la UI (mismo
      // patrón fire-and-forget que las notificaciones leídas de abajo).
      _loadPeerBadges(conv);
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

  /// Sellos de verificación de la contraparte, junto al nombre de la
  /// cabecera. Best-effort a propósito (try/catch propio, no `await`ado desde
  /// `_load`): si la RPC falla o `conv` viene sin los ids esperados, el chat
  /// se pinta igual, sin sello — nunca debe dejar la pantalla en blanco.
  Future<void> _loadPeerBadges(Map<String, dynamic> conv) async {
    try {
      final peerId = (conv['customer_id'] == _uid
          ? conv['provider_user_id']
          : conv['customer_id']) as String?;
      if (peerId == null) return;
      final badges = (await peerVerificationBadges([peerId]))[peerId];
      if (mounted) setState(() => _peerBadges = badges);
    } catch (_) {
      // best-effort: sin sello, la cabecera se pinta igual.
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
    // Aquí vivía la "auditoría 72h": el CLIENTE insertaba «¿Ya recibiste tu
    // producto?» como `kind:'audit', sender_id:null` al abrir un chat viejo.
    // Retirada el 2026-08-28 porque era IMPOSIBLE desde el 2026-07-29: la
    // política de INSERT solo admite text|address|image|quick con
    // `sender_id = auth.uid()`, así que ese insert rebotaba con 42501, retiraba
    // la burbuja optimista y le pintaba al cliente un "No se pudo enviar" que no
    // venía de nada que hubiera hecho. No se veía por dos tapaderas: el cartel
    // del cron a las 48 h ya dejaba un `audit` (`hasAuditMessage` buscaba
    // CUALQUIERA, no el suyo) y a las 72 h el chat ya estaba cerrado. Al pasar
    // el cierre a una semana las dos desaparecían a la vez, y el error habría
    // salido en cada apertura entre la hora 72 y la 144.
    // La web la retiró por lo mismo el 2026-08-13. Los carteles de plataforma
    // los pone el servidor: `warn_stale_conversations` avisa a las 24 h, 96 h y
    // 144 h, y `auto_close_stale_conversations` cierra a las 168 h.
  }

  /// Relee la conversación (estado, precio acordado…). Best-effort DE VERDAD:
  /// se traga el fallo de red, y por eso el guard vive aquí y no en cada
  /// llamador.
  ///
  /// Motivo (hallazgo de revisión, 2026-07-31): `_resume()` la llama desde un
  /// callback de ciclo de vida que NADIE atrapa — una excepción ahí se saltaba
  /// el `_setupRealtime()` de la línea siguiente y el chat se quedaba SIN
  /// realtime en silencio, justo tras volver de background, que es cuando más
  /// probable es un tropiezo de red. Y el `catch` del envío la llama antes de
  /// mostrar su SnackBar: una excepción ahí dejaba al usuario sin ningún aviso.
  ///
  /// De paso arregla tres llamadores que ya la envolvían: su `catch` cubría
  /// también la MUTACIÓN previa, así que un "Marcar como completado" que iba
  /// bien pero cuyo refresco fallaba avisaba "No se pudo marcar" — mentira.
  Future<void> _reload() async {
    try {
      final conv = await fetchConversation(widget.conversationId);
      if (mounted && conv != null) {
        setState(() => _conv = conv);
        _loadReviewContext(conv);
      }
    } catch (_) {
      // Se conserva lo que había: el estado se corrige en el próximo resume,
      // envío o recarga.
    }
  }

  /// Resuelve el contexto de calificación de ESTA conversación para el rol que
  /// la mira:
  /// - proveedor en chat de oferta: si ya calificó al cliente (panel bilateral);
  /// - siempre: el `business_id`, que el panel del CLIENTE necesita para que su
  ///   nota llegue a `business_reviews` (la que alimenta la reputación).
  ///
  /// Best-effort de punta a punta: si falla, el panel aparece igual y como
  /// mucho se pierde la segunda escritura.
  Future<void> _loadReviewContext(Map<String, dynamic> conv) async {
    final isProvider = conv['provider_user_id'] == _uid;
    final sourceId = conv['source_id'] as String?;
    final kind = conv['kind'] as String?;
    if (sourceId == null) return;
    try {
      // SOLO los chats de OFERTA resuelven negocio, aunque
      // `get_or_create_conversation` también cree los de `product_interest` y
      // `interestBusinessId()` sepa resolverlos.
      //
      // Por qué (hallazgo de la revisión final, 2026-08-01): la política de
      // INSERT de `business_reviews` (migración 20260729210000) exige
      //   EXISTS (SELECT 1 FROM provider_offers o
      //            WHERE o.customer_id = auth.uid()
      //              AND o.business_id = business_reviews.business_id
      //              AND o.unlocked_at IS NOT NULL)
      // y en un chat de producto NO hay ninguna fila así: el cliente escribió
      // por un artículo de la tienda, no por una oferta a una solicitud. La
      // escritura rebotaba con 42501 y el `catch` best-effort de `RatingPanel`
      // se la tragaba: el usuario veía "Gracias por tu calificación" y la
      // reputación no se movía. Dejando `bizId` en null ni se intenta, así que
      // no hay fallo silencioso; la nota sigue guardándose en
      // `conversation_ratings`.
      //
      // Decisión del PO: aceptar el límite por ahora. Ampliar la política para
      // admitir un `product_interest` desbloqueado agranda la superficie de
      // quién puede escribir reseñas y merece su propia sesión con verificación
      // de seguridad.
      final bizId =
          canResolveReviewBusiness(kind) ? await offerBusinessId(sourceId) : null;
      final reviewed = (isProvider && kind == 'offer')
          ? await hasCustomerReview(sourceId)
          : false;
      if (!mounted) return;
      setState(() {
        _reviewBusinessId = bizId;
        _customerReviewed = reviewed;
      });
    } catch (_) {
      // El panel no se rompe; a lo sumo no hay segunda escritura.
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
            // Llegó el mensaje: ya terminó de escribir. Bajar el indicador acá
            // (y no esperar el timeout) evita que los tres puntos queden
            // rebotando debajo del mensaje que acaban de anunciar.
            if (payload.newRecord['sender_id'] != _uid) _clearPeerTyping();
            if (_session.mergeServer(payload.newRecord)) {
              // Aviso discreto: ya estás mirando el chat, solo confirma que
              // llegó algo. Solo para lo que escribe el OTRO (mi propio eco del
              // realtime no debe sonarme) y solo mensajes de persona: 'system'
              // y 'audit' son carteles del servidor.
              final kind = payload.newRecord['kind'] as String? ?? '';
              if (payload.newRecord['sender_id'] != _uid && !isSystemKind(kind)) {
                playSfx(Sfx.messageInChat);
              }
              if (mounted) setState(() {});
              _jumpToBottom();
              _resolveChatImages();
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
        .onBroadcast(
          event: _typingEvent,
          callback: (payload) {
            // El broadcast le llega también al que lo emitió: filtrar por uid es
            // lo que evita verse a sí mismo "escribiendo".
            if (payload['uid'] == _uid) return;
            _markPeerTyping();
          },
        )
        .subscribe();
  }

  /// Levanta el indicador y (re)arma su vencimiento. Cada `typing` que llega
  /// corre el plazo hacia adelante, así que mientras el peer siga teclando el
  /// indicador se sostiene; si deja de teclar (o cierra la app, o se le cae la
  /// red) baja solo pasado [_typingTimeout] — nunca queda colgado.
  void _markPeerTyping() {
    _peerTypingTimer?.cancel();
    _peerTypingTimer = Timer(_typingTimeout, _clearPeerTyping);
    if (!_peerTyping && mounted) setState(() => _peerTyping = true);
  }

  void _clearPeerTyping() {
    _peerTypingTimer?.cancel();
    _peerTypingTimer = null;
    if (_peerTyping && mounted) setState(() => _peerTyping = false);
  }

  /// Avisa que ESTE usuario está escribiendo. Lo llama el composer en cada
  /// pulsación; el throttle vive acá para que la pantalla no tenga que saber
  /// nada del transporte.
  void _notifyTyping() {
    final ch = _channel;
    if (ch == null) return;
    final now = DateTime.now();
    final last = _lastTypingSent;
    if (last != null && now.difference(last) < _typingThrottle) return;
    _lastTypingSent = now;
    // Best-effort y deliberadamente sin `await`: si el envío falla lo único que
    // pasa es que al peer no le aparecen los puntos. Nada de esto debe poder
    // interponerse entre el usuario y su teclado — `ignore()` descarta también
    // el error, para que un socket caído no suba una excepción sin capturar.
    ch
        .sendBroadcastMessage(event: _typingEvent, payload: {'uid': _uid})
        .ignore();
  }

  void _teardownRealtime() {
    final ch = _channel;
    _channel = null;
    // El canal se va: ningún `typing` nuevo va a llegar, así que el indicador
    // no debe quedar arriba, y `_lastTypingSent` se limpia para que el primer
    // tecleo tras reconectar avise de una (no herede el throttle del canal
    // viejo).
    _clearPeerTyping();
    _lastTypingSent = null;
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
    // El ESTADO de la conversación también pudo cambiar mientras estábamos en
    // background, y no llega por realtime: `conversations` no está en la
    // publicación (solo `conversation_messages`, `notifications` y
    // `provider_offers`). Es justo la ventana del cron de inactividad: dejas
    // la app, a las 72 h se cierra el chat, vuelves y el composer seguía
    // pintado. Best-effort: si falla, se conserva lo que había.
    if (mounted) await _reload();
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
      // Las fotos que entran con el historial también hay que firmarlas, o se
      // quedan con el placeholder girando para siempre.
      _resolveChatImages();
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
    // Golpecito de "salió": este es el embudo ÚNICO de todo lo que el usuario
    // manda al chat (texto, respuesta rápida, foto, dirección, contacto,
    // ubicación, artículo de tienda), así que el pulso va acá y no repetido en
    // cada handler. Se excluye `systemSender`: esos son carteles del servidor,
    // no algo que el usuario haya enviado.
    if (!systemSender) JayaloHaptics.sent();
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
    } catch (e) {
      _session.removeOptimistic(tempId);
      final code = e is PostgrestException ? e.code : null;
      // Rechazo por RLS: la política de envío exige que la conversación esté
      // 'abierto', así que casi seguro se cerró mientras la teníamos delante
      // — el cron de inactividad (72 h) o la otra parte marcándola completada
      // o no concretada. NO hay realtime sobre `conversations` (la tabla no
      // está en la publicación), así que la pantalla no se entera sola.
      // Releemos: el composer deja paso al banner de cerrado y el aviso pasa a
      // decir la verdad en vez de invitar a reintentar contra una puerta
      // cerrada (bug del PO 2026-07-31).
      if (shouldRecheckConversation(code)) await _reload();
      if (mounted) {
        setState(() {});
        // El anti-flood y el tope de longitud del servidor traen su propio
        // texto en español; los demás fallos caen al genérico.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(sendFailureMessage(
                code: code,
                serverMessage: e is PostgrestException ? e.message : null,
                conversationClosed: !_isOpen))));
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
      // El rollback NO puede depender de que el widget siga vivo: si el usuario
      // salió del chat mientras viajaba el update, `setState` LANZA antes de
      // restaurar y el mensaje se queda pintado con una respuesta que nunca se
      // guardó. Primero se deshace el modelo, después se repinta si hay a quién.
      m.body = prevBody;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo responder. Intenta de nuevo.')));
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
      case PlusAction.sendCurrentLocation:
        await _sendCurrentLocation();
      case PlusAction.sendPhoto:
        await _pickAndSendPhoto();
      case PlusAction.sendStoreItem:
        await _pickAndSendStoreItem();
      case PlusAction.proposeDate:
        await _openProposeDate();
      case PlusAction.improveOffer:
        _openImproveOffer(); // Task 10
    }
  }

  /// Abre la hoja de proponer fecha y manda lo elegido a la RPC. La tarjeta
  /// llega por el INSERT de realtime: no hay nada optimista que pintar.
  Future<void> _openProposeDate({String? subject}) async {
    final conv = _conv;
    if (conv == null || !_isOpen) return;
    final res = await showProposeDateSheet(context,
        convId: widget.conversationId,
        defaultSubject: subject ??
            (conv['product_name'] as String?) ??
            (conv['request_title'] as String?) ??
            '');
    if (res == null || !mounted) return;
    const generico = 'No se pudo proponer la fecha. Intenta de nuevo.';
    try {
      await proposeScheduledDate(
          widget.conversationId, res.subject, res.startsAt);
    } on PostgrestException catch (e) {
      // Solo se repite el texto del servidor cuando sale de una guarda NUESTRA
      // (P0001 de la RPC, JY429 del anti-flood: la tarjeta cuenta como
      // mensaje). Cualquier otro código —PGRST202 si el APK llegó antes que la
      // migración, 42501, JWT— se queda en el genérico: mismo criterio que
      // `sendFailureMessage`, que no filtra tripas del servidor.
      if (mounted) {
        _snack(appointmentFailureMessage(
            code: e.code, serverMessage: e.message, fallback: generico));
      }
    } catch (_) {
      if (mounted) _snack(generico);
    }
  }

  /// Acción tocada en una tarjeta de fecha pautada. 'confirm' y 'cancel' van a
  /// `respond_scheduled_date`; 'done_yes'/'done_no' (tarjeta de seguimiento)
  /// van a `answer_scheduled_followup`; 'propose_again' y 'calendar' son
  /// locales de la app.
  Future<void> _onAppointmentAction(AppointmentPayload a, String action) async {
    switch (action) {
      case 'propose_again':
        await _openProposeDate(subject: a.subject);
      case 'calendar':
        // `startsAtUtc` ya es UTC verdadero: se pasa TAL CUAL, sin corregir
        // ningún huso a mano.
        await openCalendarLink(
            context,
            googleCalendarUrl(
                subject: a.subject,
                startsAtUtc: a.startsAtUtc,
                details: 'Acordada en el chat de Jayalo'));
      case 'done_yes':
      case 'done_no':
        {
          const generico = 'No se pudo enviar tu respuesta. Intenta de nuevo.';
          try {
            // El UPDATE del body llega por realtime; esta RPC no exige la
            // conversación abierta (ver `answerScheduledFollowup`), así que
            // no hay guard de `_isOpen` aquí.
            await answerScheduledFollowup(a.appointmentId, action == 'done_yes');
          } on PostgrestException catch (e) {
            // Nunca JY429 (no inserta mensaje); mismo filtro que el resto:
            // español nuestro sí, tripas del servidor no.
            if (mounted) {
              _snack(appointmentFailureMessage(
                  code: e.code, serverMessage: e.message, fallback: generico));
            }
          } catch (_) {
            if (mounted) _snack(generico);
          }
        }
      default: // 'confirm' | 'cancel'
        const generico = 'No se pudo completar la acción. Intenta de nuevo.';
        try {
          // El UPDATE del body y el cartel `system` llegan por realtime.
          await respondScheduledDate(a.appointmentId, action);
        } on PostgrestException catch (e) {
          // Esta RPC no puede dar JY429 (escribe un `system`, exento), pero el
          // filtro es el mismo: español nuestro sí, tripas del servidor no.
          if (mounted) {
            _snack(appointmentFailureMessage(
                code: e.code, serverMessage: e.message, fallback: generico));
          }
        } catch (_) {
          if (mounted) _snack(generico);
        }
    }
  }

  /// GPS del momento, no la direccion guardada: es el caso del cliente que NO
  /// esta en su casa. Best-effort — si el permiso falla no se manda nada, y si
  /// el reverse-geocode falla se manda igual con solo el enlace.
  Future<void> _sendCurrentLocation() async {
    if (_capturingLocation) return;
    setState(() => _capturingLocation = true);
    _snack('Captando tu ubicación…');
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        _snack('Sin permiso de ubicación — puedes enviar tu dirección guardada.');
        return;
      }
      // El timeout es obligatorio: sin el, un GPS que no responde deja la
      // accion colgada (mismo bug que documenta consumer_onboarding_screen).
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      var street = '';
      final token = supa.auth.currentSession?.accessToken;
      if (token != null) {
        // `lookup` NUNCA lanza: devuelve `empty` si falla.
        final place = await GeocodeClient()
            .lookup(lat: pos.latitude, lng: pos.longitude, accessToken: token);
        street = place.addressLine.isNotEmpty
            ? place.addressLine
            : composeAddressLine(
                street: place.street,
                streetNumber: place.streetNumber,
                sector: place.sector,
                city: place.city,
              );
      }
      final body = buildLocationBody(
        address: street.isNotEmpty ? street : 'Ubicación compartida',
        cityLine: '',
        reference: '',
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (body == null || !mounted) return;
      await _sendRaw('address', body);
    } catch (_) {
      if (!mounted) return;
      _snack('No pudimos captar tu ubicación — puedes enviar tu dirección guardada.');
    } finally {
      if (mounted) setState(() => _capturingLocation = false);
    }
  }

  Future<void> _pickAndSendPhoto() async {
    // Cámara o galería (pedido PO 2026-07-21: "imágenes del dispositivo").
    final source = await showModalBottomSheet<ImageSource>(
      sheetAnimationStyle: JayaloMotion.sheetMenu,
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
      // Devuelve el marcador `chat-media:{ruta}` del bucket privado, no una URL.
      final marker = await uploadChatImage(picked.path, widget.conversationId);
      await _sendRaw('image', marker);
      // Firmarla ya, para que la foto propia se vea sin esperar a un refresco.
      await _resolveChatImages();
    } catch (_) {
      _snack('No se pudo enviar la imagen.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  /// Pide URL firmada para las fotos que viven en el bucket privado y que aún no
  /// tenemos. Las que ya son URL pública (compartir-artículo) no pasan por aquí.
  ///
  /// Best-effort: si la firma falla, la burbuja se queda en su placeholder y el
  /// siguiente mensaje o recarga vuelve a intentarlo. Nunca debe tumbar el chat.
  Future<void> _resolveChatImages() async {
    final pendientes = _session.messages
        .where((m) => m.kind == 'image' && isChatMediaMarker(m.body))
        .map((m) => m.body)
        .where((b) => !_signedChatImages.containsKey(b))
        .toList();
    if (pendientes.isEmpty) return;
    try {
      final firmadas = await signChatImages(pendientes);
      if (firmadas.isEmpty || !mounted) return;
      setState(() => _signedChatImages.addAll(firmadas));
    } catch (e) {
      debugPrint('No se pudieron firmar las fotos del chat: $e');
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
      // Contenido: es el catálogo de la tienda, se navega y se lee.
      sheetAnimationStyle: JayaloMotion.sheetRise,
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
      sheetAnimationStyle: JayaloMotion.sheetMenu,
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

  /// Mejorar oferta: el proveedor baja el precio acordado en un chat abierto y
  /// se lo notifica al cliente con un mensaje system.
  ///
  /// El aviso ya NO se manda desde aquí. `authenticated` no puede insertar
  /// `kind='system'` desde el 2026-07-29 (hallazgo M-2: permitía falsificar
  /// carteles de plataforma), así que el mensaje lo escribe la propia RPC
  /// `improve_offer_price` en la misma transacción que el precio — igual que
  /// `mark_conversation_completed` con el "✓ Marcado como completado".
  ///
  /// Las validaciones de abajo se quedan como feedback inmediato, pero la
  /// autoridad es la RPC: es alcanzable directo por PostgREST.
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
                        _snack('Oferta mejorada.');
                      } catch (e, s) {
                        // Nada de `catch (_)`: este flujo estuvo roto en
                        // producción y el mensaje mudo lo tapó. Los rechazos
                        // de negocio (P0001) se muestran tal cual; el resto va
                        // al reporter para que se vea sin depender del PO.
                        unawaited(reportError(e, s));
                        if (!mounted) return;
                        _snack(improveOfferErrorCopy(e));
                      }
                      // Dentro y fuera del error: si la RPC llegó a escribir,
                      // el precio y el mensaje nuevos tienen que aparecer, y
                      // si falló hay que confirmar que el precio NO cambió.
                      await _reload();
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
        order: 1,
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
                  itemCount: ms.length +
                      (_loadingOlder ? 1 : 0) +
                      (_peerTyping ? 1 : 0),
                  // Sin esto, la clave del item no conserva nada: el sliver
                  // guarda sus hijos POR INDICE y, al correrse, tira el que no
                  // coincide y lo reconstruye. Ver chatItemIndexForKey.
                  findChildIndexCallback: (key) => chatItemIndexForKey(
                      key, ms,
                      peerTyping: _peerTyping, loadingOlder: _loadingOlder),
                  itemBuilder: (context, j) {
                    // Lista invertida: j=0 es el BORDE INFERIOR. El indicador
                    // va justo ahí, debajo del último mensaje, que es donde
                    // aparecería el que el peer está escribiendo. Los demás
                    // índices se corren uno.
                    //
                    // Los dos ítems que NO son mensajes llevan clave propia por
                    // el mismo motivo que `keyedChatItem`: aparecen y
                    // desaparecen (el indicador entra y sale por el índice 0),
                    // y sin identidad corren los emparejamientos de todo lo que
                    // tienen debajo.
                    if (_peerTyping) {
                      if (j == 0) {
                        return TypingIndicator(
                            key: chatTypingKey,
                            peerAvatarUrl: _peerAvatarUrl);
                      }
                      j -= 1;
                    }
                    if (j >= ms.length) {
                      return const Padding(
                          key: chatLoadingOlderKey,
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
                        canAnswerQuick: _isOpen,
                        onAppointmentAction: _onAppointmentAction,
                        isProvider: _isProvider,
                        conversationOpen: _isOpen,
                        signedChatImages: _signedChatImages);
                    // La clave del ítem la pone `keyedChatItem` sobre la forma
                    // FINAL (con separador o sin él): sin identidad estable, un
                    // mensaje nuevo corre todos los índices y el estado de una
                    // tarjeta de fecha pautada en vuelo se muda a otra tarjeta.
                    if (!needsDaySep(ms, i)) return keyedChatItem(m, bubble);
                    return keyedChatItem(
                        m,
                        Column(children: [
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
                        ]));
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
      // El sello se SUMA, nunca sustituye: title/subtitle intactos. `null`
      // (no un `VerifiedLabel` vacío) cuando no hay sello, para que
      // `VioletHeader` se pinte EXACTAMENTE como sin este slot — sin el
      // espaciado extra de un `Row` que solo contendría un `SizedBox.shrink()`.
      titleTrailing: (_peerBadges?.whatsappVerified ?? false) ||
              (_peerBadges?.idVerified ?? false)
          ? VerifiedLabel(
              whatsappVerified: _peerBadges?.whatsappVerified ?? false,
              idVerified: _peerBadges?.idVerified ?? false,
            )
          : null,
      onTitleTap: () => showAgreementDetails(context, conv,
          peerName: _peerName, isProvider: _isProvider),
      actions: [
        OnboardingGuide(
          // Clave por rol: el menú NO trae lo mismo para cliente y proveedor.
          key: ValueKey(_chatMenuGuideKey),
          guideKey: _chatMenuGuideKey,
          steps: onboardingCopy[_chatMenuGuideKey]!,
          order: 3,
          enabled: _conv != null,
          child: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) async {
            switch (v) {
              case 'profile':
                final cid = _conv?['customer_id'] as String?;
                if (cid != null) {
                  // El gate de identidad es POR SOLICITUD (PO 2026-08-11):
                  // se pasa el contexto de ESTE chat — la oferta o el
                  // interés del que nació la conversación.
                  final src = _conv?['source_id'] as String?;
                  final ctx = src == null
                      ? ''
                      : _conv?['kind'] == 'product_interest'
                          ? '?interest=$src'
                          : '?offer=$src';
                  context.push('/provider/customer/$cid$ctx');
                }
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
                // El diálogo vive en `widgets/conversation_actions.dart`: la
                // lista de chats ofrece la misma acción y el aviso de que es
                // irreversible tiene que ser idéntico en los dos sitios.
                if (!await confirmMarkLost(context)) return;
                if (!mounted) return;
                try {
                  await markConversationLost(widget.conversationId);
                  if (!mounted) return;
                  _snack('Marcado como no concretado.');
                  await _reload();
                } catch (_) {
                  if (mounted) _snack('No se pudo marcar. Intenta de nuevo.');
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
            for (final v in chatMenuValues(
                isProvider: _isProvider, isOpen: _isOpen))
              PopupMenuItem(
                value: v,
                child: Text(switch (v) {
                  'profile' => 'Ver perfil del cliente',
                  'complete' => 'Marcar como completado',
                  'lost' => 'Marcar como no concretado',
                  'funnel' => 'Estado del cliente',
                  _ => 'Denunciar cuenta',
                }),
              ),
          ],
          ),
        ),
      ],
    );
  }

  /// Guía del ⋮, por rol (ver `onboarding_copy.dart`).
  String get _chatMenuGuideKey =>
      _isProvider ? 'chat.menu.provider.v1' : 'chat.menu.client.v1';

  /// Banner de cerrado, o composer si la conversación sigue abierta.
  Widget _buildBottom(Map<String, dynamic> conv) {
    if (!_isProvider && conv['status'] == 'cerrado' && !_hasRating) {
      return RatingPanel(
          convId: widget.conversationId,
          customerId: conv['customer_id'] as String,
          providerUserId: conv['provider_user_id'] as String,
          businessId: _reviewBusinessId,
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
            if (showsRatingSentNote(
                isProvider: _isProvider,
                kind: conv['kind'] as String?,
                hasRating: _hasRating,
                customerReviewed: _customerReviewed))
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
      onTyping: _notifyTyping,
      onPlusAction: _handlePlus,
      onQuickItem: _sendQuickItem,
    );
  }
}
