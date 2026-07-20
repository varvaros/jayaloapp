/// El loader de Jayalo — la mascota de la web, portada a Flutter.
///
/// Espejo de `src/components/ui/JayaloLoader.tsx` de jayalo-main: mismo
/// isotipo (cuerpo cuadrado redondeado, ojo arriba-izquierda con la pupila
/// desplazada, dos antenas) y mismas animaciones — la pupila escanea, el ojo
/// parpadea, las antenas vibran y tres puntos pulsan debajo. La geometría son
/// las coordenadas exactas del SVG (viewBox 200x200), así que la silueta es
/// idéntica a la del `isojayalo.svg`.
///
/// Se pinta con `CustomPainter` a propósito: no hace falta `flutter_svg` ni
/// meter el SVG como asset, y así el loader escala sin perder nitidez.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand.dart';

/// Periodos de la web (1.7s antenas, 2s, 4s parpadeo, 3.4s escaneo, 1.4s
/// puntos) redondeados a valores conmensurables para poder animarlo todo con
/// UN solo ticker de 16s sin salto al reiniciar el ciclo.
const _cycle = Duration(seconds: 16);
const _antennaLeftPeriod = 1.6;
const _antennaRightPeriod = 2.0;
const _blinkPeriod = 4.0;
const _scanPeriod = 3.2;
const _dotPeriod = 1.6;

/// Vaivén 0→1→0 suavizado (equivale al `animation-direction: alternate` de CSS).
double _pingPong(double t, double period) {
  final p = (t % period) / period;
  return Curves.easeInOut.transform(p < .5 ? p * 2 : (1 - p) * 2);
}

/// Interpola una lista de keyframes `(posición 0-1, valor)` con easeInOut,
/// igual que los `@keyframes` del CSS de la web.
double _keyframes(double phase, List<(double, double)> frames) {
  for (var i = 0; i < frames.length - 1; i++) {
    final (p0, v0) = frames[i];
    final (p1, v1) = frames[i + 1];
    if (phase >= p0 && phase <= p1) {
      if (p1 == p0) return v1;
      final local = Curves.easeInOut.transform((phase - p0) / (p1 - p0));
      return v0 + (v1 - v0) * local;
    }
  }
  return frames.last.$2;
}

/// La mascota animada + los tres puntos. Para bloques de carga usar
/// [JayaloLoaderBlock], que la centra y admite un texto.
class JayaloLoader extends StatefulWidget {
  const JayaloLoader({super.key, this.size = 88});
  final double size;

  @override
  State<JayaloLoader> createState() => _JayaloLoaderState();
}

