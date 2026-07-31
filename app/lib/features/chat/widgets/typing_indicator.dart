/// "…está escribiendo": tres puntos rebotando dentro de una burbuja del peer.
///
/// Se dibuja donde iría el próximo mensaje entrante y con la MISMA silueta que
/// una burbuja recibida (color `pal.peer`, radio 14, hueco de avatar de 32) —
/// así el indicador no se lee como un cartel del sistema sino como el mensaje
/// que está a punto de llegar.
///
/// El vaivén de cada punto usa el mismo idioma de movimiento que la mascota de
/// [JayaloLoader]: una rampa 0→1→0 pasada por `easeInOut`, que es el
/// equivalente del `animation-direction: alternate` del CSS de la web. Un punto
/// que sube y baja con esa curva se frena arriba y abajo como una pelota; con
/// `linear` sube y baja como un pistón.
library;

import 'package:flutter/material.dart';

import '../../../core/motion.dart';
import 'bubbles.dart';

/// Ciclo de UN punto. 900ms es el compás de "alguien escribiendo": más rápido
/// se lee nervioso, más lento se lee trabado.
const _dotCycle = Duration(milliseconds: 900);

/// Atraso de cada punto respecto del anterior. A un tercio del ciclo los tres
/// puntos quedan repartidos parejo por la onda y el rebote se lee como una ola
/// que recorre, no como tres puntos independientes.
const _dotStagger = 1 / 3;

/// Cuánto sube el punto en su punto más alto, en píxeles.
const _dotRise = 5.0;

/// Vaivén 0→1→0 suavizado. Copia deliberada del `_pingPong` de
/// `jayalo_loader.dart`: es el mismo gesto y conviene que se vea igual. No se
/// comparte porque allá es privado del loader y exportarlo obligaría a abrir
/// API del isotipo para un uso que no tiene nada que ver con la marca.
double _pingPong(double t) {
  final p = t % 1.0;
  return Curves.easeInOut.transform(p < .5 ? p * 2 : (1 - p) * 2);
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, this.peerAvatarUrl});

  /// Reservado para cuando el indicador quiera mostrar la foto del peer. Hoy
  /// deja el hueco vacío igual que una burbuja de mitad de grupo, para no
  /// meter y sacar el avatar cada vez que el peer arranca y para de escribir.
  final String? peerAvatarUrl;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  // En `initState`, NO como `late final … = AnimationController(…)`: con
  // "reducir animaciones" el build no toca el campo y un `late final` se
  // inicializaría dentro de `dispose()`, donde `createTicker` va a buscar el
  // `TickerMode` de un elemento ya desactivado. Mismo motivo que en
  // `jayalo_loader.dart` y en `SkeletonCard`.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _dotCycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (JayaloMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = chatPalette(context);
    final reduced = JayaloMotion.reduced(context);

    Widget dot(int index) {
      final base = Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: pal.ink.withValues(alpha: .55),
          shape: BoxShape.circle,
        ),
      );
      // Sin movimiento: los tres puntos quietos y opacos. La burbuja ya dice
      // que el peer está escribiendo (y el Semantics de abajo lo dice en voz
      // alta); el rebote es el adorno, no la información.
      if (reduced) return base;
      return AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final k = _pingPong(_c.value - index * _dotStagger);
          return Transform.translate(
            offset: Offset(0, -_dotRise * k),
            // La opacidad acompaña al salto: el punto que está arriba es
            // también el más nítido. Solo con el salto el grupo se ve plano.
            child: Opacity(opacity: .45 + .55 * k, child: child),
          );
        },
        child: base,
      );
    }

    return Semantics(
      label: 'Escribiendo',
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Mismo hueco de 32 que reserva `buildBubble` para el avatar del
            // peer: sin él la burbuja del indicador quedaría 38px a la
            // izquierda de los mensajes recibidos y se vería como un salto.
            const SizedBox(width: 32),
            const SizedBox(width: 6),
            Container(
              // El alto sale de los puntos + el margen del salto, para que la
              // burbuja no cambie de tamaño mientras rebotan.
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: pal.peer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox(
                height: 7 + _dotRise,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                        child: dot(i),
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
