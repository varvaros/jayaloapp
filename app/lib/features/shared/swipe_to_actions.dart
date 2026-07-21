import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
  });

  /// Identidad del row (para la coordinación de "uno abierto a la vez").
  final Object id;
  final ValueNotifier<Object?> group;
  final List<SwipeAction> actions;

  /// La tarjeta, SIN margen exterior propio (lo aplica este widget).
  final Widget child;
  final double radius;
  final double actionWidth;
  final EdgeInsets margin;

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

  double get _revealW => widget.actions.length * widget.actionWidth;

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
    if (raw <= 0) return -_rubber(-raw, _maxOver * 0.6); // resistencia al cerrar
    if (raw <= _revealW) return raw; // dentro del rango: 1:1
    return _revealW + _rubber(raw - _revealW, _maxOver); // goma al abrir de más
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
            if (_dx > 0)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.radius),
                  child: Row(
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
                      Expanded(
                        child: ColoredBox(color: widget.actions.last.color),
                      ),
                    ],
                  ),
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
