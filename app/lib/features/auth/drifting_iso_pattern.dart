/// Fondo con un mosaico de isotipos MUY tenues que deriva despacio en diagonal,
/// en loop sin costura (el patrón se repite cada `tile`, así que desplazar
/// exactamente `tile` por ciclo vuelve al mismo sitio). Reemplaza al patrón que
/// venía horneado en la imagen de bienvenida.
library;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';

class DriftingIsoPattern extends StatefulWidget {
  const DriftingIsoPattern({
    super.key,
    this.bg = const Color(0xFFEDE9FA),
    this.tile = 104,
    this.opacity = .055,
    // Velocidad afinada en device por el PO: 20.0 s por ciclo (el patrón
    // recorre un `tile` en ese tiempo).
    this.period = const Duration(seconds: 20),
  });

  /// Color de fondo (y del "hueco" del ojo de cada isotipo).
  final Color bg;
  final double tile;
  final double opacity;
  final Duration period;

  @override
  State<DriftingIsoPattern> createState() => _DriftingIsoPatternState();
}

class _DriftingIsoPatternState extends State<DriftingIsoPattern>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Con "reducir animaciones" el patrón se queda quieto (mismo criterio que
    // el resto de la app), pero sigue visible.
    if (JayaloMotion.reduced(context)) {
      return CustomPaint(
        painter: _IsoPatternPainter(
            progress: 0,
            tile: widget.tile,
            opacity: widget.opacity,
            bg: widget.bg),
        size: Size.infinite,
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _IsoPatternPainter(
            progress: _c.value,
            tile: widget.tile,
            opacity: widget.opacity,
            bg: widget.bg),
        size: Size.infinite,
      ),
    );
  }
}

class _IsoPatternPainter extends CustomPainter {
  _IsoPatternPainter({
    required this.progress,
    required this.tile,
    required this.opacity,
    required this.bg,
  });

  final double progress;
  final double tile;
  final double opacity;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final draw = tile * .62; // tamaño del isotipo dentro de su celda
    final pad = (tile - draw) / 2;
    final tint = JayaloColors.primary.withValues(alpha: opacity);
    final body = Paint()..color = tint;
    final ant = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    // El ojo se pinta con el color de fondo: "recorta" un punto claro en el
    // cuerpo tenue, igual que el isotipo real.
    final eye = Paint()..color = bg;

    // Deriva diagonal: exactamente `tile` en cada eje por ciclo → sin costura.
    final off = (progress * tile) % tile;

    for (double y = -tile; y < size.height + tile; y += tile) {
      for (double x = -tile; x < size.width + tile; x += tile) {
        _iso(canvas, Offset(x - off + pad, y - off + pad), draw, body, ant, eye);
      }
    }
  }

  void _iso(Canvas canvas, Offset origin, double drawSize, Paint body,
      Paint ant, Paint eye) {
    // Coordenadas exactas del isotipo (viewBox 200×200, como en jayalo_loader).
    final s = drawSize / 200;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(s);
    canvas.drawPath(
        Path()
          ..moveTo(83, 43)
          ..cubicTo(74, 32, 58, 22, 49, 12),
        ant);
    canvas.drawPath(
        Path()
          ..moveTo(108, 43)
          ..cubicTo(117, 35, 129, 32, 138, 25),
        ant);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(29, 42, 136, 135), const Radius.circular(33)),
        body);
    canvas.drawCircle(const Offset(67, 86), 29, eye);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IsoPatternPainter old) =>
      old.progress != progress ||
      old.tile != tile ||
      old.opacity != opacity ||
      old.bg != bg;
}
