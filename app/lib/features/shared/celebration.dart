/// Celebraciones de motion graphics para las DOS confirmaciones deliberadas
/// de la app (doctrina PO 2026-07-20 "hold en ambos, con distinción visual"):
///
///   • [showUnlockCelebration] — acción PAGADA (desbloquear contacto): un
///     candado que se abre + un anillo de brillo. El premio de haber gastado
///     créditos.
///   • [showAcceptCelebration] — acción GRATIS (aceptar una oferta): confeti
///     + un cotejo que se dibuja solo. El premio de cerrar el trato.
///
/// Todo se pinta a mano con [CustomPainter] sobre los tokens de [JayaloMotion]
/// — sin paquetes de confeti/lottie (doctrina "mínimo, no replicar wrappers").
/// Se muestran como un overlay efímero por el navigator raíz: se auto-cierra al
/// terminar la animación y se puede saltar tocando la pantalla. Con "reducir
/// animaciones" del sistema cae a un destello estático breve.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import 'jayalo_loader.dart';

/// Overlay del candado abriéndose (desbloqueo pagado).
Future<void> showUnlockCelebration(BuildContext context) =>
    _showCelebration(context, _CelebrationKind.unlock);

/// Overlay de confeti + cotejo (oferta aceptada, gratis).
Future<void> showAcceptCelebration(BuildContext context) =>
    _showCelebration(context, _CelebrationKind.accept);

enum _CelebrationKind { unlock, accept }

Future<void> _showCelebration(BuildContext context, _CelebrationKind kind) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .32),
    barrierLabel:
        kind == _CelebrationKind.accept ? 'Oferta aceptada' : 'Contacto desbloqueado',
    transitionDuration: JayaloMotion.fast,
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (_, _, _) => _CelebrationOverlay(kind: kind),
  );
}

class _CelebrationOverlay extends StatefulWidget {
  const _CelebrationOverlay({required this.kind});
  final _CelebrationKind kind;
  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).maybePop();
      }
    });
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La duración se fija una vez, aquí, porque depende de "reducir
    // animaciones" del sistema (necesita context).
    if (_started) return;
    _started = true;
    final reduced = JayaloMotion.reduced(context);
    _ctrl.duration = reduced
        ? const Duration(milliseconds: 550)
        : (widget.kind == _CelebrationKind.accept
            ? const Duration(milliseconds: 1500)
            : const Duration(milliseconds: 1350));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _skip() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = JayaloMotion.reduced(context);
    return GestureDetector(
      key: ValueKey('celebration-${widget.kind.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => CustomPaint(
              painter: widget.kind == _CelebrationKind.accept
                  ? _AcceptPainter(
                      t: _ctrl.value,
                      reduced: reduced,
                      color: _brandSuccess(context))
                  : _UnlockPainter(
                      t: _ctrl.value,
                      reduced: reduced,
                      color: _brandPrimary(context)),
            ),
          ),
        ),
      ),
    );
  }
}

