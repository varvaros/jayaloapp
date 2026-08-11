import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'jayalo_imagotipo.dart';

/// La portada animada de la app: Jayi en su isla, en loop perfecto de 10 s.
///
/// Réplica 1:1 del mockup aprobado por el PO (`portada-animada.html` en el repo
/// web, 2026-08-11): cielo con sol, nubes y rachas de viento; el imagotipo
/// oficial en el cielo; isla con palmera (corrida a la izquierda); Jayi con su
/// piña colada y el teléfono con burbujas de chat; doble salto de alegría en
/// t≈6.5-8.1 s. El mar bajo la isla queda LIMPIO a propósito: ahí van los
/// botones de login (decisión PO). Todo se pinta en un espacio lógico de
/// 720×1280 escalado a "cover".
class PortadaAnimada extends StatefulWidget {
  const PortadaAnimada({super.key});

  @override
  State<PortadaAnimada> createState() => _PortadaAnimadaState();
}

class _PortadaAnimadaState extends State<PortadaAnimada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 10))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => CustomPaint(
        painter: _PortadaPainter(_c.value),
        size: Size.infinite,
      ),
    );
  }
}

/// Keyframe: posición 0-1 del loop, valor, y curva hacia el SIGUIENTE frame.
class _K {
  const _K(this.p, this.v, [this.c = Curves.easeInOut]);
  final double p;
  final double v;
  final Curve c;
}

/// Interpola una lista de keyframes como los `@keyframes` del mockup CSS.
double _kf(double t, List<_K> ks) {
  if (t <= ks.first.p) return ks.first.v;
  for (var i = 0; i < ks.length - 1; i++) {
    final a = ks[i], b = ks[i + 1];
    if (t >= a.p && t <= b.p) {
      if (b.p == a.p) return b.v;
      final local = a.c.transform((t - a.p) / (b.p - a.p));
      return a.v + (b.v - a.v) * local;
    }
  }
  return ks.last.v;
}

/// Vaivén 0→1→0 suavizado, [cycles] veces por loop, con [phase] en vueltas.
double _sway(double t, double cycles, [double phase = 0]) {
  final p = (t * cycles + phase) % 1.0;
  return Curves.easeInOut.transform(p < .5 ? p * 2 : (1 - p) * 2);
}

class _PortadaPainter extends CustomPainter {
  const _PortadaPainter(this.t);

  /// Fase 0-1 del loop de 10 s.
  final double t;

