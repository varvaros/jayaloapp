import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'onboarding_store.dart';

/// Una acción revelada por swipe (franja de color con ícono + texto).
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;

  /// Puede ser async (p. ej. abrir diálogos de confirmación antes de actuar).
  final Future<void> Function() onTap;
}

/// Arrastra la tarjeta a la DERECHA para revelar acciones en franjas de color
/// a la izquierda (pedido PO 2026-07-20: "arrastrando la solicitud a la
/// derecha va saliendo una franja roja Eliminar / azul Editar"). Sin
/// dependencias externas — respeta la tarjeta redondeada de la marca.
///
/// - Snap abierto/cerrado al soltar (según distancia o velocidad).
/// - Tocar la tarjeta abierta la cierra (no dispara su onTap).
/// - Un solo row abierto a la vez vía [group] (ValueNotifier compartido): al
///   abrir uno se cierran los demás.
class SwipeToActions extends StatefulWidget {
  const SwipeToActions({
    super.key,
    required this.id,
    required this.group,
    required this.actions,
    required this.child,
    this.radius = 18,
    this.actionWidth = 88,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.blockedReason,
    this.peekKey,
  }) : assert(actions.length > 0 || blockedReason != null,
            'un row sin acciones necesita un blockedReason que explicar');

  /// Identidad del row (para la coordinación de "uno abierto a la vez").
  final Object id;
  final ValueNotifier<Object?> group;
  final List<SwipeAction> actions;

  /// La tarjeta, SIN margen exterior propio (lo aplica este widget).
  final Widget child;
  final double radius;
  final double actionWidth;
  final EdgeInsets margin;

  /// Si no es null, el row NO ejecuta acciones: revela UNA franja gris con
  /// candado + este texto y SIEMPRE vuelve a cero al soltar. Es la respuesta
  /// al dedo cuando la fila existe pero sus acciones no aplican — antes la
  /// tarjeta quedaba inerte y el gesto no producía nada.
  final String? blockedReason;

  /// Clave de onboarding con la que enseñar el gesto UNA sola vez: la tarjeta
  /// se asoma y vuelve (patrón iOS Mail). Null = sin pista. Se pasa solo en la
  /// PRIMERA fila no bloqueada de una lista.
  final String? peekKey;

  @override
  State<SwipeToActions> createState() => _SwipeToActionsState();
}

