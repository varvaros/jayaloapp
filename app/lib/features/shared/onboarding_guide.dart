import 'package:flutter/material.dart';

import '../../core/motion.dart';
import 'onboarding_store.dart';

enum OnboardingMode { anchored, welcome }

class OnboardingStep {
  const OnboardingStep(this.message);
  final String message;
}

/// Guía contextual tipo spotlight. Envuelve el elemento objetivo ([child]).
/// La primera vez (según [onboardingStore]) monta un overlay: un velo oscuro con
/// un HUECO recortado sobre el elemento (modo [OnboardingMode.anchored]) para que
/// el elemento REAL —que sigue en su sitio, no se re-renderiza— se vea brillante
/// a través del hueco; o un velo lleno con tarjeta centrada (modo
/// [OnboardingMode.welcome]). Muestra el mensaje del paso actual y botones Saltar
/// / Siguiente / Entendido. Cerrar, saltar, tocar el velo o terminar → `markDone`
/// permanente.
///
/// El elemento NO se clona en el overlay (eso rompería con hijos que llevan
/// `GlobalKey`, como botones/forms): se mide su rect global y el velo se pinta
/// con un recorte (`BlendMode.clear`) en esa zona. Reúsa el fallback de anclaje
/// de [HoldCoachMark]: si el ancla no se puede medir tras un reintento, renderiza
/// el hijo en línea sin overlay (nunca deja la UI tapada ni el elemento
/// inaccesible).
class OnboardingGuide extends StatefulWidget {
  const OnboardingGuide({
    super.key,
    required this.guideKey,
    required this.steps,
    required this.child,
    this.enabled = true,
    this.mode = OnboardingMode.anchored,
    this.order = 0,
    this.anchorKey,
  });

  final String guideKey;
  final List<OnboardingStep> steps;
  final Widget child;
  final bool enabled;
  final OnboardingMode mode;

  /// Prioridad en el tour encadenado: menor = se muestra antes (coordinador
  /// global). Guías condicionales que aparecen tarde usan un `order` alto.
  final int order;

  /// Ancla EXTERNA: si se pasa, la guía NO envuelve al hijo para medirlo, sino
  /// que mide el widget que lleve este [GlobalKey] en otra parte del árbol
  /// (p. ej. el botón `+` de la barra). El [child] puede ser `SizedBox.shrink`.
  final GlobalKey? anchorKey;

  @override
  State<OnboardingGuide> createState() => _OnboardingGuideState();
}

