import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/ai_client.dart';
import '../../core/brand.dart';
import '../../core/center_action.dart';
import '../../core/create_request_nav.dart';
import '../../core/unsaved_guard.dart';
import '../../data/repos.dart';
import '../../domain/ai_image.dart';
import '../../domain/ai_question_options.dart';
import '../../domain/ai_turns.dart';
import '../../domain/catalog.dart';
import '../../domain/rubro_choices.dart';
import '../../core/motion.dart';
import '../../core/safe_image_picker.dart';
import '../../domain/contact_info.dart';
import '../../domain/demand_guard.dart';
import '../../domain/image_pick.dart';
import '../../domain/request_progress.dart';
import '../../domain/request_seed.dart';
import '../../domain/wholesale.dart';
import '../shell/floating_nav_bar.dart';
import '../verification/verify_banner.dart';
import 'request_success_view.dart';
import '../shared/brand_kit.dart';
import '../shared/searchable_picker.dart';
import '../shared/violet_header.dart';
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';

const _maxRequestPhotos = 2;

/// URGENCY_OPTIONS de la web (requests/new.tsx): (valor persistido, etiqueta
/// visible, descripción). El VALOR se guarda tal cual en
/// `customer_requests.urgency`; la etiqueta es la que la web muestra.
const _urgencyOptions = [
  ('Urgente - 4 horas', 'Urgente', 'Necesito respuestas rápidas.'),
  ('Normal - 24 horas', 'Hoy o mañana', 'Quiero comprar hoy o mañana.'),
  ('No tengo prisa - 72 horas', 'Sin prisa', 'Puedo esperar mejores ofertas.'),
  (
    'No voy a comprar, solo quiero saber precio',
    'Solo quiero cotizar',
    'Solo estoy cotizando.',
  ),
];

/// SERVICE_MODALITY_OPTIONS de la web: (valor, título, descripción, icono).
const _serviceModalityOptions = [
  (
    'on_site',
    'En mi ubicación',
    'El proveedor va a donde estoy.',
    Icons.place_outlined,
  ),
  (
    'at_provider',
    'En local del proveedor',
    'Yo voy a su taller / oficina.',
    Icons.storefront_outlined,
  ),
  (
    'remote',
    'Remoto / online',
    'Se puede hacer a distancia.',
    Icons.laptop_mac_outlined,
  ),
  (
    'event',
    'Evento puntual',
    'Servicio para una fecha específica.',
    Icons.celebration_outlined,
  ),
];

/// URGENCY_LEVEL_OPTIONS de la web para servicios.
const _serviceUrgencyOptions = [
  ('emergency', 'Urgente (hoy)', 'Es una emergencia.', Icons.priority_high),
  (
    'this_week',
    'Esta semana',
    'Cuando puedas en los próximos días.',
    Icons.date_range_outlined,
  ),
  (
    'flexible',
    'Flexible',
    'No tengo prisa, busco buen precio.',
    Icons.spa_outlined,
  ),
  (
    'specific_date',
    'Fecha específica',
    'Tengo una fecha concreta en mente.',
    Icons.event_available_outlined,
  ),
];

/// Frecuencia de un servicio recurrente — OPCIÓN DEL FORMULARIO, nunca una
/// pregunta de la IA (decisión PO 2026-08-12; el clarificador la tiene
/// prohibida en el prompt de la web). El valor viaja tal cual a
/// `recurrence_note`; vacío = "Una sola vez" ⇒ `is_recurring` false.
/// Paridad con `SERVICE_FREQUENCY_PRESETS` de la web (src/lib/serviceFrequency.ts):
/// si cambian las opciones allá, cambian aquí.
const _serviceFrequencyOptions = [
  ('', 'Una sola vez', 'Un trabajo puntual.', Icons.looks_one_outlined),
  ('Diario', 'Diario', 'Todos los días.', Icons.today_outlined),
  ('Semanal', 'Semanal', 'Una vez por semana.', Icons.view_week_outlined),
  ('Quincenal', 'Quincenal', 'Cada dos semanas.', Icons.date_range_outlined),
  ('Mensual', 'Mensual', 'Una vez al mes.', Icons.calendar_month_outlined),
  ('__otra__', 'Otra', 'La escribo yo.', Icons.edit_outlined),
];

/// Valor centinela de la opción "Otra": NO se guarda, abre el campo de texto.
const kServiceFrequencyOther = '__otra__';

/// Cómo se pinta el botón central de la barra según en qué punto va la
/// solicitud. Función PURA y de nivel de fichero para que tenga test propio:
/// la pantalla necesita Supabase vivo, así que su `build` no es testeable, y
/// sin esto el estado del botón se quedaría sin una sola aserción.
({IconData icon, String label, bool enabled}) centerStateForCreate({
  required bool started,
  required bool submitted,
}) {
  // Publicada: la pantalla de éxito se queda hasta que el usuario toque «Ver
  // mis solicitudes», y ahí el ＋ tampoco lleva a ningún sitio.
  if (submitted) return (icon: Icons.add, label: 'Publicada', enabled: false);
  // Conversación en marcha: apagado. Antes aquí se SOLTABA el botón, y eso
  // devolvía el «＋ Nueva solicitud» del shell pintado ENCENDIDO, cuyo toque se
  // come el guard de `pushCreateRequestOnce` — un no-op silencioso (bug PO
  // 2026-08-22).
  if (started) return (icon: Icons.add, label: 'En curso', enabled: false);
  // Componiendo: la cámara manda (pedido PO 2026-07-28).
  return (
    icon: Icons.photo_camera_outlined,
    label: 'Añadir foto',
    enabled: true,
  );
}

/// Foto pendiente de una solicitud: el `dataUrl` base64 viaja a la IA en cada
/// turno — YA achicado a 768 px por `aiPhotoDataUrl` (F2), no es la original —
/// mientras la ruta local (`file.path`), a calidad completa, se sube a
/// Storage al enviar.
class _PendingPhoto {
  _PendingPhoto(this.file, this.dataUrl);
  final XFile file;
  final String dataUrl;
}

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key, this.seedFrom});
  final String? seedFrom;
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

