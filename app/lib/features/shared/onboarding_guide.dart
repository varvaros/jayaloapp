import 'package:flutter/material.dart';

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
  });

  final String guideKey;
  final List<OnboardingStep> steps;
  final Widget child;
  final bool enabled;
  final OnboardingMode mode;

  @override
  State<OnboardingGuide> createState() => _OnboardingGuideState();
}

class _OnboardingGuideState extends State<OnboardingGuide> {
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();

  Rect? _anchorRect; // rect GLOBAL del elemento a resaltar (para el hueco)
  bool _done = false;
  bool _measureFailed = false;
  bool _acquired = false;
  int _step = 0;

  bool get _shouldShow =>
      widget.enabled && !_done && !onboardingStore.isDone(widget.guideKey);

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _releaseIfHeld() {
    if (_acquired) {
      onboardingStore.release(widget.guideKey);
      _acquired = false;
    }
  }

  void _onStore() {
    if (!mounted) return;
    if (!_shouldShow && _portal.isShowing) {
      _portal.hide();
      _releaseIfHeld();
    }
    // Si otra guía se liberó, reintentar mostrar esta.
    if (_shouldShow && !_portal.isShowing) _measureAndMaybeShow();
    setState(() {});
  }

  /// Rect GLOBAL del ancla (coords de pantalla, que es el espacio del overlay).
  Rect? _measureAnchor() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
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
    if (!onboardingStore.acquire(widget.guideKey)) return; // otra guía activa
    _acquired = true;
    _portal.show();
  }

  Future<void> _complete() async {
    setState(() => _done = true);
    if (_portal.isShowing) _portal.hide();
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

    final content = widget.mode == OnboardingMode.anchored
        ? KeyedSubtree(key: _anchorKey, child: widget.child)
        : widget.child;

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

    return Stack(
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
        // Tarjeta: centrada (welcome) o abajo (anchored).
        Align(
          alignment: widget.mode == OnboardingMode.welcome
              ? Alignment.center
              : Alignment.bottomCenter,
          child: SafeArea(child: card),
        ),
      ],
    );
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
