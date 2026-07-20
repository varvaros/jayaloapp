import 'package:flutter/material.dart';

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
  // Se crea en initState (NO `late` perezoso): si el row nunca se arrastra, un
  // `late final` se instanciaría durante dispose() al llamar `_snap.dispose()`
  // — y crear un AnimationController mientras el elemento se desactiva revienta
  // ("Looking up a deactivated widget's ancestor is unsafe").
  late final AnimationController _snap;
  Animation<double>? _anim;
  bool _busy = false;

  double get _revealW => widget.actions.length * widget.actionWidth;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
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
    if (widget.group.value != widget.id && _dx > 0 && !_busy) _animateTo(0);
  }

  void _animateTo(double target) {
    _anim = Tween<double>(begin: _dx, end: target).animate(
      CurvedAnimation(parent: _snap, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dx = _anim!.value));
    _snap.forward(from: 0);
  }

  void _close() {
    if (widget.group.value == widget.id) widget.group.value = null;
    _animateTo(0);
  }

  void _open() {
    widget.group.value = widget.id; // cierra a los demás
    _animateTo(_revealW);
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
        onHorizontalDragUpdate: (d) {
          setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _revealW));
        },
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 300) {
            _open();
          } else if (v < -300) {
            _close();
          } else if (_dx > _revealW / 2) {
            _open();
          } else {
            _close();
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
                      const Spacer(),
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
