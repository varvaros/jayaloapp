/// El menú en arco que despliega el botón central de la barra flotante.
///
/// No sabe de rutas, ni de roles, ni de qué hace cada ítem: recibe una lista y
/// avisa cuál se eligió — el mismo trato que `floating_nav_bar.dart` le da a
/// los badges. Vive en su propio archivo porque la barra ya tiene un solo
/// trabajo (dibujar la píldora) y 467 líneas para hacerlo.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/center_action.dart';
import '../../core/motion.dart';

/// Distancia del centro de cada satélite al del círculo central, abierto.
const double kArcRadius = 96;

/// Diámetro de cada satélite.
const double kSatelliteSize = 44;

/// Ancho reservado a cada satélite CON su etiqueta. Es lo que fija el radio:
/// con cuatro repartidos de 170° a 10°, dos vecinos quedan a
/// `2 · 96 · sin(26,67°) ≈ 86 px`, holgado sobre estos 76. Bajar el radio o
/// estrechar el arco los solapa — es la cuenta que hay que rehacer si alguno
/// de los dos se toca.
const double kSatelliteSlot = 76;

/// Lado de la caja cuadrada que el arco ocupa, centrada en el botón.
///
/// La mitad (130) es MENOS que `kArcRadius + kSatelliteSlot / 2` (134): la
/// etiqueta del satélite más lejano sobresale unos píxeles del borde de la
/// caja. Eso no recorta nada porque nada en esta cadena recorta: el `Stack`
/// de `CenterArcMenu` es `Clip.none` y el `OverlayPortal` que lo aloja
/// (`floating_nav_bar.dart`) tampoco pone clipper — vive de que ningún
/// ancestro entre esta caja y la pantalla decide cortar. El margen visual (un
/// texto de 11px centrado, no el círculo) alcanza para que no se sienta
/// apretado; si algún día algo en el camino empieza a recortar, hay que
/// agrandar esto o el texto se empieza a comer.
const double kArcBoxSize = 260;

/// Escalonado entre satélites: el arco se despliega, no aparece de golpe.
const _stagger = Duration(milliseconds: 30);

/// Posiciones de los satélites RELATIVAS al centro, a una `distance` dada.
///
/// Se reparten de 170° a 10° (medidos desde el eje X positivo, subiendo por
/// encima), así que en coordenadas de pantalla —donde la Y crece hacia abajo—
/// todas salen con `dy` negativo. Con `count == 1` va uno solo, arriba.
List<Offset> arcOffsets(int count, double distance) {
  if (count <= 0) return const [];
  if (count == 1) return [Offset(0, -distance)];
  const from = 170.0, to = 10.0;
  final step = (to - from) / (count - 1);
  return [
    for (var i = 0; i < count; i++)
      () {
        final rad = (from + step * i) * math.pi / 180;
        return Offset(math.cos(rad) * distance, -math.sin(rad) * distance);
      }(),
  ];
}

class CenterArcMenu extends StatelessWidget {
  const CenterArcMenu({
    super.key,
    required this.animation,
    required this.items,
    required this.centerRadius,
    required this.onPick,
  });

  /// 0 = cerrado (todos dentro del centro), 1 = abierto.
  final Animation<double> animation;
  final List<CenterMenuItem> items;

  /// Radio del círculo central de la barra — la gota nace de él.
  final double centerRadius;
  final ValueChanged<CenterMenuItem> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = JayaloMotion.reduced(context);
    const half = kArcBoxSize / 2;