Color _brandPrimary(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dPrimary
        : JayaloColors.primary;

Color _brandSuccess(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dSuccess
        : JayaloColors.success;

// ---------------------------------------------------------------------------
// Confeti + cotejo (aceptar oferta).
// ---------------------------------------------------------------------------

class _Bit {
  const _Bit(this.angle, this.speed, this.size, this.color, this.spin, this.rect);
  final double angle; // dirección de disparo (rad)
  final double speed; // 0..1, qué tan lejos llega
  final double size; // lado/diámetro en px
  final Color color;
  final double spin; // giro por unidad de t
  final bool rect; // rectángulo vs círculo
}

/// Paleta festiva anclada a la marca (nada de arcoíris de payaso): violeta de
/// acción, verde de éxito, un azul, un dorado cálido y un rosa suave — cinco
/// tonos bien separados para que el confeti se lea con variedad.
const _confettiPalette = <Color>[
  JayaloColors.primary, // violeta de acción
  JayaloColors.success, // verde de éxito
  Color(0xFF3E98FF), // azul
  Color(0xFFF2B705), // dorado cálido
  Color(0xFFEE6C9B), // rosa suave
];

final List<_Bit> _confettiBits = _buildBits();

List<_Bit> _buildBits() {
  final rnd = math.Random(7); // semilla fija → determinista (y testeable)
  return List.generate(30, (i) {
    final angle = rnd.nextDouble() * math.pi * 2;
    final speed = 0.45 + rnd.nextDouble() * 0.55;
    final size = 6.0 + rnd.nextDouble() * 7.0;
    final color = _confettiPalette[i % _confettiPalette.length];
    final spin = (rnd.nextDouble() * 2 - 1) * math.pi * 3;
    return _Bit(angle, speed, size, color, spin, rnd.nextBool());
  });
}

class _AcceptPainter extends CustomPainter {
  _AcceptPainter({required this.t, required this.reduced, required this.color});
  final double t;
  final bool reduced;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    if (!reduced) {
      final ct = Curves.easeOut.transform(t);
      for (final b in _confettiBits) {
        final dist = b.speed * size.width * 0.62 * ct;
        final gravity = size.height * 0.55 * t * t;
        final pos = Offset(
          center.dx + math.cos(b.angle) * dist,
          center.dy + math.sin(b.angle) * dist + gravity - size.height * 0.06,
        );
        final fade = t < 0.65 ? 1.0 : (1 - (t - 0.65) / 0.35).clamp(0.0, 1.0);
        if (fade <= 0) continue;
        final paint = Paint()..color = b.color.withValues(alpha: fade);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(b.spin * t);
        if (b.rect) {
          canvas.drawRect(
              Rect.fromCenter(
                  center: Offset.zero, width: b.size, height: b.size * 0.5),
              paint);
        } else {
          canvas.drawCircle(Offset.zero, b.size * 0.4, paint);
        }
        canvas.restore();
      }
    }

    _paintCheckBadge(canvas, center, size.shortestSide * 0.22, color);
  }

  void _paintCheckBadge(Canvas canvas, Offset c, double r, Color color) {
    // Escala de entrada del disco (rebote suave). Con reduce, aparece directo.
    final grow = reduced
        ? (t * 2).clamp(0.0, 1.0)
        : Curves.easeOutBack.transform((t / 0.5).clamp(0.0, 1.0));
    final radius = r * grow;
    if (radius <= 0) return;

    canvas.drawCircle(
        c, radius, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawCircle(c, radius * 0.82, Paint()..color = color);

    // Trazo del cotejo: dibujado progresivamente entre t 0.30 y 0.72.
    final prog = reduced
        ? 1.0
        : ((t - 0.30) / 0.42).clamp(0.0, 1.0);
    if (prog <= 0) return;
    final s = radius * 0.82;
    final p1 = c + Offset(-0.42, 0.02) * s;
    final p2 = c + Offset(-0.12, 0.34) * s;
    final p3 = c + Offset(0.44, -0.30) * s;
    _paintPolyProgress(canvas, [p1, p2, p3], prog,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_AcceptPainter old) => old.t != t || old.color != color;
}

/// Dibuja una polilínea hasta [prog] (0..1) de su longitud total.
void _paintPolyProgress(
    Canvas canvas, List<Offset> pts, double prog, Paint paint) {
  final segLens = <double>[];
  var total = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    final l = (pts[i + 1] - pts[i]).distance;
    segLens.add(l);
    total += l;
  }
  var target = total * prog;
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 0; i < segLens.length; i++) {
    if (target <= 0) break;
    final l = segLens[i];
    if (target >= l) {
      path.lineTo(pts[i + 1].dx, pts[i + 1].dy);
      target -= l;
    } else {
      final f = target / l;
      final p = Offset.lerp(pts[i], pts[i + 1], f)!;
      path.lineTo(p.dx, p.dy);
      target = 0;
    }
  }
  canvas.drawPath(path, paint);
}

// ---------------------------------------------------------------------------
// Candado abriéndose (desbloqueo pagado).
// ---------------------------------------------------------------------------

class _UnlockPainter extends CustomPainter {
  _UnlockPainter({required this.t, required this.reduced, required this.color});
  final double t;
  final bool reduced;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.22;

    // Disco de fondo (rebote de entrada).
    final grow = reduced
        ? (t * 2).clamp(0.0, 1.0)
        : Curves.easeOutBack.transform((t / 0.5).clamp(0.0, 1.0));
    final radius = r * grow;
    if (radius <= 0) return;
    canvas.drawCircle(
        c, radius, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawCircle(c, radius * 0.82, Paint()..color = color);

    // Anillo de brillo que se expande al abrir (fase final).
    if (!reduced) {
      final ringProg = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
      if (ringProg > 0) {
        final rr = radius * (0.82 + ringProg * 0.9);
        canvas.drawCircle(
            c,
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = radius * 0.10 * (1 - ringProg)
              ..color =
                  color.withValues(alpha: 0.55 * (1 - ringProg)));
      }
    }

    _paintPadlock(canvas, c, radius * 0.82);
  }

  void _paintPadlock(Canvas canvas, Offset c, double s) {
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Cuerpo del candado (rectángulo redondeado) — no se mueve.
    final bodyW = s * 0.92;
    final bodyH = s * 0.72;
    final bodyTop = c.dy - s * 0.02;
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(c.dx - bodyW / 2, bodyTop, bodyW, bodyH),
        Radius.circular(s * 0.16));
    canvas.drawRRect(body, white);

    // Ojo de la cerradura, en el color del disco (contraste sobre el blanco).
    final keyPaint = Paint()..color = color;
    final keyC = Offset(c.dx, bodyTop + bodyH * 0.42);
    canvas.drawCircle(keyC, s * 0.11, keyPaint);
    canvas.drawRect(
        Rect.fromLTWH(keyC.dx - s * 0.045, keyC.dy, s * 0.09, s * 0.20),
        keyPaint);

    // Arco (shackle): pivota sobre su pata derecha para "abrirse".
    final arcW = s * 0.52;
    final legLen = s * 0.42;
    final pivot = Offset(c.dx + arcW / 2, bodyTop + s * 0.02);
    final open = reduced
        ? 1.0
        : Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
    final theta = -0.95 * open; // gira hacia afuera al abrir

    // Semicírculo SUPERIOR explícito (ángulos, no `arcToPoint`, para no
    // depender de la ambigüedad del flag clockwise en y-hacia-abajo): centro
    // en (-arcW/2, -legLen), empieza en el ángulo 0 (pata derecha, y = -legLen)
    // y barre -π → pasa por arriba (-y) hasta la pata izquierda.
    final shackle = Path()
      ..moveTo(0, 0) // pata derecha (en el pivote)
      ..lineTo(0, -legLen)
      ..arcTo(
          Rect.fromCircle(
              center: Offset(-arcW / 2, -legLen), radius: arcW / 2),
          0,
          -math.pi,
          false)
      ..lineTo(-arcW, 0);

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(theta);
    canvas.drawPath(shackle, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnlockPainter old) =>
      old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Oferta enviada (proveedor): la MASCOTA celebrando + confeti, un poco más
// grande que el éxito de crear solicitud (pedido PO 2026-07-20).
// ---------------------------------------------------------------------------

Future<void> showOfferSentCelebration(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .40),
    barrierLabel: 'Oferta enviada',
    transitionDuration: JayaloMotion.fast,
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (_, _, _) => const _OfferSentOverlay(),
  );
}

