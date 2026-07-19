import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/motion.dart';

/// Doctrina de movimiento, 4ª pasada PO (2026-07-19): "el scroll de la
/// pantalla ponle 2 segundos de frenado". La fricción elegida
/// (`JayaloMotion.scrollFriction`) sale de despejar la fórmula de
/// `ClampingScrollSimulation._flingDuration`, así que conviene comprobar el
/// resultado CONTRA LA SIMULACIÓN REAL en vez de fiarse de la aritmética del
/// comentario: si una versión futura de Flutter cambia esa fórmula, o alguien
/// toca el token, este test lo caza.
ScrollMetrics _metrics() => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 10000,
      pixels: 500,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 3,
    );

void main() {
  group('frenado del scroll', () {
    test('un fling típico (3000 px/s) tarda ~2 s en detenerse, no ~1 s como '
        'el default de Android', () {
      final sim = const JayaloScrollPhysics()
          .createBallisticSimulation(_metrics(), 3000);
      expect(sim, isNotNull);

      // El umbral es 1.5 s A PROPÓSITO, y está MEDIDO, no supuesto: con la
      // fricción por defecto (0.015) este mismo fling se detiene a los
      // 1.03 s y con la nuestra a los 2.08 s. Un umbral de 1.0 s NO
      // discriminaría (el default tampoco ha terminado ahí) y el test sería
      // teatro: pasaría igual si alguien revirtiera el token.
      expect(sim!.isDone(1.5), isFalse,
          reason: 'a 1.5 s todavía debe estar planeando — con la fricción por '
              'defecto ya se habría detenido (1.03 s), así que este expect es '
              'el que separa un frenado largo de uno normal');
      expect(sim.isDone(2.5), isTrue,
          reason: 'pasados ~2.1 s el frenado ya terminó');
    });

    test('la fricción es la del token, no la de Flutter', () {
      // Blindaje del token: si alguien lo devuelve al default el test de
      // arriba también caería, pero este dice POR QUÉ.
      expect(JayaloMotion.scrollFriction, lessThan(0.015),
          reason: 'menos fricción que el default = planea más tiempo');
    });

    test('fuera de rango devuelve el muelle del borde, no un fling frenado',
        () {
      // Con `pixels` por encima de maxScrollExtent la simulación correcta es
      // el resorte que devuelve el contenido al límite: ese caso NO debe
      // heredar la fricción larga (si no, el rebote del borde se volvería
      // un planeo de 2 s).
      final fuera = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 1200,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 3,
      );
      final sim =
          const JayaloScrollPhysics().createBallisticSimulation(fuera, 0);
      expect(sim, isNotNull);
      expect(sim, isNot(isA<ClampingScrollSimulation>()),
          reason: 'el retorno al borde lo resuelve un ScrollSpringSimulation');
    });
  });
}