class _SwipeToActionsState extends State<SwipeToActions>
    with SingleTickerProviderStateMixin {
  double _dx = 0;

  /// Posición cruda del dedo (sin la goma) mientras se arrastra: el arrastre
  /// acumula aquí y `_dx` es su versión con resistencia. Así soltar y volver a
  /// arrastrar no da saltos.
  double _dragRaw = 0;

  // Se crea en initState (NO `late` perezoso): si el row nunca se arrastra, un
  // `late final` se instanciaría durante dispose() al llamar `_snap.dispose()`
  // — y crear un AnimationController mientras el elemento se desactiva revienta
  // ("Looking up a deactivated widget's ancestor is unsafe").
  late final AnimationController _snap;
  bool _busy = false;

  bool get _blocked => widget.blockedReason != null;

  /// Bloqueado: una sola franja con texto de una línea, no N íconos de 88.
  double get _revealW =>
      _blocked ? 140 : widget.actions.length * widget.actionWidth;

  /// Cuánto se puede estirar de más (con goma) pasado el ancho revelado.
  static const double _maxOver = 56;

  /// El "resorte" del asentamiento: subamortiguado a propósito (damping por
  /// debajo del crítico ≈ 2·√stiffness) para que rebote un pelín al soltar —
  /// la sensación física que pidió el PO (2026-07-22).
  static const SpringDescription _spring =
      SpringDescription(mass: 1, stiffness: 520, damping: 26);

  @override
  void initState() {
    super.initState();
    // `unbounded`: la simulación del resorte puede pasarse (rebote) del rango
    // [0, revealW]; un controlador acotado a [0,1] lo recortaría.
    _snap = AnimationController.unbounded(vsync: this);
    _snap.addListener(() {
      // Recorta el valor del resorte: el rebote de cierre no cruza a negativo
      // (dejaría un hueco a la derecha) y el de apertura se topa en el máximo
      // estirado.
      setState(() => _dx = _snap.value.clamp(0.0, _revealW + _maxOver));
    });
    widget.group.addListener(_onGroupChanged);
    // Post-frame: `_maybePeek` lee el MediaQuery, que no está disponible en
    // initState, y la pista solo tiene sentido con la lista ya pintada.
    if (widget.peekKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePeek(widget.peekKey!);
      });
    }
  }

  @override
  void dispose() {
    widget.group.removeListener(_onGroupChanged);
    _snap.dispose();
    super.dispose();
  }

  void _onGroupChanged() {
    // Otro row se abrió → cerrar este.
    if (widget.group.value != widget.id && _dx > 0 && !_busy) _springTo(0, 0);
  }

  /// Curva de goma tipo iOS: a más desplazamiento, menos avanza — retorno
  /// decreciente que tiende asintóticamente a [limit].
  double _rubber(double delta, double limit) =>
      (1 - 1 / (delta / limit + 1)) * limit;

  /// Traduce la posición cruda del dedo a la posición con resistencia.
  double _resist(double raw) {
    if (raw <= 0) return -_rubber(-raw, _maxOver * 0.6);
    // Bloqueado: goma desde el PRIMER píxel. Cede y muestra el motivo, pero
    // nunca se siente como un cajón a punto de quedarse abierto.
    if (_blocked) return _rubber(raw, _revealW);
    if (raw <= _revealW) return raw; // dentro del rango: 1:1
    return _revealW + _rubber(raw - _revealW, _maxOver);
  }

  /// Asienta al objetivo con física de resorte, respetando la velocidad de
  /// lanzamiento del dedo.
  void _springTo(double target, double velocity) {
    _snap.stop();
    _snap.animateWith(SpringSimulation(_spring, _dx, target, velocity));
  }

  void _close() {
    if (widget.group.value == widget.id) widget.group.value = null;
    _springTo(0, 0);
  }

  /// Enseña el gesto una sola vez por usuario: la tarjeta se asoma 28 px y
  /// vuelve. Best-effort de principio a fin — una pista que falla nunca puede
  /// tumbar una lista.
  Future<void> _maybePeek(String key) async {
    try {
      await onboardingStore.ensureLoaded();
    } catch (_) {
      // Sin backend de guías la pista se muestra igual: es inocua.
    }
    if (!mounted || onboardingStore.isDone(key)) return;
    // Reduce motion: se marca como enseñada IGUAL, para no dejar una pista
    // pendiente para siempre en un dispositivo que no anima.
    if (!MediaQuery.disableAnimationsOf(context)) {
      // Si el usuario ya está arrastrando por su cuenta, no interrumpirlo.
      if (_dx != 0) return;
      // TODA la secuencia (espera + sale + sostiene + resorte de vuelta) en
      // un único `animateWith`, no un `Future.delayed` suelto seguido de una
      // animación posterior: un ticker que arranca "en frío" en medio de un
      // `Future.delayed` reporta su primer tick con elapsed=0 (así es
      // `Ticker._tick`: fija su `_startTime` de forma perezosa al timestamp
      // de ESE primer tick), así que el progreso real de la fase de salida
      // quedaría invisible dentro de un solo `pump(duration)` de test.
      // Arrancando el ticker YA (con la espera codificada como una fase más
      // de la simulación, en vez de como un timer aparte) su primer tick
      // ocurre temprano, con el widget recién montado, y los ticks
      // posteriores sí acumulan tiempo real — visible en un pump posterior.
      _snap.stop();
      await _snap.animateWith(_PeekSimulation(
        delaySeconds: 0.6,
        reveal: 28,
        outSeconds: 0.18,
        holdSeconds: 0.42,
        after: SpringSimulation(_spring, 28, 0, 0),
      ));
      if (!mounted) return;
    }
    await onboardingStore.markDone(key);
  }

  Future<void> _run(SwipeAction a) async {
    if (_busy) return;
    _busy = true;
    _close();
    try {
      await a.onTap();
    } finally {
      _busy = false;
    }
  }

  /// Franja de "esto no aplica aquí": gris de superficie, candado y el motivo.
  Widget _blockedStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: _revealW,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(
                  widget.blockedReason!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionsRow() {
    return Row(
      children: [
        for (final a in widget.actions)
          SizedBox(
            width: widget.actionWidth,
            child: Material(
              color: a.color,
              child: InkWell(
                onTap: _dx > 4 ? () => _run(a) : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(a.icon, color: Colors.white, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      a.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Rellena el resto (y el rebote del resorte al abrir de
        // más) con el color de la acción contigua a la tarjeta,
        // para que un sobre-estiramiento no deje asomar el fondo.
        if (widget.actions.isNotEmpty)
          Expanded(
            child: ColoredBox(color: widget.actions.last.color),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.margin,
      child: GestureDetector(
        onHorizontalDragStart: (_) {
          _snap.stop(); // toma el control del resorte si venía asentándose
          _dragRaw = _dx; // reanuda desde donde está (en rango, resist≈1:1)
        },
        onHorizontalDragUpdate: (d) {
          _dragRaw += d.delta.dx;
          setState(() => _dx = _resist(_dragRaw));
        },
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          // Bloqueado: no hay snap abierto ni reclamo del group — la franja es
          // una revelación momentánea.
          if (_blocked) {
            _springTo(0, v);
            return;
          }
          // Decide destino por velocidad o por posición, luego SUELTA el
          // resorte con esa velocidad (asentamiento con rebote).
          final bool open;
          if (v > 300) {
            open = true;
          } else if (v < -300) {
            open = false;
          } else {
            open = _dx > _revealW / 2;
          }
          if (open) {
            widget.group.value = widget.id; // cierra a los demás
            _springTo(_revealW, v);
          } else {
            if (widget.group.value == widget.id) widget.group.value = null;
            _springTo(0, v);
          }
        },
        child: Stack(
          children: [
            // Franjas de color reveladas a la izquierda (clip redondeado a la
            // tarjeta). Solo se pintan con el swipe abierto: cerradas, el fondo
            // asomaba por las esquinas redondeadas de la tarjeta (arcos rojos).
            if (_dx > 0.5)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.radius),
                  child: _blocked ? _blockedStrip(context) : _actionsRow(),
                ),
              ),
            // La tarjeta, desplazada por el arrastre. Cuando está abierta, una
            // capa transparente encima captura el tap para CERRAR (que no
            // navegue al detalle sin querer).
            Transform.translate(
              offset: Offset(_dx, 0),
              child: Stack(
                children: [
                  widget.child,
                  if (_dx > 2)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las cuatro fases del auto-peek en un único [Simulation] continuo. Un solo
/// ticker de principio a fin — incluida la espera inicial — porque uno que
/// arranca "en frío" a mitad de un `Future.delayed` reporta su primer tick
/// con elapsed=0 (ver [Ticker._tick]): no hay forma de que el resto del
/// código (incluido cualquiera que consulte "¿sigue habiendo una animación
/// en curso?", como `pumpAndSettle` en los tests) vea progreso real de una
/// fase que empieza a mitad de un temporizador aislado.
///
/// 1. ESPERA quieta en 0 durante [delaySeconds] (da tiempo a que el usuario
///    termine de mirar la lista antes de moverle algo).
/// 2. SALE animada de 0 a [reveal] en [outSeconds], desacelerando al llegar
///    (`Curves.easeOut`). Nunca un resorte subamortiguado aquí: rebotaría al
///    asomar, y asomarse debe leerse como un gesto suave, no como una
///    sacudida.
/// 3. SOSTIENE en [reveal] durante [holdSeconds].
/// 4. VUELVE delegando en [after] (el resorte de siempre).
class _PeekSimulation extends Simulation {
  _PeekSimulation({
    required this.delaySeconds,
    required this.reveal,
    required this.outSeconds,
    required this.holdSeconds,
    required this.after,
  });

  final double delaySeconds;
  final double reveal;
  final double outSeconds;
  final double holdSeconds;
  final Simulation after;
  static const Curve _outCurve = Curves.easeOut;

  double get _outEnd => delaySeconds + outSeconds;
  double get _holdEnd => _outEnd + holdSeconds;

  @override
  double x(double time) {
    if (time < delaySeconds) return 0;
    if (time < _outEnd) {
      final t =
          outSeconds <= 0 ? 1.0 : ((time - delaySeconds) / outSeconds).clamp(0.0, 1.0);
      return reveal * _outCurve.transform(t);
    }
    if (time < _holdEnd) return reveal;
    return after.x(time - _holdEnd);
  }

  @override
  double dx(double time) {
    if (time >= _holdEnd) return after.dx(time - _holdEnd);
    // Diferencias finitas para las fases 1-3: alcanza para la única cosa que
    // consume esta velocidad (una pista al detener la simulación a medio
    // camino, p. ej. si el usuario arrastra durante el peek); no hace falta
    // la derivada analítica de la curva.
    const epsilon = 0.001;
    return (x(time + epsilon) - x(time - epsilon)) / (2 * epsilon);
  }

  @override
  bool isDone(double time) =>
      time >= _holdEnd && after.isDone(time - _holdEnd);
}
