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
///
/// Los parámetros de EXPRESIÓN (`happyEye`, `smile`, `doubtMouth`, `bodyDy`,
/// `bodyRotate`) tienen default 0 = isotipo puro, idéntico al de la marca.
/// Solo [JayaloMascotFace] los usa (gamificación de crear-solicitud); el
/// loader y los estados vacíos siguen dibujando la mascota canónica.
class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.antennaLeft,
    required this.antennaRight,
    required this.eyeScaleY,
    required this.pupilDx,
    this.pupilDy = 0,
    this.happyEye = 0,
    this.smile = 0,
    this.doubtMouth = 0,
    this.bodyDy = 0,
    this.bodyRotate = 0,
    this.inflate = 0,
    this.oMouth = 0,
    this.bodyColor = JayaloColors.mascot,
    this.inkColor = Colors.white,
  });

  /// Esquema de color de la mascota. Por defecto = cuerpo violeta de marca +
  /// "tinta" blanca (ojo/sonrisa) sobre él. Se invierte para la celebración de
  /// desbloqueo (pedido PO 2026-07-22): cuerpo BLANCO + tinta violeta, para que
  /// resalte sobre el fondo violeta a pantalla completa. El pupilo va del color
  /// del CUERPO (el "hueco" del ojo), igual que en el isotipo.
  final Color bodyColor;
  final Color inkColor;

  /// Grados de rotación de cada antena sobre su punto de anclaje al cuerpo.
  final double antennaLeft;
  final double antennaRight;

  /// Factor vertical del ojo (1 abierto, ~0 parpadeando).
  final double eyeScaleY;
  final double pupilDx;
  final double pupilDy;

  /// 0..1: el ojo se convierte en el arco feliz "∩" (celebración).
  final double happyEye;

  /// 0..1: sonrisa "‿" bajo el ojo (0 = sin boca, isotipo puro).
  final double smile;

  /// 0..1: boquita ladeada de duda (excluyente con [smile] en la práctica).
  final double doubtMouth;

  /// Salto y giro del cuerpo entero (px / grados del viewBox) — celebración.
  final double bodyDy;
  final double bodyRotate;

  /// 0..1: el cuerpo se INFLA. Las esquinas se redondean hasta volverse un
  /// círculo y la caja gana panza. 0 = isotipo puro (la "tele" de la marca).
  final double inflate;

  /// 0..1: boca de sorpresa — la "o" pequeña de "¡uy, me estoy inflando!".
  /// Cruza en fundido con [smile] (el que hace el cross-fade es [_MoodFrame]).
  final double oMouth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.save();
    canvas.scale(s);

    // Grupo del cuerpo completo: salto + giro sobre el centro (97,109).
    canvas.translate(97, 109 + bodyDy);
    canvas.rotate(bodyRotate * math.pi / 180);
    canvas.translate(-97, -109);

    final violet = Paint()..color = bodyColor;
    final stroke = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    // Antenas: giran sobre donde nacen del cuerpo (83,43) y (108,43).
    _antenna(canvas, stroke, const Offset(83, 43), antennaLeft,
        (p) => p..cubicTo(74, 32, 58, 22, 49, 12));
    _antenna(canvas, stroke, const Offset(108, 43), antennaRight,
        (p) => p..cubicTo(117, 35, 129, 32, 138, 25));

    // Cuerpo. Al inflarse NO hace falta geometría nueva: el radio de esquina
    // crece hasta 66, que es la mitad del lado corto de la caja, y eso
    // convierte la misma RRect de la marca en un círculo. La caja además se
    // ensancha y se achata un pelín para que quede con panza, no como bola de
    // billar. Con inflate=0 el rect es idéntico al del isotipo (29,42,136,135).
    final inf = inflate.clamp(0.0, 1.0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: const Offset(97, 109.5),
                width: 136 + 6 * inf,
                height: 135 - 3 * inf),
            Radius.circular(33 + 33 * inf)),
        violet);

    // Ojo. Con happyEye el círculo se funde en el arco feliz "∩" (ojo cerrado
    // de alegría, estilo ^_^): el círculo se achata y el arco toma su lugar.
    const eyeCenter = Offset(67, 86);
    final effectiveEyeY = eyeScaleY * (1 - happyEye);
    if (effectiveEyeY > .04) {
      canvas.save();
      canvas.translate(eyeCenter.dx, eyeCenter.dy);
      canvas.scale(1, math.max(effectiveEyeY, .001));
      canvas.translate(-eyeCenter.dx, -eyeCenter.dy);
      canvas.drawCircle(eyeCenter, 29, Paint()..color = inkColor);
      canvas.drawCircle(Offset(82 + pupilDx, 86 + pupilDy), 9.5, violet);
      canvas.restore();
    }
    if (happyEye > 0) {
      final happy = Paint()
        ..color = inkColor.withValues(alpha: happyEye.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;
      final arc = Path()
        ..moveTo(45, 92)
        ..quadraticBezierTo(67, 92 - 30 * happyEye, 89, 92);
      canvas.drawPath(arc, happy);
    }

    // Boca — solo en estados expresivos. Sonrisa "‿" centrada bajo el ojo.
    if (smile > 0) {
      final m = Paint()
        ..color = inkColor.withValues(alpha: smile.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      final mouth = Path()
        ..moveTo(58, 130)
        ..quadraticBezierTo(78, 130 + 20 * smile, 98, 130);
      canvas.drawPath(mouth, m);
    }
    // Boca de sorpresa: un CÍRCULO LLENO (pedido PO 2026-07-28 — en anillo se
    // leía como la letra "o", no como una boca abierta). Va en el mismo sitio
    // que la sonrisa y crece con la sorpresa.
    if (oMouth > 0) {
      final o = oMouth.clamp(0.0, 1.0);
      canvas.drawCircle(const Offset(78, 135), 5 + 4 * o,
          Paint()..color = inkColor.withValues(alpha: o));
    }
    // Boquita ladeada de duda ("mmm…").
    if (doubtMouth > 0) {
      final m = Paint()
        ..color = inkColor.withValues(alpha: doubtMouth.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(62, 133), const Offset(82, 127), m);
    }

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
      old.pupilDy != pupilDy ||
      old.happyEye != happyEye ||
      old.smile != smile ||
      old.doubtMouth != doubtMouth ||
      old.bodyDy != bodyDy ||
      old.bodyRotate != bodyRotate ||
      old.inflate != inflate ||
      old.oMouth != oMouth ||
      old.bodyColor != bodyColor ||
      old.inkColor != inkColor;
}

/// Estados de ánimo de la mascota para la gamificación de crear-solicitud.
enum MascotMood { idle, thinking, happy, celebrate }

/// Parámetros de cara/cuerpo de un instante; se interpolan entre ánimos.
class _MoodFrame {
  const _MoodFrame({
    this.antennaLeft = 0,
    this.antennaRight = 0,
    this.eyeScaleY = 1,
    this.pupilDx = 0,
    this.pupilDy = 0,
    this.happyEye = 0,
    this.smile = 0,
    this.doubtMouth = 0,
    this.bodyDy = 0,
    this.bodyRotate = 0,
    this.oMouth = 0,
  });
  final double antennaLeft, antennaRight, eyeScaleY, pupilDx, pupilDy;
  final double happyEye, smile, doubtMouth, bodyDy, bodyRotate;
  final double oMouth;

  static _MoodFrame lerp(_MoodFrame a, _MoodFrame b, double t) => _MoodFrame(
        antennaLeft: a.antennaLeft + (b.antennaLeft - a.antennaLeft) * t,
        antennaRight: a.antennaRight + (b.antennaRight - a.antennaRight) * t,
        eyeScaleY: a.eyeScaleY + (b.eyeScaleY - a.eyeScaleY) * t,
        pupilDx: a.pupilDx + (b.pupilDx - a.pupilDx) * t,
        pupilDy: a.pupilDy + (b.pupilDy - a.pupilDy) * t,
        happyEye: a.happyEye + (b.happyEye - a.happyEye) * t,
        smile: a.smile + (b.smile - a.smile) * t,
        doubtMouth: a.doubtMouth + (b.doubtMouth - a.doubtMouth) * t,
        bodyDy: a.bodyDy + (b.bodyDy - a.bodyDy) * t,
        bodyRotate: a.bodyRotate + (b.bodyRotate - a.bodyRotate) * t,
        oMouth: a.oMouth + (b.oMouth - a.oMouth) * t,
      );

  /// La misma cara, pero SORPRENDIDA: el ojo feliz "∩" se abre al ojo redondo
  /// completo y la sonrisa se cierra en la "o". Conserva antenas y cuerpo para
  /// que solo cambie la expresión al interpolar hacia acá.
  _MoodFrame get surprised => _MoodFrame(
        antennaLeft: antennaLeft,
        antennaRight: antennaRight,
        eyeScaleY: 1,
        pupilDx: pupilDx,
        bodyDy: bodyDy,
        bodyRotate: bodyRotate,
        oMouth: 1,
      );
}

/// La mascota con EXPRESIONES, estilo motion graphic (gamificación de
/// crear-solicitud, pedido PO 2026-07-20):
///
/// - [MascotMood.idle]      → respira, parpadea y escanea con la pupila.
/// - [MascotMood.thinking]  → ojo entrecerrado mirando arriba, boquita
///                            ladeada, cabeza inclinada, una antena alzada.
/// - [MascotMood.happy]     → ojo achinado + sonrisa (el resumen final).
/// - [MascotMood.celebrate] → ojo feliz "∩", sonrisón, saltitos y antenas
///                            vibrando (pantalla de éxito, con el confeti).
///
/// El cambio de ánimo se funde en 240ms (ease-in-out, morph en pantalla) y
/// [reactKey] dispara un pop de escala (240ms ease-out-back) — la reacción
/// "¡nueva pregunta!". Con "reducir animaciones" del sistema queda la cara
/// del ánimo, quieta.
class JayaloMascotFace extends StatefulWidget {
  const JayaloMascotFace({
    super.key,
    this.size = 72,
    this.mood = MascotMood.idle,
    this.reactKey = 0,
    this.inflate = 0,
    this.semanticsLabel,
    this.bodyColor,
    this.inkColor,
  });
  final double size;
  final MascotMood mood;
  final int reactKey;

  /// 0..1: cuánto está INFLADA. Lo empuja [HoldMascotLayer] con el progreso
  /// real del hold. Redondea el cuerpo hasta la esfera y, pasada la mitad,
  /// le cambia la cara a sorprendida. 0 = la mascota de siempre.
  final double inflate;

  final String? semanticsLabel;

  /// Esquema de color opcional (ver [_MascotPainter]). Null → cuerpo violeta de
  /// marca + tinta blanca. La celebración de desbloqueo los invierte
  /// (cuerpo blanco + tinta violeta) para resaltar sobre el fondo violeta.
  final Color? bodyColor;
  final Color? inkColor;

  @override
  State<JayaloMascotFace> createState() => _JayaloMascotFaceState();
}

class _JayaloMascotFaceState extends State<JayaloMascotFace>
    with TickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: _cycle)..repeat();
  // Fundido entre el ánimo anterior y el nuevo (morph: ease-in-out cúbico).
  late final AnimationController _blend = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  // Pop de reacción a pregunta nueva.
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  late MascotMood _prevMood = widget.mood;

  @override
  void didUpdateWidget(covariant JayaloMascotFace old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      _prevMood = old.mood;
      _blend.forward(from: 0);
    }
    if (old.reactKey != widget.reactKey) _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _clock.dispose();
    _blend.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// La cara viva de cada ánimo en el instante `t` (segundos del reloj).
  _MoodFrame _frame(MascotMood mood, double t) => switch (mood) {
        MascotMood.idle => _MoodFrame(
            antennaLeft: -3 + 6 * _pingPong(t, _antennaLeftPeriod),
            antennaRight: 3 - 6 * _pingPong(t, _antennaRightPeriod),
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
            bodyDy: 2 - 4 * _pingPong(t, 2.4), // respiración
          ),
        MascotMood.thinking => _MoodFrame(
            // "Mmm…": mira arriba-izquierda, cabeza ladeada, antena alzada.
            antennaLeft: 8 + 4 * _pingPong(t, 1.2),
            antennaRight: -2 + 3 * _pingPong(t, 1.7),
            eyeScaleY: .78,
            pupilDx: -8 + 2 * _pingPong(t, 2.0),
            pupilDy: -9,
            doubtMouth: 1,
            bodyRotate: -3 + 1.5 * _pingPong(t, 2.4),
            bodyDy: 1 - 2 * _pingPong(t, 2.8),
          ),
        MascotMood.happy => _MoodFrame(
            antennaLeft: -4 + 8 * _pingPong(t, 1.4),
            antennaRight: 4 - 8 * _pingPong(t, 1.8),
            eyeScaleY: 1,
            happyEye: .45,
            smile: .8,
            pupilDy: 3,
            bodyDy: 2 - 4 * _pingPong(t, 2.0),
          ),
        MascotMood.celebrate => _MoodFrame(
            // Fiesta: saltitos, antenas a toda vibración, giro juguetón.
            antennaLeft: 10 * math.sin(t * math.pi * 2 / .5),
            antennaRight: -10 * math.sin(t * math.pi * 2 / .55),
            eyeScaleY: 1,
            happyEye: 1,
            smile: 1,
            bodyDy: -14 * Curves.easeOut.transform(_pingPong(t, .9)),
            bodyRotate: 4 * math.sin(t * math.pi * 2 / 1.8),
          ),
      };

  /// Cara estática representativa (reduce-motion): el ánimo sin movimiento.
  _MoodFrame _still(MascotMood mood) => switch (mood) {
        MascotMood.idle => const _MoodFrame(pupilDx: -9),
        MascotMood.thinking => const _MoodFrame(
            eyeScaleY: .78,
            pupilDx: -8,
            pupilDy: -9,
            doubtMouth: 1,
            bodyRotate: -3),
        MascotMood.happy => const _MoodFrame(happyEye: .45, smile: .8),
        MascotMood.celebrate => const _MoodFrame(happyEye: 1, smile: 1),
      };

  /// Cuánto de la cara SORPRENDIDA se mezcla, según lo inflada que esté. Entra
  /// en la fase 2 del hold (cuando arranca la vibración) y está plena antes de
  /// la tensión final: primero está contenta, después "¡uy!".
  double get _surprise =>
      Curves.easeOut.transform(((widget.inflate - .4) / .45).clamp(0.0, 1.0));

  /// El frame del ánimo, ya mezclado con la sorpresa del inflado.
  _MoodFrame _withSurprise(_MoodFrame f) {
    final s = _surprise;
    return s <= 0 ? f : _MoodFrame.lerp(f, f.surprised, s);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      final f = _withSurprise(_still(widget.mood));
      final art = CustomPaint(
        size: Size.square(widget.size),
        painter: _MascotPainter(
          antennaLeft: f.antennaLeft,
          antennaRight: f.antennaRight,
          eyeScaleY: f.eyeScaleY,
          pupilDx: f.pupilDx,
          pupilDy: f.pupilDy,
          happyEye: f.happyEye,
          smile: f.smile,
          doubtMouth: f.doubtMouth,
          bodyDy: f.bodyDy,
          bodyRotate: f.bodyRotate,
          inflate: widget.inflate,
          oMouth: f.oMouth,
          bodyColor: widget.bodyColor ?? JayaloColors.mascot,
          inkColor: widget.inkColor ?? Colors.white,
        ),
      );
      return widget.semanticsLabel == null
          ? art
          : Semantics(label: widget.semanticsLabel, child: art);
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_clock, _blend, _pulse]),
      builder: (context, _) {
        final t = _clock.value * _cycle.inSeconds;
        final mix = Curves.easeInOutCubic.transform(_blend.value);
        final f = _withSurprise(_MoodFrame.lerp(
            _frame(_prevMood, t), _frame(widget.mood, t), mix));
        final pop = 1 + .14 * (1 - Curves.easeOutBack.transform(_pulse.value));
        final art = Transform.scale(
          scale: pop,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _MascotPainter(
              antennaLeft: f.antennaLeft,
              antennaRight: f.antennaRight,
              eyeScaleY: f.eyeScaleY,
              pupilDx: f.pupilDx,
              pupilDy: f.pupilDy,
              happyEye: f.happyEye,
              smile: f.smile,
              doubtMouth: f.doubtMouth,
              bodyDy: f.bodyDy,
              bodyRotate: f.bodyRotate,
              inflate: widget.inflate,
              oMouth: f.oMouth,
              bodyColor: widget.bodyColor ?? JayaloColors.mascot,
              inkColor: widget.inkColor ?? Colors.white,
            ),
          ),
        );
        return widget.semanticsLabel == null
            ? art
            : Semantics(label: widget.semanticsLabel, child: art);
      },
    );
  }
}
