/// Celebración de la RECARGA acreditada (mockup B aprobado por el PO
/// 2026-08-23).
///
/// Es la tercera celebración de la app y la única que llega DESPUÉS de otra
/// animación: el vuelo de monedas al contador (`VueloMonedas`, en la tienda)
/// termina y entonces baja este panel. Por eso aquí no hay espera de entrada —
/// la espera ya la hizo el vuelo.
///
/// Se distingue de [showAcceptCelebration] / [showUnlockCelebration] en dos
/// cosas, ambas a propósito:
///   • El HÉROE es el saldo nuevo, no la mascota: el proveedor acaba de pagar y
///     lo que quiere saber es con cuánto se queda. Jayi asoma por abajo.
///   • NO se auto-cierra. Su botón lleva a la lista de solicitudes, y cerrarse
///     sola le robaría el destino. Se sale por el botón (devuelve `true`) o por
///     atrás (devuelve `null`, y el proveedor sigue en la tienda).
///
/// Todo el movimiento se pinta a mano sobre los tokens de [JayaloMotion] y las
/// piezas que ya existen: la moneda de [pintarMoneda] y el confeti de
/// [ConfettiBurst]. Con «reducir animaciones» queda quieta y dice lo mismo.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import 'celebration.dart' show ConfettiBurst, JayiCelebration;
import 'moneda.dart';

/// Abre la celebración. Devuelve `true` solo si el proveedor pidió ir a buscar
/// clientes; `null` si la cerró por atrás.
///
/// [agregados] es el delta de la compra y puede ser `null` cuando no se sabía
/// el saldo previo: entonces la píldora del "+N" no se pinta. Un "+0" sería
/// peor que no decir nada.
Future<bool?> showRechargeCelebration(
  BuildContext context, {
  required int? agregados,
  required int saldo,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent, // el violeta cubre todo: sin velo extra
    barrierLabel: 'Créditos recargados',
    transitionDuration: const Duration(milliseconds: 420),
    transitionBuilder: _slideFromTop,
    pageBuilder: (_, _, _) =>
        _RechargeOverlay(agregados: agregados, saldo: saldo),
  );
}

/// Misma entrada que las otras celebraciones: el panel violeta BAJA desde
/// arriba (ease-out, frena al llegar) y al cerrarse vuelve a subir.
Widget _slideFromTop(
  BuildContext context,
  Animation<double> anim,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final offset =
      Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
    CurvedAnimation(
      parent: anim,
      curve: JayaloMotion.enter,
      reverseCurve: JayaloMotion.exit,
    ),
  );
  return SlideTransition(position: offset, child: child);
}

class _RechargeOverlay extends StatefulWidget {
  const _RechargeOverlay({required this.agregados, required this.saldo});

  final int? agregados;
  final int saldo;

  @override
  State<_RechargeOverlay> createState() => _RechargeOverlayState();
}