/// Rediseño "Jayi te entrevista" (spec 2026-07-19-solicitud-gamificada,
/// ronda 3): la mascota EXPRESIVA entrevista (preguntas de la IA como botones
/// de ancho completo, tarjeta "Tu solicitud" que se va llenando), y al turno
/// `ready` aparece el FORMULARIO FINAL de la web — mismos campos, etiquetas y
/// validaciones que requests/new.tsx (feedback PO: "no son preguntas de la
/// IA, son parte de un formulario final"). El contrato con la IA no cambia.
class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _ai = AiClient();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  // SIN tipo por defecto (pedido PO 2026-07-21): el usuario debe elegir
  // Producto / Servicio / Al por mayor antes de poder enviar (ver `_startSend`).
  String _kind = '';
  bool _wholesale = false;
  bool _busy = false;
  bool _correcting = false;
  bool _submitted = false;
  // Token de idempotencia de ESTA solicitud: se fija al ABRIR el compositor (al
  // crear el State) y se reusa en cada reintento de `_submit`. Si el ack de red
  // del primer envío se pierde y el usuario reintenta, el servidor rechaza el 2º
  // INSERT con el mismo token (índice `uq_customer_requests_client_idempotency`)
  // → sin solicitud duplicada ni doble fan-out de notificaciones.
  final String _clientRequestId = newRequestClientId();
  List<String> _categories = [];
  List<String> _rubros = [];
  final List<_PendingPhoto> _photos = [];
  AiTurn? _current;
  int _pop = 0; // key de la reacción de la mascota (cambia por turno)
  AiReady? _ready;
  bool _showOther = false; // composer visible para "Otra respuesta…"

  // ── Formulario final (paridad requests/new.tsx) ────────────────────────
  bool _wantsNew = false;
  bool _wantsUsed = false;
  // Se pone en true en cuanto el usuario toca "Nuevo" o "Usado" a mano. El
  // premarcado de la IA (ver `_handleTurn`, caso `AiReady`) es solo una ayuda
  // inicial y no debe pisar una decision explicita del usuario en una
  // correccion posterior.
  bool _conditionTouched = false;
  bool _withShipping = false;
  bool _withInstallation = false;
  bool _requiresEvaluation = false;
  // Requisitos transversales (producto y servicio, pedido PO 2026-07-22).
  bool _requiresFiscalReceipt = false;
  bool _requiresStateSupplier = false;
  String _urgency = 'Normal - 24 horas'; // default de la web
  String _serviceModality = '';
  String _urgencyLevel = '';
  DateTime? _serviceEventDate;
  // Frecuencia del servicio: la píldora elegida ('' = una sola vez, o el
  // centinela `kServiceFrequencyOther`) y el texto libre de "Otra".
  String _serviceFrequency = '';
  String _serviceFrequencyOther = '';
  // Presupuesto estimado (opcional, servicios) — paridad web requests/new.tsx.
  String _budgetMin = '';
  String _budgetMax = '';
  Set<String> _selectedRubros = {};
  Map<String, String> _rubroNames = {};
  // Catálogo de rubros de las categorías objetivo. Las sugerencias de la IA son
  // una AYUDA, no la única fuente de opciones: el servidor puede devolver cero
  // rubros (retiró su fallback "top-3" en 35b7263) y sin catálogo la sección
  // obligatoria se quedaba sin una sola ficha que tocar. Ver `rubro_choices.dart`.
  List<Map<String, dynamic>> _catalogRubros = [];
  bool _loadingCatalog = false;
  String? _catalogError;

  /// La 2ª foto la puso el usuario DENTRO de la conversación (respondiendo a
  /// un `image_request`), no en el compositor. Solo esa se va con «Atrás»
  /// cuando su mensaje (`secondPhotoMsg`) deja de estar en el historial; las
  /// del compositor nunca pasaron por el historial y se quedan (§5.2: la 1ª
  /// foto NUNCA se suelta; la app admite dos en el compositor, la web una).
  bool _secondPhotoFromChat = false;

  /// Lo que el usuario escribió en el compositor al arrancar. `_send` vacía
  /// `_input`; «Atrás» hasta el inicio lo devuelve al campo (§5.2).
  String _composerText = '';

  // Detalles de mayoreo (obligatorios cuando la solicitud es al por mayor —
  // paridad web requests/new.tsx). Slugs de `domain/wholesale.dart`.
  String _wsQuantity = '';
  String _wsSplit = '';
  String _wsPackaging = '';
  String _wsNote = '';

  /// Tear-off guardado UNA vez: [releaseCenterAction] compara por identidad y
  /// un `_showPickSheet` evaluado dos veces no garantiza ser el mismo objeto.
  late final VoidCallback _centerCamera = _showPickSheet;

  /// Lo que `_applySeed` prefijó en el input. Se descuenta de la suciedad:
  /// abrir una solicitud sembrada y cerrarla sin tocar nada no debe preguntar.
  String _seedTitle = '';

  /// Cuántas de las fotos las puso la siembra, no el usuario. Mismo motivo que
  /// [_seedTitle]. Es un CONTEO y no un flag porque `_applySeed` siempre siembra
  /// al principio: las del usuario se añaden después, así que cualquier
  /// `_photos.length` por encima de esto es trabajo suyo.
  int _seedPhotos = 0;

  /// ¿Hay trabajo del usuario que se perdería al salir? Publicada la solicitud
  /// no hay nada que perder; antes, cuenta cualquier avance real: el tipo
  /// elegido, la entrevista empezada (mensajes/respuestas), fotos adjuntas o
  /// texto propio en el input (el sembrado por `seedFrom` no es suyo).
  bool _hasUnsavedWork() {
    if (_submitted) return false;
    // Las respuestas viven en `_messages` (ver `answerTexts`): no hay lista
    // aparte que pueda desincronizarse con «Atrás».
    return _kind.isNotEmpty ||
        _messages.isNotEmpty ||
        _photos.length > _seedPhotos ||
        _input.text.trim() != _seedTitle.trim();
  }

  /// Estado del botón central de la barra, sincronizado desde `build` (mismo
  /// patrón que la pantalla de la oferta del proveedor).
  ///
  /// Los tres estados, y por qué se decide AQUÍ y no en `_send`/`_submit`:
  /// - **compositor** → cámara «Añadir foto» viva (pedido PO 2026-07-28: el ＋
  ///   no hace nada dentro de esta pantalla, así que se lo queda la cámara);
  /// - **conversación en marcha** → APAGADO (PO 2026-08-20: pasada la
  ///   composición lo principal es contestar, y una cámara presidiendo la
  ///   pantalla invita a otra cosa). Antes aquí se SOLTABA el botón, y soltarlo
  ///   devolvía el «＋ Nueva solicitud» del shell pintado encendido cuyo toque
  ///   se traga el guard de `pushCreateRequestOnce`: un no-op silencioso (bug
  ///   PO 2026-08-22);
  /// - **publicada** → APAGADO: la pantalla de éxito se queda hasta que el
  ///   usuario toque «Ver mis solicitudes», y el ＋ seguía igual de inerte.
  ///
  /// Decidirlo desde `build` y no en los cuatro puntos donde el estado cambia
  /// (`_send`, `_submit`, y los DOS `catch` que revierten al compositor si el
  /// primer turno falla) es lo que impide que el próximo camino nuevo se
  /// olvide de mantenerlo. `takeCenterAction` es idempotente, así que
  /// llamarlo en cada frame no repinta la barra.
  void _syncCenter(bool started) {
    final s = centerStateForCreate(started: started, submitted: _submitted);
    takeCenterAction(
      owner: _centerCamera,
      icon: s.icon,
      label: s.label,
      route: kCreateRequestRoute,
      action: s.enabled ? _centerCamera : null,
      enabled: s.enabled,
    );
  }

  @override
  void initState() {
    super.initState();
    // Cualquier salida — atrás del sistema (BackGuard), cambio de pestaña
    // (home_shell) o la flecha del header — pregunta antes de tirar el
    // trabajo. La función se registra una vez; la suciedad se evalúa al salir.
    takeUnsavedGuard(
      owner: this,
      check: _hasUnsavedWork,
      message: 'Perderás lo que escribiste en esta solicitud.',
    );
    // El gesto ATRÁS de Android deshace UN paso de la conversación (spec
    // §5.3) y BackGuard lo consulta antes que el aviso de descarte. En el
    // compositor (sin historial) o mientras la IA piensa no consume: se sale
    // como siempre. La flecha del header NO pasa por aquí: esa sale.
    takeBackStep(
      owner: this,
      step: () {
        if (_messages.isEmpty || _busy) return false;
        _goBack();
        return true;
      },
    );
    if (widget.seedFrom != null) {
      // fire-and-forget: prefija el input; la foto se adjunta en Task 5.
      _applySeed(widget.seedFrom!);
    }
  }

  @override
  void dispose() {
    releaseCenterAction(_centerCamera);
    releaseUnsavedGuard(this);
    releaseBackStep(this);
    // Faltaban (auditoría 2026-07-30). Esta es la pantalla que más se abre y
    // cierra del producto — el ＋ de la barra la lanza una y otra vez — así que
    // cada apertura dejaba colgando un TextEditingController con sus listeners
    // y un ScrollController con su ScrollPosition viva. En una sesión larga se
    // degrada, y en la gama baja que es el parque real en RD termina en OOM.
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _applySeed(String seedFrom) async {
    final row = await requestById(seedFrom);
    if (row == null || !mounted) return;
    final seed = RequestSeed.fromRow(row);
    _seedTitle = seed.title;
    setState(() => _input.text = seed.title);

    final url = seed.imageUrl;
    if (url == null) return;
    try {
      final bytes = await http.readBytes(Uri.parse(url));
      final png = url.toLowerCase().contains('.png');
      final ext = png ? 'png' : 'jpg';
      final f = File(
        '${Directory.systemTemp.path}/seed_'
        '${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await f.writeAsBytes(bytes);
      // Antes viajaban los bytes CRUDOS de Storage (una foto histórica podía
      // ser enorme) con el mime adivinado por la extensión. La versión IA los
      // achica a 768 px y detecta el mime por bytes mágicos (F2).
      final dataUrl = await aiPhotoDataUrl(bytes);
      if (!mounted) return;
      setState(() {
        _photos.add(_PendingPhoto(XFile(f.path), dataUrl));
        // La foto la puso la SIEMBRA, no el usuario: no cuenta como trabajo
        // suyo (ver `_hasUnsavedWork`). Sin esto, abrir "Yo también quiero
        // esto" sobre una solicitud con foto y salir sin tocar nada
        // preguntaba si descartar algo que nunca escribió.
        _seedPhotos = _photos.length;
      });
    } catch (_) {
      // Best-effort: si la descarga falla, se sigue solo con el título.
    }
  }

  /// `force` es SOLO para las continuaciones internas (el auto-"ok" del
  /// routing): se disparan dentro del `try` del envío anterior, cuando `_busy`
  /// aún es true — sin force, el guard se las tragaba en silencio y el flujo
  /// quedaba muerto esperando al usuario (bug pre-existente que el chat viejo
  /// disimulaba y la vista guiada destapó).
  ///
  /// `raw` manda `text` tal cual. Sin `raw`, la respuesta a un `question` se
  /// guarda como `Pregunta: …\nRespuesta: …` (spec §6, paridad web): el
  /// constructor de plantillas lee ese formato. La corrección tras la ficha
  /// (`_correcting`) y todo lo que no responde a un `question` van sueltos.
  Future<void> _send(String text, {bool force = false, bool raw = false}) async {
    if (text.trim().isEmpty || (_busy && !force)) return;
    // Mismo pulso que el chat entre personas: acá el usuario también le está
    // MANDANDO algo a alguien (la IA que arma la solicitud).
    JayaloHaptics.sent();
    final content =
        raw ? text : answerContent(_correcting ? null : _current, text);
    // El estado del botón central lo decide `_syncCenter` desde `build` (la
    // cámara deja de mandar en cuanto arranca la conversación, PO 2026-08-20).
    // No se pierde nada: el único punto del flujo donde hace falta otra foto es
    // el turno `image_request`, y ese trae sus propios botones dentro del
    // contenido («Tomar otra foto» / «Seguir sin foto»).
    setState(() {
      _busy = true;
      _showOther = false;
      _messages.add(AiMessage('user', content));
      _input.clear();
    });
    final ok = await _ask();
    // El mensaje que provocó el fallo se quita: el usuario reintenta desde el
    // mismo punto. Las respuestas ya no se cuentan aparte (`answerTexts` lee
    // el historial), así que no hay contador que revertir.
    if (!ok && mounted) {
      setState(() {
        _messages.removeLast();
      });
    }
  }

  /// Manda el historial TAL CUAL está y trata el turno que vuelve. `true` si
  /// llegó un turno (o la pantalla murió mientras tanto); `false` si falló,
  /// ya con su toast. Quien añadió un mensaje antes de llamar decide qué
  /// hacer con él (`_send` lo quita; `_restartWithKind` restaura el anterior).
  Future<bool> _ask() async {
    setState(() => _busy = true);
    try {
      // El JWT de la sesión exime el Turnstile del primer turno (ADR-0032);
      // el WebView del CAPTCHA se quitó: se pintaba negro en MIUI y colgaba
      // el flujo completo de crear solicitud.
      final turn = await _ai.sendTurn(
        messages: _messages,
        kind: _kind,
        wholesale: _wholesale,
        accessToken: supa.auth.currentSession?.accessToken,
        imageDataUrl: _photos.isNotEmpty ? _photos[0].dataUrl : null,
        imageDataUrl2: _photos.length > 1 ? _photos[1].dataUrl : null,
      );
      _messages.add(AiMessage('assistant', jsonEncode(turnToJson(turn))));
      // `sendTurn` tarda 2-8 s en datos móviles y el usuario puede cerrar el
      // compositor mientras tanto. Sin este guard, `_handleTurn` y los dos
      // `catch` de abajo llamaban `setState` sobre un State ya desmontado
      // ("setState() called after dispose()"): el turno se perdía y el error
      // ensuciaba el tracking. El `finally` ya lo hacía bien; estas ramas no.
      if (!mounted) return true;
      // La correccion se da por consumida SOLO cuando el turno llego. Si la
      // IA falla, `_correcting` sigue en true y el usuario vuelve a ver el
      // campo de corregir con su formulario intacto detras, en vez de
      // quedarse en una pantalla sin nada que tocar.
      setState(() => _correcting = false);
      await _handleTurn(turn);
      return true;
    } on AiHttpException catch (e) {
      if (!mounted) return false;
      _toast(
        e.status == 429
            ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
            : e.message,
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      _toast('Algo falló. Intenta de nuevo.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «Sí, cambiar» de un `kind_switch`: como la web (`new.tsx` L1860-1900),
  /// se cambia el tipo y la conversación ARRANCA DE NUEVO con solo el primer
  /// mensaje. Antes la app mandaba la opción como un mensaje más sobre el
  /// historial viejo; con el tipo cambiado, ese historial ya no vale — y el
  /// reinicio es lo que permite volver a pedir plantillas (Task 8).
  Future<void> _restartWithKind(String kind) async {
    if (_busy || _messages.isEmpty) return;
    final previous = List<AiMessage>.of(_messages);
    final previousCurrent = _current;
    final first = _messages.first;
    JayaloHaptics.sent();
    setState(() {
      _kind = kind;
      // Paridad web (new.tsx L1857): «servicio» no admite al por mayor.
      if (kind == 'servicio') _wholesale = false;
      _messages
        ..clear()
        ..add(first);
      _current = null;
      _ready = null;
      _categories = [];
      _rubros = [];
      _showOther = false;
      _pop++;
    });
    final ok = await _ask();
    if (!ok && mounted) {
      // Si el reinicio falla, se vuelve a donde estaba (con el kind ya
      // cambiado: eso lo pidió el usuario y no depende del servidor).
      setState(() {
        _messages
          ..clear()
          ..addAll(previous);
        _current = previousCurrent;
      });
    }
  }

  /// «Atrás» de la conversación (spec §5.2): deshace el último paso desde el
  /// historial, SIN llamar al servidor. Lo disparan el botón y el gesto ATRÁS
  /// de Android (`takeBackStep` en `initState`). Si no queda turno detrás se
  /// vuelve al compositor con el texto y las fotos del compositor intactos.
  void _goBack() {
    if (_busy || _messages.isEmpty) return;
    final r = stepBack(_messages);
    final routing = _lastRouting(r.messages);
    final categories = List<String>.of(routing?.categories ?? const []);
    // El catálogo de rubros es de las categorías CARGADAS; si «Atrás» cambia
    // las categorías, el catálogo y la selección ya no corresponden.
    final catalogStale = categories.join(',') != _categories.join(',');
    setState(() {
      _showOther = false;
      _correcting = false;
      if (r.turn == null) _input.text = _composerText;
      _messages
        ..clear()
        ..addAll(r.messages);
      _current = r.turn;
      _ready = switch (r.turn) {
        AiReady rd => rd,
        _ => null,
      };
      _categories = categories;
      _rubros = List<String>.of(routing?.rubros ?? const []);
      if (catalogStale) {
        _catalogRubros = [];
        _selectedRubros = {};
      }
      // Si «Atrás» deshizo el envío de la segunda foto, la foto misma se va:
      // si no, «Seguir sin foto» en el siguiente `image_request` la mandaría
      // igual (repro del PO en la web). Solo la que entró por el chat.
      if (_secondPhotoFromChat &&
          !keepsSecondPhoto(_messages) &&
          _photos.length > 1) {
        _photos.removeLast();
        _secondPhotoFromChat = false;
      }
      _pop++;
    });
    if (catalogStale && _categories.isNotEmpty) unawaited(_loadRubroCatalog());
  }

  /// El último `routing` que queda en el historial (o null): de ahí salen las
  /// categorías/rubros tras un «Atrás».
  AiRouting? _lastRouting(List<AiMessage> msgs) {
    for (final m in msgs.reversed) {
      if (m.role != 'assistant') continue;
      if (parseAssistantTurn(m.content) case AiRouting r) return r;
    }
    return null;
  }

  /// Botón «Atrás» de la conversación: texto + `arrow_back`, mismo estilo que
  /// «Otra respuesta…» (TextButton centrado). Apagado mientras la IA piensa.
  Widget _backButton() => Center(
        child: TextButton.icon(
          onPressed: _busy ? null : _goBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Atrás'),
        ),
      );

  /// Elige y valida una foto; la agrega a `_photos` (con su base64 cacheado).
  /// Devuelve true si se agregó. Con [replaceLast], la nueva foto sustituye a
  /// la última SOLO si el pick termina bien — cancelar conserva la actual.
  Future<bool> _pickPhoto(ImageSource source, {bool replaceLast = false}) async {
    final picked = await guardedPick((p) => p.pickImage(
          source: source,
          maxWidth: 1200,
          imageQuality: 85,
        ));
    if (picked == null) return false;
    // Recorte tras tomar/elegir la foto (pedido PO): el usuario ajusta el
    // encuadre antes de adjuntarla. Si cancela el crop, no se adjunta nada.
    final cropped = await _cropImage(picked);
    if (cropped == null) return false;
    final bytes = await cropped.readAsBytes();
    final res = validatePickedImage(
      sizeBytes: bytes.length,
      path: cropped.path,
      currentCount: replaceLast ? _photos.length - 1 : _photos.length,
      maxCount: _maxRequestPhotos,
    );
    if (res is ImagePickError) {
      _toast(res.message);
      return false;
    }
    // La IA recibe la versión de 768 px (F2); `cropped` conserva la original
    // para Storage y previews.
    final dataUrl = await aiPhotoDataUrl(bytes);
    if (mounted) {
      setState(() {
        if (replaceLast && _photos.isNotEmpty) _photos.removeLast();
        _photos.add(_PendingPhoto(cropped, dataUrl));
      });
    }
    return true;
  }

  /// Abre el recortador (UCrop en Android). Devuelve la foto recortada como
  /// [XFile], o `null` si el usuario cancela. Formato JPG para peso predecible.
  Future<XFile?> _cropImage(XFile src) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: src.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recortar foto',
          toolbarColor: const Color(0xFF6D28D9),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF6D28D9),
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(title: 'Recortar foto'),
      ],
    );
    return cropped == null ? null : XFile(cropped.path);
  }

  /// Responde al turno `image_request`: adjunta y manda un turno para que la IA
  /// prosiga (la foto viaja en imageDataUrl de este mismo POST).
  ///
  /// Si la IA pide foto con el cupo LLENO es que alguna no le sirvió: el
  /// cargador se ofrece igual y la nueva foto reemplaza a la última (pedido PO
  /// 2026-08-11 — antes los botones de cámara/galería desaparecían y al
  /// usuario solo le quedaba "Seguir sin foto", con la foto equivocada puesta).
  Future<void> _pickForRequest(ImageSource source) async {
    final replacing = _photos.length >= _maxRequestPhotos;
    if (await _pickPhoto(source, replaceLast: replacing)) {
      // La 2ª foto viaja con el literal de la web (`secondPhotoMsg`): «Atrás»
      // sabe que sigue en juego mientras ese mensaje siga en el historial
      // (`keepsSecondPhoto`). El servidor adjunta `imageDataUrl2` al ÚLTIMO
      // mensaje `user` sea cual sea su texto (chat-stream.ts L516-533), así
      // que el reemplazo de la 2ª también va con este literal.
      final isSecond = _photos.length == _maxRequestPhotos;
      if (isSecond) _secondPhotoFromChat = true;
      await _send(
        isSecond ? secondPhotoMsg : 'Aquí tienes una foto para más contexto.',
        raw: true,
      );
    }
  }

  /// Adjuntar espontáneo desde la barra de entrada.
  /// Contexto de la hoja de elegir foto MIENTRAS está abierta (null = cerrada).
  ///
  /// Es lo que vuelve al botón un INTERRUPTOR: el ＋ de la barra se convirtió en
  /// cámara dentro de esta pantalla y se puede tocar tantas veces como el
  /// usuario quiera. Sin este guardia cada toque apilaba otra hoja encima de la
  /// anterior (bug PO: "ventanas múltiples al presionar el botón de la cámara
  /// varias veces"), y había que cerrarlas una por una.
  ///
  /// Se guarda el CONTEXTO de la hoja y no un `bool`: para cerrarla hay que
  /// hacer pop de SU ruta. Un `Navigator.pop(context)` con el contexto de la
  /// pantalla sacaría lo que esté al tope del navigator, que no tiene por qué
  /// ser la hoja (p. ej. si encima se abrió el selector nativo de la galería).
  BuildContext? _pickSheetCtx;

  Future<void> _showPickSheet() async {
    // Segundo toque = cerrar (pedido PO: "el botón debe sacar la ventana y al
    // darle otra vez al botón debe ocultarla"). El `mounted` cubre el caso de
    // que la hoja se haya ido por otra vía (atrás, tocar fuera) entre medio.
    final open = _pickSheetCtx;
    if (open != null) {
      if (open.mounted) Navigator.of(open).pop();
      _pickSheetCtx = null;
      return;
    }
    if (_photos.length >= _maxRequestPhotos) {
      _toast('Puedes subir hasta $_maxRequestPhotos fotos.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      sheetAnimationStyle: JayaloMotion.sheetMenu,
      context: context,
      builder: (sheetCtx) {
        // Se registra en el build de la hoja: a partir de acá el botón cierra
        // en vez de abrir. Se limpia SIEMPRE al terminar el `await` de abajo,
        // sin importar cómo se haya cerrado (elección, atrás o tocar fuera).
        _pickSheetCtx = sheetCtx;
        return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      );
      },
    );
    _pickSheetCtx = null;
    if (source != null) await _pickPhoto(source);
  }


  Future<void> _handleTurn(AiTurn turn) async {
    switch (turn) {
      // Todo turno que NO es `ready` tumba el formulario final: `_ready` es el
      // dato, pero también el gate de lo que se pinta (ver `_guidedView`), y
      // si sobrevive a una pregunta nueva la pantalla repinta el formulario
      // VIEJO y la pregunta queda invisible — la corrección del usuario se
      // traga en silencio. Paridad con la web, donde el gate es
      // `current.type === "ready"` y un turno nuevo lo tumba solo.
      case AiQuestion q:
        setState(() {
          _ready = null;
          _current = q;
          _pop++;
        });
      case AiKindSwitch k:
        setState(() {
          _ready = null;
          _current = k;
          _pop++;
        });
      case AiImageRequest ir:
        setState(() {
          _ready = null;
          _current = ir;
          _pop++;
        });
      case AiRouting r:
        setState(() {
          _ready = null;
          _categories = r.categories;
          _rubros = r.rubros;
          _current = r;
        });
        // En paralelo al auto-"ok": el catálogo debe estar listo cuando se pinte
        // el formulario final, tanto si la IA sugirió rubros como si no.
        unawaited(_loadRubroCatalog());
        if (r.readyNext case final rn?) {
          // F3: el servidor ya adjuntó el ready — el POST del auto-«ok» (que
          // re-subía la foto entera) se ahorra. El historial queda IGUAL que
          // por el camino lento: el mismo 'ok' + el ready serializado con el
          // mismo `turnToJson` — las correcciones tras la ficha dependen de
          // esa coherencia.
          _messages.add(const AiMessage('user', 'ok'));
          _messages.add(AiMessage('assistant', jsonEncode(turnToJson(rn))));
          await _handleTurn(rn);
        } else {
          // Servidor viejo o readyNext omitido: el camino de siempre.
          await _send('ok', force: true);
        }
      case AiReady rd:
        setState(() {
          _ready = rd;
          _current = rd;
          _pop++;
          // Premarcado del form si la IA captó el estado en la conversación —
          // paridad exacta con `applyReadyCondition`/`conditionToFlags` web.
          if (_kind == 'producto' && rd.condition != null && !_conditionTouched) {
            _wantsNew = rd.condition == 'nuevo' || rd.condition == 'ambos';
            _wantsUsed = rd.condition == 'usado' || rd.condition == 'ambos';
          }
          if (_selectedRubros.isEmpty) _selectedRubros = _rubros.toSet();
        });
        if (_rubroNames.isEmpty && _rubros.isNotEmpty) {
          unawaited(_loadRubroNames());
        }
        // Red de seguridad: si la IA saltó el turno `routing` (el prompt se lo
        // pide, nada lo obliga) no hay categorías ni catálogo. Con categorías,
        // se carga aquí por si el turno `routing` no llegó a dispararlo.
        if (_catalogRubros.isEmpty && !_loadingCatalog) {
          unawaited(_loadRubroCatalog());
        }
    }
  }

  Future<void> _loadRubroNames() async {
    try {
      final names = await rubroNames(_rubros);
      if (mounted) setState(() => _rubroNames = names);
    } catch (_) {
      // Sin nombres se muestran chips genéricos; no bloquea el flujo.
    }
  }

  /// Lee los rubros de las categorías objetivo para que SIEMPRE haya algo que
  /// elegir, sugiera la IA o no. Sin esto, un turno `routing` con `rubros: []`
  /// dejaba la sección obligatoria vacía y la solicitud no se podía enviar.
  Future<void> _loadRubroCatalog() async {
    if (_categories.isEmpty) return;
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      // `_kind` es lo que el usuario tocó antes de escribir (producto/servicio):
      // es la señal con la que el picker aplica la misma reja que el servidor.
      final rows = await rubrosForCategories(
        List.of(_categories),
        kind: _kind.isEmpty ? null : _kind,
      );
      if (mounted) setState(() => _catalogRubros = rows);
    } catch (e) {
      debugPrint('[create_request] catálogo de rubros falló: $e');
      if (mounted) {
        setState(() => _catalogError = 'No pudimos cargar los rubros.');
      }
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  /// El usuario elige la categoría a mano cuando la IA no emitió turno `routing`
  /// (sin categorías no hay catálogo que leer, y volveríamos al bloqueo).
  void _pickCategory(String id) {
    setState(() {
      _categories = [id];
      _catalogRubros = [];
      _selectedRubros = {};
    });
    unawaited(_loadRubroCatalog());
  }

  /// Gates idénticos al `submit()` de la web (requests/new.tsx L520-570).
  Future<void> _submit() async {
    final r = _ready!;
    final isService = _kind == 'servicio';
    // Combina el "al por mayor" que dijo la IA con el toggle manual — mismo
    // criterio que ya usa esta pantalla para el chip/persistencia (L432/1108).
    final effectiveWholesale = r.wholesale || _wholesale;
    if (!isService && !_wantsNew && !_wantsUsed) {
      _toast('Indica si lo quieres nuevo o usado.');
      return;
    }
    if (isService) {
      if (_serviceModality.isEmpty) {
        _toast('Selecciona dónde se hace el servicio.');
        return;
      }
      if (_urgencyLevel.isEmpty) {
        _toast('Indica cuándo lo necesitas.');
        return;
      }
      if (_serviceModality == 'event' && _serviceEventDate == null) {
        _toast('Indica la fecha del evento.');
        return;
      }
      // "Otra" en blanco guardaría un servicio recurrente SIN frecuencia, que
      // al proveedor no le dice más que "una sola vez".
      if (_serviceFrequency == kServiceFrequencyOther &&
          _serviceFrequencyOther.trim().isEmpty) {
        _toast('Escribe cada cuánto se repite el servicio.');
        return;
      }
    }
    if (!isService && effectiveWholesale) {
      final qty = int.tryParse(_wsQuantity.trim());
      if (qty == null || qty <= 0) {
        _toast('Indica la cantidad que necesitas (al por mayor).');
        return;
      }
      if (_wsSplit.isEmpty) {
        _toast('Elige cómo dividir el pedido.');
        return;
      }
      if (_wsPackaging.isEmpty) {
        _toast('Elige el empaque o presentación.');
        return;
      }
      if ((_wsPackaging == 'otro' || _wsSplit == 'cantidades_especificas') &&
          _wsNote.trim().isEmpty) {
        _toast('Especifica el detalle del empaque/cantidades.');
        return;
      }
    }
    if (_selectedRubros.isEmpty) {
      _toast('Selecciona al menos un rubro específico.');
      return;
    }
    final conditionValue = _wantsNew && _wantsUsed
        ? 'ambos'
        : _wantsNew
        ? 'nuevo'
        : _wantsUsed
        ? 'usado'
        : '';
    // Anti-elusión (PO 2026-07-29): mismas columnas que vigila el trigger
    // `enforce_no_contact_info` para `customer_requests` — title, description
    // (armado uniendo bullets con ' • ', ver `submitRequest` en
    // data/repos.dart) y wholesale_note; recurrence_note siempre viaja vacío.
    // Revisar el texto YA unido de `description` cubre también un dato de
    // contacto que quedara partido entre dos bullets. MANTENIMIENTO: si
    // agregas un campo de texto libre nuevo que llegue a una columna vigilada
    // de `customer_requests`, súmalo también aquí (no hay Map único que
    // enumerar — ver la nota del reporte de la Task 4 sobre por qué es a mano).
    final wholesaleNoteValue =
        (!isService &&
                effectiveWholesale &&
                (_wsPackaging == 'otro' ||
                    _wsSplit == 'cantidades_especificas'))
        ? _wsNote.trim()
        : '';
    final contactCheckValues = <String>[
      r.title,
      r.bullets.join(' • '),
      wholesaleNoteValue,
    ];
    if (contactCheckValues.any(containsContactInfo)) {
      _toast(contactInfoMessage);
      return;
    }
    // Pasaron TODOS los gates: la solicitud se va de verdad. El pulso va acá y
    // no al tocar el botón, para que un rechazo por validación (que solo saca
    // un toast) no se sienta igual que un envío exitoso.
    JayaloHaptics.sent();
    setState(() => _busy = true);
    try {
      // Subir las fotos a Storage antes de insertar (nunca base64 en la BD).
      final imageUrls = await Future.wait(
        _photos.map((p) => uploadRequestImage(p.file.path)),
      );
      await submitRequest(
        title: r.title,
        bullets: r.bullets,
        kind: _kind,
        wholesale: r.wholesale || _wholesale,
        categories: _categories,
        rubros: _selectedRubros.toList(),
        clientRequestId: _clientRequestId,
        imageUrls: imageUrls,
        condition: conditionValue,
        urgency: _urgency,
        withShipping: _withShipping,
        withInstallation: _withInstallation,
        requiresEvaluation: _requiresEvaluation,
        requiresFiscalReceipt: _requiresFiscalReceipt,
        requiresStateSupplier: _requiresStateSupplier,
        serviceModality: _serviceModality,
        urgencyLevel: _urgencyLevel,
        serviceEventDate: _serviceEventDate,
        // El centinela de "Otra" no se guarda: viaja lo que escribió el cliente.
        serviceFrequency: _serviceFrequency == kServiceFrequencyOther
            ? _serviceFrequencyOther.trim()
            : _serviceFrequency,
        budgetMin: isService ? _parseMoney(_budgetMin) : null,
        budgetMax: isService ? _parseMoney(_budgetMax) : null,
        wholesaleQuantity: (!isService && effectiveWholesale)
            ? int.tryParse(_wsQuantity.trim())
            : null,
        wholesaleSplit: (!isService && effectiveWholesale) ? _wsSplit : null,
        wholesalePackaging: (!isService && effectiveWholesale)
            ? _wsPackaging
            : null,
        wholesaleNote:
            (!isService &&
                effectiveWholesale &&
                (_wsPackaging == 'otro' ||
                    _wsSplit == 'cantidades_especificas'))
            ? _wsNote.trim()
            : null,
      );
      if (!mounted) return;
      // El botón central pasa a «Publicada» apagado en el `build` siguiente
      // (`_syncCenter`): soltarlo aquí devolvía el ＋ encendido del shell, que
      // en esta ruta no navega a ningún sitio.
      //
      // Publicada: nada que perder — que ninguna salida pregunte.
      releaseUnsavedGuard(this);
      setState(() => _submitted = true);
    } catch (e) {
      // Red de seguridad: si el aviso previo no atrapó algo, los triggers de
      // la BD sí lo bloquean — traducir su SQLSTATE al mensaje humano en vez
      // del genérico de abajo. JY422 = contacto; JY423 = "esto es una venta,
      // no una solicitud" (solo demanda, PO 2026-08-13).
      _toast(
        isContactInfoError(e)
            ? contactInfoMessage
            : isOfferNotAllowedError(e)
            ? offerNotAllowedMessage
            : 'No se pudo enviar la solicitud.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) showJayaloToast(context, m);
  }

  /// Convierte lo escrito en el campo de presupuesto (admite "5,000", "RD$5000")
  /// a un número; null si está vacío. Solo dígitos.
  num? _parseMoney(String s) {
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  @override
  Widget build(BuildContext context) {
    final started = _messages.isNotEmpty;
    _syncCenter(started);
    return Scaffold(
      body: Column(
        children: [
          // Header violeta: "Crear solicitud" centrado, SIN campana (pedido PO
          // 2026-07-21: fuera el ícono de notificaciones aquí). Los botones de
          // tipo (Producto/Servicio/Al por mayor) bajaron al cuerpo, debajo de
          // la barra de búsqueda (mismo pedido).
          VioletHeader(
            leading: HeaderCircleButton(
              icon: Icons.arrow_back_ios_new,
              tooltip: 'Atrás',
              // Mismo aviso que el atrás del sistema: esta flecha no pasa por
              // BackGuard.
              onTap: () async {
                if (_hasUnsavedWork()) {
                  final salir = await confirmDiscard(context);
                  if (!salir) return;
                  if (!context.mounted) return;
                }
                context.pop();
              },
            ),
            title: 'Crear solicitud',
            titleAlign: HeaderTitleAlign.center,
          ),
          if (!_submitted)
            // Nudge de verificación (spec §6.1) — cerrable, nunca bloquea el envío.
            const VerifyWhatsappBanner(),
          Expanded(
            child: _submitted
                ? _successView()
                : !started
                ? _emptyState()
                : _guidedView(),
          ),
          // El campo de escribir solo aparece cuando de verdad toca escribir:
          // corregir, "Otra respuesta…", o una pregunta sin opciones. El campo
          // del ARRANQUE ya no vive aquí abajo: subió al cuerpo del empty state
          // con borde violeta (pedido PO 2026-07-21).
          if ((_ready == null || _correcting) &&
              !_submitted &&
              started &&
              (_correcting ||
                  _showOther ||
                  (!_busy &&
                      _current is AiQuestion &&
                      (_current as AiQuestion).options.isEmpty)))
            SafeArea(
              // '/client/create' es una pestaña del shell: la barra flotante
              // sigue visible aquí (ver home_shell.dart), pero con
              // `extendBody: true` el `Scaffold` ya infla
              // `MediaQuery.paddingOf(context).bottom` al alto COMPLETO de la
              // barra (ver el doc-comment de `navBarReservedSpace` en
              // `floating_nav_bar.dart`) — y `SafeArea` lee ese mismo
              // `MediaQuery`. Sumarle `kNavBarReservedSpace` aquí encima
              // contaba la barra dos veces (bug C2: 144px de hueco muerto
              // entre el campo de escribir y la barra). El padding de 12 de
              // abajo es solo el respiro visual normal del composer.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _input,
                  enabled: !_busy,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: _correcting
                        ? 'Escribe qué corregir…'
                        : 'Escribe tu respuesta…',
                    // "F1 · Rellenos suaves" (elegido por el PO para este grupo).
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    // Cámara a la vista (pedido PO: "no está el botón de hacer
                    // la foto"): el ícono es la cámara y el sheet ofrece
                    // Tomar foto / Galería.
                    prefixIcon: IconButton(
                      tooltip: 'Tomar o subir foto',
                      icon: const Icon(Icons.photo_camera_outlined),
                      onPressed: _busy ? null : _showPickSheet,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () => _send(_input.text),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Arranque rediseñado (pedido PO 2026-07-21): el mensaje es "¿Qué quieres
  /// jayar hoy?", el campo de describir sube AQUÍ (con borde violeta, ya no
  /// pegado al fondo) y debajo van los botones de tipo Producto / Servicio /
  /// Al por mayor — SIN selección por defecto: hay que elegir uno para poder
  /// enviar.
  Widget _emptyState() {
    final cs = Theme.of(context).colorScheme;
    // Anclado ARRIBA (no centrado en vertical, pedido PO 2026-07-21: la
    // mascota quedaba grande y "detrás del buscador" al centrar) y con la
    // mascota más pequeña, como estaba antes del rediseño.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Jayi DETECTIVE con su lupa al ojo (mockup aprobado PO 08-10):
          // sustituye a la cara respirando. OJO: va dentro de un Center
          // porque la columna es `stretch` y su CustomPaint ADOPTA las
          // constraints del padre (a ancho completo se pintaba GIGANTE
          // detrás del buscador — QA PO 2026-07-21); el Center lo suelta a
          // su tamaño propio.
          const Center(child: _JayiDetective(pensando: false)),
          const SizedBox(height: 12),
          Text(
            '¿Qué quieres jayar hoy?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: jayaloHead(context),
            ),
          ),
          const SizedBox(height: 16),
          // La barra de búsqueda, con BORDE VIOLETA (pedido PO).
          TextField(
            controller: _input,
            enabled: !_busy,
            onSubmitted: _startSend,
            decoration: InputDecoration(
              hintText: 'Describe lo que quieres encontrar.',
              filled: true,
              fillColor: cs.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: cs.primary, width: 1.6),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              prefixIcon: OnboardingGuide(
                guideKey: 'client.request_photo.v1',
                steps: onboardingCopy['client.request_photo.v1']!,
                order: 2,
                child: IconButton(
                  tooltip: 'Tomar o subir foto',
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: _busy ? null : _showPickSheet,
                ),
              ),
              // Botón con TEXTO "Buscar" en vez del avioncito (pedido PO
              // 2026-08-11): dice lo que hace.
              suffixIcon: OnboardingGuide(
                guideKey: 'client.create_request.v2',
                steps: onboardingCopy['client.create_request.v2']!,
                order: 3,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                      textStyle: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _busy ? null : () => _startSend(_input.text),
                    child: const Text('Buscar'),
                  ),
                ),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          const SizedBox(height: 12),
          // Tipo de solicitud DEBAJO de la barra (pedido PO). Sin default.
          // Flujo (PO 2026-07-22): inicial Producto|Servicio; al elegir
          // Producto se OCULTA Servicio y aparece "Al por mayor"; al elegir
          // Servicio se oculta Producto. Tocar el tipo elegido de nuevo lo
          // deselecciona y vuelve a los dos botones.
          OnboardingGuide(
            guideKey: 'client.request_kind.v1',
            steps: onboardingCopy['client.request_kind.v1']!,
            order: 1,
            child: Row(
              children: [
                if (_kind != 'servicio')
                  Expanded(child: _kindPill('producto', 'Producto')),
                if (_kind == 'producto') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OnboardingGuide(
                      guideKey: 'client.request_wholesale.v1',
                      steps: onboardingCopy['client.request_wholesale.v1']!,
                      order: 9,
                      child: _kindPill('mayor', 'Al por mayor'),
                    ),
                  ),
                ],
                if (_kind != 'producto') ...[
                  if (_kind != 'servicio') const SizedBox(width: 10),
                  Expanded(child: _kindPill('servicio', 'Servicio')),
                ],
              ],
            ),
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_photos[i].file.path),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.cancel, size: 20),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _photos.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Sube una foto y describe lo que buscas para mejor resultado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          // Los chips "Tomar foto"/"Galería" que iban aquí se QUITARON (pedido
          // PO 2026-07-28): la cámara ya está dos veces a la vista — el ícono
          // de la barra de búsqueda y el botón central de la navbar, que dentro
          // de esta pantalla es una cámara. Su guía de onboarding se mudó al
          // ícono de la barra, que es lo que ahora señala.
        ],
      ),
    );
  }

  /// Píldora de tipo (Producto / Servicio / Al por mayor). "Al por mayor" es
  /// un TOGGLE extra del producto (solo visible con Producto elegido, pedido
  /// PO 2026-07-21): producto+wholesale en el modelo de datos.
  Widget _kindPill(String key, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = switch (key) {
      'producto' => _kind == 'producto',
      'servicio' => _kind == 'servicio',
      _ => _wholesale,
    };
    return GestureDetector(
      onTap: _busy
          ? null
          : () => setState(() {
              if (key == 'mayor') {
                _wholesale = !_wholesale; // toggle, producto sigue elegido
              } else if (_kind == key) {
                _kind = ''; // deseleccionar → vuelve a los dos botones
                _wholesale = false;
              } else {
                _kind = key;
                if (key == 'servicio') _wholesale = false;
              }
            }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14),
        // VIOLETA también sin elegir (pedido PO 2026-07-28: "que se noten
        // más"). Antes eran gris `surfaceContainerHighest` y se perdían bajo
        // la barra de búsqueda. Sin elegir copian el borde violeta de esa
        // barra, que está justo encima; elegida se rellena de violeta sólido,
        // que es lo que distingue los dos estados.
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary, width: selected ? 0 : 1.6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.primary,
          ),
        ),
      ),
    );
  }

  /// Gate del primer envío (pedido PO 2026-07-21): sin tipo elegido no se
  /// envía la solicitud.
  void _startSend(String text) {
    if (_kind.isEmpty) {
      _toast('Elige Producto, Servicio o Al por mayor para continuar.');
      return;
    }
    // «Atrás» hasta el inicio devuelve esto al campo (spec §5.2).
    _composerText = text.trim();
    // En PRODUCTO la descripción es opcional si hay foto (pedido PO
    // 2026-08-11): la foto habla por el usuario — viaja en el dataUrl de este
    // mismo POST y el servidor ya usa este mismo texto por defecto para los
    // mensajes que solo traen imagen. Antes `_send` ignoraba el toque en
    // silencio y el botón parecía muerto.
    if (text.trim().isEmpty) {
      if (_kind == 'producto' && _photos.isNotEmpty) {
        _send('Esto es lo que busco.');
      } else if (_kind == 'producto') {
        _toast('Escribe qué buscas o sube una foto.');
      } else {
        _toast('Describe el servicio que necesitas.');
      }
      return;
    }
    _send(text);
  }

  /// El corazón del rediseño: mascota expresiva + pregunta en grande +
  /// botones de ancho completo + tarjeta "Tu solicitud"; al `ready`, el
  /// FORMULARIO FINAL de la web.
  Widget _guidedView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        16 + navBarReservedSpace(context),
      ),
      children: [
        Center(
          // Mientras la IA piensa, el Jayi con la mano en la barbilla y sus
          // puntitos (mockup aprobado PO 08-10) sustituye a la cara de duda.
          // La cara expresiva queda MONTADA en Offstage para no perder su
          // estado: al volver, el `reactKey` nuevo dispara el pop de
          // "¡nueva pregunta!" como siempre.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Offstage(
                offstage: _busy,
                child: JayaloMascotFace(
                  size: 68,
                  reactKey: _pop,
                  // Sonrisa cuando la solicitud está lista.
                  mood: _ready != null ? MascotMood.happy : MascotMood.idle,
                ),
              ),
              if (_busy) const _JayiDetective(pensando: true, ancho: 140),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_ready != null && !_correcting)
          _finalForm(cs)
        else ...[
          if (_busy)
            Column(
              children: [
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const JayaloSpinner(size: 14),
                    const SizedBox(width: 8),
                    Text(
                      'Pensando…',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            _questionArea(cs),
          _buildingCard(cs),
        ],
      ],
    );
  }

  Widget _questionArea(ColorScheme cs) {
    final String question;
    List<Widget> actions = const [];
    String? counter;
    if (_correcting) {
      question = '¿Qué quieres corregir?';
      counter = 'Escríbelo abajo y lo ajustamos.';
      // Salida: si el usuario toco "Corregir algo" sin querer (o se
      // arrepiente), esto lo regresa al formulario final sin perder nada —
      // guarda defensiva `_ready != null` porque sin un `ready` previo no
      // hay formulario al que volver.
      if (_ready != null) {
        actions = [
          _optionButton(
            'Volver al formulario',
            () => setState(() => _correcting = false),
            icon: Icons.arrow_back,
          ),
        ];
      }
    } else {
      switch (_current) {
        case AiQuestion q:
          question = q.question;
          // Del historial, no de un contador: «Atrás» lo baja solo.
          counter = 'Pregunta ${answeredCount(_messages) + 1}';
          // Si la IA ya ofreció un catch-all ("Otros", "Otra marca"), ese botón
          // ES el disparador del campo de texto: enviarlo tal cual mandaba
          // "Otros" al proveedor como si fuera la respuesta (bug PO
          // 2026-07-28). Paridad con la web (requests/new.tsx + isCatchAllOption).
          final hasCatchAll = q.options.any(isCatchAllOption);
          actions = [
            for (final op in q.options)
              if (isCatchAllOption(op))
                _optionButton(op, () => setState(() => _showOther = true),
                    icon: Icons.edit_outlined)
              else
                _optionButton(op, () => _send(op)),
            // El campo de texto vive escondido: esto lo revela solo cuando
            // ninguna opción sirve (feedback PO: "se ve todo el tiempo
            // enviar mensaje cuando solo se está dando clic"). Con un
            // catch-all a la vista el enlace sobraría (igual que en la web).
            if (q.allowOther &&
                q.options.isNotEmpty &&
                !hasCatchAll &&
                !_showOther)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showOther = true),
                  child: const Text('Otra respuesta…'),
                ),
              ),
            _backButton(),
          ];
        case AiKindSwitch k:
          question = k.message;
          actions = [
            for (final op in k.options)
              _optionButton(op, () {
                final low = op.toLowerCase();
                if (low.startsWith('sí') || low.startsWith('si')) {
                  // Reinicio con el tipo nuevo (paridad web).
                  _restartWithKind(k.suggestedKind);
                } else {
                  // «No»: formato de la web (new.tsx L1950), sigue el hilo.
                  _send(kindSwitchNoContent(k, _kind), raw: true);
                }
              }),
            _backButton(),
          ];
        case AiImageRequest ir:
          question = ir.hint.isEmpty ? ir.message : '${ir.message}\n${ir.hint}';
          // El cargador se ofrece SIEMPRE: con el cupo lleno la nueva foto
          // reemplaza a la última (ver `_pickForRequest`). Antes desaparecía
          // y la foto equivocada quedaba clavada.
          actions = [
            _optionButton(
              _photos.length >= _maxRequestPhotos
                  ? 'Tomar otra foto'
                  : 'Tomar foto',
              icon: Icons.photo_camera_outlined,
              () => _pickForRequest(ImageSource.camera),
            ),
            _optionButton(
              'Elegir de la galería',
              icon: Icons.photo_library_outlined,
              () => _pickForRequest(ImageSource.gallery),
            ),
            _optionButton('Seguir sin foto', () => _send('Sigamos sin foto.')),
            _backButton(),
          ];
        case AiRouting r:
          // Solo se ve si el auto-«ok» falló (si no, el routing dura lo que
          // tarda el POST siguiente). Antes aquí no había NADA que tocar;
          // «Atrás» es la salida de ese callejón: se vuelve a la pregunta
          // anterior y se reintenta desde ahí.
          question = r.message;
          actions = [_backButton()];
        default:
          return const SizedBox.shrink();
      }
    }
    return Column(
      key: ValueKey('pregunta-$_pop-$_correcting'),
      children: [
        Text(
          question,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w500,
            color: jayaloHead(context),
          ),
        ),
        if (counter != null) ...[
          const SizedBox(height: 6),
          Text(
            counter,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
        if (actions.isNotEmpty) ...[const SizedBox(height: 16), ...actions],
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  /// Botón-respuesta de ancho completo (doctrina: sin bordes, sombra cálida).
  Widget _optionButton(String label, VoidCallback onTap, {IconData? icon}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: jayaloCardShadow(context),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: jayaloHead(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Tu solicitud" — la esencia a la vista: fotos, descripción y cada
  /// respuesta con su check, más la barra honesta "N de ~M".
  Widget _buildingCard(ColorScheme cs) {
    final answers = answerTexts(_messages);
    final answered = answers.length;
    final total = estimatedTotal(answered: answered, wholesale: _wholesale);
    final frac = (answered / total).clamp(0.0, .96);
    // Lila del detalle sin foto (JayaloStatus.responded) — tinta violeta.
    const bg = Color(0xFFEDEBFF);
    const ink = Color(0xFF3C3489);
    const check = Color(0xFF1D9E75);
    final description = _messages.isEmpty ? '' : _messages.first.content;
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Tu solicitud',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.primary,
                ),
              ),
              const Spacer(),
              Text(
                '$answered de ~$total',
                style: const TextStyle(fontSize: 12, color: ink),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: frac),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (_, v, child) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: Colors.white,
                color: cs.primary,
              ),
            ),
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_photos[i].file.path),
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -10,
                        right: -10,
                        child: IconButton(
                          tooltip: 'Quitar',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.cancel, size: 18, color: ink),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _photos.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(fontSize: 13, height: 1.35, color: ink),
            ),
          ],
          for (final a in answers)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 15, color: check),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      a,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── FORMULARIO FINAL (paridad requests/new.tsx) ────────────────────────

  /// Rótulo de un rubro: primero el catálogo (tiene el nombre real), luego los
  /// nombres que se pidieron para los sugeridos, y solo entonces el genérico.
  String _rubroLabel(String id, Map<String, String> fromCatalog) =>
      fromCatalog[id] ?? _rubroNames[id] ?? 'Sugerido';

  /// Fichas de rubro. Se alimentan del catálogo de las categorías objetivo MÁS
  /// lo que sugirió la IA (ver `rubroChoiceIds`), nunca solo de la IA.
  Widget _rubroChips(ColorScheme cs) {
    final names = {
      for (final r in _catalogRubros)
        if (r['id'] is String && r['name'] is String)
          r['id'] as String: r['name'] as String,
    };
    // Arriba solo lo relevante (sugerido + ya elegido); el resto del catálogo
    // vive en el desplegable. Pedido del PO: la parrilla completa es tediosa.
    final ids = rubroChipIds(
      suggested: _rubros,
      selected: _selectedRubros,
      catalog: _catalogRubros,
    );
    final masOpciones = rubroDropdownIds(catalog: _catalogRubros, shown: ids);

    if (ids.isEmpty && masOpciones.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _catalogError ?? 'No hay rubros para esta categoría.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          TextButton(
            // Limpia también la selección: un rubro de la categoría anterior
            // sería huérfano de la nueva y el trigger
            // `trg_validate_customer_request_rubros` rechazaría el INSERT.
            onPressed: () => setState(() {
              _categories = [];
              _catalogRubros = [];
              _selectedRubros = {};
              _catalogError = null;
            }),
            child: const Text('Elegir otra categoría'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_catalogError != null) ...[
          Text(
            _catalogError!,
            style: TextStyle(fontSize: 12, color: cs.error),
          ),
          const SizedBox(height: 6),
        ],
        if (ids.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final id in ids)
                FilterChip(
                  label: Text(_rubroLabel(id, names)),
                  selected: _selectedRubros.contains(id),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _selectedRubros.add(id);
                    } else {
                      _selectedRubros.remove(id);
                    }
                  }),
                ),
            ],
          ),
        if (masOpciones.isNotEmpty) ...[
          SizedBox(height: ids.isEmpty ? 0 : 12),
          _rubroDropdown(cs, masOpciones, names),
        ],
      ],
    );
  }

  /// Desplegable que AGREGA (no que selecciona): al elegir, el rubro sube a las
  /// fichas de arriba ya marcado y sale de la lista.
  ///
  /// [SearchablePickerField] (pedido PO 2026-08-08): buscador + alfabético.
  /// De paso murió el gotcha de la `key` por opciones: la hoja no retiene
  /// selección, así que no hay `_DropdownButtonFormFieldState` que purgar.
  Widget _rubroDropdown(
    ColorScheme cs,
    List<String> opciones,
    Map<String, String> names,
  ) => SearchablePickerField(
    hint: 'Proveedores de…',
    items: [for (final id in opciones) PickerItem(id, _rubroLabel(id, names))],
    onPick: (v) => setState(() => _selectedRubros.add(v)),
    decoration: InputDecoration(
      labelText: 'Proveedores de…',
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      suffixIcon: const Icon(Icons.expand_more),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );

  /// Salida de emergencia cuando la IA no dejó categorías: elegir una a mano
  /// carga su catálogo de rubros y desbloquea el envío.
  Widget _categoryFallbackPicker(ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Elige primero la categoría de lo que buscas:',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final c in kCategories)
            ActionChip(
              label: Text(c.name),
              onPressed: () => _pickCategory(c.id),
            ),
        ],
      ),
    ],
  );

  Widget _sectionTitle(String text, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: jayaloHead(context),
            ),
          ),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );

  /// Checkbox de dos líneas del form final (Nuevo / Usado / Con envío…),
  /// mismas etiquetas y descripciones que la web.
  Widget _checkTile(
    String title,
    String desc,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: value ? const Color(0xFFEDEBFF) : cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Icon(
                  value ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: value ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          color: jayaloHead(context),
                        ),
                      ),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Campo numérico del presupuesto (Desde / Hasta). Sin controlador: arranca
  /// vacío y su texto lo conserva su propio State; `onChanged` alimenta el
  /// string del formulario.
  Widget _budgetField(String label, ValueChanged<String> onChanged) =>
      TextField(
        keyboardType: TextInputType.number,
        enabled: !_busy,
        onChanged: onChanged,
        decoration: filledField(context, label),
      );

  /// Opción exclusiva de dos líneas (cuándo / dónde), estilo web: activa =
  /// lavado lila; sin bordes (doctrina).
  Widget _selectTile(
    String title,
    String desc,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? const Color(0xFFEDEBFF) : cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                          color: jayaloHead(context),
                        ),
                      ),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 18, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// El formulario final COMPLETO de la web tras el `ready`: resumen de la IA
  /// + rubro específico + (producto: checkboxes y "¿Cuándo quieres comprar?" /
  /// servicio: dónde y cuándo) + Enviar.
  Widget _finalForm(ColorScheme cs) {
    final r = _ready!;
    final isService = _kind == 'servicio';
    final effectiveWholesale = r.wholesale || _wholesale;
    return Column(
      key: const ValueKey('form-final'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JayaloCard(
          padding: const EdgeInsets.all(16),
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Esto es lo que entendí',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                r.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context),
                ),
              ),
              const SizedBox(height: 8),
              for (final b in r.bullets) Text('• $b'),
              if (r.wholesale || _wholesale)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: StatusChip(
                    label: 'Al por mayor',
                    icon: Icons.storefront_outlined,
                    tone: Theme.of(context).brightness == Brightness.dark
                        ? JayaloStatus.respondedDark
                        : JayaloStatus.respondedLight,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('¿Dónde más buscamos?', required: true),
        Text(
          'Para que solo proveedores realmente especializados reciban tu solicitud.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        // Sin categorías la IA no clasificó (saltó el turno `routing`): no hay
        // catálogo que leer, así que el usuario elige la categoría a mano en vez
        // de quedarse ante una sección obligatoria y vacía.
        if (_categories.isEmpty)
          _categoryFallbackPicker(cs)
        else if (_loadingCatalog && _catalogRubros.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: JayaloSpinner(size: 16)),
          )
        else
          _rubroChips(cs),
        const SizedBox(height: 16),
        // Requisitos transversales (aplican a producto Y servicio, pedido PO
        // 2026-07-22): van fuera del bloque `if (!isService)`.
        _checkTile(
          'Requiere comprobante fiscal',
          'El proveedor debe poder emitir comprobante fiscal (NCF).',
          _requiresFiscalReceipt,
          (v) => setState(() => _requiresFiscalReceipt = v),
        ),
        _checkTile(
          'Requiere ser suplidor del estado',
          'Necesitas un proveedor registrado como suplidor del Estado.',
          _requiresStateSupplier,
          (v) => setState(() => _requiresStateSupplier = v),
        ),
        if (!isService) ...[
          _checkTile(
            'Nuevo',
            'Producto sin uso previo.',
            _wantsNew,
            (v) => setState(() {
              _wantsNew = v;
              _conditionTouched = true;
            }),
          ),
          _checkTile(
            'Usado',
            'Acepto producto de segunda mano.',
            _wantsUsed,
            (v) => setState(() {
              _wantsUsed = v;
              _conditionTouched = true;
            }),
          ),
          _checkTile(
            'Con traslado',
            'Que coticen también el traslado.',
            _withShipping,
            (v) => setState(() => _withShipping = v),
          ),
          _checkTile(
            'Con instalación',
            'Que incluyan el costo de instalación.',
            _withInstallation,
            (v) => setState(() => _withInstallation = v),
          ),
          _checkTile(
            'Requiere evaluación',
            'El precio depende de revisar en sitio.',
            _requiresEvaluation,
            (v) => setState(() => _requiresEvaluation = v),
          ),
          if (effectiveWholesale) ...[
            const SizedBox(height: 16),
            _sectionTitle('Detalles de mayoreo', required: true),
            const SizedBox(height: 6),
            _sectionTitle('Cantidad que necesitas', required: true),
            const SizedBox(height: 6),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Ej. 200'),
              onChanged: (v) => _wsQuantity = v,
            ),
            const SizedBox(height: 16),
            _sectionTitle('¿Cómo necesitas dividir el pedido?', required: true),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (slug, label) in kWholesaleSplitOptions)
                  ChoiceChip(
                    label: Text(label),
                    selected: _wsSplit == slug,
                    onSelected: (_) => setState(() => _wsSplit = slug),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle(
              '¿Necesitas algún tipo de empaque o presentación?',
              required: true,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (slug, label) in kWholesalePackagingOptions)
                  ChoiceChip(
                    label: Text(label),
                    selected: _wsPackaging == slug,
                    onSelected: (_) => setState(() => _wsPackaging = slug),
                  ),
              ],
            ),
            if (_wsPackaging == 'otro' ||
                _wsSplit == 'cantidades_especificas') ...[
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Especifica el detalle',
                ),
                onChanged: (v) => _wsNote = v,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Se enviará priorizando a proveedores mayoristas.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('¿Cuándo quieres comprar?'),
          const SizedBox(height: 6),
          for (final (value, title, desc) in _urgencyOptions)
            _selectTile(
              title,
              desc,
              _urgency == value,
              () => setState(() => _urgency = value),
            ),
        ] else ...[
          _sectionTitle('¿Dónde se hace el servicio?', required: true),
          const SizedBox(height: 6),
          for (final (value, title, desc, icon) in _serviceModalityOptions)
            _selectTile(
              title,
              desc,
              _serviceModality == value,
              () => setState(() => _serviceModality = value),
              icon: icon,
            ),
          if (_serviceModality == 'event') ...[
            const SizedBox(height: 6),
            _selectTile(
              _serviceEventDate == null
                  ? 'Elegir la fecha del evento'
                  : 'Fecha: ${_serviceEventDate!.day.toString().padLeft(2, '0')}/${_serviceEventDate!.month.toString().padLeft(2, '0')}/${_serviceEventDate!.year}',
              'Toca para cambiarla.',
              _serviceEventDate != null,
              () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      _serviceEventDate ??
                      DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                // `showDatePicker` tarda lo que el usuario quiera: sin el guard
                // el `setState` corre sobre un widget que pudo desmontarse.
                if (picked != null && mounted) {
                  setState(() => _serviceEventDate = picked);
                }
              },
              icon: Icons.event_outlined,
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('¿Cuándo lo necesitas?', required: true),
          const SizedBox(height: 6),
          for (final (value, title, desc, icon) in _serviceUrgencyOptions)
            _selectTile(
              title,
              desc,
              _urgencyLevel == value,
              () => setState(() => _urgencyLevel = value),
              icon: icon,
            ),
          const SizedBox(height: 16),
          _sectionTitle('¿Cada cuánto se repite?'),
          Text(
            'Limpieza semanal, mantenimiento mensual, etc.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final (value, title, desc, icon) in _serviceFrequencyOptions)
            _selectTile(
              title,
              desc,
              _serviceFrequency == value,
              () => setState(() {
                _serviceFrequency = value;
                // Cambiar de píldora descarta lo escrito en "Otra": si no, un
                // texto viejo viajaría con una opción cerrada elegida.
                if (value != kServiceFrequencyOther) _serviceFrequencyOther = '';
              }),
              icon: icon,
            ),
          if (_serviceFrequency == kServiceFrequencyOther) ...[
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => _serviceFrequencyOther = v,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Escribe la frecuencia',
                hintText: 'Ej: cada lunes a las 9am',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('Presupuesto estimado'),
          Text(
            'Opcional. Ayuda a los proveedores a saber si encajan.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _budgetField('Desde RD\$', (v) => _budgetMin = v),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _budgetField('Hasta RD\$', (v) => _budgetMax = v),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const JayaloSpinner(size: 16, color: Colors.white)
                  : const Text('Enviar solicitud'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _correcting = true;
                    }),
              child: const Text('Corregir algo'),
            ),
            // «Atrás» desde la ficha (spec §5.2): vuelve al routing/última
            // pregunta sin llamar al servidor. Oculto mientras `_correcting`
            // porque entonces no se pinta la ficha, sino `_questionArea`.
            TextButton.icon(
              onPressed: _busy ? null : _goBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Atrás'),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _successView() =>
      RequestPublishedView(onSeeRequests: () => context.go('/client'));
}

/// Jayi de crear-solicitud (mockup aprobado PO 2026-08-10, v4 con codos):
/// dos modos en un solo painter.
///
/// - [pensando] = false → JAYI DETECTIVE: la lupa al ojo con el ojo GIGANTE
///   aumentado a través del cristal; el conjunto brazo+lupa pasea en
///   circulito (se acerca, se aleja, se inclina), el cuerpo se ladea
///   escaneando, la pupila barre, un destello cruza el cristal y pestañea.
/// - [pensando] = true → mano en la BARBILLA dando golpecitos, ojo mirando
///   arriba a tres puntitos violeta que laten en escalera, ladeo suave y
///   antenas temblando alternadas.
///
/// Mismo patrón que los Jayi de Mis ofertas / Recargar créditos / Mensajes:
/// painter propio, cero assets, frame fijo en tests y con «reducir
/// movimiento». Todos los ritmos son conmensurables con el ciclo de 5,2 s
/// para que el bucle reinicie sin salto (patrón del JayaloLoader).
class _JayiDetective extends StatefulWidget {
  const _JayiDetective({required this.pensando, this.ancho = 190});

  final bool pensando;

  /// Ancho del lienzo; el alto sale de la proporción 190×130 del mockup.
  final double ancho;

  @override
  State<_JayiDetective> createState() => _JayiDetectiveState();
}

class _JayiDetectiveState extends State<_JayiDetective>
    with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));
  late final AnimationController _fx = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5200));

  /// En widget-tests el bucle infinito rompe TODO `pumpAndSettle` de la
  /// pantalla (nunca "asienta"): frame fijo. `Platform.environment` y no
  /// `bool.fromEnvironment` (ese dart-define NO está definido bajo
  /// `flutter test` y el gate no gateaba).
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enTest || JayaloMotion.reduced(context)) {
      _bob.stop();
      _fx.stop();
    } else {
      if (!_bob.isAnimating) _bob.repeat(reverse: true);
      if (!_fx.isAnimating) _fx.repeat();
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estatico = _enTest || JayaloMotion.reduced(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_bob, _fx]),
      builder: (_, _) => CustomPaint(
        key: ValueKey(widget.pensando ? 'jayi_pensando' : 'jayi_lupa'),
        size: Size(widget.ancho, widget.ancho * 130 / 190),
        painter: _JayiDetectivePainter(
          pensando: widget.pensando,
          t: _fx.value,
          bob: _bob.value,
          estatico: estatico,
        ),
      ),
    );
  }
}

