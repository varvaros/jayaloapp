/// Celebraciones de motion graphics para las DOS confirmaciones deliberadas
/// de la app (doctrina PO 2026-07-20 "hold en ambos, con distinción visual"):
///
///   • [showUnlockCelebration] — acción PAGADA (desbloquear contacto): la
///     MASCOTA celebrando + ráfaga de confeti + mensaje juguetón (rediseño PO
///     2026-07-22; antes era un candado abriéndose). El premio de haber
///     gastado créditos.
///   • [showAcceptCelebration] — acción GRATIS (aceptar una oferta): confeti
///     + un cotejo que se dibuja solo. El premio de cerrar el trato.
///
/// Además vive aquí [HoldMascotLayer]: la mascota que se INFLA al ritmo del
/// hold-to-confirm del desbloqueo y hace "¡PUM!" al completarse (pedido PO
/// 2026-07-22). Escucha el progreso REAL del [HoldToConfirmButton] — cero
/// timers propios de conteo.
///
/// Todo se pinta a mano con [CustomPainter] sobre los tokens de [JayaloMotion]
/// — sin paquetes de confeti/lottie (doctrina "mínimo, no replicar wrappers").
/// Se muestran como un overlay efímero por el navigator raíz: se auto-cierra al
/// terminar la animación y se puede saltar tocando la pantalla. Con "reducir
/// animaciones" del sistema cae a un destello estático breve.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/sfx.dart';
import 'jayalo_loader.dart';

/// Overlay de la mascota celebrando (desbloqueo pagado). `footer` (pedido PO
/// 2026-07-23): el botón de "¡Iniciar conversación!" vive DENTRO de la misma
/// pantalla violeta — sin hoja de contacto intermedia. Con footer la
/// celebración NO se auto-cierra: espera al botón (via `dismiss`).
Future<void> showUnlockCelebration(
  BuildContext context, {
  Widget Function(VoidCallback dismiss)? footer,
}) => _showCelebration(context, _CelebrationKind.unlock, footer: footer);

/// Overlay de confeti + cotejo (oferta aceptada, gratis). `footer` (pedido PO
/// 2026-07-22): contenido que aparece DENTRO de la misma ventana violeta,
/// debajo de la animación (ej. el aviso de "Cuida tu reputación" + su botón).
/// Cuando se pasa, la celebración NO se auto-cierra: espera a que el footer la
/// cierre con el callback `dismiss`.
Future<void> showAcceptCelebration(
  BuildContext context, {
  Widget Function(VoidCallback dismiss)? footer,
}) => _showCelebration(context, _CelebrationKind.accept, footer: footer);

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
    barrierLabel: kind == _CelebrationKind.accept
        ? 'Oferta aceptada'
        : 'Contacto desbloqueado',
    transitionDuration: const Duration(milliseconds: 420),
    transitionBuilder: _slideFromTopTransition,
    pageBuilder: (_, _, _) => _CelebrationOverlay(kind: kind, footer: footer),
  );
}

/// Entrada de las celebraciones: el panel violeta BAJA desde arriba de la
/// pantalla (ease-out, frena al llegar) y al cerrarse vuelve a subir.
Widget _slideFromTopTransition(
  BuildContext context,
  Animation<double> anim,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final offset = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
      .animate(
        CurvedAnimation(
          parent: anim,
          curve: JayaloMotion.enter,
          reverseCurve: JayaloMotion.exit,
        ),
      );
  return SlideTransition(position: offset, child: child);
}

