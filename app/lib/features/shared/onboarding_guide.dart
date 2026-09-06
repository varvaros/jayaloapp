import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/motion.dart';
import 'onboarding_store.dart';

enum OnboardingMode { anchored, welcome }

class OnboardingStep {
  const OnboardingStep(this.message, {this.anchorKey, this.tapThrough = false});

  final String message;

  /// Ancla PROPIA del paso: la guía mide el widget que lleve este [GlobalKey]
  /// en cualquier parte del árbol (la pantalla, el shell, el encabezado). Sin
  /// ella, el paso mide el [OnboardingGuide.child] envuelto, como siempre.
  /// Un recorrido de N pasos con N anclas va saltando de elemento en elemento.
  final GlobalKey? anchorKey;

  /// El toque DENTRO del elemento real pasa al widget de debajo (se aprende
  /// haciéndolo) y, a la vez, la guía se da por vista y se cierra. Solo tiene
  /// sentido cuando tocar el elemento es la acción que el paso enseña (el `+`).
  final bool tapThrough;
}

/// Casa los mensajes de un recorrido (que viven en `onboarding_copy.dart`, para
/// que el PO los edite sin tocar pantallas) con sus anclas (que solo existen en
/// tiempo de ejecución, en el `State` de la pantalla o en `TourAnchors`).
/// [tapThroughAt] marca el índice del paso cuyo elemento se puede tocar.
List<OnboardingStep> anchorSteps(
  List<OnboardingStep> copy,
  List<GlobalKey?> anchors, {
  int? tapThroughAt,
}) {
  assert(copy.length == anchors.length,
      'recorrido de ${copy.length} pasos con ${anchors.length} anclas');
  return [
    for (var i = 0; i < copy.length; i++)
      OnboardingStep(
        copy[i].message,
        anchorKey: anchors[i],
        tapThrough: i == tapThroughAt,
      ),
  ];
}

/// Guía contextual tipo spotlight. Envuelve el elemento objetivo ([child]).
/// La primera vez (según [onboardingStore]) monta un overlay: un velo oscuro con
/// un HUECO recortado sobre el elemento (modo [OnboardingMode.anchored]) para que
/// el elemento REAL —que sigue en su sitio, no se re-renderiza— se vea brillante
/// a través del hueco; o un velo lleno con tarjeta centrada (modo
/// [OnboardingMode.welcome]). Muestra el mensaje del paso actual en una burbuja
/// con cola y un chevron que señalan el hueco, y botones Saltar / Siguiente /
/// Entendido. Con varios pasos es un RECORRIDO: cada paso puede llevar su
/// propia ancla ([OnboardingStep.anchorKey]), el hueco se desliza de una a
/// otra y la cabecera dice «PASO n DE N». Saltar o terminar → `markDone`
/// permanente del recorrido entero. Tocar el velo la cierra SOLO por esta vez
/// (PO 2026-09-05: un toque instintivo no puede quemar la guía); con
/// [OnboardingStep.tapThrough], tocar DENTRO del elemento real llega a él y
/// ese toque sí la da por vista.
///
/// El elemento NO se clona en el overlay (eso rompería con hijos que llevan
/// `GlobalKey`, como botones/forms): se mide su rect global y el velo se pinta
/// con un recorte (`BlendMode.clear`) en esa zona. Reúsa el fallback de anclaje
/// de [HoldCoachMark]: si el ancla no se puede medir tras un reintento, renderiza
/// el hijo en línea sin overlay (nunca deja la UI tapada ni el elemento
/// inaccesible). Un paso cuya ancla no existe o no se ve se muestra centrado,
/// sin hueco: mejor el texto sin foco que perder el paso.
class OnboardingGuide extends StatefulWidget {
  const OnboardingGuide({
    super.key,
    required this.guideKey,
    required this.steps,
    required this.child,
    this.enabled = true,
    this.mode = OnboardingMode.anchored,
    this.order = 0,
  });

  final String guideKey;
  final List<OnboardingStep> steps;
  final Widget child;
  final bool enabled;
  final OnboardingMode mode;