class _OfferSentOverlay extends StatefulWidget {
  const _OfferSentOverlay();
  @override
  State<_OfferSentOverlay> createState() => _OfferSentOverlayState();
}

class _OfferSentOverlayState extends State<_OfferSentOverlay> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Deja terminar el confeti (1.8 s) antes de cerrar y navegar.
    final ms = JayaloMotion.reduced(context) ? 700 : 2000;
    Future.delayed(Duration(milliseconds: ms), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = JayaloMotion.reduced(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (mounted) Navigator.of(context).maybePop();
      },
      child: Stack(children: [
        if (!reduced)
          const Positioned.fill(child: IgnorePointer(child: ConfettiBurst())),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Más grande que el éxito de solicitud (96) — pedido PO.
              JayaloMascotFace(size: 128, mood: MascotMood.celebrate)
                  .animate()
                  .scale(
                      begin: const Offset(.7, .7),
                      end: const Offset(1, 1),
                      duration: 260.ms,
                      curve: Curves.easeOutBack),
              const SizedBox(height: 18),
              Text('¡Oferta enviada!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: jayaloHead(context))),
              const SizedBox(height: 8),
              Text('Te avisamos si te aceptan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Confeti propio (sin dependencias): ~40 partículas de la paleta cayendo con
/// giro, entrada escalonada y fundido, una sola vez, ~1.8 s. Se movió aquí
/// desde `request_success_view.dart` para reusarlo también en la oferta enviada.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(
                _c.value, Theme.of(context).colorScheme.primary),
            size: Size.infinite),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.primary);
  final double t;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7); // semilla fija: la misma lluvia, solo avanza t
    final colors = [
      primary,
      const Color(0xFFEF9F27),
      const Color(0xFFD4537E),
      const Color(0xFF1D9E75),
    ];
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final drift = (rnd.nextDouble() - .5) * 90;
      final y0 = size.height * (.02 + rnd.nextDouble() * .2);
      final dist = size.height * (.35 + rnd.nextDouble() * .35);
      final spinSeed = rnd.nextDouble() * 6.3;
      final spinDir = rnd.nextBool() ? 6 : -6;
      final s = 6.0 + rnd.nextDouble() * 6;
      final delay = rnd.nextDouble() * .35;
      final tl = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (tl <= 0) continue;
      final fall = Curves.easeIn.transform(tl);
      final fade = (1 - Curves.easeIn.transform(tl)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x + drift * tl, y0 + dist * fall);
      canvas.rotate(spinSeed + tl * spinDir);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: s, height: s * .6),
              const Radius.circular(2)),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