    return SizedBox(
      width: kArcBoxSize,
      height: kArcBoxSize,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // Con "reducir animaciones" no hay escalonado: todos a la vez.
          double tFor(int i) {
            if (reduced) return animation.value;
            final delay =
                (_stagger.inMilliseconds * i) /
                JayaloMotion.base.inMilliseconds;
            final span = 1 - delay;
            if (span <= 0) return animation.value;
            return ((animation.value - delay) / span).clamp(0.0, 1.0);
          }

          final posiciones = [
            for (var i = 0; i < items.length; i++)
              arcOffsets(items.length, kArcRadius * tFor(i))[i],
          ];

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: ArcBlobPainter(
                    color: cs.primary,
                    center: const Offset(half, half),
                    centerRadius: centerRadius,
                    satellites: [
                      for (final p in posiciones) const Offset(half, half) + p,
                    ],
                    satelliteRadius: kSatelliteSize / 2,
                  ),
                ),
              ),
              // El disco central de la gota de arriba se pinta ARRIBA de la
              // barra y cae exacto sobre el botón real (mismo centro, mismo
              // radio 28): tapa píxel a píxel la ✕ que gira por debajo, en
              // `floating_nav_bar.dart`. Se duplica el glyph AQUÍ para que se
              // vea; el de la barra real queda como respaldo semántico (sigue
              // siendo el que expone `Semantics`/`onTap` de "Cerrar menú").
              // `IgnorePointer` porque el toque debe seguir llegando al botón
              // de abajo — es el que de verdad abre y cierra el arco.
              // `Positioned` DEBE ser hijo directo del `Stack` (es lo que
              // este mira para leer left/top/width/height); envolverlo en
              // `IgnorePointer` por fuera lo dejaría sin efecto.
              Positioned(
                left: half - centerRadius,
                top: half - centerRadius,
                width: centerRadius * 2,
                height: centerRadius * 2,
                child: IgnorePointer(
                  child: FadeTransition(
                    // En t=0 (cerrado) no debe verse nada — el botón real,
                    // debajo, ya pinta su propio ＋.
                    opacity: animation,
                    child: Center(
                      child: RotationTransition(
                        // Un CUARTO de vuelta, no un octavo. El glifo ya ES una
                        // ✕: a 45° se ve como un ＋ y el usuario lee "añadir"
                        // donde debería leer "cerrar" (lo cazó el smoke en
                        // device, ningún test lo veía porque todos afirmaban el
                        // token del icono, no su ángulo). La ✕ es simétrica a
                        // 90°, así que el giro se conserva y el estado final es
                        // una ✕ de verdad.
                        turns: animation.drive(Tween(begin: 0.0, end: .25)),
                        child: Icon(Icons.close, color: cs.onPrimary, size: 28),
                      ),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                _Satellite(
                  item: items[i],
                  at: const Offset(half, half) + posiciones[i],
                  t: tFor(i),
                  onPick: onPick,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Satellite extends StatelessWidget {
  const _Satellite({
    required this.item,
    required this.at,
    required this.t,
    required this.onPick,
  });

  final CenterMenuItem item;
  final Offset at;
  final double t;
  final ValueChanged<CenterMenuItem> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Atenuado, no de otro color: sigue siendo el mismo botón, apagado.
    final fg = item.enabled
        ? cs.onPrimary
        : cs.onPrimary.withValues(alpha: .38);
    // ⚠️ El `left` se descuenta con el ancho del SLOT, no con el del círculo.
    // La columna la ensancha su ETIQUETA ("Mi tienda" mide más que los 44 del
    // círculo), así que restar `kSatelliteSize / 2` dejaría cada satélite
    // corrido a la derecha en media etiqueta — y corrido DISTINTO en cada uno,
    // porque las cuatro etiquetas miden distinto. El `SizedBox` de abajo fija
    // el ancho para que la cuenta valga.
    return Positioned(
      left: at.dx - kSatelliteSlot / 2,
      top: at.dy - kSatelliteSize / 2,
      width: kSatelliteSlot,
      // `t` manda también en lo tocable: cerrado, los satélites están DENTRO
      // del centro y no deben interceptar nada.
      child: IgnorePointer(
        ignoring: t < .5,
        child: Opacity(
          opacity: t,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: item.label,
                button: true,
                enabled: item.enabled,
                excludeSemantics: true,
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    // Apagado con algo que avisar (p. ej. tope de fotos):
                    // toca y dispara `onDisabledTap` SIN pasar por `onPick`
                    // — el arco no se cierra, es solo un aviso. Apagado por
                    // `busy` (`onDisabledTap` null) el toque queda inerte.
                    onTap: item.enabled
                        ? () => onPick(item)
                        : item.onDisabledTap,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: kSatelliteSize,
                      height: kSatelliteSize,
                      child: Icon(item.icon, color: fg, size: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: kSatelliteSlot,
                child: Text(
                  item.label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La "gota": el centro y sus satélites unidos por puentes de cintura fina.
///
/// No se usa `Path.combine(union)` ni el truco de blur + umbral de color. Con
/// un relleno OPACO y de un solo color, pintar los círculos y los puentes uno
/// encima de otro se ve exactamente igual que su unión, y cuesta una fracción
/// — importa porque esto repinta en cada frame de la animación y el suelo de
/// gama baja de Android es el que manda. El día que la gota lleve borde o
/// sombra propia, esto deja de valer y hay que unir de verdad.
///
/// La curva es de la misma familia que `buildPillNotchPath`
/// (`floating_nav_bar.dart`): una cintura cóncava entre un círculo y otra
/// silueta.
class ArcBlobPainter extends CustomPainter {
  const ArcBlobPainter({
    required this.color,
    required this.center,
    required this.centerRadius,
    required this.satellites,
    required this.satelliteRadius,
  });

  final Color color;
  final Offset center;
  final double centerRadius;
  final List<Offset> satellites;
  final double satelliteRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawCircle(center, centerRadius, paint);
    for (final s in satellites) {
      final bridge = _bridge(center, centerRadius, s, satelliteRadius);
      if (bridge != null) canvas.drawPath(bridge, paint);
      canvas.drawCircle(s, satelliteRadius, paint);
    }
  }

  /// Puente entre dos círculos. `null` cuando están tan pegados que el puente
  /// quedaría dentro de ellos, o tan lejos que la gota ya se rompió.
  Path? _bridge(Offset a, double ra, Offset b, double rb) {
    final v = b - a;
    final d = v.distance;
    if (d <= ra || d >= (ra + rb) * 2.2) return null;

    final dir = v / d;
    final perp = Offset(-dir.dy, dir.dx);
    // Cuanto más lejos, más fino el puente: así se estira y termina rompiendo.
    final k = (1 - (d - ra) / ((ra + rb) * 1.2)).clamp(0.0, 1.0);
    final a1 = a + perp * ra * k, a2 = a - perp * ra * k;
    final b1 = b + perp * rb * k, b2 = b - perp * rb * k;
    final mid = a + dir * (d / 2);
    // La cintura queda MÁS CERCA del eje que los extremos: eso es lo que la
    // hace cóncava en vez de un simple trapecio.
    final waist = (ra + rb) / 2 * k * .6;

    return Path()
      ..moveTo(a1.dx, a1.dy)
      ..quadraticBezierTo(
        mid.dx + perp.dx * waist,
        mid.dy + perp.dy * waist,
        b1.dx,
        b1.dy,
      )
      ..lineTo(b2.dx, b2.dy)
      ..quadraticBezierTo(
        mid.dx - perp.dx * waist,
        mid.dy - perp.dy * waist,
        a2.dx,
        a2.dy,
      )
      ..close();
  }

  @override
  bool shouldRepaint(covariant ArcBlobPainter old) =>
      old.color != color ||
      old.center != center ||
      old.centerRadius != centerRadius ||
      old.satelliteRadius != satelliteRadius ||
      !listEquals(old.satellites, satellites);
}
