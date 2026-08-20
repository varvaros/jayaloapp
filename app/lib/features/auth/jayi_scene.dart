// La ilustración de cada lámina del intro: Jayi ACTUANDO lo que dice el
// titular. Port a Canvas del `.scene` de la maqueta de onboarding
// (artifact 660ac0ab, «Onboarding Jayalo»), que define un Jayi canónico
// dibujado UNA vez y reutilizado, más los accesorios propios de cada lámina.
//
// Por qué vectorial y no la webp de la portada: la portada es UN render fijo,
// así que las tres láminas contaban la misma imagen mientras el texto cambiaba
// — la escena era justo lo que hacía que el carrusel explicara algo. Aquí cada
// lámina tiene sus bracitos y sus objetos, del mismo violeta del isotipo.
//
// Sin dependencias nuevas (no hay `flutter_svg` en el proyecto): las figuras de
// la maqueta son rectángulos redondeados, círculos y dos curvas, que se pintan
// directo con `Canvas`. Las coordenadas son las del `viewBox` 168×132 de la
// maqueta, sin convertir: así un cambio en el SVG se puede portar leyendo.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/motion.dart';

/// Qué está haciendo Jayi. Una por lámina del intro.
enum JayiSceneKind {
  /// Lámina común: bracitos abiertos entre quien pide y quien vende.
  common,

  /// Cliente 2: las ofertas suben hacia él.
  consumerOffers,

  /// Cliente 3: cierra el candado (sus datos son suyos).
  consumerLock,

  /// Proveedor 2: las solicitudes caen en su bandeja.
  providerTray,

  /// Proveedor 3: la moneda gira (ofertar es gratis, cobras al final).
  providerCoin,
}

/// Violeta del ISOTIPO (`--violeta-jayi`), que NO es el violeta de acción
/// (`JayaloColors.primary`, #7147F2). La maqueta los distingue a propósito:
/// el de acción significa «esto se toca» y Jayi no se toca.
const _jayi = Color(0xFF6B3FE8);

/// `--violeta-hondo`: solo la pupila, para que el ojo tenga profundidad.
const _hondo = Color(0xFF5A2FD6);

/// El halo y el destello usan el violeta de ACCIÓN, como en la maqueta.
const _halo = Color(0xFF7147F2);

/// Sombra de piso: marrón cálido de la arena, no negro.
const _piso = Color(0xFF5D4826);

const double _vbW = 168;
const double _vbH = 132;

/// Fase 0..1 dentro de un ciclo de [period] segundos, con [delay] de arranque.
double _phase(double t, double period, [double delay = 0]) {
  final x = (t - delay) % period;
  return (x < 0 ? x + period : x) / period;
}

/// Los keyframes `0%,100% {a} 50% {b}` de la maqueta, con `ease-in-out` en cada
/// mitad. Es el pulso de `float`, `bob`, `breathe` y `gshadow`.
double _pingPong(double phase, double a, double b) {
  final half = phase < .5 ? phase * 2 : (1 - phase) * 2;
  return a + (b - a) * Curves.easeInOut.transform(half);
}

/// Interpolación lineal por tramos, como los keyframes con porcentajes sueltos
/// (`rise`, `drop`, `tick`, `flip`). [at] va en orden ascendente y del mismo
/// largo que [v].
double _stops(double p, List<double> at, List<double> v) {
  if (p <= at.first) return v.first;
  for (var i = 1; i < at.length; i++) {
    if (p <= at[i]) {
      final span = at[i] - at[i - 1];
      final k = span == 0 ? 0.0 : (p - at[i - 1]) / span;
      return v[i - 1] + (v[i] - v[i - 1]) * k;
    }
  }
  return v.last;
}

/// La escena de una lámina. Mantiene su relación 168:132 y se centra sola.
class JayiScene extends StatefulWidget {
  const JayiScene({super.key, required this.kind});

  final JayiSceneKind kind;

  @override
  State<JayiScene> createState() => _JayiSceneState();
}

