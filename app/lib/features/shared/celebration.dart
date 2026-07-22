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
import '../../core/sfx.dart';
import 'jayalo_loader.dart';

/// Overlay del candado abriéndose (desbloqueo pagado).
Future<void> showUnlockCelebration(BuildContext context) =>
    _showCelebration(context, _CelebrationKind.unlock);

/// Overlay de confeti + cotejo (oferta aceptada, gratis). `footer` (pedido PO
/// 2026-07-22): contenido que aparece DENTRO de la misma ventana violeta,
/// debajo de la animación (ej. el aviso de "Cuida tu reputación" + su botón).
/// Cuando se pasa, la celebración NO se auto-cierra: espera a que el footer la
/// cierre con el callback `dismiss`.
Future<void> showAcceptCelebration(
  BuildContext context, {
  Widget Function(VoidCallback dismiss)? footer,
}) =>
    _showCelebration(context, _CelebrationKind.accept, footer: footer);

enum _CelebrationKind { unlock, accept }

/// Rediseño PO 2026-07-21: "el fondo violeta entra desde arriba, se forma el
/// círculo del cotejo y explota el confetti; ícono blanco, letra blanca" —
/// para aceptar Y para desbloquear. Pantalla completa violeta que baja desde
/// el tope (reemplaza el modal blanco con zoom de la iteración anterior).
Future<void> _showCelebration(
  BuildContext context,
  _CelebrationKind kind, {
  Widget Function(VoidCallback dismiss)? footer,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent, // el violeta cubre todo: sin velo extra
    barrierLabel:
        kind == _CelebrationKind.accept ? 'Oferta aceptada' : 'Contacto desbloqueado',
    transitionDuration: const Duration(milliseconds: 420),
    transitionBuilder: _slideFromTopTransition,
    pageBuilder: (_, _, _) => _CelebrationOverlay(kind: kind, footer: footer),
  );
}

/// Entrada de las celebraciones: el panel violeta BAJA desde arriba de la
/// pantalla (ease-out, frena al llegar) y al cerrarse vuelve a subir.
Widget _slideFromTopTransition(BuildContext context, Animation<double> anim,
    Animation<double> secondaryAnimation, Widget child) {
  final offset = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
      .animate(CurvedAnimation(
          parent: anim,
          curve: JayaloMotion.enter,
          reverseCurve: JayaloMotion.exit));
  return SlideTransition(position: offset, child: child);
}

/// Transición compartida de las celebraciones (pedido PO): el modal entra con
/// un ZOOM IN (con un pequeño rebote) y sale con ZOOM OUT, acompañado de un
/// fundido del fondo. `easeOutBack` da el pop de entrada; al revertir la ruta,
/// la escala baja de vuelta = zoom out.
Widget _zoomModalTransition(BuildContext context, Animation<double> anim,
    Animation<double> secondaryAnimation, Widget child) {
  final scale = Tween<double>(begin: .82, end: 1).animate(CurvedAnimation(
      parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn));
  return FadeTransition(
    opacity: anim,
    child: ScaleTransition(scale: scale, child: child),
  );
}

