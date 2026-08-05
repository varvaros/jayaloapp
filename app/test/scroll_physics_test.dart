import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/motion.dart';

/// Doctrina de movimiento. PO 2026-07-19 (4ª y 5ª pasada): "el scroll de la
/// pantalla ponle 2 segundos de frenado" → 4 s.
///
/// PO 2026-08-03: "el scroll solo se siente suave cuando hago un swipe muy
/// brusco; con uno moderado frena de golpe". Medido con una sonda sobre 615
/// flings reales: con la spline de Android la duración iba como `v^0.736`, así
/// que entre el swipe suave y el brusco del uso real había **6.3×**. Se cambió
/// a decaimiento exponencial (`FrictionSimulation`), que hace la duración
/// logarítmica en la velocidad y baja ese reparto a ~1.7×.
///
/// Todo se comprueba CONTRA LA SIMULACIÓN REAL y no contra la aritmética del
/// comentario: si una versión futura de Flutter cambia sus constantes o alguien
/// toca un token, estos tests lo cazan antes que los ojos del PO.
ScrollMetrics _metrics({double pixels = 500, double dpr = 3}) =>
    FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 10000,
      pixels: pixels,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: dpr,
    );

/// Instante en que la simulación se da por terminada (búsqueda binaria sobre
/// `isDone`, que es lo que de verdad corta el fling).
double _stopTime(Simulation sim) {
  var lo = 0.0, hi = 30.0;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (sim.isDone(mid)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi;
}

double _flingStopTime(double velocity, {double dpr = 3}) {
  final sim = const JayaloScrollPhysics()
      .createBallisticSimulation(_metrics(dpr: dpr), velocity);
  return _stopTime(sim!);
}

void main() {
  group('frenado del scroll', () {
    test('la palanca manda: un fling típico se detiene a los segundos que '
        'diga JayaloMotion.scrollBrake (hoy 4 s), no en ~1 s como el default',
        () {
      final objetivo = JayaloMotion.scrollBrake.inMilliseconds / 1000;
      final real = _flingStopTime(JayaloMotion.flingReference);

      // ±10%: es lo que hace útil la palanca — poner N segundos debe producir
      // un frenado de N segundos. Un test que solo mirara "más lento que el
      // default" no cazaría un error en la fórmula de `dragForBrake`.
      expect(real, closeTo(objetivo, objetivo * 0.10));
      expect(objetivo, greaterThan(1.5),
          reason: 'si alguien deja la palanca por debajo del default de '
              'Android (~1 s), el frenado largo dejó de existir');
    });

    test('dragForBrake acierta para varios objetivos, no solo para el valor '
        'que hoy tiene la palanca', () {
      const tol = 1 / (0.05 * 3); // el de un device con dpr 3
      for (final segundos in [1.0, 2.0, 4.0, 6.0]) {
        final target = Duration(milliseconds: (segundos * 1000).round());
        final sim = FrictionSimulation(
          dragForBrake(target, velocity: 1400, toleranceVelocity: tol),
          0,
          1400,
          tolerance: const Tolerance(velocity: tol),
        );
        expect(_stopTime(sim), closeTo(segundos, segundos * 0.05),
            reason: 'pedido $segundos s');
      }
    });

    test('EL ARREGLO: el swipe moderado ya no frena de golpe', () {
      // 627 px/s es el p25 del uso real medido. Con la spline de Android
      // frenaba en 1.26 s, que el ojo lee como un frenazo en vez de inercia.
      expect(_flingStopTime(627), greaterThan(2.5),
          reason: 'un swipe moderado tiene que planear de forma perceptible');
      // Y el roce más suave del uso real (p5) tampoco puede morir al instante.
      expect(_flingStopTime(288), greaterThan(2.0));
    });

    test('EL ARREGLO: la duración es consistente entre velocidades', () {
      // La queja del PO era el REPARTO, no la duración de un fling concreto:
      // solo el swipe brusco se sentía premium. Con la spline de Android este
      // cociente valía 6.3× sobre el uso real medido (p5=288, p95=3497), y
      // NINGÚN valor de `scrollBrake` podía bajarlo — la fricción es un
      // multiplicador sobre todas las velocidades a la vez.
      final suave = _flingStopTime(288);
      final fuerte = _flingStopTime(3497);
      expect(fuerte / suave, lessThan(2.0),
          reason: 'suave ${suave.toStringAsFixed(2)}s vs fuerte '
              '${fuerte.toStringAsFixed(2)}s — el reparto se volvió a abrir');
    });

    test('los segundos de la palanca se cumplen en devices con distinto dpr',
        () {
      // La tolerancia de parada es `1/(0.05·devicePixelRatio)`, así que un
      // arrastre CONSTANTE daría duraciones distintas según la pantalla. Por
      // eso `scrollDragFor` lo resuelve con la tolerancia real del
      // `ScrollMetrics`; este test es el que protege esa decisión.
      final objetivo = JayaloMotion.scrollBrake.inMilliseconds / 1000;
      for (final dpr in [1.0, 2.0, 3.14375, 4.0]) {
        expect(_flingStopTime(JayaloMotion.flingReference, dpr: dpr),
            closeTo(objetivo, objetivo * 0.10),
            reason: 'dpr $dpr');
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
      final sim = state.resolvedPhysics!.createBallisticSimulation(
          state.position, JayaloMotion.flingReference);

      expect(sim, isA<FrictionSimulation>(),
          reason: 'la lista real hereda el fling exponencial');
      expect(_stopTime(sim!),
          closeTo(JayaloMotion.scrollBrake.inMilliseconds / 1000, 0.5));
    });
  });

  /// El pedido del PO al cambiar de modelo fue explícito: "sin modificar el
  /// arrastre manual, el rebote ni el comportamiento de los bordes". Este grupo
  /// es esa garantía, comprobada contra `ClampingScrollPhysics` sin tocar.
  group('solo cambia la fase de fling', () {
    const nuestra = JayaloScrollPhysics();
    const original = ClampingScrollPhysics();

    test('el arrastre con el dedo es idéntico al de Android', () {
      for (final offset in [-120.0, -1.0, 1.0, 45.5, 300.0]) {
        expect(nuestra.applyPhysicsToUserOffset(_metrics(), offset),
            original.applyPhysicsToUserOffset(_metrics(), offset),
            reason: 'offset $offset');
      }
    });

    test('el clamp de los bordes es idéntico al de Android', () {
      // Dentro de rango, chocando con el tope de abajo, y ya pasado.
      final casos = <(double, double)>[
        (500, 600),
        (9000, 10500),
        (10000, 10600),
        (100, -50),
      ];
      for (final (pixels, value) in casos) {
        expect(nuestra.applyBoundaryConditions(_metrics(pixels: pixels), value),
            original.applyBoundaryConditions(_metrics(pixels: pixels), value),
            reason: 'pixels $pixels → $value');
      }
    });

    test('el muelle del rebote es el mismo objeto de siempre', () {
      expect(nuestra.spring.mass, original.spring.mass);
      expect(nuestra.spring.stiffness, original.spring.stiffness);
      expect(nuestra.spring.damping, original.spring.damping);
    });

    test('fuera de rango devuelve el muelle del borde, no un fling', () {
      // Con `pixels` por encima de maxScrollExtent la simulación correcta es
      // el resorte que devuelve el contenido al límite: ese caso NO debe
      // heredar el planeo largo (si no, el rebote del borde se volvería un
      // viaje de 4 s).
      final sim = nuestra.createBallisticSimulation(
          _metrics(pixels: 10500).copyWith(maxScrollExtent: 10000), 0);
      expect(sim, isA<ScrollSpringSimulation>());
      expect(sim, isNot(isA<FrictionSimulation>()));
    });

    test('sin fling no se inventa un fling', () {
      // Bajo la tolerancia de velocidad, y pegado al tope: en ambos casos
      // Android devuelve null y nosotros también.
      expect(nuestra.createBallisticSimulation(_metrics(), 0.5), isNull);
      expect(
          nuestra.createBallisticSimulation(
              _metrics(pixels: 10000), 800),
          isNull);
      expect(nuestra.createBallisticSimulation(_metrics(pixels: 0), -800),
          isNull);
    });

    test('la sonda de calibración está apagada por defecto', () {
      // Va tras `--dart-define=SCROLL_PROBE`, así que un release no puede
      // llevarla. Si alguien la deja encendida, el log de producción se llena.
      expect(const bool.fromEnvironment('SCROLL_PROBE'), isFalse);
    });
  });
}