// TickerProviderStateMixin (no Single) por el mismo motivo que `PortadaJayi`:
// el ticker se re-crea si el sistema cambia "reducir animaciones" con la
// pantalla montada, y el Single lanza en debug a la segunda creación aunque la
// primera esté dispuesta.
class _JayiSceneState extends State<JayiScene> with TickerProviderStateMixin {
  /// Segundos transcurridos: TODOS los relojes de la escena (4 / 3.4 / 3.6 /
  /// 5 / 3.2 / 3 s) derivan de aquí, así que un solo ticker mueve la lámina.
  final ValueNotifier<double> _t = ValueNotifier(0);
  Ticker? _ticker;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = JayaloMotion.reduced(context);
    if (reduced == _reduced && _ticker != null) return;
    _reduced = reduced;
    _ticker?.dispose();
    _ticker = null;
    if (!reduced) {
      _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6)..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: _vbW / _vbH,
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _ScenePainter(
          kind: widget.kind,
          time: _t,
          animated: !_reduced,
        ),
      ),
    ),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.kind,
    required this.time,
    required this.animated,
  }) : super(repaint: time);

  final JayiSceneKind kind;
  final ValueNotifier<double> time;

  /// Con "reducir animaciones" se pinta el ESTADO BASE de cada figura (sin
  /// transformación y a opacidad plena), que es lo que hace el
  /// `prefers-reduced-motion` de la maqueta con `animation: none`. Congelar en
  /// el instante 0 sería otra cosa: ahí las ofertas y el paquete valen
  /// `opacity: 0` y la lámina se quedaría sin la mitad de su contenido.
  final bool animated;

  double get _t => animated ? time.value : 0;

  Paint get _fill => Paint()..color = _jayi;

  Paint _stroke(double w, [Color c = _jayi]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _vbW);
    _paintHalo(canvas);
    _paintGround(canvas);
    _paintJayi(canvas);
    switch (kind) {
      case JayiSceneKind.common:
        _paintCommon(canvas);
      case JayiSceneKind.consumerOffers:
        _paintOffers(canvas);
      case JayiSceneKind.consumerLock:
        _paintLock(canvas);
      case JayiSceneKind.providerTray:
        _paintTray(canvas);
      case JayiSceneKind.providerCoin:
        _paintCoin(canvas);
    }
    canvas.restore();
  }

  /// `.scene::before`: disco tenue con dos anillos (los `box-shadow` con
  /// spread de la maqueta), respirando en 4 s.
  void _paintHalo(Canvas canvas) {
    final op = animated ? _pingPong(_phase(_t, 4), 1, .65) : 1.0;
    final c = Offset(_vbW / 2, _vbH * .46);
    void disc(double r, double a) =>
        canvas.drawCircle(c, r, Paint()..color = _halo.withValues(alpha: a * op));
    disc(133, .022); // box-shadow 46px
    disc(109, .04); //  box-shadow 22px
    disc(38.3, .08); // el degradado, sólido hasta el 44 % del radio
  }

  /// `.scene::after`: la elipse de piso, que se encoge con el flote.
  void _paintGround(Canvas canvas) {
    final op = animated ? _pingPong(_phase(_t, 4), .95, .55) : .95;
    final sx = animated ? _pingPong(_phase(_t, 4), 1, .82) : 1.0;
    final rect = Rect.fromCenter(
      center: const Offset(_vbW / 2, 134),
      width: 96 * sx,
      height: 14,
    );
    final base = _piso.withValues(alpha: .17 * op);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [base, base.withValues(alpha: 0)],
          stops: const [0, .68],
        ).createShader(rect),
    );
  }

  /// El cuerpo canónico: cuadrado redondeado, UN ojo descentrado con la pupila
  /// abajo-derecha y DOS antenas curvas. No cambia nunca entre láminas.
  void _paintJayi(Canvas canvas) {
    final dy = animated ? _pingPong(_phase(_t, 4), 0, -4) : 0.0;
    canvas.save();
    canvas.translate(14, 8 + dy); // el `use x=14 y=8 width=112` de la maqueta
    canvas.scale(112 / 120); //      viewBox propio de Jayi: 120×120
    final antena = _stroke(5);
    canvas.drawPath(
      Path()
        ..moveTo(46, 33)
        ..cubicTo(42, 21, 38, 16, 33, 11),
      antena,
    );
    canvas.drawPath(
      Path()
        ..moveTo(74, 33)
        ..cubicTo(78, 21, 82, 16, 87, 11),
      antena,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 30, 80, 72),
        const Radius.circular(26),
      ),
      _fill,
    );
    canvas.drawCircle(
      const Offset(49, 64),
      17,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(const Offset(55, 70), 7, Paint()..color = _hondo);
    canvas.restore();
  }

  void _arm(Canvas canvas, Offset from, Offset ctrl, Offset to, [double w = 8]) {
    canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy),
      _stroke(w),
    );
  }

  // ── Lámina común: los dos bracitos abiertos y una burbuja a cada lado ────
  void _paintCommon(Canvas canvas) {
    _arm(canvas, const Offset(33, 78), const Offset(24, 76), const Offset(18, 70));
    _arm(
      canvas,
      const Offset(107, 78),
      const Offset(116, 76),
      const Offset(122, 70),
    );
    _bubble(canvas, x: 0, delay: 0, alpha: 1);
    _bubble(canvas, x: 138, delay: 1.7, alpha: .72);
  }

  void _bubble(
    Canvas canvas, {
    required double x,
    required double delay,
    required double alpha,
  }) {
    final dy = animated ? _pingPong(_phase(_t, 3.4, delay), 0, -6) : 0.0;
    canvas.save();
    canvas.translate(0, dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 32, 30, 24),
        const Radius.circular(8),
      ),
      Paint()..color = _jayi.withValues(alpha: alpha),
    );
    // Los renglones van a blanco pleno también en la burbuja del 72 %: en la
    // maqueta el `opacity` está en el rectángulo, no en las líneas.
    final linea = _stroke(3.4, const Color(0xFFFFFFFF));
    canvas.drawLine(Offset(x + 7, 41), Offset(x + 23, 41), linea);
    canvas.drawLine(Offset(x + 7, 49), Offset(x + 17, 49), linea);
    canvas.restore();
  }

  // ── Cliente 2: tres ofertas que suben y se desvanecen ───────────────────
  void _paintOffers(Canvas canvas) {
    _arm(
      canvas,
      const Offset(104, 78),
      const Offset(118, 78),
      const Offset(126, 76),
    );
    _offer(canvas, const Rect.fromLTWH(118, 66, 40, 15), 7.5, 1, 0);
    _offer(canvas, const Rect.fromLTWH(124, 46, 34, 14), 7, .7, 1.2);
    _offer(canvas, const Rect.fromLTWH(120, 26, 30, 13), 6.5, .45, 2.4);
  }

  void _offer(Canvas canvas, Rect r, double radius, double alpha, double delay) {
    var dy = 0.0;
    var op = 1.0;
    if (animated) {
      final p = _phase(_t, 3.6, delay);
      dy = 18 + (-16 - 18) * p; // `rise`: de +18 a -16, lineal
      op = _stops(p, const [0, .26, .68, 1], const [0, 1, 1, 0]);
    }
    canvas.save();
    canvas.translate(0, dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(radius)),
      Paint()..color = _jayi.withValues(alpha: alpha * op),
    );
    canvas.restore();
  }

  // ── Cliente 3: el candado, con el golpecito de `tick` ───────────────────
  void _paintLock(Canvas canvas) {
    // `transform-origin: 4% 96%` sobre la caja del grupo (x 104..151,
    // y 32..78): el hombro, para que el golpe salga del brazo y no del aire.
    const pivot = Offset(105.9, 76.2);
    final rot = animated
        ? _stops(
            _phase(_t, 5),
            const [0, .84, .89, .94, 1],
            const [0, 0, -7, 4, 0],
          )
        : 0.0;
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(rot * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    _arm(canvas, const Offset(104, 78), const Offset(120, 74), const Offset(126, 64));
    // El arco del SVG (`a9 9 0 0 1 18 0`) es media circunferencia exacta:
    // cuerda 18, radio 9. En horario y con la Y hacia abajo, sube.
    canvas.drawPath(
      Path()
        ..moveTo(128, 47)
        ..lineTo(128, 41)
        ..arcToPoint(
          const Offset(146, 41),
          radius: const Radius.circular(9),
          clockwise: true,
        )
        ..lineTo(146, 47),
      _stroke(5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(123, 46, 28, 21),
        const Radius.circular(7),
      ),
      _fill,
    );
    canvas.drawCircle(
      const Offset(137, 56),
      3.5,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.restore();
  }

  // ── Proveedor 2: la solicitud cae en la bandeja ─────────────────────────
  void _paintTray(Canvas canvas) {
    // El paquete va PRIMERO: cae por detrás de la bandeja, como en la maqueta.
    var dy = 0.0;
    var op = 1.0;
    if (animated) {
      final p = _phase(_t, 3);
      dy = -16 + 42 * math.min(p / .68, 1); // de -16 a +26 hasta el 68 %
      op = _stops(p, const [0, .22, .68, 1], const [0, .6, 0, 0]);
    }
    canvas.save();
    canvas.translate(0, dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(122, 24, 28, 20),
        const Radius.circular(6),
      ),
      Paint()..color = _jayi.withValues(alpha: op),
    );
    canvas.restore();

    _arm(canvas, const Offset(104, 80), const Offset(120, 78), const Offset(126, 72));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(116, 58, 42, 28),
        const Radius.circular(9),
      ),
      _fill,
    );
    final linea = _stroke(3.6, const Color(0xFFFFFFFF));
    canvas.drawLine(const Offset(124, 68), const Offset(150, 68), linea);
    canvas.drawLine(const Offset(124, 76), const Offset(141, 76), linea);
  }

  // ── Proveedor 3: la moneda girando de canto ─────────────────────────────
  void _paintCoin(Canvas canvas) {
    _arm(canvas, const Offset(104, 78), const Offset(120, 74), const Offset(126, 62));
    const c = Offset(138, 43);
    final sx = animated
        ? _stops(
            _phase(_t, 3.2),
            const [0, .44, .56, 1],
            const [1, .08, .08, 1],
          )
        : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(sx, 1);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(c, 16, _fill);
    canvas.drawCircle(c, 9, _stroke(3.2, const Color(0xFFFFFFFF)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.kind != kind || old.animated != animated; // el tiempo va por `repaint`
}