class _JayiDetectivePainter extends CustomPainter {
  _JayiDetectivePainter({
    required this.pensando,
    required this.t,
    required this.bob,
    required this.estatico,
  });

  final bool pensando;

  /// 0..1 del ciclo maestro de 5,2 s.
  final double t;

  /// 0..1 con repeat(reverse): el flote.
  final double bob;

  final bool estatico;

  static const _violetaTubo = Color(0xFF6B40EE);
  static const _cuerpoA = Color(0xFF7E56F5);
  static const _cuerpoB = Color(0xFF6438E8);
  static const _oroLupa = Color(0xFFB47A1D);
  static const _violeta = Color(0xFF7147F2);

  /// Vaivén 0→1→0 suavizado; [ciclos] = cuántas idas-y-vueltas por ciclo
  /// maestro (2 → periodo de 2,6 s).
  double _ping(double ciclos, [double desfase = 0]) {
    final p = (t * ciclos + desfase) % 1;
    return Curves.easeInOut.transform(p < .5 ? p * 2 : (1 - p) * 2);
  }

  /// Interpola keyframes `(fase 0-1, valor)` con easeInOut entre tramos
  /// (mismo truco que el JayaloLoader para calcar @keyframes del CSS).
  static double _kf(double fase, List<(double, double)> frames) {
    for (var i = 0; i < frames.length - 1; i++) {
      final (p0, v0) = frames[i];
      final (p1, v1) = frames[i + 1];
      if (fase >= p0 && fase <= p1) {
        if (p1 == p0) return v1;
        final local = Curves.easeInOut.transform((fase - p0) / (p1 - p0));
        return v0 + (v1 - v0) * local;
      }
    }
    return frames.last.$2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 190);
    canvas.translate(0, -4 * bob);
    if (pensando) {
      _modoPensando(canvas);
    } else {
      _modoLupa(canvas);
    }
  }

  /// Pestañeo una vez por ciclo, al final (fase .88–.94).
  double get _ojoAbierto {
    if (estatico) return 1;
    if (t < .88 || t > .94) return 1;
    return 1 - .9 * math.sin(math.pi * (t - .88) / .06);
  }

  void _antenas(Canvas canvas, Paint tubo,
      {double rotIzq = 0, double rotDer = 0}) {
    tubo.strokeWidth = 5;
    canvas.save();
    canvas.translate(83, 26);
    canvas.rotate(rotIzq * math.pi / 180);
    canvas.translate(-83, -26);
    canvas.drawPath(
        Path()
          ..moveTo(83, 26)
          ..cubicTo(79, 18, 71, 15, 66, 18),
        tubo);
    canvas.restore();
    canvas.save();
    canvas.translate(101, 25);
    canvas.rotate(rotDer * math.pi / 180);
    canvas.translate(-101, -25);
    canvas.drawPath(
        Path()
          ..moveTo(101, 25)
          ..cubicTo(105, 17, 113, 14, 118, 17),
        tubo);
    canvas.restore();
  }

  void _cuerpo(Canvas canvas) {
    const bodyRect = Rect.fromLTWH(58, 24, 70, 66);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(22)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cuerpoA, _cuerpoB],
        ).createShader(bodyRect),
    );
  }

  void _bracitoIzquierdo(Canvas canvas, Paint tubo) {
    tubo.strokeWidth = 7;
    canvas.drawPath(
        Path()
          ..moveTo(60, 68)
          ..cubicTo(48, 74, 46, 86, 56, 90),
        tubo);
    canvas.drawCircle(const Offset(57, 90), 5.5, Paint()..color = _cuerpoA);
  }

  // ── Modo detective: la lupa al ojo ─────────────────────────────────────

  void _modoLupa(Canvas canvas) {
    // Escaneo del cuerpo: ladeo + vaivén lateral, ida y vuelta cada 2,6 s.
    final v = estatico ? .5 : _ping(2);
    canvas.save();
    canvas.translate(95, 110);
    canvas.rotate((-2.4 + 4.8 * v) * math.pi / 180);
    canvas.translate(-95 + (-3 + 6 * v), -110);

    final tubo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = _violetaTubo;

    _antenas(canvas, tubo);
    _cuerpo(canvas);
    _bracitoIzquierdo(canvas, tubo);

    // El conjunto brazo+lupa+ojo aumentado PASEA en circulito (que no
    // parezca un monóculo fijo — corrección PO sobre la v2 del mockup).
    final px = estatico
        ? 0.0
        : _kf(t, const [(0, 0), (.22, -4), (.45, 2), (.68, 5), (.86, -2), (1, 0)]);
    final py = estatico
        ? 0.0
        : _kf(t,
            const [(0, 0), (.22, -3), (.45, 2.5), (.68, -2), (.86, 1.5), (1, 0)]);
    final pr = estatico
        ? 0.0
        : _kf(t,
            const [(0, 0), (.22, -4), (.45, 2), (.68, 4.5), (.86, -2), (1, 0)]);
    canvas.save();
    canvas.translate(100 + px, 71 + py);
    canvas.rotate(pr * math.pi / 180);
    canvas.translate(-100, -71);

    // Brazo con el CODO asomando por la derecha del cuerpo.
    tubo.strokeWidth = 7;
    canvas.drawPath(
        Path()
          ..moveTo(124, 62)
          ..cubicTo(142, 66, 146, 84, 130, 89)
          ..cubicTo(118, 93, 104, 84, 100, 72),
        tubo);
    // Mango.
    canvas.drawLine(
        const Offset(92, 61),
        const Offset(100, 71),
        Paint()
          ..color = _oroLupa
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round);

    // OJO GIGANTE visto a través del cristal (pestañea).
    const ojo = Offset(81, 50);
    canvas.save();
    canvas.translate(ojo.dx, ojo.dy);
    canvas.scale(1, _ojoAbierto.clamp(.1, 1.0));
    canvas.drawCircle(Offset.zero, 15.5, Paint()..color = Colors.white);
    // La pupila agrandada barre con el escaneo del cuerpo.
    canvas.drawCircle(
        Offset(-4 + 8.5 * v, 2), 7.5, Paint()..color = _cuerpoB);
    canvas.restore();

    // Cristal + aro dorado.
    canvas.drawCircle(
        ojo, 16.5, Paint()..color = Colors.white.withValues(alpha: .22));
    canvas.drawCircle(
        ojo,
        16.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..color = _oroLupa);

    // Destello que cruza el cristal (dos pasadas por ciclo).
    if (!estatico) {
      final g = (t * 2) % 1;
      if (g >= .55 && g <= .85) {
        final gg = (g - .55) / .3;
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: ojo, radius: 15)));
        canvas.translate(81 + (-8 + 17 * gg), 50 + (6 - 13 * gg));
        canvas.rotate(-38 * math.pi / 180);
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: 5, height: 40),
            Paint()
              ..color = Colors.white
                  .withValues(alpha: .85 * math.sin(math.pi * gg)));
        canvas.restore();
      }
    }

    // Manita agarrando el mango.
    canvas.drawCircle(const Offset(100, 71), 5.5, Paint()..color = _cuerpoA);

    canvas.restore(); // paseo de la lupa
    canvas.restore(); // escaneo del cuerpo
  }

  // ── Modo pensando: mano en la barbilla + puntitos ──────────────────────

  void _modoPensando(Canvas canvas) {
    final v = estatico ? .5 : _ping(2);
    canvas.save();
    canvas.translate(95, 100);
    canvas.rotate((-2.4 + 4.4 * v) * math.pi / 180);
    canvas.translate(-95, -100);

    final tubo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = _violetaTubo;

    // Antenas temblando alternadas (piensa con las antenas).
    _antenas(canvas, tubo,
        rotIzq: estatico ? 0 : -4 + 9 * _ping(2),
        rotDer: estatico ? 0 : 5 - 9 * _ping(2, .3));
    _cuerpo(canvas);

    // Ojo mirando ARRIBA a sus puntitos (y pestañea).
    canvas.save();
    canvas.translate(81, 50);
    canvas.scale(1, _ojoAbierto.clamp(.1, 1.0));
    canvas.drawCircle(Offset.zero, 14, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(4, -6), 5.2, Paint()..color = _cuerpoB);
    canvas.restore();

    _bracitoIzquierdo(canvas, tubo);

    // Brazo derecho a la barbilla, con el codo afuera y golpecitos.
    final tap =
        estatico ? 0.0 : -2.2 * math.sin(math.pi * ((t * 8) % 2)).abs();
    canvas.save();
    canvas.translate(0, tap);
    tubo.strokeWidth = 7;
    canvas.drawPath(
        Path()
          ..moveTo(124, 68)
          ..cubicTo(141, 74, 143, 90, 128, 93)
          ..cubicTo(116, 95, 104, 92, 99, 87),
        tubo);
    canvas.drawCircle(const Offset(99, 86), 6, Paint()..color = _cuerpoA);
    canvas.restore();

    canvas.restore(); // ladeo

    // Puntitos de pensar en escalera (fuera del ladeo, como en el mockup).
    const puntos = [(Offset(134, 34), 4.0), (Offset(146, 24), 5.5), (Offset(161, 13), 7.0)];
    for (var d = 0; d < puntos.length; d++) {
      final (c, r) = puntos[d];
      final fase = estatico ? .35 : ((t * 4) - d * .15) % 1;
      final k = _kf(fase, const [(0, 0), (.35, 1), (.7, 0), (1, 0)]);
      canvas.drawCircle(
          c,
          r * (.8 + .35 * k),
          Paint()..color = _violeta.withValues(alpha: .35 + .65 * k));
    }
  }

  @override
  bool shouldRepaint(_JayiDetectivePainter old) =>
      old.pensando != pensando ||
      old.t != t ||
      old.bob != bob ||
      old.estatico != estatico;
}
