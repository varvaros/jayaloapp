import 'package:flutter/material.dart';
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

    testWidgets(
        'la física llega de verdad a una lista real de la app (el token no '
        'sirve de nada si el scrollBehavior no está cableado)', (tester) async {
      // No basta con probar la simulación aislada: lo que puede romperse en
      // silencio es el CABLEADO (que MaterialApp deje de pasar el
      // scrollBehavior). Se monta un scrollable normal bajo el mismo
      // behavior de la app y se pregunta qué física resolvió.
      await tester.pumpWidget(MaterialApp(
        scrollBehavior: const JayaloScrollBehavior(),
        home: ListView.builder(
          itemCount: 50,
          itemBuilder: (_, i) => SizedBox(height: 100, child: Text('$i')),
        ),
      ));

      // OJO con lo que se mide: un `ListView` vertical sin controller trae
      // `AlwaysScrollableScrollPhysics` PROPIA (ver el initializer de
      // `ScrollView`), así que mirar `Scrollable.physics` haría creer que el
      // behavior global no pinta nada. No es así: `ScrollableState`
      // (scrollable.dart) compone `physicsDelWidget.applyTo(physicsDelBehavior)`
      // — la del widget queda ENCIMA y la nuestra como padre, y
      // `AlwaysScrollableScrollPhysics` no redefine `createBallisticSimulation`,
      // así que el fling termina en la nuestra. Lo que hay que comprobar es
      // por tanto la física RESUELTA, y no por su tipo sino por lo que
      // produce: la simulación real de esta lista real.
      final state = tester.state<ScrollableState>(find.byType(Scrollable));
      final sim =
          state.resolvedPhysics!.createBallisticSimulation(state.position, 3000);

      expect(sim, isNotNull,
          reason: 'un fling de 3000 px/s sobre una lista de 50 filas debe '
              'producir simulación');
      expect(sim!.isDone(1.5), isFalse,
          reason: 'la lista real hereda el frenado largo (con el default ya '
              'habría parado a los 1.03 s)');
      expect(sim.isDone(2.5), isTrue);
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
