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

/// Qué tiene Jayi en la mano. Una pose por lámina del intro.
enum JayiPose {
  /// Pregunta y cierre neutro: bracitos abiertos entre la solicitud y la oferta.
  open,

  /// La reacción: pulgar arriba.
  thumbsUp,

  /// «Navega con libertad»: bracitos abiertos y flote amplio.
  free,

  /// «Hacer ofertas es gratis»: la etiqueta de precio.
  priceTag,

  /// Los créditos de regalo: la moneda dorada.
  coin,
}

/// PUENTE hasta la Task 6 del plan 2026-09-18: `login_screen.dart` todavía
/// habla en láminas viejas. Se borra junto con este enum.
enum JayiSceneKind {
  common,
  consumerOffers,
  consumerLock,
  providerTray,
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

/// La moneda: lo ÚNICO no violeta del intro (PO 2026-09-18).
const _oroBorde = Color(0xFFC98D1F);
const _oroLuz = Color(0xFFFFF0BF);
const _oroClaro = Color(0xFFFBD66E);
const _oroOscuro = Color(0xFFE5A72A);

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
  const JayiScene({super.key, required this.pose});

  /// PUENTE hasta la Task 6: traduce la lámina vieja a la pose nueva.
  factory JayiScene.kind(JayiSceneKind kind, {Key? key}) => JayiScene(
    key: key,
    pose: switch (kind) {
      JayiSceneKind.common => JayiPose.open,
      JayiSceneKind.consumerOffers ||
      JayiSceneKind.consumerLock => JayiPose.free,
      JayiSceneKind.providerTray => JayiPose.priceTag,
      JayiSceneKind.providerCoin => JayiPose.coin,
    },
  );