class _OnboardingGuideState extends State<OnboardingGuide>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();

  // Animación de entrada/salida del overlay (velo + tarjeta): la guía "abre" al
  // ganar el turno y "cierra" al terminar, para que dos guías seguidas no
  // parezcan la misma ventana (feedback PO 2026-07-27). Fade global + leve
  // deslizamiento de la tarjeta hacia el hueco. Respeta "reducir animaciones".
  // Inicializados en initState (NO `late` lazy): si se crearan al primer acceso
  // y ese acceso fuera `dispose()` (una guía que nunca se mostró), crear el
  // controller haría un lookup de InheritedWidget durante el teardown → crash.
  late final AnimationController _anim;
  late final Animation<double> _fade;

  Rect? _anchorRect; // rect GLOBAL del elemento a resaltar (para el hueco)
  bool _done = false;
  bool _closing = false; // cerrando con animación (evita doble _complete)
  bool _measureFailed = false;
  bool _acquired = false;
  int _step = 0;

  bool get _shouldShow =>
      widget.enabled && !_done && !onboardingStore.isDone(widget.guideKey);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: JayaloMotion.base);
    _fade = CurvedAnimation(
        parent: _anim, curve: JayaloMotion.enter, reverseCurve: JayaloMotion.exit);
    onboardingStore.addListener(_onStore);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndMaybeShow());
    }
  }

  @override
  void didUpdateWidget(OnboardingGuide old) {
    super.didUpdateWidget(old);
    // Disparo por evento con datos: enabled pasa de false a true (p. ej. llegó
    // la primera oferta) → intentar mostrar ahora.
    if (widget.enabled && !old.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndMaybeShow());
    }
    // enabled pasa de true a false: liberar el coordinador si estaba
    // mostrándose, para no bloquear otras guías. No hace falta llamar
    // `_portal.hide()` aquí (no se puede durante la fase de build): el build()
    // que sigue ya no renderiza el OverlayPortal porque `_shouldShow` es falso,
    // así que el portal se desmonta solo. `release()` se difiere a después del
    // frame: notifica listeners sincrónicamente (incluido este propio widget vía
    // `_onStore`), y esa notificación no puede intentar tocar el portal mientras
    // seguimos dentro de la fase de build.
    if (!widget.enabled && old.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _releaseIfHeld();
      });
    }
  }

  @override
  void dispose() {
    onboardingStore.removeListener(_onStore);
    _releaseIfHeld();
    _anim.dispose();
    super.dispose();
  }

  void _releaseIfHeld() {
    if (_acquired) {
      onboardingStore.withdraw(widget.guideKey);
      _acquired = false;
    }
  }

  void _onStore() {
    if (!mounted) return;
    if (!_shouldShow) {
      if (_portal.isShowing) _hideAnimated();
      _releaseIfHeld();
    } else {
      // Si aún no tengo turno ni portal, (re)pido turno.
      if (!_portal.isShowing && !onboardingStore.isActive(widget.guideKey)) {
        _measureAndMaybeShow();
      }
      _syncPortal();
    }
    setState(() {});
  }

  /// Rect GLOBAL del ancla (coords de pantalla). Usa el ancla externa si se dio.
  Rect? _measureAnchor() {
    final ctx = (widget.anchorKey ?? _anchorKey).currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _measureAndMaybeShow() {
    if (!mounted || !_shouldShow) return;
    if (widget.mode == OnboardingMode.welcome) {
      _tryShow(); // sin ancla que medir
      return;
    }
    final rect = _measureAnchor();
    if (rect != null) {
      setState(() => _anchorRect = rect);
      _tryShow();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = _measureAnchor();
        if (retry != null) {
          setState(() => _anchorRect = retry);
          _tryShow();
        } else {
          setState(() => _measureFailed = true); // fallback: hijo en línea
        }
      });
    }
  }

  void _tryShow() {
    if (!mounted || !_shouldShow) return;
    onboardingStore.requestSlot(widget.guideKey, widget.order);
    _acquired = true;
    // Ventana de recolección: junta las candidatas de este frame y resuelve al
    // final. Idempotente si varias guías la agendan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onboardingStore.resolvePending();
    });
    _syncPortal();
  }

  /// Muestra el portal (con animación de apertura) cuando la guía gana el turno.
  /// El ocultar animado lo maneja [_hideAnimated] (desde [_complete] o al perder
  /// `_shouldShow`) para no cortar la animación de salida a la mitad.
  void _syncPortal() {
    if (!mounted) return;
    if (onboardingStore.isActive(widget.guideKey) && !_portal.isShowing) {
      _portal.show();
      _anim.duration =
          JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base;
      _anim.forward(from: 0);
    }
  }

  /// Cierra el overlay con la animación de salida y luego desmonta el portal.
  Future<void> _hideAnimated() async {
    if (!_portal.isShowing) return;
    _anim.duration =
        JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base;
    await _anim.reverse();
    if (mounted && _portal.isShowing) _portal.hide();
  }

  Future<void> _complete() async {
    // Cierra con animación ANTES de liberar el turno: así la siguiente guía
    // abre cuando esta ya cerró (nunca se solapan → se ve "abrir y cerrar").
    if (_closing || _done) return;
    _closing = true;
    await _hideAnimated();
    if (!mounted) return;
    setState(() => _done = true);
    _releaseIfHeld();
    await onboardingStore.markDone(widget.guideKey);
  }

  void _next() {
    if (_step < widget.steps.length - 1) {
      setState(() => _step++);
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow || _measureFailed) return widget.child;

    // Con ancla externa NO se envuelve el hijo (el GlobalKey vive en el target).
    final wrap =
        widget.mode == OnboardingMode.anchored && widget.anchorKey == null;
    final content =
        wrap ? KeyedSubtree(key: _anchorKey, child: widget.child) : widget.child;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: content,
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLast = _step == widget.steps.length - 1;
    final card = Card(
      key: const Key('onboardingCard'),
      color: cs.surface,
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.steps[_step].message,
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _complete, child: const Text('Saltar')),
                FilledButton(
                  onPressed: _next,
                  child: Text(isLast ? 'Entendido' : 'Siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final hole = widget.mode == OnboardingMode.anchored ? _anchorRect : null;
    final screenH = MediaQuery.of(context).size.height;
    // Con el ancla en la mitad INFERIOR, la tarjeta va ENCIMA del hueco (si no,
    // lo taparía — p. ej. el botón `+` o el ✨ del composer); con el ancla en la
    // mitad superior, va DEBAJO (p. ej. el ⋮ del header). Siempre PEGADA al
    // hueco para que el texto se lea junto al resaltado.
    final anchorLow = hole != null && hole.center.dy >= screenH / 2;

    // Tarjeta con leve deslizamiento hacia el hueco al entrar.
    final slidCard = SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, anchorLow ? .06 : -.06),
        end: Offset.zero,
      ).animate(_fade),
      child: card,
    );

    final Widget placedCard;
    if (hole == null) {
      placedCard = Align(alignment: Alignment.center, child: SafeArea(child: slidCard));
    } else {
      placedCard = Positioned(
        left: 0,
        right: 0,
        top: anchorLow ? null : hole.bottom + 8,
        bottom: anchorLow ? (screenH - hole.top) + 8 : null,
        child: slidCard,
      );
    }

    final overlay = Stack(
      children: [
        // Velo oscuro con hueco recortado sobre el elemento (spotlight). No
        // intercepta toques (IgnorePointer): el elemento real vive debajo, en su
        // sitio, y se ve brillante por el hueco.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ScrimPainter(
                hole: hole,
                color: const Color(0x8C000000),
                ringColor: cs.primary,
              ),
            ),
          ),
        ),
        // Captura de toques a pantalla completa (incluye el hueco): cerrar y
        // marcar visto. Va debajo de la tarjeta para que sus botones reciban tap.
        Positioned.fill(
          child: GestureDetector(
            key: const Key('onboardingScrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _complete,
            child: const SizedBox.expand(),
          ),
        ),
        placedCard,
      ],
    );

    // Fade global del velo + tarjeta: la guía "abre" al entrar y "cierra" al
    // salir, así dos guías seguidas no parecen la misma ventana.
    return FadeTransition(opacity: _fade, child: overlay);
  }
}

/// Pinta el velo oscuro a pantalla completa y, si hay [hole], recorta ese rect
/// (con un margen y esquinas redondeadas) para que el elemento real se vea, más
/// un anillo de resalte alrededor. El recorte usa `saveLayer` + `BlendMode.clear`.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.color, required this.ringColor});

  final Rect? hole;
  final Color color;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    if (hole == null) {
      canvas.drawRect(full, Paint()..color = color);
      return;
    }
    final rr = RRect.fromRectAndRadius(hole!.inflate(6), const Radius.circular(12));
    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, Paint()..color = color);
    canvas.drawRRect(rr, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ringColor,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.color != color || old.ringColor != ringColor;
}