  /// Prioridad en el tour encadenado: menor = se muestra antes (coordinador
  /// global). Guías condicionales que aparecen tarde usan un `order` alto.
  final int order;

  @override
  State<OnboardingGuide> createState() => _OnboardingGuideState();
}

/// Menos espacio que esto a un lado del hueco no da ni para el texto ni para
/// los botones (ni para la cola y el chevron): la guía se centra en vez de
/// espachurrarse contra el borde.
const double _kMinCardSpace = 190;

/// Del borde del hueco al borde exterior de la burbuja (que además lleva 24 px
/// de margen): ahí viven la cola y el chevron que señala el ancla.
const double _kArrowSpace = 44;
const double _kBubbleRadius = 20;

/// Velo violáceo al 78 % (sin negro puro, doctrina de la app). El de antes era
/// negro al 55 % y dejaba el resto de la pantalla casi igual de visible.
const Color _kScrimColor = Color(0xC71A1230);

/// Ciclo del chevron: sube y baja 8 px hacia el hueco.
const Duration _kNudgeCycle = Duration(milliseconds: 1100);

/// Un ancla más chica que esto no es un elemento: es un `SizedBox.shrink`
/// esperando datos (la monedita del saldo antes de saber el número). Se trata
/// como «sin ancla» → paso centrado, no un hueco de 12 px sobre nada.
const double _kMinAnchorSide = 8;

/// Forma del hueco: el rect del ancla con 6 px de aire y el radio a la mitad
/// del lado corto — círculo para un botón cuadrado (el `+`), estadio para una
/// pestaña o un botón ancho. Antes era siempre un rectángulo de radio 12, que
/// alrededor de un botón redondo se leía como «un cuadrado con algo dentro».
@visibleForTesting
RRect onboardingHoleShape(Rect anchor) {
  final r = anchor.inflate(6);
  return RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
}

