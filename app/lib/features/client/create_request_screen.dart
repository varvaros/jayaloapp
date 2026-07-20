import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/ai_client.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/ai_turns.dart';
import '../../domain/image_pick.dart';
import '../shell/floating_nav_bar.dart';
import '../verification/verify_banner.dart';
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

class _Bubble {
  _Bubble.user(this.text)
      : isUser = true,
        turn = null;
  _Bubble.ai(this.turn, this.text) : isUser = false;
  final bool isUser;
  final String text;
  final AiTurn? turn;
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

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _ai = AiClient();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  final List<_Bubble> _bubbles = [];
  String _kind = 'producto';
  bool _wholesale = false;
  bool _busy = false;
  List<String> _categories = [];
  List<String> _rubros = [];
  final List<_PendingPhoto> _photos = [];
  AiReady? _ready;

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _bubbles.add(_Bubble.user(text));
      _messages.add(AiMessage('user', text));
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
        _bubbles.removeLast();
      });
    } catch (e) {
      _toast('Algo falló. Intenta de nuevo.');
      setState(() {
        _messages.removeLast();
        _bubbles.removeLast();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
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
        setState(() => _bubbles.add(_Bubble.ai(q, q.question)));
      case AiKindSwitch k:
        setState(() => _bubbles.add(_Bubble.ai(k, k.message)));
      case AiImageRequest ir:
        // La IA pide una foto: mostramos el mensaje y ofrecemos adjuntarla
        // (los botones viven en _turnActions). El modelo la verá vía imageDataUrl.
        setState(() => _bubbles.add(_Bubble.ai(
            ir, ir.hint.isEmpty ? ir.message : '${ir.message}\n${ir.hint}')));
      case AiRouting r:
        setState(() {
          _categories = r.categories;
          _rubros = r.rubros;
          _bubbles.add(_Bubble.ai(r, '${r.message} ${r.categories.join(", ")}'));
        });
        await _send('ok');
      case AiReady rd:
        setState(() {
          _ready = rd;
          _bubbles.add(_Bubble.ai(rd, '¡Listo! Revisa tu solicitud:'));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('¡Solicitud enviada! 🎉')));
      context.go('/client');
    } catch (_) {
      _toast('No se pudo enviar la solicitud.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) showJayaloToast(context, m);
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
        // Nudge de verificación (spec §6.1) — cerrable, nunca bloquea el envío.
        const VerifyWhatsappBanner(),
        Expanded(
          child: _bubbles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // La mascota "buscando" — el mismo vacío de la web.
                        const JayaloMascot(size: 76),
                        const SizedBox(height: 16),
                        Text(
                            'Sube una foto y describe lo que buscas\npara mejor resultado.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 16),
                        // El botón de HACER la foto, visible desde el arranque
                        // (pedido PO): cámara primero, galería al lado. La foto
                        // queda en la tira y viaja con el primer mensaje.
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          ActionChip(
                              avatar: const Icon(Icons.photo_camera_outlined,
                                  size: 18),
                              label: const Text('Tomar foto'),
                              onPressed: () =>
                                  _pickPhoto(ImageSource.camera)),
                          ActionChip(
                              avatar: const Icon(Icons.photo_library_outlined,
                                  size: 18),
                              label: const Text('Galería'),
                              onPressed: () =>
                                  _pickPhoto(ImageSource.gallery)),
                        ]),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 16 + navBarReservedSpace(context)),
                  itemCount: _bubbles.length,
                  itemBuilder: (_, i) {
                    final b = _bubbles[i];
                    final isLast = i == _bubbles.length - 1;
                    return Column(
                      crossAxisAlignment:
                          b.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color:
                                b.isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(b.text),
                        ),
                        if (!b.isUser && isLast && !_busy) _turnActions(b.turn),
                      ],
                    );
                  },
                ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(children: [
              const JayaloSpinner(size: 16),
              const SizedBox(width: 8),
              Text('Pensando…',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        if (_photos.isNotEmpty) _photoStrip(),
        if (_ready == null)
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
                  hintText: started ? 'Escribe tu respuesta…' : '¿Qué estás buscando?',
                  // "F1 · Rellenos suaves" (elegido por el PO para este grupo).
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
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

  Widget _turnActions(AiTurn? t) => switch (t) {
        AiQuestion q => Wrap(spacing: 8, runSpacing: 4, children: [
            for (final op in q.options)
              ActionChip(label: Text(op), onPressed: () => _send(op)),
          ]),
        AiImageRequest _ => Wrap(spacing: 8, runSpacing: 4, children: [
            if (_photos.length < _maxRequestPhotos) ...[
              ActionChip(
                  avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Cámara'),
                  onPressed: () => _pickForRequest(ImageSource.camera)),
              ActionChip(
                  avatar: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galería'),
                  onPressed: () => _pickForRequest(ImageSource.gallery)),
            ],
            ActionChip(
                label: const Text('Seguir sin foto'),
                onPressed: () => _send('Sigamos sin foto.')),
          ]),
        AiKindSwitch k => Wrap(spacing: 8, runSpacing: 4, children: [
            for (final op in k.options)
              ActionChip(
                  label: Text(op),
                  onPressed: () {
                    final low = op.toLowerCase();
                    if (low.startsWith('sí') || low.startsWith('si')) {
                      setState(() => _kind = k.suggestedKind);
                    }
                    _send(op);
                  }),
          ]),
        AiReady r => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: JayaloCard(
              padding: const EdgeInsets.all(16),
              margin: EdgeInsets.zero,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                              tone: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? JayaloStatus.respondedDark
                                  : JayaloStatus.respondedLight)),
                    const SizedBox(height: 12),
                    Row(children: [
                      FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: const Text('Enviar solicitud')),
                      const SizedBox(width: 8),
                      TextButton(
                          onPressed: () => setState(() => _ready = null),
                          child: const Text('Corregir algo')),
                    ]),
                  ]),
            ),
          ),
        _ => const SizedBox.shrink(),
      };
}
