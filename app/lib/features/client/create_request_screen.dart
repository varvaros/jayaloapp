import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/ai_client.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/ai_turns.dart';
import '../../domain/image_pick.dart';
import '../../domain/request_progress.dart';
import '../../domain/request_seed.dart';
import '../../domain/wholesale.dart';
import '../shell/floating_nav_bar.dart';
import '../verification/verify_banner.dart';
import 'request_success_view.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

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

/// Foto pendiente de una solicitud: el `dataUrl` base64 viaja a la IA en cada
/// turno; la ruta local (`file.path`) se sube a Storage al enviar.
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
  final List<String> _answers = [];
  AiTurn? _current;
  int _pop = 0; // key de la reacción de la mascota (cambia por turno)
  AiReady? _ready;
  bool _showOther = false; // composer visible para "Otra respuesta…"

  // ── Formulario final (paridad requests/new.tsx) ────────────────────────
  bool _wantsNew = false;
  bool _wantsUsed = false;
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
  // Presupuesto estimado (opcional, servicios) — paridad web requests/new.tsx.
  String _budgetMin = '';
  String _budgetMax = '';
  Set<String> _selectedRubros = {};
  Map<String, String> _rubroNames = {};
  int _aiAnswered = 0;

  // Detalles de mayoreo (obligatorios cuando la solicitud es al por mayor —
  // paridad web requests/new.tsx). Slugs de `domain/wholesale.dart`.
  String _wsQuantity = '';
  String _wsSplit = '';
  String _wsPackaging = '';
  String _wsNote = '';

  @override
  void initState() {
    super.initState();
    if (widget.seedFrom != null) {
      // fire-and-forget: prefija el input; la foto se adjunta en Task 5.
      _applySeed(widget.seedFrom!);
    }
  }

  Future<void> _applySeed(String seedFrom) async {
    final row = await requestById(seedFrom);
    if (row == null || !mounted) return;
    final seed = RequestSeed.fromRow(row);
    setState(() => _input.text = seed.title);

    final url = seed.imageUrl;
    if (url == null) return;
    try {
      final bytes = await http.readBytes(Uri.parse(url));
      final png = url.toLowerCase().contains('.png');
      final mime = png ? 'image/png' : 'image/jpeg';
      final ext = png ? 'png' : 'jpg';
      final f = File(
        '${Directory.systemTemp.path}/seed_'
        '${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await f.writeAsBytes(bytes);
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      if (!mounted) return;
      setState(() => _photos.add(_PendingPhoto(XFile(f.path), dataUrl)));
    } catch (_) {
      // Best-effort: si la descarga falla, se sigue solo con el título.
    }
  }

  /// `force` es SOLO para las continuaciones internas (el auto-"ok" del
  /// routing): se disparan dentro del `try` del envío anterior, cuando `_busy`
  /// aún es true — sin force, el guard se las tragaba en silencio y el flujo
  /// quedaba muerto esperando al usuario (bug pre-existente que el chat viejo
  /// disimulaba y la vista guiada destapó).
  Future<void> _send(String text, {bool force = false}) async {
    if (text.trim().isEmpty || (_busy && !force)) return;
    // Solo cuentan como "respuesta" de la solicitud las contestaciones a una
    // pregunta real de la IA (no el auto-"ok" del routing, ni la foto, ni las
    // correcciones tras el ready).
    final record =
        !_correcting && (_current is AiQuestion || _current is AiKindSwitch);
    setState(() {
      _busy = true;
      _correcting = false;
      _showOther = false;
      _messages.add(AiMessage('user', text));
      if (record) {
        _answers.add(text);
        _aiAnswered++;
      }
      _input.clear();
    });
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
      _messages.add(AiMessage('assistant', jsonEncode(_turnToJson(turn))));
      await _handleTurn(turn);
    } on AiHttpException catch (e) {
      _toast(
        e.status == 429
            ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
            : e.message,
      );
      setState(() {
        _messages.removeLast();
        if (record) {
          _answers.removeLast();
          _aiAnswered--;
        }
      });
    } catch (e) {
      _toast('Algo falló. Intenta de nuevo.');
      setState(() {
        _messages.removeLast();
        if (record) {
          _answers.removeLast();
          _aiAnswered--;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Elige y valida una foto; la agrega a `_photos` (con su base64 cacheado).
  /// Devuelve true si se agregó.
  Future<bool> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return false;
    // Recorte tras tomar/elegir la foto (pedido PO): el usuario ajusta el
    // encuadre antes de adjuntarla. Si cancela el crop, no se adjunta nada.
    final cropped = await _cropImage(picked);
    if (cropped == null) return false;
    final bytes = await cropped.readAsBytes();
    final res = validatePickedImage(
      sizeBytes: bytes.length,
      path: cropped.path,
      currentCount: _photos.length,
      maxCount: _maxRequestPhotos,
    );
    if (res is ImagePickError) {
      _toast(res.message);
      return false;
    }
    final dataUrl =
        'data:${_imageMime(cropped.path)};base64,${base64Encode(bytes)}';
    if (mounted) setState(() => _photos.add(_PendingPhoto(cropped, dataUrl)));
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
  Future<void> _pickForRequest(ImageSource source) async {
    if (await _pickPhoto(source)) {
      await _send('Aquí tienes una foto para más contexto.');
    }
  }

  /// Adjuntar espontáneo desde la barra de entrada.
  Future<void> _showPickSheet() async {
    if (_photos.length >= _maxRequestPhotos) {
      _toast('Puedes subir hasta $_maxRequestPhotos fotos.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
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
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  String _imageMime(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  Future<void> _handleTurn(AiTurn turn) async {
    switch (turn) {
      case AiQuestion q:
        setState(() {
          _current = q;
          _pop++;
        });
      case AiKindSwitch k:
        setState(() {
          _current = k;
          _pop++;
        });
      case AiImageRequest ir:
        setState(() {
          _current = ir;
          _pop++;
        });
      case AiRouting r:
        setState(() {
          _categories = r.categories;
          _rubros = r.rubros;
          _current = r;
        });
        await _send('ok', force: true);
      case AiReady rd:
        setState(() {
          _ready = rd;
          _current = rd;
          _pop++;
          // Premarcado del form si la IA captó el estado en la conversación —
          // paridad exacta con `applyReadyCondition`/`conditionToFlags` web.
          if (_kind == 'producto' && rd.condition != null) {
            _wantsNew = rd.condition == 'nuevo' || rd.condition == 'ambos';
            _wantsUsed = rd.condition == 'usado' || rd.condition == 'ambos';
          }
          if (_selectedRubros.isEmpty) _selectedRubros = _rubros.toSet();
        });
        if (_rubroNames.isEmpty && _rubros.isNotEmpty) {
          unawaited(_loadRubroNames());
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

  Map<String, dynamic> _turnToJson(AiTurn t) => switch (t) {
    AiQuestion q => {
      'type': 'question',
      'question': q.question,
      'options': q.options,
      'allowOther': q.allowOther,
    },
    AiImageRequest i => {
      'type': 'image_request',
      'message': i.message,
      'hint': i.hint,
    },
    AiRouting r => {
      'type': 'routing',
      'message': r.message,
      'categories': r.categories,
      'rubros': r.rubros,
    },
    AiReady r => {
      'type': 'ready',
      'title': r.title,
      'bullets': r.bullets,
      if (r.wholesale) 'wholesale': true,
    },
    AiKindSwitch k => {
      'type': 'kind_switch',
      'message': k.message,
      'suggested_kind': k.suggestedKind,
      'options': k.options,
    },
  };

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
      setState(() => _submitted = true);
    } catch (_) {
      _toast('No se pudo enviar la solicitud.');
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
              onTap: () => context.pop(),
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
          if (_ready == null &&
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
          // La mascota respirando — misma cara "buscando" de la web. OJO: va
          // dentro de un Center porque la columna es `stretch` y su
          // CustomPaint ADOPTA las constraints del padre (a ancho completo se
          // pintaba GIGANTE detrás del buscador — QA PO 2026-07-21); el
          // Center la suelta a su tamaño propio. 112 = "100% más grande"
          // que la pasada de 56 (pedido PO).
          const Center(child: JayaloMascotFace(size: 112)),
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
              hintText: '¿Qué estás buscando?',
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
              prefixIcon: IconButton(
                tooltip: 'Tomar o subir foto',
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: _busy ? null : _showPickSheet,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => _startSend(_input.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Tipo de solicitud DEBAJO de la barra (pedido PO). Sin default.
          // Flujo (PO 2026-07-22): inicial Producto|Servicio; al elegir
          // Producto se OCULTA Servicio y aparece "Al por mayor"; al elegir
          // Servicio se oculta Producto. Tocar el tipo elegido de nuevo lo
          // deselecciona y vuelve a los dos botones.
          Row(
            children: [
              if (_kind != 'servicio')
                Expanded(child: _kindPill('producto', 'Producto')),
              if (_kind == 'producto') ...[
                const SizedBox(width: 10),
                Expanded(child: _kindPill('mayor', 'Al por mayor')),
              ],
              if (_kind != 'producto') ...[
                if (_kind != 'servicio') const SizedBox(width: 10),
                Expanded(child: _kindPill('servicio', 'Servicio')),
              ],
            ],
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
          const SizedBox(height: 8),
          // El botón de HACER la foto, visible desde el arranque
          // (pedido PO): cámara primero, galería al lado. La foto
          // viaja con el primer mensaje.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Tomar foto'),
                onPressed: () => _pickPhoto(ImageSource.camera),
              ),
              ActionChip(
                avatar: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Galería'),
                onPressed: () => _pickPhoto(ImageSource.gallery),
              ),
            ],
          ),
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
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurface,
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
          child: JayaloMascotFace(
            size: 68,
            reactKey: _pop,
            // Duda mientras piensa, sonrisa cuando la solicitud está lista.
            mood: _busy
                ? MascotMood.thinking
                : _ready != null
                ? MascotMood.happy
                : MascotMood.idle,
          ),
        ),
        const SizedBox(height: 14),
        if (_ready != null)
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
    } else {
      switch (_current) {
        case AiQuestion q:
          question = q.question;
          counter = 'Pregunta ${_aiAnswered + 1}';
          actions = [
            for (final op in q.options) _optionButton(op, () => _send(op)),
            // El campo de texto vive escondido: esto lo revela solo cuando
            // ninguna opción sirve (feedback PO: "se ve todo el tiempo
            // enviar mensaje cuando solo se está dando clic").
            if (q.allowOther && q.options.isNotEmpty && !_showOther)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showOther = true),
                  child: const Text('Otra respuesta…'),
                ),
              ),
          ];
        case AiKindSwitch k:
          question = k.message;
          actions = [
            for (final op in k.options)
              _optionButton(op, () {
                final low = op.toLowerCase();
                if (low.startsWith('sí') || low.startsWith('si')) {
                  setState(() => _kind = k.suggestedKind);
                }
                _send(op);
              }),
          ];
        case AiImageRequest ir:
          question = ir.hint.isEmpty ? ir.message : '${ir.message}\n${ir.hint}';
          actions = [
            if (_photos.length < _maxRequestPhotos) ...[
              _optionButton(
                'Tomar foto',
                icon: Icons.photo_camera_outlined,
                () => _pickForRequest(ImageSource.camera),
              ),
              _optionButton(
                'Elegir de la galería',
                icon: Icons.photo_library_outlined,
                () => _pickForRequest(ImageSource.gallery),
              ),
            ],
            _optionButton('Seguir sin foto', () => _send('Sigamos sin foto.')),
          ];
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
    final total = estimatedTotal(answered: _aiAnswered, wholesale: _wholesale);
    final frac = (_aiAnswered / total).clamp(0.0, .96);
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
                '$_aiAnswered de ~$total',
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
          for (final a in _answers)
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
        _sectionTitle('Elige uno o más rubros', required: true),
        Text(
          'Para que solo proveedores realmente especializados reciban tu solicitud.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (_rubroNames.isEmpty && _rubros.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: JayaloSpinner(size: 16)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final id in _rubros)
                FilterChip(
                  label: Text(_rubroNames[id] ?? 'Sugerido'),
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
            (v) => setState(() => _wantsNew = v),
          ),
          _checkTile(
            'Usado',
            'Acepto producto de segunda mano.',
            _wantsUsed,
            (v) => setState(() => _wantsUsed = v),
          ),
          _checkTile(
            'Con envío',
            'Que coticen también el envío.',
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
                if (picked != null) {
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
        Row(
          children: [
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const JayaloSpinner(size: 16, color: Colors.white)
                  : const Text('Enviar solicitud'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _ready = null;
                      _correcting = true;
                    }),
              child: const Text('Corregir algo'),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _successView() =>
      RequestPublishedView(onSeeRequests: () => context.go('/client'));
}