class _OnboardingGuideState extends State<OnboardingGuide>
    with TickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();

  /// Bajo `flutter test` los bucles no arrancan: un `repeat()` vivo cuelga
  /// `pumpAndSettle` en cualquier test que monte una pantalla con guía
  /// (mismo guard que `ai_wait_thread.dart`).
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  // Animación de entrada/salida del overlay (velo + tarjeta): la guía "abre" al
  // ganar el turno y "cierra" al terminar, para que dos guías seguidas no
  // parezcan la misma ventana (feedback PO 2026-07-27). Fade global + leve
  // deslizamiento de la tarjeta hacia el hueco. Respeta "reducir animaciones".
  // Inicializados en initState (NO `late` lazy): si se crearan al primer acceso
  // y ese acceso fuera `dispose()` (una guía que nunca se mostró), crear el
  // controller haría un lookup de InheritedWidget durante el teardown → crash.
  late final AnimationController _anim;
  late final Animation<double> _fade;

  /// Bucles decorativos mientras la guía está abierta: aros que laten desde el
  /// hueco y el chevron que señala. Se PARAN (no solo se ignoran) con reducir
  /// animaciones y en tests; ver [_syncLoops].
  late final AnimationController _pulse;
  late final AnimationController _nudge;

  /// Cambio de paso: el hueco se desliza del ancla anterior ([_holeFrom]) a la
  /// nueva. Un solo tick de `setState` por frame mientras dura.
  late final AnimationController _stepAnim;
  Rect? _holeFrom;

  Rect? _anchorRect; // rect GLOBAL del elemento a resaltar (para el hueco)

  /// Scroll que contiene al ancla, mientras la guía espera a que el ancla
  /// entre en pantalla. Ver [_watchScroll].
  ScrollPosition? _watched;
  bool _scrollCheckQueued = false;

  bool _done = false;
  bool _closing = false; // cerrando con animación (evita doble _complete)
  bool _snoozed = false; // cerrada por esta vez con un toque en el velo
  bool _measureFailed = false;
  bool _acquired = false;
  int _step = 0;

  /// Última generación de "Reiniciar tutorial" vista por esta guía.
  int _seenReset = onboardingStore.resetGeneration;

  bool get _shouldShow =>
      widget.enabled &&
      !_done &&
      !_snoozed &&
      !onboardingStore.isDone(widget.guideKey);

  OnboardingStep get _current => widget.steps[_step];

  /// Ancla del paso actual: la propia del paso o, si no tiene, el hijo envuelto.
  GlobalKey get _currentAnchorKey => _current.anchorKey ?? _anchorKey;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: JayaloMotion.base);
    _fade = CurvedAnimation(
        parent: _anim, curve: JayaloMotion.enter, reverseCurve: JayaloMotion.exit);
    _pulse =
        AnimationController(vsync: this, duration: JayaloMotion.pulseCycle);
    _nudge = AnimationController(vsync: this, duration: _kNudgeCycle);
    _stepAnim = AnimationController(vsync: this, duration: JayaloMotion.base)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    onboardingStore.addListener(_onStore);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndMaybeShow());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoops(); // "reducir animaciones" puede cambiar con la guía abierta
  }

  @override
  void didUpdateWidget(OnboardingGuide old) {
    super.didUpdateWidget(old);
    // Disparo por evento con datos: enabled pasa de false a true (p. ej. llegó
    // la primera oferta, o se vuelve a la pantalla del `+`) → intentar mostrar
    // ahora. Un cierre "por esta vez" caduca aquí: volver a la pantalla es
    // otra vez.
    if (widget.enabled && !old.enabled) {
      _snoozed = false;
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
    _watched?.removeListener(_onScroll);
    _releaseIfHeld();
    _anim.dispose();
    _pulse.dispose();
    _nudge.dispose();
    _stepAnim.dispose();
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
    // "Reiniciar tutorial" (Ajustes): la guía vuelve a estar pendiente aunque
    // ya se hubiera completado EN ESTA sesión, sin desmontar la pantalla. Se
    // mira el CONTADOR de reinicios y no `isDone`, porque entre cerrar una
    // guía y persistirla hay un frame en que el store todavía no la tiene —
    // ahí `isDone` diría "pendiente" y la guía resucitaría sola.
    if (onboardingStore.resetGeneration != _seenReset) {
      _seenReset = onboardingStore.resetGeneration;
      _done = false;
      _closing = false;
      _snoozed = false;
      _step = 0;
    }
    // Cerrando con animación: la marca «vista» ya está en el store (ver
    // [_complete]) y esta notificación es la nuestra. Ni ocultar, ni liberar,
    // ni reconstruir: el turno se suelta cuando la animación termina, y así
    // la siguiente guía abre cuando esta ya cerró.
    if (_closing) return;
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

  /// Rect GLOBAL (coords de pantalla) del widget que lleva [key], o null si no
  /// está montado, no tiene tamaño o es un hueco esperando datos (ver
  /// [_kMinAnchorSide]).
  Rect? _measureKey(GlobalKey key) {
    final ctx = key.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    if (box.size.shortestSide < _kMinAnchorSide) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Rect GLOBAL del ancla del paso actual.
  Rect? _measureAnchor() => _measureKey(_currentAnchorKey);

  /// Franja de pantalla que el usuario VE de verdad: sin la zona del sistema
  /// de arriba y sin lo que tape el teclado. Fuera de aquí no hay guía que
  /// valga — ni el hueco se ve ni la tarjeta se lee.
  ///
  /// Se lee de [View] y NO de [MediaQuery]: el `Scaffold` que redimensiona con
  /// el teclado le QUITA los `viewInsets` al MediaQuery de su cuerpo, así que
  /// desde dentro de una pantalla el teclado parece no existir — y un ancla
  /// tapada por el teclado se daría por visible.
  Rect _viewport(BuildContext context) {
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    final size = view.physicalSize / dpr;
    return Rect.fromLTRB(
      0,
      view.padding.top / dpr,
      size.width,
      size.height - view.viewInsets.bottom / dpr,
    );
  }

  /// ¿El ancla está lo bastante dentro de la pantalla como para resaltarla?
  /// Exige que se vea al menos el 60% de su alto: media docena de píxeles
  /// asomando por el borde no es "visible", y anclar ahí deja la tarjeta
  /// pegada al canto.
  bool _anchorVisible(Rect r, Rect vp) {
    final visibleHeight =
        math.min(r.bottom, vp.bottom) - math.max(r.top, vp.top);
    return visibleHeight >= r.height * .6 && r.left < vp.right && r.right > vp.left;
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
      // El ancla existe pero está FUERA de la pantalla (el caso del botón de
      // enviar la oferta, al final de un formulario largo: el `RenderBox` está
      // dispuesto y se mide, solo que 1.200 px más abajo del borde). Mostrar
      // ahí pintaba el velo con el hueco y la tarjeta fuera de cuadro — el
      // usuario veía la pantalla oscura y sin texto, y al tocar para salir la
      // guía se marcaba como vista PARA SIEMPRE (bug PO 2026-08-22). Ahora se
      // ESPERA: ni se pide turno ni se quema; cuando el ancla entra en
      // pantalla al hacer scroll, la guía aparece sobre ella.
      if (!_anchorVisible(rect, _viewport(context)) && _watchScroll()) {
        return; // hay scroll: se espera a que el ancla suba a la pantalla
      }
      _tryShow();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = _measureAnchor();
        if (retry != null) {
          setState(() => _anchorRect = retry);
          if (!_anchorVisible(retry, _viewport(context)) && _watchScroll()) {
            return;
          }
          _tryShow();
        } else if (_current.anchorKey != null) {
          // Un recorrido cuyo primer elemento aún no está (lista vacía,
          // saldo sin cargar) se muestra igual, con ese paso centrado: el
          // hijo envuelto es un `SizedBox.shrink`, no hay nada que dejar
          // «en línea».
          setState(() => _anchorRect = null); // agenda el frame del turno
          _tryShow();
        } else {
          setState(() => _measureFailed = true); // fallback: hijo en línea
        }
      });
      // Un post-frame no agenda frame por sí solo: sin esto, el reintento
      // esperaría al siguiente frame que otro provocara (en una pantalla
      // quieta, nunca).
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  /// Se engancha al scroll VERTICAL que contiene al ancla para volver a
  /// intentarlo cuando el elemento entre en pantalla. Sin esto, una guía cuyo
  /// botón nace bajo el pliegue no se mostraría nunca: un scroll no
  /// reconstruye a la guía, así que ningún `post-frame` la despertaría.
  /// Devuelve `false` si el ancla NO vive dentro de ningún scroll vertical:
  /// ahí no hay nada que esperar, así que la guía se muestra igual — con la
  /// tarjeta centrada y sin hueco (ver [_buildOverlay]). Perder una guía por
  /// callada sería peor que enseñarla sin foco. Los scrolls HORIZONTALES (los
  /// segmentados del encabezado) no cuentan: un ancla que asoma por arriba no
  /// va a entrar por mucho que se deslice de lado.
  bool _watchScroll() {
    final ctx = _currentAnchorKey.currentContext;
    var pos = ctx == null ? null : Scrollable.maybeOf(ctx)?.position;
    if (pos != null && pos.axis != Axis.vertical) pos = null;
    if (identical(pos, _watched)) return _watched != null;
    _watched?.removeListener(_onScroll);
    _watched = pos;
    _watched?.addListener(_onScroll);
    return pos != null;
  }

  /// Reintento al asentarse el frame (el scroll notifica muchas veces por
  /// gesto; una sola comprobación por frame basta).
  void _onScroll() {
    if (!mounted || _scrollCheckQueued || !_shouldShow) return;
    if (_portal.isShowing || onboardingStore.isActive(widget.guideKey)) return;
    _scrollCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCheckQueued = false;
      if (mounted) _measureAndMaybeShow();
    });
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
      // Re-medir AHORA: entre la medición y el turno pueden pasar frames (la
      // guía espera en cola detrás de otra, o el ancla venía animando su
      // entrada), y abrir con un rect viejo deja el foco desalineado.
      if (widget.mode == OnboardingMode.anchored) {
        _anchorRect = _measureAnchor();
      }
      _portal.show();
      _anim.duration =
          JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base;
      _anim.forward(from: 0);
      _syncLoops();
    }
  }

  /// Arranca o PARA los bucles decorativos según la guía esté abierta y el
  /// movimiento esté permitido. Parar el ticker (no solo ignorar su valor):
  /// un `repeat()` que nadie mira le pide un frame por vsync a toda la app.
  void _syncLoops() {
    if (!mounted) return;
    final on = _portal.isShowing && !_enTest && !JayaloMotion.reduced(context);
    if (on) {
      if (!_pulse.isAnimating) _pulse.repeat();
      if (!_nudge.isAnimating) _nudge.repeat();
    } else {
      _pulse.stop();
      _nudge.stop();
    }
  }

  /// Cierra el overlay con la animación de salida y luego desmonta el portal.
  Future<void> _hideAnimated() async {
    if (!_portal.isShowing) return;
    _anim.duration =
        JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base;
    await _anim.reverse();
    if (mounted && _portal.isShowing) _portal.hide();
    _syncLoops();
  }

  Future<void> _complete() async {
    // Cierra con animación ANTES de liberar el turno: así la siguiente guía
    // abre cuando esta ya cerró (nunca se solapan → se ve "abrir y cerrar").
    if (_closing || _done) return;
    _closing = true;
    // Marcar vista YA, antes de la animación: la marca es síncrona en el store
    // y así no se pierde si el widget se desmonta a mitad del cierre (tocar
    // «Entendido» y navegar en el acto dejaba la guía sin marcar y volvía a
    // salir). La notificación que dispara no desmonta el portal: `_onStore` y
    // `build` respetan `_closing`.
    final gen = onboardingStore.resetGeneration;
    final marked = onboardingStore.markDone(widget.guideKey);
    await _hideAnimated();
    // Si «Reiniciar tutorial» llegó durante el cierre, `_onStore` ya dejó la
    // guía pendiente: no pisarlo con `_done`.
    if (mounted && onboardingStore.resetGeneration == gen) {
      setState(() {
        _done = true;
        _closing = false;
      });
    }
    _releaseIfHeld();
    await marked;
  }

  /// Toque en el velo: cierra SOLO por esta vez. No marca vista (un toque
  /// instintivo no puede quemar la guía) y suelta el turno para que el tour
  /// siga con la siguiente. Vuelve a salir al remontar la pantalla o cuando
  /// `enabled` pasa otra vez a true.
  Future<void> _snooze() async {
    if (_closing || _done) return;
    // Mientras el hueco viaja al paso siguiente, un toque impaciente (el
    // segundo toque sobre «Siguiente», que ya se movió) caería en el velo:
    // no cuenta como «cerrar por esta vez».
    if (_stepAnim.isAnimating) return;
    _closing = true;
    final gen = onboardingStore.resetGeneration;
    await _hideAnimated();
    if (!mounted) return;
    if (onboardingStore.resetGeneration == gen) {
      setState(() {
        _snoozed = true;
        _closing = false;
      });
    }
    _releaseIfHeld();
  }

  void _next() {
    if (_closing || _done) return;
    if (_step < widget.steps.length - 1) {
      // Al cambiar de paso se mide el ancla NUEVA y el hueco viaja desde la
      // vieja. Sin ancla visible en alguno de los dos lados no hay viaje: el
      // hueco aparece o desaparece con el paso.
      final from = _anchorRect;
      setState(() {
        _step++;
        _anchorRect = _measureAnchor();
      });
      _holeFrom = from;
      _stepAnim.duration =
          JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base;
      _stepAnim.forward(from: 0);
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    // `_closing`: la guía ya no "debería" verse (está marcada vista) pero su
    // animación de cierre sigue en curso — el portal se queda hasta que acabe.
    if ((!_shouldShow && !_closing) || _measureFailed) return widget.child;

    // El hijo se envuelve para poder medirlo (los pasos sin ancla propia lo
    // señalan). Con anclas por paso el `KeyedSubtree` sobra pero no estorba.
    final content = widget.mode == OnboardingMode.anchored
        ? KeyedSubtree(key: _anchorKey, child: widget.child)
        : widget.child;

    // `rootOverlay`: el velo y la tarjeta se pintan por ENCIMA de todo,
    // incluida la barra flotante del shell. Sin esto, una guía declarada dentro
    // de una pantalla entra en el Overlay del Navigator ANIDADO —que el
    // `Scaffold` del shell pinta DEBAJO de su `bottomNavigationBar`— y con el
    // ancla baja la barra le tapaba los botones «Saltar/Entendido» (visto en
    // device, PO 2026-08-22). Las guías del propio shell nunca lo sufrieron
    // porque ya nacían en el Overlay raíz.
    return OverlayPortal(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: _buildOverlay,
      child: content,
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isLast = _step == widget.steps.length - 1;
    // El color de tarjeta del proyecto en ambos temas (blanco en claro,
    // tarjeta elevada en oscuro). La cola lo comparte para no dejar costura.
    final bubbleColor = cs.surfaceContainerLowest;
    final tour = widget.steps.length > 1;

    final card = Container(
      key: const Key('onboardingCard'),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(_kBubbleRadius),
        boxShadow: const [
          BoxShadow(
              color: Color(0x59140C28), blurRadius: 40, offset: Offset(0, 18)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tour) ...[
            Row(children: [
              Text(
                'PASO ${_step + 1} DE ${widget.steps.length}',
                style: tt.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant, letterSpacing: .8),
              ),
              const SizedBox(width: 8),
              for (var i = 0; i < widget.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    width: i == _step ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _step ? cs.primary : cs.primaryContainer,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
          ],
          // El texto se funde al cambiar de paso (el hueco viaja a la vez).
          AnimatedSwitcher(
            duration: JayaloMotion.reduced(context)
                ? Duration.zero
                : JayaloMotion.base,
            switchInCurve: JayaloMotion.enter,
            switchOutCurve: JayaloMotion.exit,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, ?current],
            ),
            child: Text(
              _current.message,
              key: ValueKey(_step),
              style: tt.bodyLarge,
            ),
          ),
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
    );

    final vp = _viewport(context);
    final view = View.of(context);
    final screenH = view.physicalSize.height / view.devicePixelRatio;
    // Solo se recorta el hueco si el ancla se ve de verdad. Si no (rect viejo,
    // teclado que la tapó, pantalla que cambió entre medir y abrir, o el paso
    // señala algo que aún no está), la guía degrada a tarjeta centrada: mejor
    // el texto sin foco que una pantalla oscura y muda.
    final measured = widget.mode == OnboardingMode.anchored ? _anchorRect : null;
    final target =
        measured != null && _anchorVisible(measured, vp) ? measured : null;
    // Viaje del hueco entre pasos: solo si hay hueco a ambos lados.
    final from = _holeFrom;
    final hole = _stepAnim.isAnimating && from != null && target != null
        ? Rect.lerp(from, target, JayaloMotion.enter.transform(_stepAnim.value))
        : target;
    final shape = hole == null ? null : onboardingHoleShape(hole);
    // Zona que deja pasar el toque con `tapThrough`: el elemento REAL con su
    // misma redondez (círculo en el `+`), sin los 6 px de aire del hueco. Un
    // toque en el aire o en las esquinas del cuadrado que rodea al círculo no
    // llega al botón, así que no puede contar como «Entendido»: es un toque en
    // el velo (reserva del verificador 2026-09-05). Mientras el hueco viaja no
    // se deja pasar nada: el elemento aún no está debajo.
    final pass = target == null || !_current.tapThrough || hole != target
        ? null
        : RRect.fromRectAndRadius(
            target, Radius.circular(target.shortestSide / 2));

    // La tarjeta va al lado del hueco donde QUEPA — con el ancla abajo va
    // encima (si no, la taparía: el `+` de la barra, el ✨ del composer) y con
    // el ancla arriba va debajo (el ⋮ del header). Se elige por espacio real y
    // no por "mitad de pantalla": el botón de enviar la oferta puede quedar a
    // 20 px del borde inferior con el teclado abierto, y ahí la regla vieja
    // empujaba la tarjeta fuera de cuadro.
    final spaceBelow =
        hole == null ? 0.0 : vp.bottom - (hole.bottom + _kArrowSpace);
    final spaceAbove =
        hole == null ? 0.0 : (hole.top - _kArrowSpace) - vp.top;
    final below = spaceBelow >= spaceAbove;
    final space = math.max(spaceBelow, spaceAbove);
    final anchored = hole != null && space >= _kMinCardSpace;

    // Cola de la burbuja: en el borde que mira al hueco, alineada con el
    // centro del ancla (acotada para no caer en las esquinas redondeadas).
    // Va DENTRO del mismo deslizamiento que la tarjeta pero FUERA del widget
    // con `Key('onboardingCard')`: los tests miden ese rect contra la pantalla.
    Widget bubble = card;
    if (anchored) {
      final tailX = hole.center.dx.clamp(
        24 + _kBubbleRadius + 8,
        vp.right - 24 - _kBubbleRadius - 8,
      );
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            left: tailX - 8,
            top: below ? 24 - 8 : null,
            bottom: below ? null : 24 - 8,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Tarjeta con leve deslizamiento hacia el hueco al entrar.
    final slidCard = SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, below ? -.06 : .06),
        end: Offset.zero,
      ).animate(_fade),
      child: bubble,
    );

    final Widget placedCard;
    if (!anchored) {
      // Sin hueco visible, o con el hueco comiéndose la pantalla entera: la
      // tarjeta al centro, acotada a la franja visible.
      placedCard = Positioned.fill(
        child: Padding(
          padding: EdgeInsets.only(top: vp.top, bottom: screenH - vp.bottom),
          child: Center(
            child: SingleChildScrollView(child: slidCard),
          ),
        ),
      );
    } else {
      placedCard = Positioned(
        left: 0,
        right: 0,
        top: below ? hole.bottom + _kArrowSpace : null,
        bottom: below ? null : (screenH - hole.top) + _kArrowSpace,
        // Acotada al hueco libre: un copy largo en una pantalla corta hacía
        // desbordar la tarjeta por el borde en vez de recortarse.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: space),
          child: SingleChildScrollView(child: slidCard),
        ),
      );
    }

    // Chevron blanco entre la burbuja y el hueco, apuntando al ancla y
    // moviéndose 8 px hacia ella. Es LA flecha que el PO pidió: sin ella, el
    // «este botón» del copy no señalaba nada.
    Widget? chevron;
    if (anchored) {
      const size = 36.0;
      // Franja entre el anillo del hueco y la cola: [+6, +_kArrowSpace+24-8].
      final lane = _kArrowSpace + 24 - 8 - 6;
      final offset = 6 + (lane - size) / 2;
      chevron = Positioned(
        left: hole.center.dx - size / 2,
        top: below ? hole.bottom + offset : hole.top - offset - size,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _nudge,
              builder: (_, child) => Transform.translate(
                offset: Offset(
                  0,
                  (below ? -1 : 1) * math.sin(_nudge.value * math.pi) * 8,
                ),
                child: child,
              ),
              child: Icon(
                below
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: size,
                color: Colors.white,
                shadows: const [
                  Shadow(
                      color: Color(0x73000000),
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
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
                hole: shape,
                color: _kScrimColor,
                haloColor: cs.primary.withValues(alpha: .35),
              ),
            ),
          ),
        ),
        // Aros que laten desde el hueco hacia fuera: el foco se ve aunque el
        // velo y el ancla compartan color (el `+` violeta con anillo violeta
        // era invisible).
        if (shape != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) => CustomPaint(
                    painter: _PulsePainter(hole: shape, t: _pulse.value),
                  ),
                ),
              ),
            ),
          ),
        // Captura de toques a pantalla completa: cerrar por esta vez. Va
        // debajo de la tarjeta para que sus botones reciban tap. Con
        // `tapThrough`, el elemento real queda FUERA de su hit-test para que
        // el toque llegue a él.
        Positioned.fill(
          child: _HoleHitTest(
            hole: pass,
            child: GestureDetector(
              key: const Key('onboardingScrim'),
              behavior: HitTestBehavior.opaque,
              onTap: _snooze,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // Con `tapThrough`: el toque dentro del elemento también cuenta como
        // «Entendido». `translucent` recibe el puntero sin consumir el hit, y
        // como un `Listener` no entra en la arena de gestos, el botón real
        // sigue recibiendo su tap. (Un arrastre que termine dentro también
        // cierra: no hay slop, y es aceptable.)
        if (pass != null)
          Positioned.fromRect(
            rect: pass.outerRect,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerUp: (e) {
                if (pass.contains(e.position)) _complete();
              },
              child: const SizedBox.expand(),
            ),
          ),
        ?chevron,
        placedCard,
      ],
    );

    // Fade global del velo + tarjeta: la guía "abre" al entrar y "cierra" al
    // salir, así dos guías seguidas no parecen la misma ventana.
    return FadeTransition(opacity: _fade, child: overlay);
  }
}

