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
    test('la palanca manda: un fling típico se detiene a los segundos que '
        'diga JayaloMotion.scrollBrake (hoy 4 s), no en ~1 s como el default',
        () {
      final sim = const JayaloScrollPhysics()
          .createBallisticSimulation(_metrics(), JayaloMotion.flingReference);
      expect(sim, isNotNull);

      final objetivo = JayaloMotion.scrollBrake.inMilliseconds / 1000;
      // Se comprueba que la duración REAL cae junto al objetivo pedido (±15%),
      // que es lo que hace útil la palanca: cambiar `scrollBrake` a N segundos
      // debe producir un frenado de N segundos. Un test que solo mirara
      // "más lento que el default" no cazaría un error en la fórmula de
      // `frictionForBrake`.
      expect(sim!.isDone(objetivo * 0.85), isFalse,
          reason: 'antes del objetivo todavía debe estar planeando');
      expect(sim.isDone(objetivo * 1.15), isTrue,
          reason: 'poco después del objetivo el frenado ya terminó');

      // Y que de verdad es MUCHO más lento que Android (1.03 s medido).
      expect(objetivo, greaterThan(1.5),
          reason: 'si alguien deja la palanca por debajo del default, el '
              'frenado largo dejó de existir');
    });

    test('la fricción es la del token, no la de Flutter', () {
      // Blindaje del token: si alguien lo devuelve al default el test de
      // arriba también caería, pero este dice POR QUÉ.
      expect(JayaloMotion.scrollFriction, lessThan(0.015),
          reason: 'menos fricción que el default = planea más tiempo');
    });

    test('frictionForBrake acierta para varios objetivos, no solo para el '
        'valor que hoy tiene la palanca', () {
      // La fórmula se despejó a mano; conviene comprobarla en varios puntos
      // contra la simulación REAL de Flutter (si una versión futura cambia
      // sus constantes, esto lo caza antes que los ojos del PO).
      for (final segundos in [1.0, 2.0, 4.0, 6.0]) {
        final target = Duration(milliseconds: (segundos * 1000).round());
        final sim = ClampingScrollSimulation(
          position: 0,
          velocity: 3000,
          friction: frictionForBrake(target),
        );
        expect(sim.isDone(segundos * 0.9), isFalse,
            reason: 'pedido $segundos s: no debería haber parado aún');
        expect(sim.isDone(segundos * 1.1), isTrue,
            reason: 'pedido $segundos s: ya debería haber parado');
      }
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
      final sim = state.resolvedPhysics!
          .createBallisticSimulation(state.position, JayaloMotion.flingReference);

      expect(sim, isNotNull,
          reason: 'un fling de 3000 px/s sobre una lista de 50 filas debe '
              'producir simulación');
      expect(sim!.isDone(1.5), isFalse,
          reason: 'la lista real hereda el frenado largo (con el default ya '
              'habría parado a los 1.03 s)');
      expect(sim.isDone(JayaloMotion.scrollBrake.inMilliseconds / 1000 * 1.15),
          isTrue);
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