class _RechargeOverlayState extends State<_RechargeOverlay>
    with SingleTickerProviderStateMixin {
  /// UNA sola línea de tiempo para la lluvia. `forward()` y no `repeat()`: un
  /// bucle infinito deja `pumpAndSettle` colgado para siempre y con él todos
  /// los tests de la tienda. La lluvia dura lo que tarda en cruzar la
  /// pantalla; después el panel se queda quieto esperando al proveedor.
  ///
  /// Se crea en `initState` y NO con un inicializador `late`: con «reducir
  /// animaciones» nadie lo tocaba en toda la vida del widget y era `dispose`
  /// quien acababa construyéndolo — creando un Ticker contra un contexto ya
  /// desactivado.
  late final AnimationController _lluvia;

  bool _arrancada = false;

  @override
  void initState() {
    super.initState();
    _lluvia = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancada) return;
    _arrancada = true;
    // Con «reducir animaciones» no cae nada: el usuario pidió sin movimiento y
    // el sonido ya lo dio el vuelo de monedas que trajo hasta aquí.
    if (!JayaloMotion.reduced(context)) _lluvia.forward();
  }

  @override
  void dispose() {
    _lluvia.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = JayaloMotion.reduced(context);
    final violet = Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dPrimary
        : JayaloColors.primary;
    final agregados = widget.agregados;

    return Material(
      key: const ValueKey('celebration-recharge'),
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: violet),

          // Lluvia de monedas a pantalla completa: las MISMAS monedas del
          // contador y de las pilas de los paquetes, cayendo hasta salir por
          // abajo (pedido PO: "que caigan hasta el final, sin desvanecerse").
          if (!reduced)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _lluvia,
                  builder: (_, _) => CustomPaint(
                    painter: _LluviaMonedas(
                      seconds:
                          (_lluvia.lastElapsedDuration ?? Duration.zero)
                                  .inMicroseconds /
                              1e6,
                    ),
                  ),
                ),
              ),
            ),

          if (!reduced)
            const Positioned.fill(
              child: IgnorePointer(child: ConfettiBurst(onViolet: true)),
            ),

          // Jayi ASOMA por el borde de abajo (mockup B): recortada, empujando
          // la escena hacia arriba en vez de competir con el número.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 116,
            child: IgnorePointer(
              child: ClipRect(
                child: OverflowBox(
                  maxHeight: 168,
                  alignment: Alignment.topCenter,
                  child: const JayiCelebration(
                    onViolet: true,
                    size: 168,
                    semanticsLabel: 'Créditos recargados',
                    // Una vuelta y se queda en su pose: este panel no se cierra
                    // solo, y un salto en bucle durante minutos cansa.
                    repeat: false,
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 132),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (agregados != null && agregados > 0)
                      _PildoraDelta(agregados: agregados)
                          .animate(target: reduced ? 1 : null)
                          .fadeIn(duration: JayaloMotion.base, delay: 100.ms)
                          .slideY(
                            begin: .3,
                            end: 0,
                            duration: JayaloMotion.base,
                            delay: 100.ms,
                            curve: JayaloMotion.enter,
                          ),
                    const SizedBox(height: 14),
                    _SaldoHeroe(saldo: widget.saldo, reduced: reduced),
                    const SizedBox(height: 30),
                    Text(
                      '¡Ya estás listo!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontVariations: [FontVariation('wght', 800)],
                        fontWeight: FontWeight.w800,
                        fontSize: 25,
                        height: 1.2,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    )
                        .animate(target: reduced ? 1 : null)
                        .fadeIn(duration: JayaloMotion.base, delay: 550.ms)
                        .slideY(
                          begin: .25,
                          end: 0,
                          duration: JayaloMotion.base,
                          delay: 550.ms,
                          curve: JayaloMotion.enter,
                        ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                      child: Text(
                        'Ninguna oportunidad se te escapa. Ve por los clientes '
                        'que ya te están buscando.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontVariations: const [FontVariation('wght', 700)],
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: .9),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                        .animate(target: reduced ? 1 : null)
                        .fadeIn(duration: JayaloMotion.base, delay: 700.ms)
                        .slideY(
                          begin: .3,
                          end: 0,
                          duration: JayaloMotion.base,
                          delay: 700.ms,
                          curve: JayaloMotion.enter,
                        ),
                    const SizedBox(height: 34),
                    _BotonBuscarClientes(
                      onPressed: () => Navigator.of(context).pop(true),
                    )
                        .animate(target: reduced ? 1 : null)
                        .fadeIn(duration: JayaloMotion.base, delay: 900.ms)
                        .slideY(
                          begin: .3,
                          end: 0,
                          duration: JayaloMotion.base,
                          delay: 900.ms,
                          curve: JayaloMotion.enter,
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La píldora dorada del delta: la moneda de la marca + "+N CRÉDITOS".
class _PildoraDelta extends StatelessWidget {
  const _PildoraDelta({required this.agregados});

  final int agregados;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: kOroMoneda,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 16, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MonedaJayalo(size: 22),
              const SizedBox(width: 8),
              Text(
                '+$agregados CRÉDITOS',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontVariations: [FontVariation('wght', 900)],
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: .2,
                  color: kTintaOro,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      );
}

/// El número nuevo, que es el héroe de la pantalla. Late una vez al entrar —
/// no en bucle: un latido perpetuo no deja leerlo y deja los tests colgados.
class _SaldoHeroe extends StatelessWidget {
  const _SaldoHeroe({required this.saldo, required this.reduced});

  final int saldo;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final numero = Text(
      '$saldo',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Nunito',
        fontVariations: [FontVariation('wght', 900)],
        fontWeight: FontWeight.w900,
        fontSize: 116,
        height: 1,
        letterSpacing: -4,
        color: Colors.white,
        decoration: TextDecoration.none,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        reduced
            ? numero
            : numero
                .animate()
                .fadeIn(duration: JayaloMotion.base, delay: 250.ms)
                .scaleXY(
                  begin: .84,
                  end: 1,
                  duration: 520.ms,
                  delay: 250.ms,
                  curve: Curves.easeOutBack,
                ),
        const SizedBox(height: 2),
        Text(
          'CRÉDITOS',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontVariations: const [FontVariation('wght', 700)],
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: 3,
            color: Colors.white.withValues(alpha: .82),
            decoration: TextDecoration.none,
          ),
        )
            .animate(target: reduced ? 1 : null)
            .fadeIn(duration: JayaloMotion.base, delay: 380.ms),
      ],
    );
  }
}

class _BotonBuscarClientes extends StatelessWidget {
  const _BotonBuscarClientes({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final violet = Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dPrimary
        : JayaloColors.primary;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: violet,
          padding: const EdgeInsets.symmetric(horizontal: 34),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontVariations: [FontVariation('wght', 800)],
            fontWeight: FontWeight.w800,
            fontSize: 16.5,
          ),
        ),
        child: const Text('Buscar clientes'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// La lluvia de monedas.
// ---------------------------------------------------------------------------

/// Una moneda de la lluvia. Semilla fija → la misma lluvia en cada recarga y
/// el mismo frame en los tests.
class _Gota {
  const _Gota(this.x, this.r, this.delay, this.vel, this.giro);

  /// Posición horizontal, 0..1 del ancho.
  final double x;

  /// Radio en px.
  final double r;

  /// Segundos que tarda en asomar.
  final double delay;

  /// Caída en ALTURAS de pantalla por segundo: así una pantalla alta y una
  /// baja tardan lo mismo en despejarse.
  final double vel;

  /// Giro en rad/s.
  final double giro;
}

final List<_Gota> _gotas = _construirGotas(11, 23);

List<_Gota> _construirGotas(int cuantas, int semilla) {
  final rnd = math.Random(semilla);
  return List.generate(cuantas, (i) {
    // Una franja por moneda: reparte el ancho sin dejar la lluvia apelotonada
    // en el centro, y el jitter evita que se lea como una rejilla.
    final franja = (i + .5) / cuantas;
    return _Gota(
      (franja + (rnd.nextDouble() - .5) * .06).clamp(.03, .97),
      10 + rnd.nextDouble() * 9, // de moneda de contador a moneda de pila
      rnd.nextDouble() * 2.0,
      .42 + rnd.nextDouble() * .30,
      (rnd.nextDouble() * 2 - 1) * (1.4 + rnd.nextDouble() * 2.2),
    );
  });
}

/// Monedas que entran por arriba y caen hasta SALIR por el borde de abajo. Sin
/// fundido: nada se desvanece en el aire (misma regla que el confeti).
class _LluviaMonedas extends CustomPainter {
  _LluviaMonedas({required this.seconds});

  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (seconds <= 0) return;
    for (final g in _gotas) {
      final t = seconds - g.delay;
      if (t <= 0) continue;
      final y = -g.r * 2 + t * g.vel * size.height;
      if (y - g.r * 2 > size.height) continue; // ya salió por abajo
      pintarMoneda(canvas, Offset(g.x * size.width, y), g.r, rot: t * g.giro);
    }
  }

  @override
  bool shouldRepaint(_LluviaMonedas old) => old.seconds != seconds;
}
