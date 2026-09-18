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

/// El oro «plano» del destello que suelta la moneda al aterrizar: una sola
/// estrellita, sin degradado, así que no sale de los cuatro tonos del disco.
const _oro = Color(0xFFF2BD4A);

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

/// Abre un grupo de dibujo con opacidad [alpha] — SIEMPRE se cierra con un
/// `canvas.restore()`, valga lo que valga [alpha]. La capa aparte solo se paga
/// cuando de verdad hay transparencia: con `alpha == 1` un `saveLayer` cuesta
/// un búfer entero para nada (y es el caso de TODA la escena en reposo).
void _grupo(Canvas canvas, double alpha) {
  final a = alpha.clamp(0.0, 1.0);
  if (a >= 1) {
    canvas.save();
  } else {
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
  }
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

  /// La pose anterior y en qué segundo del reloj cambió: el pintor anima la
  /// entrada de la nueva y la salida de la vieja a partir de aquí. `null` =
  /// nunca cambió (solo el aterrizaje del montaje).
  JayiPose? _prev;
  double _changedAt = 0;

  @override
  void didUpdateWidget(covariant JayiScene old) {
    super.didUpdateWidget(old);
    if (old.pose != widget.pose) {
      _prev = old.pose;
      _changedAt = _t.value;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = JayaloMotion.reduced(context);
    if (reduced == _reduced && _ticker != null) return;
    _reduced = reduced;
    _ticker?.dispose();
    _ticker = null;
    // El ticker nuevo cuenta desde 0, así que un `_changedAt` del reloj viejo
    // dejaría `_since` en negativo: la pose saliente se pintaría opaca encima
    // de una entrante todavía invisible. La transición en curso se descarta.
    _prev = null;
    _changedAt = 0;
    // El primer frame del ticker nuevo pinta ANTES de que corra su callback,
    // con el valor viejo del reloj: se reinicia aquí también.
    _t.value = 0;
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
          prev: _prev,
          changedAt: _changedAt,
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
    required this.prev,
    required this.changedAt,
    required this.time,
    required this.animated,
  }) : super(repaint: time);

  final JayiPose pose;

  /// La pose que se está yendo, y el segundo del reloj en que se fue.
  final JayiPose? prev;
  final double changedAt;

  final ValueNotifier<double> time;

  /// Con "reducir animaciones" se pinta el ESTADO BASE de cada figura (sin
  /// transformación y a opacidad plena), que es lo que hace el
  /// `prefers-reduced-motion` de la maqueta con `animation: none`. Congelar en
  /// el instante 0 sería otra cosa: ahí las ofertas y el paquete valen
  /// `opacity: 0` y la lámina se quedaría sin la mitad de su contenido.
  final bool animated;

  double get _t => animated ? time.value : 0;

  /// Segundos desde el último cambio de pose. Sin animación es INFINITO, y esa
  /// es la pieza que hace que «reducir animaciones» pinte el estado FINAL sin
  /// un solo `if (animated)` por delante: toda entrada ya terminó, la saliente
  /// ya se fue y ningún destello está en curso.
  double get _since => animated ? time.value - changedAt : double.infinity;

  /// Segundos desde el montaje (el aterrizaje).
  double get _sinceMount => animated ? time.value : double.infinity;

  static double _sec(Duration d) => d.inMilliseconds / 1000;
  static final _land = _sec(JayaloMotion.introLand);
  static final _gesture = _sec(JayaloMotion.introGesture);
  static final _reveal = _sec(JayaloMotion.intro);
  static final _out = _sec(JayaloMotion.base);

  /// Progreso 0..1 de una entrada de [dur] segundos que empezó en [delay].
  double _in(double dur, [double delay = 0]) =>
      ((_since - delay) / dur).clamp(0.0, 1.0);

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
    // La pose saliente se apaga en `base` (250 ms) sin re-entrar: se va tal y
    // como estaba. Sin animación no hay saliente, porque `_since` es infinito.
    if (prev != null && _since < _out) {
      final q = JayaloMotion.exit.transform((_since / _out).clamp(0.0, 1.0));
      _paintPose(canvas, prev!, alpha: 1 - q, thumbRot: 78 * q, saliente: true);
    }
    _paintPose(canvas, pose, alpha: 1, saliente: false);
    canvas.restore();
  }

  /// Pinta el accesorio de [p]. [alpha] es el fundido de salida, [thumbRot]
  /// FUERZA el grado del pulgar (el que se cae al irse) y `null` deja mandar a
  /// la coreografía, y [saliente] apaga las ENTRADAS: lo que se va no vuelve a
  /// nacer, solo se apaga desde su estado final.
  void _paintPose(
    Canvas canvas,
    JayiPose p, {
    required double alpha,
    required bool saliente,
    double? thumbRot,
  }) {
    switch (p) {
      case JayiPose.open:
        _paintOpen(canvas, bubbles: true, alpha: alpha, saliente: saliente);
      case JayiPose.free:
        _paintOpen(canvas, bubbles: false, alpha: alpha, saliente: saliente);
      case JayiPose.thumbsUp:
        // Entrada: de 78° a 0° con el único rebote del sistema, en
        // `introGesture`. Luego, dos golpecitos en el último tercio de un
        // ciclo de 2,8 s.
        final k = saliente ? 1.0 : _in(_gesture);
        var rot = 78 * (1 - JayaloMotion.bounce.transform(k));
        if (k >= 1 && animated && !saliente) {
          rot += _stops(
            _phase(_since - _gesture, 2.8),
            const [0, .62, .70, .78, .86, .94, 1],
            const [0, 0, -6, 0, -5, 0, 0],
          );
        }
        _paintThumb(canvas, rot: thumbRot ?? rot, alpha: alpha);
      case JayiPose.priceTag:
        final k = saliente ? 1.0 : _in(_reveal);
        _paintTag(
          canvas,
          alpha: alpha * k,
          dy: 12 * (1 - JayaloMotion.brake.transform(k)),
        );
      case JayiPose.coin:
        _paintCoin(canvas, alpha: alpha, entrando: !saliente);
    }
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
    final libre = pose == JayiPose.free;
    var dy = animated
        ? _pingPong(_phase(_t, libre ? 3.4 : 4), 0, libre ? -9 : -4)
        : 0.0;
    var sx = 1.0, sy = 1.0, rot = 0.0;
    if (libre && animated) {
      rot = _pingPong(_phase(_t, 3.4), -1.2, 1.2) * math.pi / 180;
    }
    // Aterrizaje al abrir (los primeros `introLand` s desde el montaje).
    if (_sinceMount < _land) {
      final p = JayaloMotion.brake.transform(_sinceMount / _land);
      dy += _stops(p, const [0, .55, 1], const [-34, 0, 0]);
      sx = _stops(p, const [0, .55, .68, .84, 1], const [.98, 1, 1.06, .98, 1]);
      sy = _stops(
        p,
        const [0, .55, .68, .84, 1],
        const [1.02, 1, .93, 1.03, 1],
      );
    }
    // Saltito al entrar en la reacción (los primeros `introGesture` s).
    final salta = pose == JayiPose.thumbsUp && prev != null;
    if (salta && _since < _gesture) {
      final p = JayaloMotion.emphasized.transform(_since / _gesture);
      dy += _stops(p, const [0, .22, .52, .78, 1], const [0, 0, -10, 0, 0]);
      sx *= _stops(
        p,
        const [0, .22, .52, .78, 1],
        const [1, 1.05, .97, 1.03, 1],
      );
      sy *= _stops(
        p,
        const [0, .22, .52, .78, 1],
        const [1, .93, 1.05, .96, 1],
      );
    }
    // Las antenas tiemblan al 75 % del aterrizaje y del saltito.
    final wob =
        _wobble(_sinceMount, _land) + (salta ? _wobble(_since, _gesture) : 0);
    canvas.save();
    canvas.translate(70, 78 + dy); // pivote: el centro del cuerpo
    canvas.rotate(rot);
    canvas.scale(sx, sy);
    canvas.translate(-70, -78);
    canvas.translate(14, 8); // el `use x=14 y=8 width=112` de la maqueta
    canvas.scale(112 / 120); // viewBox propio de Jayi: 120×120
    _antena(
      canvas,
      const Offset(46, 33),
      const Offset(42, 21),
      const Offset(38, 16),
      const Offset(33, 11),
      wob,
    );
    _antena(
      canvas,
      const Offset(74, 33),
      const Offset(78, 21),
      const Offset(82, 16),
      const Offset(87, 11),
      wob,
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
    canvas.drawCircle(
      const Offset(55, 70) + _pupil(),
      7,
      Paint()..color = _hondo,
    );
    canvas.restore();
  }

  /// Grados de temblor de antena tras un evento de [dur] s ocurrido hace
  /// [since] s. Empieza al 75 % del evento — cuando el cuerpo ya frenó — y se
  /// apaga solo: es la inercia de la antena, no un bucle.
  double _wobble(double since, double dur) {
    final start = dur * .75;
    if (since < start || since > start + _gesture) return 0;
    return _stops(
      (since - start) / _gesture,
      const [0, .28, .58, .82, 1],
      const [0, -9, 6, -2.5, 0],
    );
  }

  /// Una antena, girada [deg] grados sobre SU BASE (nunca sobre el cuerpo: la
  /// anatomía no se mueve, solo se mece la antena).
  void _antena(
    Canvas canvas,
    Offset base,
    Offset c1,
    Offset c2,
    Offset tip,
    double deg,
  ) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-base.dx, -base.dy);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, tip.dx, tip.dy),
      _stroke(5),
    );
    canvas.restore();
  }

  /// A dónde mira la pupila en cada pose. Son desplazamientos de POCOS píxeles
  /// dentro del ojo: el ojo, su tamaño y su sitio no cambian nunca.
  static Offset _lookOf(JayiPose p) => switch (p) {
    JayiPose.open => const Offset(-1, 2),
    JayiPose.thumbsUp => const Offset(3, -3),
    JayiPose.free => Offset.zero,
    JayiPose.priceTag => const Offset(3, -1),
    JayiPose.coin => const Offset(4, -2),
  };

  /// La pupila mira al objeto nuevo en `intro` s, con `emphasized`.
  Offset _pupil() {
    final to = _lookOf(pose);
    if (prev == null || _since >= _reveal) return to;
    final k = JayaloMotion.emphasized.transform(_since / _reveal);
    return Offset.lerp(_lookOf(prev!), to, k)!;
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
  void _paintOpen(
    Canvas canvas, {
    required bool bubbles,
    double alpha = 1,
    bool saliente = false,
  }) {
    _grupo(canvas, alpha);
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
    if (bubbles) {
      // En el PRIMER montaje las burbujas esperan a que Jayi aterrice; si
      // llegan por un cambio de lámina entran ya, con el resto del accesorio.
      final espera = prev == null; // saliente siempre trae `prev`
      _bubble(
        canvas,
        x: 0,
        delay: 0,
        alpha: 1,
        entra: saliente ? 1 : _in(_reveal, espera ? _land * .8 : 0),
      );
      _bubble(
        canvas,
        x: 138,
        delay: 1.7,
        alpha: .72,
        entra: saliente ? 1 : _in(_reveal, espera ? _land * .9 : 0),
      );
    }
    canvas.restore();
  }

  void _bubble(
    Canvas canvas, {
    required double x,
    required double delay,
    required double alpha,
    required double entra,
  }) {
    final dy = animated ? _pingPong(_phase(_t, 3.4, delay), 0, -6) : 0.0;
    _grupo(canvas, entra);
    canvas.translate(0, dy + 12 * (1 - entra));
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
  void _paintTag(Canvas canvas, {double alpha = 1, double dy = 0}) {
    final bob = animated ? _pingPong(_phase(_t, 3.4), 0, -6) : 0.0;
    // El brazo va DENTRO del mismo desplazamiento que la etiqueta: si se queda
    // fuera, la etiqueta flota y la mano no, y se abre un hueco entre las dos.
    // El hombro (104,78) cae dentro de la silueta, así que moverlo no se ve.
    _grupo(canvas, alpha);
    canvas.translate(0, dy + bob);
    _arm(
      canvas,
      const Offset(104, 78),
      const Offset(114, 76),
      const Offset(120, 68),
    );
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
    _grupo(canvas, alpha);
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
  void _paintCoin(Canvas canvas, {double alpha = 1, bool entrando = true}) {
    // Entrada: sale de detrás de la palma girando, se pasa y aterriza
    // (`introLand`), empezando a mitad de la subida del brazo.
    final pin = entrando ? _in(_land, _reveal * .5) : 1.0;
    final e = JayaloMotion.brake.transform(pin);
    final dyIn = _stops(e, const [0, .60, .78, 1], const [30, -6, 2, 0]);
    final sxIn = _stops(e, const [0, .60, 1], const [.15, 1, 1]);
    final aIn = _stops(e, const [0, .35, 1], const [0, 1, 1]);
    // El destello: uno solo, al 80 % del aterrizaje, dura `intro`.
    final ps = entrando
        ? ((_since - _reveal * .5 - _land * .8) / _reveal).clamp(0.0, 1.0)
        : 1.0;
    // El brazo NO espera a la moneda: sube solo en `intro`, la misma entrada
    // que la etiqueta. Si compartiera el fundido de la moneda (que arranca a
    // la mitad) la mano estaría invisible los primeros ~210 ms y la moneda
    // saldría de detrás de una palma que no existe. Saliente: solo se funde.
    final armIn = entrando ? _in(_reveal) : 1.0;
    _grupo(canvas, alpha * armIn);
    canvas.translate(0, 12 * (1 - JayaloMotion.brake.transform(armIn)));
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
    canvas.restore(); // el brazo
    _grupo(canvas, alpha * aIn);
    const c = Offset(141, 46);
    const r = 16.0;
    // El ciclo de 3,2 s del reposo (giro y brillo comparten fase) NO se
    // muestrea en el reloj absoluto: así arrancaba en una fase cualquiera y una
    // de cada tres veces la moneda saltaba a canto (sx .12) en UN frame justo
    // al terminar la entrada. Se cuenta desde el final de la entrada, de modo
    // que en ese instante la fase vale 0.
    // El ciclo de reposo (giro + brillo) solo corre para la moneda ENTRANTE y
    // después de aterrizar: la saliente se funde de frente, y durante la
    // entrada el brillo descansa en -26. Arranca en fase 0 justo al aterrizar.
    final giro = (animated && entrando && pin >= 1)
        ? _phase(time.value - (changedAt + _reveal * .5 + _land), 3.2)
        : 0.0;
    // Giro de reposo: de frente el 68 % del ciclo, de canto solo al final.
    // Mientras entra manda el giro de la entrada, que nace casi de canto.
    final sxIdle = _stops(
      giro,
      const [0, .68, .79, .86, 1],
      const [1, 1, .12, .12, 1],
    );
    final sx = pin < 1 ? sxIn : sxIdle;
    canvas.save();
    canvas.translate(0, dyIn);
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
    final gx = _stops(giro, const [0, .22, .60, 1], const [-26, 26, 26, -26]);
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
    canvas.restore(); // el brillo
    canvas.restore(); // el giro y la subida de la moneda
    // UN destello al aterrizar, y ninguno más: la moneda ya tiene su brillo en
    // bucle. Con «reducir animaciones» no existe (`ps` nace en 1).
    if (animated && ps > 0 && ps < 1) {
      final op = _stops(ps, const [0, .4, 1], const [0, 1, 0]);
      final esc = _stops(ps, const [0, .4, 1], const [.2, 1.15, .7]);
      final estrella = Path();
      for (var i = 0; i < 8; i++) {
        final rr = i.isEven ? 5.0 : 1.6;
        final ang = i * math.pi / 4;
        final px = math.cos(ang) * rr, py = math.sin(ang) * rr;
        if (i == 0) {
          estrella.moveTo(px, py);
        } else {
          estrella.lineTo(px, py);
        }
      }
      estrella.close();
      canvas.save();
      canvas.translate(158, 27);
      canvas.rotate(45 * ps * math.pi / 180);
      canvas.scale(esc);
      canvas.drawPath(estrella, Paint()..color = _oro.withValues(alpha: op));
      canvas.restore();
    }
    canvas.restore(); // la opacidad del accesorio
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.pose != pose ||
      old.prev != prev ||
      old.changedAt != changedAt ||
      old.animated != animated; // el tiempo va por `repaint`
}