/// Transición compartida de las celebraciones (pedido PO): el modal entra con
/// un ZOOM IN (con un pequeño rebote) y sale con ZOOM OUT, acompañado de un
/// fundido del fondo. `easeOutBack` da el pop de entrada; al revertir la ruta,
/// la escala baja de vuelta = zoom out.
Widget _zoomModalTransition(
  BuildContext context,
  Animation<double> anim,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final scale = Tween<double>(begin: .82, end: 1).animate(
    CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    ),
  );
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
          _dismissOnce();
        }
      }
    });
  bool _started = false;
  bool _revealed = false;
  bool _closed = false;

  /// ÚNICO camino de cierre del overlay. El latch evita el DOBLE pop (bug
  /// pantalla negra 2026-07-23): tocar para saltar arranca la transición de
  /// salida (~420 ms) pero el State sigue `mounted` hasta que la ruta muere —
  /// si el controlador completaba en esa ventana, el segundo `maybePop` ya no
  /// encontraba la celebración arriba y se llevaba la ruta del SHELL →
  /// navigator vacío → pantalla negra congelada (mismo over-pop que el error
  /// de BackGuard capturado en error_events el 2026-07-22).
  void _dismissOnce() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).maybePop();
  }

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
    // larga (accept, pedido PO "confetti de mayor duración") / la mascota
    // celebrando + confeti, ventana corta (unlock, PO 2026-07-22: "la
    // animación y el mensaje deben ser rápidos para no retrasar el acceso al
    // contacto"). Con reduce: destello estático breve.
    _ctrl.duration = reduced
        ? const Duration(milliseconds: 600)
        : (accept
              ? const Duration(milliseconds: 3000)
              : const Duration(milliseconds: 2600));
    _ctrl.forward();
    // Golpe en la mano. Va FUERA del `if (!reduced)` a propósito: "reducir
    // animaciones" es una preferencia de MOVIMIENTO, no de vibración — el
    // criterio está razonado en `JayaloHaptics`. Justo a quien apagó las
    // animaciones es a quien menos hay que quitarle la confirmación.
    JayaloHaptics.success();
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
    _dismissOnce();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = JayaloMotion.reduced(context);
    final violet = _brandPrimary(context);
    final accept = widget.kind == _CelebrationKind.accept;
    // Título del desbloqueo en Nunito (la redondeada de la marca en la web) y
    // SIN línea bajo el texto (pedido PO 2026-07-22): `decoration: none`
    // explícito + el Material transparente de abajo matan el subrayado
    // amarillo que aparece en overlays sin Material ancestro.
    final titleStyle = accept
        ? Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          )
        : const TextStyle(
            fontFamily: 'Nunito',
            fontVariations: [FontVariation('wght', 800)],
            fontWeight: FontWeight.w800,
            fontSize: 26,
            color: Colors.white,
            decoration: TextDecoration.none,
          );
    return GestureDetector(
      key: ValueKey('celebration-${widget.kind.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      // Pantalla COMPLETA violeta (pedido PO): ícono y letra en blanco. El
      // Material transparente da el DefaultTextStyle sano (sin subrayados).
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: violet), // pantalla COMPLETA violeta
            // UNA sola explosión de confeti a PANTALLA COMPLETA que cae con
            // física real hasta salir por abajo (pedido PO 2026-07-23). Detrás
            // del contenido y sin robar toques.
            if (!reduced)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, _) => CustomPaint(
                      painter: _ConfettiField(
                        seconds:
                            (_ctrl.lastElapsedDuration ?? Duration.zero)
                                .inMicroseconds /
                            1e6,
                        bits: _celebBits,
                        flash: true,
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // La mascota Jayi celebrando (Lottie), variante BLANCA para
                    // resaltar sobre el violeta a pantalla completa.
                    SizedBox(
                      width: 230,
                      height: 230,
                      child: JayiCelebration(
                        onViolet: true,
                        size: 230,
                        semanticsLabel: accept
                            ? 'Oferta aceptada'
                            : 'Contacto desbloqueado',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                          accept
                              ? '¡Oferta aceptada!'
                              : '¡Contacto desbloqueado!',
                          textAlign: TextAlign.center,
                          style: titleStyle,
                        )
                        .animate()
                        .fadeIn(duration: JayaloMotion.base, delay: 350.ms)
                        .slideY(
                          begin: .25,
                          end: 0,
                          duration: JayaloMotion.base,
                          delay: 350.ms,
                          curve: JayaloMotion.enter,
                        ),
                    // Mensaje juguetón de la mascota (pedido PO 2026-07-22): corto
                    // y rápido, para no retrasar el acceso al contacto.
                    if (!accept)
                      Padding(
                            padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
                            child: Text(
                              '¡Yeiii! ¡Ahora sí! ¡Ahora ve por esa venta!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontVariations: const [
                                  FontVariation('wght', 700),
                                ],
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                                height: 1.35,
                                color: Colors.white.withValues(alpha: .92),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(duration: JayaloMotion.base, delay: 600.ms)
                          .slideY(
                            begin: .3,
                            end: 0,
                            duration: JayaloMotion.base,
                            delay: 600.ms,
                            curve: JayaloMotion.enter,
                          ),
                    // Aviso dentro de la misma ventana violeta (pedido PO
                    // 2026-07-22): aparece cuando termina (o se adelanta) la
                    // animación.
                    if (_revealed && widget.footer != null)
                      Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: widget.footer!(_dismissOnce),
                          )
                          .animate()
                          .fadeIn(duration: JayaloMotion.base)
                          .slideY(
                            begin: .15,
                            end: 0,
                            duration: JayaloMotion.base,
                            curve: JayaloMotion.enter,
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _brandPrimary(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? JayaloColors.dPrimary
    : JayaloColors.primary;

/// La mascota **Jayi celebrando** (salto con squash, parpadeo, antenas y brazos
/// animados) — animación Lottie exportada del SVG de Adobe Animate del PO y
/// convertida con el conversor propio (pedido PO 2026-07-23). Reemplaza al
/// [JayaloMascotFace] en modo `celebrate` de las pantallas de éxito.
///
/// [onViolet] elige la variante de color, con el mismo criterio que antes
/// invertía `bodyColor`/`inkColor`:
///   • `false` (por defecto) → Jayi violeta, para fondos claros (tarjeta de
///     "oferta enviada", éxito de crear solicitud).
///   • `true` → Jayi blanca con ojo/boca violeta, para el fondo violeta de la
///     celebración a pantalla completa (aceptar / desbloquear).
///
/// Con "reducir animaciones" del sistema queda quieta en el primer frame (pose
/// de reposo, brazos arriba).
class JayiCelebration extends StatelessWidget {
  const JayiCelebration({
    super.key,
    this.onViolet = false,
    this.size = 160,
    this.semanticsLabel,
    this.repeat = true,
  });

  final bool onViolet;
  final double size;
  final String? semanticsLabel;

  /// Si la mascota vuelve a empezar al terminar. Las celebraciones que se
  /// AUTO-CIERRAN la dejan en bucle (nunca llega a dar dos vueltas). La de
  /// recarga, que se queda en pantalla hasta que el proveedor decide, la pasa
  /// UNA vez y la deja en su pose: un salto perpetuo durante minutos cansa, y
  /// además deja el árbol animándose para siempre (`pumpAndSettle` no asienta).
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    final reduced = JayaloMotion.reduced(context);
    final asset = onViolet
        ? 'assets/anim/jayi_celebrando_blanco.json'
        : 'assets/anim/jayi_celebrando.json';
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: Lottie.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        repeat: repeat && !reduced,
        animate: !reduced,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confeti compartido de las celebraciones (aceptar y desbloquear).
// ---------------------------------------------------------------------------

class _Bit {
  const _Bit(
    this.angle,
    this.speed,
    this.size,
    this.color,
    this.spin,
    this.shape, {
    this.swayFreq = 0,
    this.swayPhase = 0,
  });
  final double angle; // dirección de disparo (rad)
  final double speed; // 0..1, velocidad inicial del estallido
  final double size; // lado/diámetro en px
  final Color color;
  final double spin; // giro por segundo
  final int shape; // 0 = serpentina, 1 = círculo, 2 = estrella
  final double swayFreq; // rad/s del vaivén tipo hoja al flotar
  final double swayPhase;
}

/// Estrella de 5 puntas (radio exterior 1, interior 1/2.5) construida UNA vez y
/// escalada por pieza — el confeti mezcla serpentinas, círculos y estrellas.
final Path _confettiStar = _buildStar();
Path _buildStar() {
  const points = 5;
  const ext = 1.0;
  const intR = 1.0 / 2.5;
  final step = 2 * math.pi / points;
  final half = step / 2;
  final p = Path()..moveTo(ext, 0);
  for (var a = 0.0; a < 2 * math.pi - 1e-6; a += step) {
    p.lineTo(math.cos(a) * ext, math.sin(a) * ext);
    p.lineTo(math.cos(a + half) * intR, math.sin(a + half) * intR);
  }
  p.close();
  return p;
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

/// Paleta para el confeti sobre fondo CLARO (tarjeta de oferta enviada, éxito
/// de crear solicitud): el violeta de marca sí se lee, más dorado, rosa y verde.
const _cardConfettiPalette = <Color>[
  JayaloColors.primary, // violeta de marca
  Color(0xFFF2B705), // dorado
  Color(0xFFEE6C9B), // rosa
  JayaloColors.success, // verde
];

final List<_Bit> _celebBits = _buildFieldBits(150, _confettiPalette, 7);
final List<_Bit> _cardBits = _buildFieldBits(80, _cardConfettiPalette, 11);

/// Piezas de una explosión: dirección radial + velocidad inicial, forma, giro y
/// un vaivén de "hoja que cae" propio de cada una (semilla fija → determinista).
List<_Bit> _buildFieldBits(int count, List<Color> palette, int seed) {
  final rnd = math.Random(seed);
  return List.generate(count, (i) {
    final angle = rnd.nextDouble() * math.pi * 2;
    final speed = 0.35 + rnd.nextDouble() * 0.9; // magnitud del estallido
    final size = 6.0 + rnd.nextDouble() * 12.0; // de chispas a serpentinas
    final color = palette[i % palette.length];
    final spin =
        (rnd.nextDouble() * 2 - 1) * (2 + rnd.nextDouble() * 3); // rad/s
    return _Bit(
      angle,
      speed,
      size,
      color,
      spin,
      rnd.nextInt(3),
      swayFreq: 2.0 + rnd.nextDouble() * 2.5,
      swayPhase: rnd.nextDouble() * 6.3,
    );
  });
}

/// UNA sola explosión de confeti con FÍSICA por tiempo real (pedido PO
/// 2026-07-23: "una sola explosión que explota, cae hasta salir de la pantalla,
/// flotando con física"):
///
///   • Estallido: cada pieza sale del centro con velocidad inicial radial.
///   • Arrastre de aire (drag lineal, cte [_k]): frena el estallido en ~0.4 s;
///     el desplazamiento integra a `v0·(1-e^{-k·t})/k` → el spread llega a un
///     límite y se detiene (deja de "volar").
///   • Gravedad → velocidad TERMINAL [_vt]: pasado el estallido todas caen a
///     ritmo parejo (flotan hacia abajo) hasta SALIR por el borde inferior.
///   • Vaivén lateral tipo hoja mientras flota + giro (aleteo de las planas).
///
/// Sin fundido: nada se desvanece en el aire — las piezas se van solo al cruzar
/// el borde de abajo. Se avanza con [seconds] = tiempo real transcurrido.
class _ConfettiField extends CustomPainter {
  _ConfettiField({
    required this.seconds,
    required this.bits,
    this.flash = false,
  });
  final double seconds;
  final List<_Bit> bits;
  final bool flash; // destello blanco inicial (solo sobre el fondo violeta)

  static const double _k = 2.8; // arrastre del aire (1/s)

  @override
  void paint(Canvas canvas, Size size) {
    if (seconds <= 0) return;
    final ox = size.width / 2;
    final oy = size.height * 0.42; // el estallido nace donde está la mascota
    final ex = (1 - math.exp(-_k * seconds)) / _k; // ∫ del decaimiento del drag
    final vt = size.height * 0.62; // velocidad terminal de caída (px/s)
    final swayIn = 1 - math.exp(-_k * seconds); // el vaivén entra al frenar

    // Destello inicial: anillo blanco que se expande y se apaga (~0.35 s).
    if (flash) {
      final ring = (seconds / 0.35).clamp(0.0, 1.0);
      if (ring < 1) {
        final rr = Curves.easeOut.transform(ring);
        canvas.drawCircle(
          Offset(ox, oy),
          size.shortestSide * (0.05 + rr * 0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.5, 7 * (1 - rr))
            ..color = Colors.white.withValues(alpha: 0.45 * (1 - rr)),
        );
      }
    }

    for (final b in bits) {
      // Velocidades iniciales del estallido (px/s), radiales desde el centro.
      final v0x = math.cos(b.angle) * b.speed * size.width * 2.2;
      final v0y = math.sin(b.angle) * b.speed * size.height * 1.1;
      // Posición integrando drag (horizontal) + drag→terminal (vertical).
      final sway =
          size.width *
          0.03 *
          math.sin(seconds * b.swayFreq + b.swayPhase) *
          swayIn;
      final px = ox + v0x * ex + sway;
      final py = oy + vt * seconds + (v0y - vt) * ex;
      if (py - b.size > size.height) continue; // ya salió por abajo
      final paint = Paint()..color = b.color; // SIN fundido
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(b.spin * seconds);
      switch (b.shape) {
        case 1: // círculo
          canvas.drawCircle(Offset.zero, b.size * 0.45, paint);
        case 2: // estrella
          canvas.scale(b.size * 0.62);
          canvas.drawPath(_confettiStar, paint);
        default: // serpentina que aletea (voltea sobre su eje) al caer
          canvas.scale(1, math.cos(b.spin * seconds * 1.6));
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: b.size * 1.3,
              height: b.size * 0.45,
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiField old) => old.seconds != seconds;
}

// ---------------------------------------------------------------------------
// La mascota que se INFLA con el hold de desbloqueo + "¡PUM!" (PO 2026-07-22).
// ---------------------------------------------------------------------------

/// Capa visual de la hoja "Desbloquear contacto": la mascota aparece al
/// empezar el hold y se infla al ritmo del progreso REAL del botón —
/// [progress] es el espejo del AnimationController del [HoldToConfirmButton]
/// (cero timers de conteo propios; si el usuario suelta, el mismo reverse del
/// botón la desinfla). Fases del PO sobre t lineal (2.5 s):
///
///   • 0 → 0.4: inflado suave (ease-out).
///   • 0.4 → 0.8: sigue inflando lineal + vibración ligera creciente.
///   • 0.8 → 1: llega al máximo, crecimiento frenado + más vibración =
///     tensión/anticipación.
///   • t == 1: "¡PUM!" — la única animación propia (la explosión, ~560 ms,
///     [JayaloMotion.mascotPum]) + un golpe háptico.
///
/// El inflado NO es solo escala: el progreso viaja como `inflate` a
/// [JayaloMascotFace], que redondea el cuerpo de "tele" a esfera y, pasada la
/// mitad, le cambia la cara de feliz a sorprendida (la "o"). Escalar sola se
/// leía como un zoom; lo que vende el aire es que la silueta cambie.
///
/// Va dentro de un IgnorePointer: jamás roba toques al botón. Con "reducir
/// animaciones" no se muestra nada.
class HoldMascotLayer extends StatefulWidget {
  const HoldMascotLayer({
    super.key,
    required this.progress,
    this.alignment = Alignment.center,
  });

  /// Progreso del hold (0→1) — el `progress` del [HoldToConfirmButton].
  final ValueListenable<double> progress;

  /// Dónde se ancla la mascota dentro de su caja, en coordenadas de [Alignment]
  /// (-1 = borde superior, 0 = centro, +1 = borde inferior).
  ///
  /// Sirve para las hojas que siguen posicionando la mascota SOBRE todo su
  /// contenido con una proporción (`inbox_screen` .12, `offer_actions` .60).
  ///
  /// El default es el centro porque el desbloqueo de contacto —que era el único
  /// que lo usaba— dejó de necesitarlo: su mascota ahora vive DENTRO de la
  /// columna, en el hueco que dejó el ícono del candado, dibujándose a través de
  /// un `OverflowBox` (ver `openUnlockSheet`). Ese camino es el bueno y quedó
  /// documentado ahí: clava la mascota al sitio exacto en cualquier tamaño de
  /// pantalla, mientras que una proporción sobre la hoja entera se desalinea
  /// según el alto del teléfono (la columna mide siempre lo mismo en px, la
  /// hoja crece). Las otras dos hojas conservan el modo proporcional porque su
  /// mascota no tiene que calzar con ningún elemento concreto.
  final Alignment alignment;

  @override
  State<HoldMascotLayer> createState() => _HoldMascotLayerState();
}

class _HoldMascotLayerState extends State<HoldMascotLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pum = AnimationController(
    vsync: this,
    duration: JayaloMotion.mascotPum,
  );
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onProgress);
  }

  void _onProgress() {
    if (_fired || widget.progress.value < 1) return;
    _fired = true;
    HapticFeedback.mediumImpact(); // el golpe del ¡PUM!
    _pum.forward();
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    _pum.dispose();
    super.dispose();
  }

  /// Escala de reposo (antes de presionar) y a lo largo del hold. La mascota
  /// ya está PRESENTE al abrir la hoja (pedido PO 2026-07-22: "que esté ahí
  /// desde que abre la ventana"), en reposo, y se infla con el progreso real.
  static const double _restScale = .62;

  @override
  Widget build(BuildContext context) {
    final reduced = JayaloMotion.reduced(context);
    // Con "reducir animaciones": la mascota está presente pero quieta (sin
    // inflado ni PUM) — sigue siendo la protagonista de la hoja.
    if (reduced) return _mascot(context, scale: _restScale);

    return AnimatedBuilder(
      animation: Listenable.merge([widget.progress, _pum]),
      builder: (context, _) {
        // Tras el PUM la mascota queda "congelada" en su máximo y explota;
        // antes, sigue el progreso vivo (incluida la reversa al soltar).
        final t = _fired ? 1.0 : widget.progress.value.clamp(0.0, 1.0);
        final b = _fired ? _pum.value : 0.0;

        // Escala por fases del PO (t es TIEMPO lineal del hold). En reposo
        // (t==0) parte de _restScale y de ahí se infla.
        double scale;
        if (t < .4) {
          scale =
              _restScale +
              (1.0 - _restScale) * Curves.easeOut.transform(t / .4); // suave
        } else if (t < .8) {
          scale = 1.0 + .55 * ((t - .4) / .4); // sigue inflando
        } else {
          // Frena el crecimiento: el aire "ya no cabe" — tensión.
          scale = 1.55 + .25 * Curves.easeIn.transform((t - .8) / .2);
        }
        // El PUM estira la escala un golpe más antes de desvanecerla.
        if (b > 0) scale *= 1 + .45 * Curves.easeOutCubic.transform(b);

        // Vibración: nace en la fase 2 y sube en la 3 (traslación + giro
        // diminutos a ~frecuencia de zumbido; t recorre 2.5 s).
        var wobble = Offset.zero;
        var jitter = 0.0;
        if (b == 0 && t > .4) {
          final amp = t < .8
              ? 1.6 * ((t - .4) / .4)
              : 1.6 + 1.9 * ((t - .8) / .2);
          wobble =
              Offset(
                math.sin(t * math.pi * 2 * 45),
                math.cos(t * math.pi * 2 * 38),
              ) *
              amp;
          jitter = math.sin(t * math.pi * 2 * 33) * .015 * (amp / 1.6);
        }

        // Solo el PUM la desvanece; en reposo y durante el hold está a plena
        // opacidad (ya no aparece al presionar — vive ahí desde el inicio).
        final opacity = b < .22
            ? 1.0
            : 1 - Curves.easeIn.transform(((b - .22) / .30).clamp(0.0, 1.0));

        return Stack(
          alignment: Alignment.center,
          children: [
            // Onda + partículas del PUM (detrás de la mascota).
            if (b > 0)
              Align(
                alignment: widget.alignment,
                child: CustomPaint(
                  size: const Size(300, 300),
                  painter: _PumPainter(
                    t: b,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            _mascot(
              context,
              scale: scale,
              opacity: opacity,
              wobble: wobble,
              jitter: jitter,
              // El cuerpo se redondea al ritmo del hold; tras el PUM `t` ya
              // quedó clavado en 1, así que explota bien inflada.
              inflate: t,
            ),
          ],
        );
      },
    );
  }

  /// La mascota (halo + cara feliz) en su posición de la hoja, con la
  /// transformación dada. Compartida por el reposo, el hold y reduce-motion.
  Widget _mascot(
    BuildContext context, {
    required double scale,
    double opacity = 1,
    Offset wobble = Offset.zero,
    double jitter = 0,
    double inflate = 0,
  }) {
    if (opacity <= 0) return const SizedBox.shrink();
    return Align(
      alignment: widget.alignment,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: wobble,
          child: Transform.rotate(
            angle: jitter,
            child: Transform.scale(
              scale: scale,
              // Un halo suave separa a la mascota del contenido de la hoja que
              // va tapando al inflarse.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: .85),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: JayaloMascotFace(
                    size: 92,
                    mood: MascotMood.happy,
                    inflate: inflate,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El "¡PUM!": una onda expansiva (anillo del violeta de acción) + partículas
/// de la paleta de marca que salen disparadas — pintado sobre el fondo CLARO
/// de la hoja (por eso no usa la paleta blanca del confeti del overlay).
class _PumPainter extends CustomPainter {
  _PumPainter({required this.t, required this.color});
  final double t; // 0..1 del controlador del PUM
  final Color color;

  static final List<_Bit> _bits = _buildPumBits();

  static List<_Bit> _buildPumBits() {
    final rnd = math.Random(3); // determinista
    const palette = <Color>[
      Color(0xFFF2B705), // dorado
      JayaloColors.success, // verde
      Color(0xFFEE6C9B), // rosa
      Color(0xFF7FBCFF), // azul claro
    ];
    return List.generate(14, (i) {
      final angle = rnd.nextDouble() * math.pi * 2;
      final speed = 0.55 + rnd.nextDouble() * 0.45;
      final size = 5.0 + rnd.nextDouble() * 6.0;
      final spin = (rnd.nextDouble() * 2 - 1) * math.pi * 3;
      return _Bit(
        angle,
        speed,
        size,
        palette[i % palette.length],
        spin,
        rnd.nextInt(3),
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide * 0.22;

    // Onda expansiva: crece y se apaga.
    final ring = Curves.easeOutCubic.transform(t);
    canvas.drawCircle(
      c,
      base * (0.9 + ring * 1.9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, base * 0.12 * (1 - ring))
        ..color = color.withValues(alpha: 0.5 * (1 - ring)),
    );

    // Partículas radiales con leve gravedad y fundido.
    final pt = Curves.easeOut.transform(t);
    for (final bit in _bits) {
      final dist = bit.speed * size.width * 0.45 * pt;
      final pos = Offset(
        c.dx + math.cos(bit.angle) * dist,
        c.dy + math.sin(bit.angle) * dist + size.height * 0.10 * pt * pt,
      );
      final fade = t < 0.55 ? 1.0 : (1 - (t - 0.55) / 0.45).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      final paint = Paint()..color = bit.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(bit.spin * pt);
      switch (bit.shape) {
        case 1: // círculo
          canvas.drawCircle(Offset.zero, bit.size * 0.4, paint);
        case 2: // estrella
          canvas.scale(bit.size * 0.55);
          canvas.drawPath(_confettiStar, paint);
        default: // rectángulo
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: bit.size,
              height: bit.size * 0.5,
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PumPainter old) => old.t != t || old.color != color;
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
            curve: Curves.elasticOut,
          )
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
            // Bug de layout (hallado 2026-08-01 al testear RatingPanel de
            // punta a punta): con 220 el título envuelve a 2 líneas en el
            // ancho de 232 disponibles y el Column desborda ~51px (con 260,
            // ~11px — el contenido real mide 223px de alto). 284 deja margen
            // de sobra sin desentonar con el resto de celebraciones
            // (_OfferSentOverlay usa 300, más holgado todavía).
            height: 284,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!reduced)
                  const Positioned.fill(
                    child: IgnorePointer(child: ConfettiBurst()),
                  ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      star,
                      const SizedBox(height: 12),
                      Text(
                        '¡Gracias por tu calificación!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tu opinión ayuda a la comunidad.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!reduced)
                  const Positioned.fill(
                    child: IgnorePointer(child: ConfettiBurst()),
                  ),
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const JayiCelebration(
                        size: 150,
                        semanticsLabel: 'Oferta enviada',
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '¡Oferta enviada!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: jayaloHead(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Te avisamos si te aceptan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Confeti propio (sin dependencias): UNA explosión desde el centro con física
/// real ([_ConfettiField]) que cae hasta SALIR del área, sin desvanecerse en el
/// aire. Se usa en la tarjeta de "oferta enviada", en el éxito de crear
/// solicitud y en la celebración de recarga.
///
/// [onViolet] elige la paleta con el mismo criterio que [JayiCelebration]:
///   • `false` (por defecto) → [_cardBits], para fondos CLAROS.
///   • `true` → [_celebBits] + destello inicial, la misma mezcla que la
///     celebración a pantalla completa (sobre el violeta de marca, el violeta
///     del confeti desaparecería).
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.onViolet = false});

  final bool onViolet;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  // Ventana suficiente para que la explosión caiga y SALGA del área (tarjeta o
  // pantalla): no se desvanece en el aire, se va al cruzar el borde de abajo.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(
      painter: _ConfettiField(
        seconds: (_c.lastElapsedDuration ?? Duration.zero).inMicroseconds / 1e6,
        bits: widget.onViolet ? _celebBits : _cardBits,
        flash: widget.onViolet,
      ),
      size: Size.infinite,
    ),
  );
}