  final JayiPose pose;

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
          pose: widget.pose,
          time: _t,
          animated: !_reduced,
        ),
      ),
    ),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.pose,
    required this.time,
    required this.animated,
  }) : super(repaint: time);

  final JayiPose pose;
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
    switch (pose) {
      case JayiPose.open:
        _paintOpen(canvas, bubbles: true);
      case JayiPose.free:
        _paintOpen(canvas, bubbles: false);
      case JayiPose.thumbsUp:
        _paintThumb(canvas);
      case JayiPose.priceTag:
        _paintTag(canvas);
      case JayiPose.coin:
        _paintCoin(canvas);
    }
    canvas.restore();
  }

  /// `.scene::before`: disco tenue con dos anillos (los `box-shadow` con
  /// spread de la maqueta), respirando en 4 s.
  void _paintHalo(Canvas canvas) {
    final op = animated ? _pingPong(_phase(_t, 4), 1, .65) : 1.0;
    final c = Offset(_vbW / 2, _vbH * .46);
    void disc(double r, double a) => canvas.drawCircle(
      c,
      r,
      Paint()..color = _halo.withValues(alpha: a * op),
    );
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

  void _arm(
    Canvas canvas,
    Offset from,
    Offset ctrl,
    Offset to, [
    double w = 8,
  ]) {
    canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy),
      _stroke(w),
    );
  }

  // ── Bracitos abiertos. Con [bubbles], una burbuja a cada lado ───────────
  void _paintOpen(Canvas canvas, {required bool bubbles}) {
    _arm(
      canvas,
      const Offset(33, 78),
      const Offset(24, 76),
      const Offset(18, 70),
    );
    _arm(
      canvas,
      const Offset(107, 78),
      const Offset(116, 76),
      const Offset(122, 70),
    );
    if (!bubbles) return;
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

  // ── Proveedor: la etiqueta de precio («Hacer ofertas es gratis») ────────
  void _paintTag(Canvas canvas) {
    final dy = animated ? _pingPong(_phase(_t, 3.4), 0, -6) : 0.0;
    _arm(
      canvas,
      const Offset(104, 78),
      const Offset(114, 76),
      const Offset(120, 68),
    );
    canvas.save();
    canvas.translate(0, dy);
    canvas.drawPath(
      Path()
        ..moveTo(118, 30)
        ..lineTo(144, 30)
        ..arcToPoint(const Offset(152, 38), radius: const Radius.circular(8))
        ..lineTo(152, 58)
        ..arcToPoint(const Offset(144, 66), radius: const Radius.circular(8))
        ..lineTo(118, 66)
        ..lineTo(106, 48)
        ..close(),
      _fill,
    );
    canvas.drawCircle(
      const Offset(124, 47),
      4,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final linea = _stroke(3.4, const Color(0xFFFFFFFF));
    canvas.drawLine(const Offset(134, 42), const Offset(147, 42), linea);
    canvas.drawLine(const Offset(134, 52), const Offset(143, 52), linea);
    canvas.restore();
  }

  // ── La reacción: pulgar arriba. Un solo grupo que rota desde el hombro ──
  /// [rot] en grados: 0 = arriba; 78 = brazo caído (estado de entrada).
  void _paintThumb(Canvas canvas, {double rot = 0, double alpha = 1}) {
    const shoulder = Offset(104, 78);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    canvas.translate(shoulder.dx, shoulder.dy);
    canvas.rotate(rot * math.pi / 180);
    canvas.translate(-shoulder.dx, -shoulder.dy);
    _arm(canvas, shoulder, const Offset(116, 72), const Offset(124, 60));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(116, 50, 21, 17),
        const Radius.circular(7.5),
      ),
      _fill,
    );
    canvas.save();
    canvas.translate(119.75, 53);
    canvas.rotate(-14 * math.pi / 180);
    canvas.translate(-119.75, -53);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(115.5, 35, 8.5, 20),
        const Radius.circular(4.25),
      ),
      _fill,
    );
    canvas.restore();
    final nudillo = _stroke(1.6, _hondo.withValues(alpha: .55));
    canvas.drawLine(const Offset(122, 58.5), const Offset(131, 58.5), nudillo);
    canvas.drawLine(const Offset(122, 63), const Offset(130, 63), nudillo);
    canvas.restore();
  }

  // ── Los créditos: la moneda dorada en la palma ──────────────────────────
  void _paintCoin(Canvas canvas) {
    _arm(
      canvas,
      const Offset(104, 78),
      const Offset(118, 76),
      const Offset(126, 66),
    );
    _arm(
      canvas,
      const Offset(124, 68),
      const Offset(134, 72),
      const Offset(146, 66),
      7,
    );
    const c = Offset(141, 46);
    const r = 16.0;
    // Giro de reposo: de frente el 68 % del ciclo, de canto solo al final.
    final sx = animated
        ? _stops(
            _phase(_t, 3.2),
            const [0, .68, .79, .86, 1],
            const [1, 1, .12, .12, 1],
          )
        : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(sx, 1);
    canvas.translate(-c.dx, -c.dy);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_oroClaro, _oroOscuro],
        ).createShader(rect),
    );
    canvas.drawCircle(c, r, _stroke(2.6, _oroBorde));
    canvas.drawCircle(c, 10.5, _stroke(2, _oroLuz.withValues(alpha: .9)));
    // La «J».
    final j = _stroke(2.4, _oroBorde);
    canvas.drawPath(
      Path()
        // barra superior
        ..moveTo(137.5, 39.5)
        ..lineTo(146, 39.5)
        // el palo, a la derecha
        ..moveTo(143, 39.5)
        ..lineTo(143, 49)
        // el gancho: media vuelta por abajo hacia la izquierda
        ..arcToPoint(
          const Offset(138, 49),
          radius: const Radius.circular(2.5),
          clockwise: true,
        ),
      j,
    );
    // El brillo cruza una vez por ciclo, recortado al círculo.
    // Base = -26: el brillo descansa FUERA del círculo (recortado), no cruzando la moneda.
    final gx = animated
        ? _stops(
            _phase(_t, 3.2),
            const [0, .22, .60, 1],
            const [-26, 26, 26, -26],
          )
        : -26.0;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - 1)));
    canvas.translate(gx, 0);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(28 * math.pi / 180);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(137.5, 26, 7, 40),
        const Radius.circular(3.5),
      ),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .55),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.pose != pose || old.animated != animated; // el tiempo va por `repaint`
}
