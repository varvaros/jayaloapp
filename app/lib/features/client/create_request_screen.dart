import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/ai_client.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/ai_turns.dart';
import '../../domain/image_pick.dart';
import '../../domain/request_progress.dart';
import '../shell/floating_nav_bar.dart';
import '../verification/verify_banner.dart';
import 'request_success_view.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

const _maxRequestPhotos = 2;

/// Foto pendiente de una solicitud: el `dataUrl` base64 viaja a la IA en cada
/// turno; la ruta local (`file.path`) se sube a Storage al enviar.
class _PendingPhoto {
  _PendingPhoto(this.file, this.dataUrl);
  final XFile file;
  final String dataUrl;
}

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

/// Píldora "Al por mayor" para el header violeta: blanca plena con check al
/// activarse, translúcida al apagarse.
class _WholesaleToggle extends StatelessWidget {
  const _WholesaleToggle({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (selected) ...[
            Icon(Icons.check, size: 14, color: cs.primary),
            const SizedBox(width: 4),
          ],
          Text('Al por mayor',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: selected ? cs.primary : Colors.white)),
        ]),
      ),
    );
  }
}

/// Rediseño "Jayi te entrevista" (spec 2026-07-19-solicitud-gamificada):
/// sin burbujas de chat — la mascota pregunta, las opciones son botones de
/// ancho completo y abajo la tarjeta "Tu solicitud" se va llenando con cada
/// respuesta (barra honesta "N de ~M"). El contrato con la IA no cambia.
class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _ai = AiClient();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  String _kind = 'producto';
  bool _wholesale = false;
  bool _busy = false;
  bool _correcting = false;
  bool _submitted = false;
  List<String> _categories = [];
  List<String> _rubros = [];
  final List<_PendingPhoto> _photos = [];
  final List<String> _answers = [];
  AiTurn? _current;
  int _pop = 0; // key de la micro-reacción de la mascota (cambia por turno)
  AiReady? _ready;

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _busy) return;
    // Solo cuentan como "respuesta" de la solicitud las contestaciones a una
    // pregunta real de la IA (no el auto-"ok" del routing, ni la foto, ni las
    // correcciones tras el ready).
    final record =
        !_correcting && (_current is AiQuestion || _current is AiKindSwitch);
    setState(() {
      _busy = true;
      _correcting = false;
      _messages.add(AiMessage('user', text));
      if (record) _answers.add(text);
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
          imageDataUrl2: _photos.length > 1 ? _photos[1].dataUrl : null);
      _messages.add(AiMessage('assistant', jsonEncode(_turnToJson(turn))));
      await _handleTurn(turn);
    } on AiHttpException catch (e) {
      _toast(e.status == 429
          ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
          : e.message);
      setState(() {
        _messages.removeLast();
        if (record) _answers.removeLast();
      });
    } catch (e) {
      _toast('Algo falló. Intenta de nuevo.');
      setState(() {
        _messages.removeLast();
        if (record) _answers.removeLast();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Elige y valida una foto; la agrega a `_photos` (con su base64 cacheado).
  /// Devuelve true si se agregó.
  Future<bool> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return false;
    final bytes = await picked.readAsBytes();
    final res = validatePickedImage(
        sizeBytes: bytes.length,
        path: picked.path,
        currentCount: _photos.length,
        maxCount: _maxRequestPhotos);
    if (res is ImagePickError) {
      _toast(res.message);
      return false;
    }
    final dataUrl = 'data:${_imageMime(picked.path)};base64,${base64Encode(bytes)}';
    if (mounted) setState(() => _photos.add(_PendingPhoto(picked, dataUrl)));
    return true;
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
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
        await _send('ok');
      case AiReady rd:
        setState(() {
          _ready = rd;
          _current = rd;
          _pop++;
        });
    }
  }

  Map<String, dynamic> _turnToJson(AiTurn t) => switch (t) {
        AiQuestion q => {
            'type': 'question',
            'question': q.question,
            'options': q.options,
            'allowOther': q.allowOther
          },
        AiImageRequest i => {
            'type': 'image_request',
            'message': i.message,
            'hint': i.hint
          },
        AiRouting r => {
            'type': 'routing',
            'message': r.message,
            'categories': r.categories,
            'rubros': r.rubros
          },
        AiReady r => {
            'type': 'ready',
            'title': r.title,
            'bullets': r.bullets,
            if (r.wholesale) 'wholesale': true
          },
        AiKindSwitch k => {
            'type': 'kind_switch',
            'message': k.message,
            'suggested_kind': k.suggestedKind,
            'options': k.options
          },
      };

  Future<void> _submit() async {
    final r = _ready!;
    if (_rubros.isEmpty) {
      _toast('La solicitud no tiene rubros; escribe "corrige la categoría" para reintentar.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Subir las fotos a Storage antes de insertar (nunca base64 en la BD).
      final imageUrls =
          await Future.wait(_photos.map((p) => uploadRequestImage(p.file.path)));
      await submitRequest(
          title: r.title,
          bullets: r.bullets,
          kind: _kind,
          wholesale: r.wholesale || _wholesale,
          categories: _categories,
          rubros: _rubros,
          imageUrls: imageUrls);
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

  @override
  Widget build(BuildContext context) {
    final started = _messages.isNotEmpty;
    return Scaffold(
      body: Column(children: [
        // Header violeta: "Crear solicitud" centrado, y antes de empezar el
        // toggle Producto/Servicio + la píldora "Al por mayor" (doctrina: el
        // header envuelve los controles de la pantalla).
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            onTap: () => context.pop(),
          ),
          title: 'Crear solicitud',
          titleAlign: HeaderTitleAlign.center,
          actions: const [HeaderBell()],
          below: started
              ? null
              : Row(children: [
                  HeaderSegmented(
                    options: const ['Producto', 'Servicio'],
                    index: _kind == 'producto' ? 0 : 1,
                    onChanged: (i) => setState(() {
                      _kind = i == 0 ? 'producto' : 'servicio';
                      if (_kind == 'servicio') _wholesale = false;
                    }),
                  ),
                  if (_kind == 'producto') ...[
                    const SizedBox(width: 8),
                    _WholesaleToggle(
                      selected: _wholesale,
                      onTap: () => setState(() => _wholesale = !_wholesale),
                    ),
                  ],
                ]),
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
        if (!started && _photos.isNotEmpty) _photoStrip(),
        if (_ready == null && !_submitted)
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
                      : started
                          ? 'Escribe tu respuesta…'
                          : '¿Qué estás buscando?',
                  // "F1 · Rellenos suaves" (elegido por el PO para este grupo).
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none),
                  // Cámara a la vista (pedido PO: "no está el botón de hacer
                  // la foto"): el ícono es la cámara y el sheet ofrece
                  // Tomar foto / Galería.
                  prefixIcon: IconButton(
                      tooltip: 'Tomar o subir foto',
                      icon: const Icon(Icons.photo_camera_outlined),
                      onPressed: _busy ? null : _showPickSheet),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.send), onPressed: () => _send(_input.text)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // La mascota "buscando" — el mismo vacío de la web.
              const JayaloMascot(size: 76),
              const SizedBox(height: 16),
              Text('Sube una foto y describe lo que buscas\npara mejor resultado.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              // El botón de HACER la foto, visible desde el arranque
              // (pedido PO): cámara primero, galería al lado. La foto
              // queda en la tira y viaja con el primer mensaje.
              Wrap(spacing: 8, runSpacing: 4, children: [
                ActionChip(
                    avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Tomar foto'),
                    onPressed: () => _pickPhoto(ImageSource.camera)),
                ActionChip(
                    avatar: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Galería'),
                    onPressed: () => _pickPhoto(ImageSource.gallery)),
              ]),
            ],
          ),
        ),
      );

  /// El corazón del rediseño: mascota entrevistadora + pregunta en grande +
  /// botones de ancho completo + tarjeta "Tu solicitud" que se va llenando.
  Widget _guidedView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: _scroll,
      padding:
          EdgeInsets.fromLTRB(20, 20, 20, 16 + navBarReservedSpace(context)),
      children: [
        Center(
          child: const JayaloMascot(size: 64)
              .animate(key: ValueKey('mascota-$_pop'))
              .scale(
                  begin: const Offset(.85, .85),
                  end: const Offset(1, 1),
                  duration: 200.ms,
                  curve: Curves.easeOutBack),
        ),
        const SizedBox(height: 14),
        if (_ready != null)
          _readyCard(_ready!)
        else ...[
          if (_busy)
            Column(children: [
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const JayaloSpinner(size: 14),
                const SizedBox(width: 8),
                Text('Pensando…',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ]),
            ])
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
          counter = 'Pregunta ${_answers.length + 1}';
          actions = [for (final op in q.options) _optionButton(op, () => _send(op))];
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
              _optionButton('Tomar foto',
                  icon: Icons.photo_camera_outlined,
                  () => _pickForRequest(ImageSource.camera)),
              _optionButton('Elegir de la galería',
                  icon: Icons.photo_library_outlined,
                  () => _pickForRequest(ImageSource.gallery)),
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
        Text(question,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: jayaloHead(context))),
        if (counter != null) ...[
          const SizedBox(height: 6),
          Text(counter,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...actions,
        ],
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
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14.5, color: jayaloHead(context))),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// "Tu solicitud" — la esencia a la vista: fotos, descripción y cada
  /// respuesta con su check, más la barra honesta "N de ~M".
  Widget _buildingCard(ColorScheme cs) {
    final answered = _answers.length;
    final total = estimatedTotal(answered: answered, wholesale: _wholesale);
    final frac = progressFraction(
        answered: answered, wholesale: _wholesale, ready: false);
    // Lila del detalle sin foto (JayaloStatus.responded) — tinta violeta.
    const bg = Color(0xFFEDEBFF);
    const ink = Color(0xFF3C3489);
    const check = Color(0xFF1D9E75);
    final description = _messages.isEmpty ? '' : _messages.first.content;
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.assignment_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text('Tu solicitud',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: cs.primary)),
          const Spacer(),
          Text('$answered de ~$total',
              style: const TextStyle(fontSize: 12, color: ink)),
        ]),
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
                color: cs.primary),
          ),
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(clipBehavior: Clip.none, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(_photos[i].file.path),
                      width: 52, height: 52, fit: BoxFit.cover),
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
              ]),
          ]),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description,
              style: const TextStyle(fontSize: 13, height: 1.35, color: ink)),
        ],
        for (final a in _answers)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle, size: 15, color: check),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(a,
                      style: const TextStyle(
                          fontSize: 13, height: 1.35, color: ink))),
            ]),
          ),
      ]),
    );
  }

  /// Turno `ready`: la tarjeta final protagonista.
  Widget _readyCard(AiReady r) => JayaloCard(
        padding: const EdgeInsets.all(16),
        margin: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¡Listo! Revisa tu solicitud:',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(r.title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context))),
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
                        : JayaloStatus.respondedLight)),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const JayaloSpinner(size: 16, color: Colors.white)
                    : const Text('Enviar solicitud')),
            const SizedBox(width: 8),
            TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _ready = null;
                          _correcting = true;
                        }),
                child: const Text('Corregir algo')),
          ]),
        ]),
      );

  Widget _successView() => RequestPublishedView(
        onSeeRequests: () => context.go('/client'),
      );

  Widget _photoStrip() => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(spacing: 8, children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(_photos[i].file.path),
                      width: 64, height: 64, fit: BoxFit.cover),
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
              ]),
          ]),
        ),
      );
}