/// Deja el hueco FUERA del hit-test del velo: un toque ahí no lo ve el
/// `GestureDetector` de dentro y sigue bajando por el Overlay raíz hasta el
/// elemento real (`_RenderTheatre` prueba las entradas inferiores mientras las
/// superiores devuelvan false). Sin [hole] es un proxy transparente.
class _HoleHitTest extends SingleChildRenderObjectWidget {
  const _HoleHitTest({required this.hole, required super.child});

  /// En coordenadas GLOBALES (las mismas en que se midió el ancla).
  final RRect? hole;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHoleHitTest(hole);

  @override
  void updateRenderObject(
          BuildContext context, _RenderHoleHitTest renderObject) =>
      renderObject.hole = hole;
}

class _RenderHoleHitTest extends RenderProxyBox {
  _RenderHoleHitTest(this.hole);

  RRect? hole;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final h = hole;
    // Devolver false SIN consultar al hijo: si se delegara, el detector opaco
    // de dentro reclamaría el toque igual.
    if (h != null && h.contains(localToGlobal(position))) return false;
    return super.hitTest(result, position: position);
  }
}

/// Pinta el velo oscuro a pantalla completa y, si hay [hole], lo recorta (ya
/// viene con aire y con la forma del ancla, ver [onboardingHoleShape]) para que
/// el elemento real se vea, más un anillo blanco fino y un halo del color de
/// acción. El recorte usa `saveLayer` + `BlendMode.clear`.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter(
      {required this.hole, required this.color, required this.haloColor});

  final RRect? hole;
  final Color color;
  final Color haloColor;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final rr = hole;
    if (rr == null) {
      canvas.drawRect(full, Paint()..color = color);
      return;
    }
    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, Paint()..color = color);
    canvas.drawRRect(rr, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
    // Halo suave por fuera del anillo, y el anillo blanco encima. Blanco a
    // propósito: el anillo de antes era `primary`, el MISMO violeta que el
    // botón `+`, y no lo separaba de nada.
    canvas.drawRRect(
      rr.inflate(4.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = haloColor,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.color != color || old.haloColor != haloColor;
}

/// Dos aros que nacen en el borde del hueco y se abren hasta 1,8× mientras se
/// desvanecen, desfasados media vuelta. [t] va de 0 a 1 por ciclo. Parado
/// (t = 0) deja un aro quieto en el borde y otro a medio camino: el foco se
/// sigue viendo con "reducir animaciones".
class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.hole, required this.t});

  final RRect hole;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final phase in [t, (t + .5) % 1]) {
      final scale = 1 + .8 * phase;
      final ring = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: hole.center,
          width: hole.width * scale,
          height: hole.height * scale,
        ),
        Radius.circular(hole.tlRadiusX * scale),
      );
      canvas.drawRRect(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: .9 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.hole != hole || old.t != t;
}