class _JayaloLoaderState extends State<JayaloLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _cycle)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Accesibilidad: con "reducir animaciones" del sistema se muestra la
    // mascota quieta (la web hace lo mismo con prefers-reduced-motion).
    if (MediaQuery.disableAnimationsOf(context)) {
      return JayaloMascot(size: widget.size, semanticsLabel: 'Cargando');
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * _cycle.inSeconds;
        return Semantics(
          label: 'Cargando',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _MascotPainter(
                  // -4° → 4°, como `jyl-wl` / `jyl-wr` (opuestas entre sí).
                  antennaLeft: -4 + 8 * _pingPong(t, _antennaLeftPeriod),
                  antennaRight: 4 - 8 * _pingPong(t, _antennaRightPeriod),
                  eyeScaleY: _keyframes((t % _blinkPeriod) / _blinkPeriod, const [
                    (0, 1),
                    (.84, 1),
                    (.88, .08),
                    (.92, 1),
                    (1, 1),
                  ]),
                  pupilDx: _keyframes((t % _scanPeriod) / _scanPeriod, const [
                    (0, -9),
                    (.16, -9),
                    (.46, 4),
                    (.64, 4),
                    (.92, -9),
                    (1, -9),
                  ]),
                ),
              ),
              SizedBox(height: widget.size * .11),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final delay in const [0.0, 0.2, 0.4])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _Dot(phase: ((t - delay) % _dotPeriod) / _dotPeriod),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.phase});
  final double phase;

  @override
  Widget build(BuildContext context) {
    // `jyl-dot`: escala .7→1 y opacidad .35→1 en el medio del ciclo.
    final k = _keyframes(phase, const [(0, 0), (.5, 1), (1, 0)]);
    return Opacity(
      opacity: .35 + .65 * k,
      child: Container(
        width: 8 * (.7 + .3 * k),
        height: 8 * (.7 + .3 * k),
        decoration: const BoxDecoration(
          color: JayaloColors.mascot,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// La mascota quieta. La web la usa en estados vacíos con la pupila mirando
/// abajo-izquierda, "como buscando algo que no encontró".
class JayaloMascot extends StatelessWidget {
  const JayaloMascot({super.key, this.size = 72, this.semanticsLabel});
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final art = CustomPaint(
      size: Size.square(size),
      painter: const _MascotPainter(
        antennaLeft: 0,
        antennaRight: 0,
        eyeScaleY: 1,
        // Pupila abajo-izquierda: `cx 58 cy 96` del SVG (base 82,86).
        pupilDx: -24,
        pupilDy: 10,
      ),
    );
    return semanticsLabel == null
        ? art
        : Semantics(label: semanticsLabel, child: art);
  }
}

/// Bloque de carga centrado — equivalente del `JayaloLoaderBlock` de la web,
/// para reemplazar spinners de pantalla completa.
///
/// NO aparece de inmediato: espera [delay] antes de mostrar la mascota (PO
/// 2026-07-19, comparando con WhatsApp/Spotify — "solo le das clic y pasa"):
/// una carga típica de esta app resuelve en un puñado de ms, y mostrar la
/// mascota en cada navegación la hacía sentir más lenta de lo que es. Si la
/// carga sí tarda (red mala), el loader aparece pasado el umbral — nunca deja
/// al usuario mirando una pantalla en blanco sin explicación. Pasar
/// `delay: Duration.zero` para los pocos casos que SÍ deben verse al
/// instante (hoy: ninguno de los que usan este widget).
class JayaloLoaderBlock extends StatefulWidget {
  const JayaloLoaderBlock({
    super.key,
    this.label,
    this.size = 88,
    this.delay = const Duration(milliseconds: 400),
  });
  final String? label;
  final double size;
  final Duration delay;

  @override
  State<JayaloLoaderBlock> createState() => _JayaloLoaderBlockState();
}

class _JayaloLoaderBlockState extends State<JayaloLoaderBlock> {
  late bool _show = widget.delay == Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!_show) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _show = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          JayaloLoader(size: widget.size),
          if (widget.label != null) ...[
            const SizedBox(height: 16),
            Text(widget.label!,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// Spinner chico para botones — el "ojo" de Jayalo: aro tenue con la pupila
/// orbitando. Usa el color de texto heredado, como el `JayaloSpinner` de la web.
class JayaloSpinner extends StatefulWidget {
  const JayaloSpinner({super.key, this.size = 18, this.color});
  final double size;
  final Color? color;

  @override
  State<JayaloSpinner> createState() => _JayaloSpinnerState();
}

class _JayaloSpinnerState extends State<JayaloSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'Cargando',
      child: RotationTransition(
        turns: _c,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SpinnerPainter(color),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // viewBox 24x24 de la web
    final center = Offset(12 * s, 12 * s);
    canvas.drawCircle(
        center,
        8.5 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * s
          ..color = color.withValues(alpha: .25));
    canvas.drawCircle(
        Offset(12 * s, 3.5 * s), 2.6 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.color != color;
}

/// Dibuja el isotipo con las coordenadas exactas del SVG (viewBox 200x200).
class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.antennaLeft,
    required this.antennaRight,
    required this.eyeScaleY,
    required this.pupilDx,
    this.pupilDy = 0,
  });

  /// Grados de rotación de cada antena sobre su punto de anclaje al cuerpo.
  final double antennaLeft;
  final double antennaRight;

  /// Factor vertical del ojo (1 abierto, ~0 parpadeando).
  final double eyeScaleY;
  final double pupilDx;
  final double pupilDy;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.save();
    canvas.scale(s);

    final violet = Paint()..color = JayaloColors.mascot;
    final stroke = Paint()
      ..color = JayaloColors.mascot
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    // Antenas: giran sobre donde nacen del cuerpo (83,43) y (108,43).
    _antenna(canvas, stroke, const Offset(83, 43), antennaLeft,
        (p) => p..cubicTo(74, 32, 58, 22, 49, 12));
    _antenna(canvas, stroke, const Offset(108, 43), antennaRight,
        (p) => p..cubicTo(117, 35, 129, 32, 138, 25));

    // Cuerpo.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(29, 42, 136, 135), const Radius.circular(33)),
        violet);

    // Ojo (parpadea escalando en Y sobre su centro) + pupila.
    const eyeCenter = Offset(67, 86);
    canvas.save();
    canvas.translate(eyeCenter.dx, eyeCenter.dy);
    canvas.scale(1, math.max(eyeScaleY, .001));
    canvas.translate(-eyeCenter.dx, -eyeCenter.dy);
    canvas.drawCircle(eyeCenter, 29, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(82 + pupilDx, 86 + pupilDy), 9.5, violet);
    canvas.restore();

    canvas.restore();
  }

  void _antenna(Canvas canvas, Paint paint, Offset pivot, double degrees,
      Path Function(Path) draw) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawPath(draw(Path()..moveTo(pivot.dx, pivot.dy)), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.antennaLeft != antennaLeft ||
      old.antennaRight != antennaRight ||
      old.eyeScaleY != eyeScaleY ||
      old.pupilDx != pupilDx ||
      old.pupilDy != pupilDy;
}