/// Tarjeta-modal blanca de bordes redondeados que contiene la celebración
/// (pedido PO: "un modal con fondo blanco, bordes redondeados"). Recorta su
/// contenido al radio para que el confeti/animación queden dentro.
class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _CelebrationOverlay extends StatefulWidget {
  const _CelebrationOverlay({required this.kind, this.footer});
  final _CelebrationKind kind;
  final Widget Function(VoidCallback dismiss)? footer;
  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        // Con footer NO se auto-cierra: revela el aviso y espera su botón.
        if (widget.footer != null) {
          setState(() => _revealed = true);
        } else {
          Navigator.of(context).maybePop();
        }
      }
    });
  bool _started = false;
  bool _revealed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La duración se fija una vez, aquí, porque depende de "reducir
    // animaciones" del sistema (necesita context).
    if (_started) return;
    _started = true;
    final reduced = JayaloMotion.reduced(context);
    final accept = widget.kind == _CelebrationKind.accept;
    // Con movimiento: círculo que se forma → cotejo → explosión de confeti más
    // larga (accept, pedido PO "confetti de mayor duración") / candado que se
    // abre + halo, ventana de 4 s (unlock, pedido PO). Con reduce: destello
    // estático breve.
    _ctrl.duration = reduced
        ? const Duration(milliseconds: 600)
        : (accept
            ? const Duration(milliseconds: 3000)
            : const Duration(milliseconds: 4000));
    _ctrl.forward();
    // Sonido de la celebración (pedido PO 2026-07-21: sonido en ambas). El
    // audio es decorativo — playSfx nunca lanza.
    if (!reduced) {
      playSfx(accept ? Sfx.offerAccepted : Sfx.unlock);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _skip() {
    if (!mounted) return;
    // Con footer, tocar adelanta la animación para mostrar el aviso (no cierra
    // — el cierre es responsabilidad del botón del footer).
    if (widget.footer != null) {
      if (!_revealed) setState(() => _revealed = true);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = JayaloMotion.reduced(context);
    final violet = _brandPrimary(context);
    final accept = widget.kind == _CelebrationKind.accept;
    return GestureDetector(
      key: ValueKey('celebration-${widget.kind.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      // Pantalla COMPLETA violeta (pedido PO): ícono y letra en blanco.
      child: Container(
        color: violet,
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 280,
                height: 280,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, _) => accept
                      ? CustomPaint(
                          painter: _AcceptPainter(
                              t: _ctrl.value, reduced: reduced, bg: violet),
                          size: const Size(280, 280),
                        )
                      : _UnlockLockAnimation(t: _ctrl.value, reduced: reduced),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                accept ? '¡Oferta aceptada!' : '¡Contacto desbloqueado!',
                textAlign: TextAlign.center,
                // Misma tipografía de marca que el resto de títulos (hereda la
                // familia del textTheme); blanca sobre el violeta. Pedido PO.
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              )
                  .animate()
                  .fadeIn(duration: JayaloMotion.base, delay: 350.ms)
                  .slideY(
                      begin: .25,
                      end: 0,
                      duration: JayaloMotion.base,
                      delay: 350.ms,
                      curve: JayaloMotion.enter),
              // Aviso dentro de la misma ventana violeta (pedido PO 2026-07-22):
              // aparece cuando termina (o se adelanta) la animación.
              if (_revealed && widget.footer != null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: widget.footer!(() {
                    if (mounted) Navigator.of(context).maybePop();
                  }),
                ).animate().fadeIn(duration: JayaloMotion.base).slideY(
                      begin: .15,
                      end: 0,
                      duration: JayaloMotion.base,
                      curve: JayaloMotion.enter,
                    ),
            ],
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

/// Paleta festiva anclada a la marca (nada de arcoíris de payaso). Sobre el
/// FONDO VIOLETA de la celebración el violeta de acción desaparecería, así que
/// su lugar lo toma el blanco: blanco, verde de éxito, un azul claro, un
/// dorado cálido y un rosa suave — cinco tonos que se leen sobre el violeta.
const _confettiPalette = <Color>[
  Colors.white,
  JayaloColors.success, // verde de éxito
  Color(0xFF7FBCFF), // azul claro
  Color(0xFFF2B705), // dorado cálido
  Color(0xFFEE6C9B), // rosa suave
];

final List<_Bit> _confettiBits = _buildBits();

List<_Bit> _buildBits() {
  final rnd = math.Random(7); // semilla fija → determinista (y testeable)
  // Ráfaga más tupida (PO 2026-07-21: "confetti de mayor duración" — junto con
  // la ventana de aceptar ampliada a 3 s, cae más y por más tiempo).
  return List.generate(46, (i) {
    final angle = rnd.nextDouble() * math.pi * 2;
    final speed = 0.45 + rnd.nextDouble() * 0.55;
    final size = 6.0 + rnd.nextDouble() * 7.0;
    final color = _confettiPalette[i % _confettiPalette.length];
    final spin = (rnd.nextDouble() * 2 - 1) * math.pi * 3;
    return _Bit(angle, speed, size, color, spin, rnd.nextBool());
  });
}

/// Cotejo sobre el fondo violeta (pedido PO 2026-07-21): primero SE FORMA EL
/// CÍRCULO (un anillo blanco que se dibuja barriendo), luego el cotejo se
/// traza, y al completarse EXPLOTA el confetti. Todo el ícono en blanco.
class _AcceptPainter extends CustomPainter {
  _AcceptPainter({required this.t, required this.reduced, required this.bg});
  final double t;
  final bool reduced;

  /// El violeta del fondo (para tintes translúcidos coherentes).
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.24;

    // 1. El anillo se forma: barrido de 360° entre t 0 y 0.32 (arranca arriba).
    final ringProg = reduced
        ? 1.0
        : Curves.easeInOut.transform((t / 0.32).clamp(0.0, 1.0));
    if (ringProg > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          -math.pi / 2,
          math.pi * 2 * ringProg,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.12
            ..strokeCap = StrokeCap.round
            ..color = Colors.white);
    }
    // Relleno sutil dentro del anillo cuando ya cerró (asienta el cotejo).
    if (ringProg >= 1) {
      canvas.drawCircle(
          c, r * 0.90, Paint()..color = Colors.white.withValues(alpha: .12));
    }

    // 2. El cotejo se traza entre t 0.30 y 0.52.
    final prog = reduced ? 1.0 : ((t - 0.30) / 0.22).clamp(0.0, 1.0);
    if (prog > 0) {
      final s = r * 0.82;
      final p1 = c + Offset(-0.42, 0.02) * s;
      final p2 = c + Offset(-0.12, 0.34) * s;
      final p3 = c + Offset(0.44, -0.30) * s;
      _paintPolyProgress(canvas, [p1, p2, p3], prog,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.14
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }

    // 3. Al completarse el cotejo EXPLOTA el confetti (t 0.5 → 1).
    if (!reduced) {
      final ct = Curves.easeOut.transform(((t - 0.5) / 0.5).clamp(0.0, 1.0));
      if (ct > 0) {
        for (final b in _confettiBits) {
          final dist = b.speed * size.width * 0.72 * ct;
          final gravity = size.height * 0.35 * ct * ct;
          final pos = Offset(
            c.dx + math.cos(b.angle) * dist,
            c.dy + math.sin(b.angle) * dist + gravity - size.height * 0.04,
          );
          final fade =
              ct < 0.6 ? 1.0 : (1 - (ct - 0.6) / 0.4).clamp(0.0, 1.0);
          if (fade <= 0) continue;
          final paint = Paint()..color = b.color.withValues(alpha: fade);
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(b.spin * ct);
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
    }
  }

  @override
  bool shouldRepaint(_AcceptPainter old) => old.t != t || old.bg != bg;
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
//
// Rediseño PO 2026-07-21: el candado dibujado a mano quedaba DEFORME (el arco
// pivotaba y se despegaba del cuerpo). Se reemplaza por los GLIFOS de Material
// (`Icons.lock_rounded` → `Icons.lock_open_rounded`) — geometría impecable por
// construcción, imposible de deformar — animados con un cross-fade y un pop, un
// halo y unas chispas pintadas detrás. La ventana dura 4 s (ver duración del
// controlador). Sin paquete de animación externo: los glifos SON la "librería".
// ---------------------------------------------------------------------------

/// El candado cerrado (que entra con rebote), se abre con un POP y suelta un
/// halo + chispas; luego respira suave hasta cerrar la ventana de 4 s.
/// Recibe [t] 0..1 del controlador de la celebración.
class _UnlockLockAnimation extends StatelessWidget {
  const _UnlockLockAnimation({required this.t, required this.reduced});
  final double t;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    // Entrada con rebote (0 → 0.18).
    final appear = reduced
        ? 1.0
        : Curves.easeOutBack.transform((t / 0.18).clamp(0.0, 1.0));

    // Anticipación: un leve bamboleo justo antes de abrir (0.18 → 0.30).
    double rot = 0;
    if (!reduced && t > 0.18 && t < 0.30) {
      rot = math.sin(((t - 0.18) / 0.12) * math.pi * 2) * 0.09;
    }

    // Cross-fade cerrado→abierto centrado en t≈0.30.
    final openT =
        reduced ? 1.0 : ((t - 0.27) / 0.06).clamp(0.0, 1.0);

    // POP al abrir: un pequeño salto de escala en forma de campana (0.28→0.42).
    double pop = 1.0;
    if (!reduced) {
      final p = ((t - 0.28) / 0.14).clamp(0.0, 1.0);
      pop = 1 + math.sin(p * math.pi) * 0.16;
    }

    // Respiración suave en la cola (0.55→1) para que los 4 s no se sientan
    // muertos.
    double breathe = 1.0;
    if (!reduced && t > 0.55) {
      breathe = 1 + math.sin((t - 0.55) * math.pi * 2 * 1.1) * 0.02;
    }

    final scale = appear * pop * breathe;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (!reduced)
          Positioned.fill(child: CustomPaint(painter: _UnlockGlowPainter(t))),
        Transform.rotate(
          angle: rot,
          child: Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Candado CERRADO (se desvanece al abrir).
                Opacity(
                  opacity: 1 - openT,
                  child: const Icon(Icons.lock_rounded,
                      size: 150, color: Colors.white),
                ),
                // Candado ABIERTO (aparece).
                Opacity(
                  opacity: openT,
                  child: const Icon(Icons.lock_open_rounded,
                      size: 150, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Halo blanco que se expande al abrir + un puñado de chispas radiales.
/// Detrás del glifo del candado; todo en blanco sobre el violeta del fondo.
class _UnlockGlowPainter extends CustomPainter {
  _UnlockGlowPainter(this.t);
  final double t;

  static final _sparkleAngles = List<double>.generate(
      8, (i) => -math.pi / 2 + i * (math.pi * 2 / 8) + 0.2);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide * 0.20;

    // Halo: un anillo que crece y se desvanece al abrir (0.30 → 0.72).
    final ringT = ((t - 0.30) / 0.42).clamp(0.0, 1.0);
    if (ringT > 0 && ringT < 1) {
      final rr = base * (1.2 + ringT * 1.7);
      canvas.drawCircle(
          c,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = base * 0.14 * (1 - ringT)
            ..color = Colors.white.withValues(alpha: 0.55 * (1 - ringT)));
    }

    // Chispas: salen disparadas al abrir y se apagan (0.30 → 0.65).
    final sparkT = ((t - 0.30) / 0.35).clamp(0.0, 1.0);
    if (sparkT > 0 && sparkT < 1) {
      final eased = Curves.easeOut.transform(sparkT);
      final fade = (1 - sparkT).clamp(0.0, 1.0);
      final paint = Paint()..color = Colors.white.withValues(alpha: fade);
      for (final a in _sparkleAngles) {
        final dist = base * (1.1 + eased * 1.6);
        final p = c + Offset(math.cos(a), math.sin(a)) * dist;
        canvas.drawCircle(p, base * 0.09 * (1 - sparkT * 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_UnlockGlowPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Oferta enviada (proveedor): la MASCOTA celebrando + confeti, un poco más
// grande que el éxito de crear solicitud (pedido PO 2026-07-20).
// ---------------------------------------------------------------------------

/// Estrella + "¡Gracias por tu calificación!" tras enviar una calificación
/// (pedido PO 2026-07-21). Modal blanco efímero que se auto-cierra.
Future<void> showRatingThanks(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: .45),
    barrierLabel: 'Gracias por tu calificación',
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: _zoomModalTransition,
    pageBuilder: (_, _, _) => const _RatingThanksOverlay(),
  );
}

class _RatingThanksOverlay extends StatefulWidget {
  const _RatingThanksOverlay();
  @override
  State<_RatingThanksOverlay> createState() => _RatingThanksOverlayState();
}

class _RatingThanksOverlayState extends State<_RatingThanksOverlay> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final ms = JayaloMotion.reduced(context) ? 800 : 1800;
    Future.delayed(Duration(milliseconds: ms), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = JayaloMotion.reduced(context);
    const gold = Color(0xFFF2B705);
    Widget star = const Icon(Icons.star_rounded, size: 96, color: gold);
    if (!reduced) {
      star = star
          .animate()
          .scale(
              begin: const Offset(.3, .3),
              end: const Offset(1, 1),
              duration: 480.ms,
              curve: Curves.elasticOut)
          .then()
          .shimmer(duration: 900.ms, color: Colors.white);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (mounted) Navigator.of(context).maybePop();
      },
      child: Center(
        child: _CelebrationCard(
          child: SizedBox(
            width: 280,
            height: 220,
            child: Stack(alignment: Alignment.center, children: [
              if (!reduced)
                const Positioned.fill(
                    child: IgnorePointer(child: ConfettiBurst())),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  star,
                  const SizedBox(height: 12),
                  Text('¡Gracias por tu calificación!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                  const SizedBox(height: 4),
                  Text('Tu opinión ayuda a la comunidad.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

Future<void> showOfferSentCelebration(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .40),
    barrierLabel: 'Oferta enviada',
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: _zoomModalTransition,
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
      child: Center(
        // Modal blanco de bordes redondeados (pedido PO): el confeti vive
        // DENTRO de la tarjeta, recortado a sus esquinas.
        child: _CelebrationCard(
          child: SizedBox(
            width: 300,
            height: 300,
            child: Stack(alignment: Alignment.center, children: [
              if (!reduced)
                const Positioned.fill(
                    child: IgnorePointer(child: ConfettiBurst())),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  JayaloMascotFace(size: 120, mood: MascotMood.celebrate)
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
            ]),
          ),
        ),
      ),
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