  static const _w = 720.0;
  static const _h = 1280.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Encaje "cover" centrado del lienzo lógico 720×1280.
    final s = math.max(size.width / _w, size.height / _h);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
        (size.width - _w * s) / 2, (size.height - _h * s) / 2);
    canvas.scale(s);

    _cielo(canvas);
    _viento(canvas);
    _nubes(canvas);
    _mar(canvas);
    _isla(canvas);
    _palmera(canvas);
    _logo(canvas);
    _jayi(canvas);
    _burbujas(canvas);

    canvas.restore();
  }

  // ---------------------------------------------------------------- cielo --
  void _cielo(Canvas c) {
    const skyRect = Rect.fromLTWH(0, 0, _w, 805);
    c.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3D9BE2), Color(0xFF6FBCEE), Color(0xFFA9DDF7)],
          stops: [0, .55, 1],
        ).createShader(skyRect),
    );

    // Sol con halo que respira.
    final glow = _kf(t, const [
      _K(0, .55),
      _K(.25, .85),
      _K(.5, .6),
      _K(.75, .8),
      _K(1, .55),
    ]);
    c.drawCircle(
      const Offset(160, 190),
      130,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFFFF3B0).withValues(alpha: .85 * .7 * glow),
          const Color(0xFFFFF3B0).withValues(alpha: .4 * .7 * glow),
          const Color(0x00FFF3B0),
        ], stops: const [
          0,
          .45,
          1
        ]).createShader(
            Rect.fromCircle(center: const Offset(160, 190), radius: 130)),
    );
    c.drawCircle(const Offset(160, 190), 48, Paint()..color = const Color(0xFFF7D354));
  }

  // --------------------------------------------------------------- viento --
  void _viento(Canvas c) {
    void racha(Path p, double w, double x0, double x1, List<_K> op,
        double p0, double p1) {
      final o = _kf(t, op);
      if (o <= 0) return;
      final dx = t <= p0
          ? x0
          : t >= p1
              ? x1
              : x0 + (x1 - x0) * (t - p0) / (p1 - p0);
      c.save();
      c.translate(dx, 0);
      c.drawPath(
        p,
        Paint()
          ..color = Colors.white.withValues(alpha: o)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
      c.restore();
    }

    final w1 = Path()
      ..moveTo(60, 335)
      ..quadraticBezierTo(240, 300, 400, 332)
      ..quadraticBezierTo(560, 364, 690, 322);
    racha(
        w1,
        14,
        150,
        -190,
        const [_K(0, 0), _K(.07, 0), _K(.14, .4), _K(.38, .35), _K(.45, 0), _K(1, 0)],
        .07,
        .45);

    final w2 = Path()
      ..moveTo(10, 545)
      ..quadraticBezierTo(200, 515, 380, 548)
      ..quadraticBezierTo(560, 581, 700, 535);
    racha(
        w2,
        12,
        170,
        -210,
        const [_K(0, 0), _K(.29, 0), _K(.38, .45), _K(.62, .4), _K(.72, 0), _K(1, 0)],
        .29,
        .72);

    final w3 = Path()
      ..moveTo(120, 452)
      ..quadraticBezierTo(300, 432, 470, 458)
      ..quadraticBezierTo(640, 484, 700, 448);
    racha(
        w3,
        9,
        150,
        -180,
        const [_K(0, 0), _K(.56, 0), _K(.66, .38), _K(.84, .3), _K(.93, 0), _K(1, 0)],
        .56,
        .93);
  }

  // ---------------------------------------------------------------- nubes --
  void _nube(Canvas c, double dx, double opacity, List<Rect> ovalos,
      RRect? barra, Rect? sombra) {
    c.save();
    c.translate(dx, 0);
    final blanco = Paint()..color = Colors.white.withValues(alpha: opacity);
    if (barra != null) c.drawRRect(barra, blanco);
    for (final o in ovalos) {
      c.drawOval(o, blanco);
    }
    if (sombra != null) {
      c.drawOval(sombra,
          Paint()..color = const Color(0xFFDCEBF7).withValues(alpha: opacity));
    }
    c.restore();
  }

  void _nubes(Canvas c) {
    final dxA = -30 * _sway(t, 1);
    final dxB = 24 * _sway(t, 1);
    // cloudC del CSS: 0→-14 (25%) → 10 (75%) → 0; lo aproximamos con dos senos.
    double dxC(double phase) {
      final p = (t + phase) % 1.0;
      return _kf(p, const [_K(0, 0), _K(.25, -14), _K(.75, 10), _K(1, 0)]);
    }

    _nube(
      c,
      dxA,
      1,
      [
        Rect.fromCenter(center: const Offset(530, 205), width: 124, height: 68),
        Rect.fromCenter(center: const Offset(588, 185), width: 104, height: 80),
        Rect.fromCenter(center: const Offset(640, 210), width: 96, height: 56),
      ],
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(475, 196, 212, 32), const Radius.circular(16)),
      Rect.fromCenter(center: const Offset(560, 228), width: 180, height: 32),
    );
    _nube(
      c,
      dxB,
      1,
      [
        Rect.fromCenter(center: const Offset(270, 352), width: 104, height: 56),
        Rect.fromCenter(center: const Offset(322, 335), width: 88, height: 64),
        Rect.fromCenter(center: const Offset(368, 356), width: 80, height: 48),
      ],
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(222, 346, 180, 26), const Radius.circular(13)),
      Rect.fromCenter(center: const Offset(295, 370), width: 144, height: 24),
    );
    _nube(
      c,
      dxC(0),
      .95,
      [
        Rect.fromCenter(center: const Offset(586, 408), width: 68, height: 36),
        Rect.fromCenter(center: const Offset(618, 397), width: 56, height: 40),
      ],
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(556, 402, 98, 18), const Radius.circular(9)),
      null,
    );
    _nube(
      c,
      dxC(.25),
      .8,
      [
        Rect.fromCenter(center: const Offset(80, 432), width: 60, height: 28),
        Rect.fromCenter(center: const Offset(110, 424), width: 48, height: 32),
      ],
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(52, 428, 88, 14), const Radius.circular(7)),
      null,
    );

    // Nubes pegadas al horizonte.
    final pegada = Paint()..color = const Color(0xFFEAF6FD).withValues(alpha: .9);
    c.save();
    c.translate(dxB, 0);
    c.drawOval(
        Rect.fromCenter(center: const Offset(46, 762), width: 190, height: 88),
        pegada);
    c.restore();
    c.save();
    c.translate(dxA, 0);
    c.drawOval(
        Rect.fromCenter(center: const Offset(680, 748), width: 210, height: 104),
        pegada);
    c.restore();
    c.save();
    c.translate(dxC(0), 0);
    c.drawOval(
        Rect.fromCenter(center: const Offset(600, 792), width: 140, height: 52),
        pegada);
    c.restore();
  }

  // ------------------------------------------------------------------ mar --
  void _mar(Canvas c) {
    const seaRect = Rect.fromLTWH(0, 795, _w, _h - 795);
    c.drawRect(
      seaRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF55C0EC), Color(0xFF2E9FE0), Color(0xFF1B7ECB)],
          stops: [0, .18, 1],
        ).createShader(seaRect),
    );
    c.drawRect(const Rect.fromLTWH(0, 795, _w, 14),
        Paint()..color = const Color(0xFF8FD8F4).withValues(alpha: .8));

    // El agua bajo la isla queda LIMPIA (zona de botones). Solo una línea de
    // espuma pegada al borde inferior + una manchita.
    final dx1 = _kf(t, const [_K(0, 0), _K(.25, -26), _K(.75, 22), _K(1, 0)]);
    final ola = Path()
      ..moveTo(60, 1240)
      ..quadraticBezierTo(170, 1229, 300, 1241)
      ..quadraticBezierTo(430, 1253, 560, 1237)
      ..quadraticBezierTo(690, 1221, 700, 1243);
    c.save();
    c.translate(dx1, 0);
    c.drawPath(
      ola,
      Paint()
        ..color = Colors.white.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    c.restore();

    final dx3 = -16 * _sway(t, 1);
    c.save();
    c.translate(dx3, 0);
    c.drawOval(
        Rect.fromCenter(center: const Offset(600, 1262), width: 112, height: 20),
        Paint()..color = Colors.white.withValues(alpha: .3));
    c.restore();
  }

  // ----------------------------------------------------------------- isla --
  void _ripple(Canvas c, Offset centro, double rx, double ry, double sw,
      double baseOp, double phase) {
    final p = (t + phase) % 1.0;
    final k = _kf(p, const [_K(0, 0), _K(.25, 1), _K(.5, 0), _K(.75, 1), _K(1, 0)]);
    final escala = 1 + .045 * k;
    final op = baseOp * (1 - .45 * k);
    c.save();
    c.translate(centro.dx, centro.dy);
    c.scale(escala);
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()
        ..color = Colors.white.withValues(alpha: op)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );
    c.restore();
  }

  void _isla(Canvas c) {
    _ripple(c, const Offset(362, 868), 225, 52, 5, .55, 0);
    _ripple(c, const Offset(362, 870), 258, 60, 4, .22, .12);

    final arena = Path()
      ..moveTo(180, 860)
      ..quadraticBezierTo(200, 822, 280, 818)
      ..quadraticBezierTo(330, 800, 400, 804)
      ..quadraticBezierTo(480, 800, 520, 822)
      ..quadraticBezierTo(560, 836, 548, 860)
      ..quadraticBezierTo(500, 886, 360, 888)
      ..quadraticBezierTo(220, 886, 180, 860)
      ..close();
    c.drawPath(
      arena,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7DA80), Color(0xFFE9BC55)],
        ).createShader(const Rect.fromLTWH(180, 800, 380, 88)),
    );

    c.drawOval(
        Rect.fromCenter(center: const Offset(285, 852), width: 18, height: 12),
        Paint()..color = const Color(0xFF8A6A43));
    c.drawOval(
        Rect.fromCenter(center: const Offset(452, 846), width: 22, height: 14),
        Paint()..color = const Color(0xFF75542F));

    final hierba = Paint()..color = const Color(0xFF3FA34D);
    final h1 = Path()
      ..moveTo(212, 836)
      ..relativeQuadraticBezierTo(-4, -16, 2, -22)
      ..relativeQuadraticBezierTo(2, 10, 6, 14)
      ..relativeQuadraticBezierTo(0, -14, 8, -18)
      ..relativeQuadraticBezierTo(2, 12, 0, 20)
      ..relativeQuadraticBezierTo(8, -10, 14, -10)
      ..relativeQuadraticBezierTo(-4, 12, -12, 18)
      ..close();
    c.drawPath(h1, hierba);
    final h2 = Path()
      ..moveTo(482, 830)
      ..relativeQuadraticBezierTo(-2, -14, 4, -19)
      ..relativeQuadraticBezierTo(1, 9, 4, 12)
      ..relativeQuadraticBezierTo(1, -12, 8, -15)
      ..relativeQuadraticBezierTo(1, 10, -1, 17)
      ..relativeQuadraticBezierTo(7, -8, 12, -8)
      ..relativeQuadraticBezierTo(-4, 10, -10, 15)
      ..close();
    c.drawPath(h2, hierba);
  }

  // -------------------------------------------------------------- palmera --
  void _palmera(Canvas c) {
    final rot = _kf(t, const [_K(0, 0), _K(.25, -1.8), _K(.75, 1.6), _K(1, 0)]) *
        math.pi /
        180;
    c.save();
    c.translate(-38, 0); // corrida a la izquierda de la isla (pedido PO)
    c.translate(300, 835);
    c.rotate(rot);
    c.translate(-300, -835);

    final tronco = Path()
      ..moveTo(292, 838)
      ..cubicTo(282, 790, 268, 726, 255, 678)
      ..lineTo(277, 672)
      ..cubicTo(292, 720, 302, 786, 308, 836)
      ..close();
    c.drawPath(tronco, Paint()..color = const Color(0xFFA9713D));

    final banda = Paint()
      ..color = const Color(0xFF8A5A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final (x, y, w) in [
      (285.0, 800.0, 18.0),
      (279.0, 764.0, 18.0),
      (272.0, 728.0, 18.0),
      (266.0, 696.0, 16.0)
    ]) {
      final p = Path()
        ..moveTo(x, y)
        ..relativeQuadraticBezierTo(w * .55, -4, w, 0);
      c.drawPath(p, banda);
    }

    c.drawCircle(const Offset(252, 676), 13, Paint()..color = const Color(0xFF7B4A2C));
    c.drawCircle(const Offset(274, 668), 12, Paint()..color = const Color(0xFF8A5633));

    final verdeOscuro = Paint()..color = const Color(0xFF4CAF3E);
    for (final f in [
      (Path()
        ..moveTo(262, 668)
        ..cubicTo(222, 636, 176, 640, 152, 666)
        ..cubicTo(168, 668, 176, 672, 184, 678)
        ..cubicTo(210, 668, 236, 672, 260, 680)
        ..close()),
      (Path()
        ..moveTo(262, 664)
        ..cubicTo(238, 614, 198, 600, 164, 608)
        ..cubicTo(176, 616, 182, 624, 186, 632)
        ..cubicTo(212, 636, 240, 652, 260, 672)
        ..close()),
      (Path()
        ..moveTo(264, 660)
        ..cubicTo(256, 608, 272, 576, 300, 562)
        ..cubicTo(298, 574, 300, 582, 304, 590)
        ..cubicTo(290, 612, 278, 638, 272, 664)
        ..close()),
      (Path()
        ..moveTo(266, 674)
        ..cubicTo(304, 690, 330, 712, 340, 740)
        ..cubicTo(328, 732, 318, 730, 308, 730)
        ..cubicTo(292, 712, 276, 692, 264, 682)
        ..close()),
    ]) {
      c.drawPath(f, verdeOscuro);
    }
    final verdeClaro = Paint()..color = const Color(0xFF66BB4A);
    for (final f in [
      (Path()
        ..moveTo(266, 664)
        ..cubicTo(298, 616, 344, 604, 378, 618)
        ..cubicTo(364, 622, 356, 628, 350, 636)
        ..cubicTo(322, 638, 292, 652, 272, 670)
        ..close()),
      (Path()
        ..moveTo(266, 670)
        ..cubicTo(314, 650, 358, 660, 382, 688)
        ..cubicTo(368, 686, 358, 688, 350, 692)
        ..cubicTo(322, 680, 292, 676, 270, 678)
        ..close()),
      (Path()
        ..moveTo(262, 666)
        ..cubicTo(238, 628, 238, 592, 258, 566)
        ..cubicTo(260, 578, 264, 586, 270, 592)
        ..cubicTo(264, 616, 264, 644, 268, 664)
        ..close()),
      (Path()
        ..moveTo(260, 674)
        ..cubicTo(226, 694, 208, 720, 206, 748)
        ..cubicTo(214, 738, 222, 734, 232, 732)
        ..cubicTo(240, 712, 252, 692, 264, 682)
        ..close()),
    ]) {
      c.drawPath(f, verdeClaro);
    }
    c.restore();
  }

  // ----------------------------------------------------------------- logo --
  void _logo(Canvas c) {
    // 30 % más grande y alto en el cielo (rondas PO): 520 de ancho, y=300.
    paintImagotipo(c, const Rect.fromLTWH(100, 300, 520, 189.09));
  }

  // ----------------------------------------------------------------- Jayi --
  ({double dy, double sy, double rot}) _salto() {
    final dy = _kf(t, const [
      _K(0, 0),
      _K(.10, 2),
      _K(.20, 0),
      _K(.35, 2),
      _K(.50, 0),
      _K(.63, 0),
      _K(.65, 7, Curves.easeOut),
      _K(.695, -88, Curves.easeIn),
      _K(.735, 0),
      _K(.75, 4, Curves.easeOut),
      _K(.78, -46, Curves.easeIn),
      _K(.81, 0),
      _K(.825, 3),
      _K(.85, 0),
      _K(.92, 2),
      _K(1, 0),
    ]);
    final sy = _kf(t, const [
      _K(0, 1),
      _K(.10, .99),
      _K(.20, 1),
      _K(.35, .99),
      _K(.50, 1),
      _K(.63, 1),
      _K(.65, .9, Curves.easeOut),
      _K(.695, 1.04, Curves.easeIn),
      _K(.735, 1),
      _K(.75, .92, Curves.easeOut),
      _K(.78, 1.02, Curves.easeIn),
      _K(.81, 1),
      _K(.825, .96),
      _K(.85, 1),
      _K(.92, .99),
      _K(1, 1),
    ]);
    final rot = _kf(t, const [
      _K(0, 0),
      _K(.65, 0, Curves.easeOut),
      _K(.695, -4, Curves.easeIn),
      _K(.735, 0, Curves.easeOut),
      _K(.78, -2.5, Curves.easeIn),
      _K(.81, 0),
      _K(1, 0),
    ]);
    return (dy: dy, sy: sy, rot: rot);
  }

  void _jayi(Canvas c) {
    final salto = _salto();
    c.save();
    // transform-origin: centro-abajo del cuerpo (405, 888).
    c.translate(405, 888);
    c.translate(0, salto.dy);
    c.scale(1, salto.sy);
    c.rotate(salto.rot * math.pi / 180);
    c.translate(-405, -888);

    _gotitas(c);
    _antenas(c);
    _jugo(c);
    _cuerpo(c);
    _telefono(c);
    _ticks(c);
    _cara(c);
    _polvito(c);

    c.restore();
  }

  void _gotitas(Canvas c) {
    void gota(Offset base, List<_K> op, List<_K> dx, List<_K> dy, double r) {
      final o = _kf(t, op);
      if (o <= 0) return;
      c.save();
      c.translate(base.dx + _kf(t, dx), base.dy + _kf(t, dy));
      final p = Path()
        ..moveTo(0, 0)
        ..relativeQuadraticBezierTo(r, r * 1.6, 0, r * 2.2)
        ..relativeQuadraticBezierTo(-r, -r * .6, 0, -r * 2.2)
        ..close();
      c.drawPath(p, Paint()..color = const Color(0xFFBFE8FF).withValues(alpha: o));
      c.restore();
    }

    gota(
        const Offset(468, 700),
        const [_K(0, 0), _K(.66, 0), _K(.70, .95), _K(.77, 0), _K(1, 0)],
        const [_K(0, 0), _K(.66, 0), _K(.70, 14), _K(.77, 26), _K(1, 26)],
        const [_K(0, 0), _K(.66, 0), _K(.70, -26), _K(.77, -40), _K(1, -40)],
        4);
    gota(
        const Offset(368, 696),
        const [_K(0, 0), _K(.67, 0), _K(.72, .9), _K(.79, 0), _K(1, 0)],
        const [_K(0, 0), _K(.67, 0), _K(.72, -12), _K(.79, -20), _K(1, -20)],
        const [_K(0, 0), _K(.67, 0), _K(.72, -30), _K(.79, -46), _K(1, -46)],
        4);
    gota(
        const Offset(462, 712),
        const [_K(0, 0), _K(.75, 0), _K(.785, .9), _K(.83, 0), _K(1, 0)],
        const [_K(0, 0), _K(.75, 0), _K(.785, 16), _K(.83, 26), _K(1, 26)],
        const [_K(0, 0), _K(.75, 0), _K(.785, -20), _K(.83, -32), _K(1, -32)],
        3.4);
  }

  void _antenas(Canvas c) {
    final rotL = _kf(t, const [
      _K(0, 0),
      _K(.08, -7),
      _K(.16, 4),
      _K(.30, -5),
      _K(.44, 3),
      _K(.58, -4),
      _K(.67, -16),
      _K(.71, 10),
      _K(.75, -13),
      _K(.79, 8),
      _K(.84, -4),
      _K(.92, 2),
      _K(1, 0),
    ]);
    final rotR = _kf(t, const [
      _K(0, 0),
      _K(.08, 6),
      _K(.16, -4),
      _K(.30, 5),
      _K(.44, -3),
      _K(.58, 4),
      _K(.67, 15),
      _K(.71, -9),
      _K(.75, 12),
      _K(.79, -7),
      _K(.84, 4),
      _K(.92, -2),
      _K(1, 0),
    ]);
    final trazo = Paint()
      ..color = const Color(0xFF4A2A96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final relleno = Paint()..color = const Color(0xFF4A2A96);

    c.save();
    c.translate(388, 745);
    c.rotate(rotL * math.pi / 180);
    c.translate(-388, -745);
    c.drawPath(
        Path()
          ..moveTo(388, 745)
          ..cubicTo(385, 732, 379, 725, 372, 721),
        trazo);
    c.drawCircle(const Offset(371, 720), 4.5, relleno);
    c.restore();

    c.save();
    c.translate(422, 745);
    c.rotate(rotR * math.pi / 180);
    c.translate(-422, -745);
    c.drawPath(
        Path()
          ..moveTo(422, 745)
          ..cubicTo(425, 732, 431, 725, 438, 721),
        trazo);
    c.drawCircle(const Offset(439, 720), 4.5, relleno);
    c.restore();
  }

  void _jugo(Canvas c) {
    // Alzado durante el salto (rotación sobre el "hombro" + traslación).
    final k = _kf(t, const [
      _K(0, 0),
      _K(.63, 0),
      _K(.68, 1),
      _K(.80, 1),
      _K(.84, 0),
      _K(1, 0),
    ]);
    c.save();
    c.translate(352, 806);
    c.rotate(-10 * k * math.pi / 180);
    c.translate(-352, -806);
    c.translate(22 * k, -32 * k);

    // Brazo.
    c.drawPath(
        Path()
          ..moveTo(350, 818)
          ..cubicTo(336, 812, 328, 806, 322, 798),
        Paint()
          ..color = const Color(0xFF5B32B4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round);

    // Piña (grupo desplazado junto al cuerpo, como el mockup).
    c.save();
    c.translate(24, -10);

    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(262, 780, 54, 60), const Radius.circular(18)),
        Paint()..color = const Color(0xFFF3B843));
    final rejilla = Paint()
      ..color = const Color(0xFFDB9C2B).withValues(alpha: .8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(262, 780, 54, 60), const Radius.circular(18)));
    c.drawLine(const Offset(268, 792), const Offset(310, 826), rejilla);
    c.drawLine(const Offset(268, 818), const Offset(308, 788), rejilla);
    c.drawLine(const Offset(264, 806), const Offset(294, 834), rejilla);
    c.drawLine(const Offset(286, 784), const Offset(314, 810), rejilla);
    c.restore();

    final hojas = Paint()..color = const Color(0xFF4CAF3E);
    c.drawPath(
        Path()
          ..moveTo(280, 782)
          ..relativeQuadraticBezierTo(-8, -14, -2, -22)
          ..relativeQuadraticBezierTo(8, 6, 8, 18)
          ..close(),
        hojas);
    c.drawPath(
        Path()
          ..moveTo(292, 780)
          ..relativeQuadraticBezierTo(0, -16, 10, -20)
          ..relativeQuadraticBezierTo(4, 10, -4, 20)
          ..close(),
        hojas);
    c.drawPath(
        Path()
          ..moveTo(272, 784)
          ..relativeQuadraticBezierTo(-12, -8, -12, -18)
          ..relativeQuadraticBezierTo(10, 0, 16, 12)
          ..close(),
        hojas);

    // Pajita doblada hacia Jayi.
    c.drawPath(
        Path()
          ..moveTo(300, 780)
          ..cubicTo(302, 758, 310, 748, 330, 750),
        Paint()
          ..color = const Color(0xFFF08A2E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round);

    // Sombrillita.
    c.save();
    c.translate(252, 750);
    c.rotate(-22 * math.pi / 180);
    c.translate(-252, -750);
    final canopy = Path()
      ..moveTo(252, 728)
      ..arcToPoint(const Offset(280, 754), radius: const Radius.circular(28))
      ..lineTo(224, 754)
      ..arcToPoint(const Offset(252, 728), radius: const Radius.circular(28))
      ..close();
    c.drawPath(canopy, Paint()..color = const Color(0xFFF26D9A));
    final rib = Paint()
      ..color = const Color(0xFFD24E7E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    c.drawLine(const Offset(252, 728), const Offset(252, 754), rib);
    c.drawLine(const Offset(236, 733), const Offset(231, 754), rib);
    c.drawLine(const Offset(268, 733), const Offset(273, 754), rib);
    final feston = Path()..moveTo(224, 754);
    for (var i = 0; i < 4; i++) {
      feston.relativeQuadraticBezierTo(7, i.isEven ? -5 : 5, 14, 0);
    }
    c.drawPath(
        feston,
        Paint()
          ..color = const Color(0xFFD24E7E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    c.drawLine(const Offset(252, 754), const Offset(262, 788),
        Paint()
          ..color = const Color(0xFFB98046)
          ..strokeWidth = 3.5);
    c.restore();

    c.restore(); // piña
    c.restore(); // alzado
  }

  void _cuerpo(Canvas c) {
    const cuerpoRect = Rect.fromLTWH(335, 742, 140, 140);
    c.drawRRect(
      RRect.fromRectAndRadius(cuerpoRect, const Radius.circular(42)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7A48DB), Color(0xFF5B32B4)],
        ).createShader(cuerpoRect),
    );
    c.drawPath(
        Path()
          ..moveTo(355, 752)
          ..relativeQuadraticBezierTo(40, -14, 84, 2),
        Paint()
          ..color = const Color(0xFF8B5CE8).withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round);
  }

  void _telefono(Canvas c) {
    final k = _kf(t, const [
      _K(0, 0),
      _K(.63, 0),
      _K(.68, 1),
      _K(.80, 1),
      _K(.84, 0),
      _K(1, 0),
    ]);
    c.save();
    c.translate(505, 788);
    c.rotate(6 * k * math.pi / 180);
    c.translate(-505, -788);
    c.translate(0, -8 * k);

    c.drawPath(
        Path()
          ..moveTo(470, 820)
          ..cubicTo(490, 810, 500, 796, 505, 784),
        Paint()
          ..color = const Color(0xFF5B32B4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round);

    c.save();
    c.translate(520, 756);
    c.rotate(12 * math.pi / 180);
    c.translate(-520, -756);
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(498, 716, 46, 80), const Radius.circular(10)),
        Paint()..color = const Color(0xFF263250));
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(503, 722, 36, 64), const Radius.circular(6)),
        Paint()..color = const Color(0xFF33405F));
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(509, 730, 24, 4), const Radius.circular(2)),
        Paint()..color = const Color(0xFF8FA4C8).withValues(alpha: .9));
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(509, 739, 17, 4), const Radius.circular(2)),
        Paint()..color = const Color(0xFF8FA4C8).withValues(alpha: .6));
    c.restore();

    c.drawCircle(const Offset(505, 788), 11, Paint()..color = const Color(0xFF6D3FCB));
    c.restore();
  }

  void _ticks(Canvas c) {
    final o = _kf(t, const [
      _K(0, 0),
      _K(.09, 0),
      _K(.11, 1),
      _K(.13, 1),
      _K(.15, 0),
      _K(.56, 0),
      _K(.58, 1),
      _K(.60, 1),
      _K(.62, 0),
      _K(1, 0),
    ]);
    if (o <= 0) return;
    final p = Paint()
      ..color = const Color(0xFFFFF6C9).withValues(alpha: o)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    c.save();
    c.translate(482, 700);
    c.scale(.5 + .5 * o);
    c.translate(-482, -700);
    c.drawLine(const Offset(478, 708), const Offset(470, 690), p);
    c.drawLine(const Offset(494, 702), const Offset(492, 682), p);
    c.restore();
  }

  void _cara(Canvas c) {
    final opN = _kf(t, const [
      _K(0, 1),
      _K(.645, 1),
      _K(.655, 0),
      _K(.815, 0),
      _K(.825, 1),
      _K(1, 1),
    ]);
    final opJ = 1 - opN;

    if (opN > 0) {
      final blink = _kf(t, const [
        _K(0, 1),
        _K(.23, 1),
        _K(.242, .06),
        _K(.255, 1),
        _K(.54, 1),
        _K(.552, .06),
        _K(.565, 1),
        _K(1, 1),
      ]);
      final pdx = _kf(t, const [
        _K(0, 0),
        _K(.26, 0),
        _K(.32, -16),
        _K(.42, -16),
        _K(.48, 0),
        _K(1, 0),
      ]);
      final pdy = _kf(t, const [
        _K(0, 0),
        _K(.26, 0),
        _K(.32, 5),
        _K(.42, 5),
        _K(.48, 0),
        _K(1, 0),
      ]);

      c.save();
      c.translate(405, 798);
      c.scale(1, math.max(blink, .001));
      c.translate(-405, -798);
      c.drawOval(
          Rect.fromCenter(center: const Offset(405, 798), width: 62, height: 66),
          Paint()..color = Colors.white.withValues(alpha: opN));
      c.drawCircle(Offset(412 + pdx, 800 + pdy), 19,
          Paint()..color = const Color(0xFF232C4E).withValues(alpha: opN));
      c.drawCircle(Offset(419 + pdx, 792 + pdy), 6.5,
          Paint()..color = Colors.white.withValues(alpha: opN));
      c.restore();

      c.drawPath(
          Path()
            ..moveTo(389, 849)
            ..quadraticBezierTo(405, 860, 421, 849),
          Paint()
            ..color = const Color(0xFF3A1E63).withValues(alpha: opN)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round);
    }

    if (opJ > 0) {
      c.drawPath(
          Path()
            ..moveTo(377, 800)
            ..quadraticBezierTo(405, 776, 433, 800),
          Paint()
            ..color = Colors.white.withValues(alpha: opJ)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round);
      final boca = Path()
        ..moveTo(377, 836)
        ..quadraticBezierTo(405, 830, 433, 836)
        ..quadraticBezierTo(433, 874, 405, 876)
        ..quadraticBezierTo(377, 874, 377, 836)
        ..close();
      c.drawPath(boca,
          Paint()..color = const Color(0xFF391A6B).withValues(alpha: opJ));
      final dientes = Path()
        ..moveTo(381, 836)
        ..quadraticBezierTo(405, 831, 429, 836)
        ..lineTo(429, 846)
        ..quadraticBezierTo(405, 842, 381, 846)
        ..close();
      c.drawPath(
          dientes, Paint()..color = Colors.white.withValues(alpha: opJ));
      c.drawOval(
          Rect.fromCenter(center: const Offset(405, 866), width: 28, height: 16),
          Paint()..color = const Color(0xFFE9608C).withValues(alpha: opJ));
    }
  }

  void _polvito(Canvas c) {
    final o = _kf(t, const [
      _K(0, 0),
      _K(.725, 0),
      _K(.745, .8),
      _K(.78, 0),
      _K(1, 0),
    ]);
    if (o <= 0) return;
    final k = _kf(t, const [_K(.725, .3), _K(.745, 1), _K(.78, 1.5), _K(1, 1.5)]);
    final p = Paint()..color = const Color(0xFFFBEBB8).withValues(alpha: o);
    for (final (x, y, r) in [
      (346.0, 886.0, 9.0),
      (470.0, 884.0, 8.0),
      (332.0, 880.0, 5.0),
      (484.0, 878.0, 5.0)
    ]) {
      c.drawCircle(Offset(x, y), r * k, p);
    }
  }

  // ------------------------------------------------------------- burbujas --
  void _burbuja(
    Canvas c, {
    required List<_K> vida,
    required Offset origen,
    required double bobPhase,
    required void Function(Canvas, double) pinta,
  }) {
    final k = _kf(t, vida); // 0 = oculta, 1 = plena (con rebote >1 al brotar)
    if (k <= 0) return;
    final dy = -6 * _sway(t, 3, bobPhase);
    c.save();
    c.translate(origen.dx, origen.dy + dy);
    c.scale(k.clamp(0, 2).toDouble());
    c.translate(-origen.dx, -origen.dy);
    pinta(c, math.min(k, 1));
    c.restore();
  }

  void _lineas(Canvas c, double op, List<(double, double, double)> filas) {
    for (final (x, y, w) in filas) {
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, w, 5), const Radius.circular(2.5)),
          Paint()..color = Colors.white.withValues(alpha: op));
    }
  }

  void _burbujas(Canvas c) {
    // b1 violeta.
    _burbuja(
      c,
      vida: const [
        _K(0, 1),
        _K(.62, 1),
        _K(.645, 0),
        _K(.855, 0),
        _K(.875, 1.12),
        _K(.89, 1),
        _K(1, 1),
      ],
      origen: const Offset(474.4, 720),
      bobPhase: 0,
      pinta: (c, op) {
        final f = Paint()..color = const Color(0xFF8B5CF6).withValues(alpha: op);
        c.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(462, 668, 62, 42), const Radius.circular(12)),
            f);
        c.drawPath(
            Path()
              ..moveTo(474, 710)
              ..relativeLineTo(6, 10)
              ..relativeLineTo(8, -10)
              ..close(),
            f);
        _lineas(c, .95 * op, [(472, 680, 34)]);
        _lineas(c, .8 * op, [(472, 691, 24)]);
      },
    );

    // b2 verde: alterna líneas ↔ "escribiendo…".
    final dots = _kf(t, const [
      _K(0, 0),
      _K(.24, 0),
      _K(.27, 1),
      _K(.40, 1),
      _K(.43, 0),
      _K(1, 0),
    ]);
    _burbuja(
      c,
      vida: const [
        _K(0, 1),
        _K(.625, 1),
        _K(.65, 0),
        _K(.885, 0),
        _K(.905, 1.12),
        _K(.92, 1),
        _K(1, 1),
      ],
      origen: const Offset(551.8, 661),
      bobPhase: .18,
      pinta: (c, op) {
        final f = Paint()..color = const Color(0xFF54C97B).withValues(alpha: op);
        c.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(532, 612, 58, 40), const Radius.circular(12)),
            f);
        c.drawPath(
            Path()
              ..moveTo(544, 652)
              ..relativeLineTo(6, 9)
              ..relativeLineTo(8, -9)
              ..close(),
            f);
        final opLineas = (1 - dots) * op;
        if (opLineas > 0) {
          _lineas(c, .95 * opLineas, [(542, 623, 32)]);
          _lineas(c, .8 * opLineas, [(542, 634, 22)]);
        }
        if (dots > 0) {
          final d = Paint()..color = Colors.white.withValues(alpha: dots * op);
          for (final x in [550.0, 561.0, 572.0]) {
            c.drawCircle(Offset(x, 632), 3.5, d);
          }
        }
      },
    );

    // b3 coral.
    _burbuja(
      c,
      vida: const [
        _K(0, 1),
        _K(.63, 1),
        _K(.655, 0),
        _K(.915, 0),
        _K(.935, 1.12),
        _K(.95, 1),
        _K(1, 1),
      ],
      origen: const Offset(536.2, 723),
      bobPhase: .36,
      pinta: (c, op) {
        final f = Paint()..color = const Color(0xFFF0697C).withValues(alpha: op);
        c.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(530, 676, 56, 38), const Radius.circular(11)),
            f);
        c.drawPath(
            Path()
              ..moveTo(542, 714)
              ..relativeLineTo(6, 9)
              ..relativeLineTo(8, -9)
              ..close(),
            f);
        _lineas(c, .95 * op, [(540, 687, 30)]);
        _lineas(c, .8 * op, [(540, 697, 20)]);
      },
    );

    // b4 naranja "…": aparece a mitad de loop, dos veces.
    _burbuja(
      c,
      vida: const [
        _K(0, 0),
        _K(.16, 0),
        _K(.185, 1.1),
        _K(.20, 1),
        _K(.42, 1),
        _K(.445, 0),
        _K(.50, 0),
        _K(.525, 1.08),
        _K(.54, 1),
        _K(.605, 1),
        _K(.63, 0),
        _K(1, 0),
      ],
      origen: const Offset(513.2, 634),
      bobPhase: .5,
      pinta: (c, op) {
        final f = Paint()..color = const Color(0xFFF5A14B).withValues(alpha: op);
        c.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(490, 592, 50, 34), const Radius.circular(10)),
            f);
        c.drawPath(
            Path()
              ..moveTo(500, 626)
              ..relativeLineTo(5, 8)
              ..relativeLineTo(7, -8)
              ..close(),
            f);
        final d = Paint()..color = Colors.white.withValues(alpha: op);
        for (final x in [504.0, 514.0, 524.0]) {
          c.drawCircle(Offset(x, 609), 3.2, d);
        }
      },
    );
  }

  @override
  bool shouldRepaint(covariant _PortadaPainter old) => old.t != t;
}
