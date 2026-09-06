import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';

/// PO 2026-09-05: la guía del botón `+` no se notaba y un toque instintivo
/// fuera del hueco la quemaba para siempre. Ahora: tocar el velo solo la
/// cierra por esta vez; con `tapThrough` el toque dentro del hueco llega al
/// botón real y ESE toque sí la da por vista; el tour encadenado dice
/// «Paso n de N»; el hueco toma la forma del ancla.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

const _kDest = SizedBox(width: 100, height: 40, child: Text('destino'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  final card = find.byKey(const Key('onboardingCard'));

  group('tocar el velo (fuera del hueco)', () {
    testWidgets('cierra por esta vez, NO marca vista y libera el turno', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          const OnboardingGuide(
            guideKey: 'x.velo.v1',
            steps: [OnboardingStep('Hola guia')],
            child: _kDest,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(card, findsOneWidget);

      await t.tapAt(
        const Offset(4, 4),
      ); // esquina: lejos del hueco y la tarjeta
      await t.pumpAndSettle();

      expect(card, findsNothing);
      expect(find.text('destino'), findsOneWidget);
      expect(
        onboardingStore.isDone('x.velo.v1'),
        isFalse,
        reason: 'un toque fuera no puede quemar la guía',
      );
      expect(
        onboardingStore.isActive('x.velo.v1'),
        isFalse,
        reason: 'debe soltar el turno del coordinador',
      );
    });

    testWidgets('vuelve a salir al remontar la pantalla', (t) async {
      await t.pumpWidget(
        _host(
          const OnboardingGuide(
            guideKey: 'x.velo.v1',
            steps: [OnboardingStep('Hola guia')],
            child: _kDest,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tapAt(const Offset(4, 4));
      await t.pumpAndSettle();
      expect(card, findsNothing);

      await t.pumpWidget(_host(const SizedBox()));
      await t.pumpWidget(
        _host(
          const OnboardingGuide(
            guideKey: 'x.velo.v1',
            steps: [OnboardingStep('Hola guia')],
            child: _kDest,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(card, findsOneWidget);
    });

    testWidgets('vuelve a salir cuando enabled pasa de false a true', (
      t,
    ) async {
      Widget guide(bool enabled) => _host(
        OnboardingGuide(
          guideKey: 'x.velo.v1',
          enabled: enabled,
          steps: const [OnboardingStep('Hola guia')],
          child: _kDest,
        ),
      );
      await t.pumpWidget(guide(true));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(4, 4));
      await t.pumpAndSettle();
      expect(card, findsNothing);

      await t.pumpWidget(guide(false));
      await t.pumpAndSettle();
      await t.pumpWidget(guide(true));
      await t.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(onboardingStore.isDone('x.velo.v1'), isFalse);
    });

    testWidgets('la siguiente guía del tour toma el turno', (t) async {
      await t.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              OnboardingGuide(
                guideKey: 'x.a.v1',
                order: 1,
                steps: [OnboardingStep('Primera')],
                child: SizedBox(width: 80, height: 30, child: Text('a')),
              ),
              OnboardingGuide(
                guideKey: 'x.b.v1',
                order: 2,
                steps: [OnboardingStep('Segunda')],
                child: SizedBox(width: 80, height: 30, child: Text('b')),
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Primera'), findsOneWidget);

      await t.tapAt(const Offset(4, 4));
      await t.pumpAndSettle();
      expect(find.text('Primera'), findsNothing);
      expect(find.text('Segunda'), findsOneWidget);
      expect(onboardingStore.isDone('x.a.v1'), isFalse);
    });

    testWidgets('Saltar sí la marca vista', (t) async {
      await t.pumpWidget(
        _host(
          const OnboardingGuide(
            guideKey: 'x.velo.v1',
            steps: [OnboardingStep('Hola guia')],
            child: _kDest,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();
      expect(onboardingStore.isDone('x.velo.v1'), isTrue);
    });
  });

  group('tapThrough', () {
    Widget scene({required bool tapThrough, required VoidCallback onPressed}) {
      final anchor = GlobalKey();
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: FilledButton(
                  key: anchor,
                  onPressed: onPressed,
                  child: const Text('Real'),
                ),
              ),
              OnboardingGuide(
                guideKey: 'x.tap.v1',
                steps: [
                  OnboardingStep(
                    'Toca el botón',
                    anchorKey: anchor,
                    tapThrough: tapThrough,
                  ),
                ],
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('el toque dentro del hueco llega al botón real Y marca vista', (
      t,
    ) async {
      var pressed = 0;
      await t.pumpWidget(scene(tapThrough: true, onPressed: () => pressed++));
      await t.pumpAndSettle();
      expect(card, findsOneWidget);

      await t.tap(find.text('Real'), warnIfMissed: false);
      await t.pumpAndSettle();

      expect(pressed, 1, reason: 'el botón real no recibió el toque');
      expect(
        onboardingStore.isDone('x.tap.v1'),
        isTrue,
        reason: 'aprender haciéndolo cuenta como «Entendido»',
      );
      expect(card, findsNothing);
    });

    testWidgets(
      'un toque en la esquina del hueco (fuera del botón redondo) NO la marca',
      (t) async {
        var pressed = 0;
        await t.pumpWidget(
          scene(tapThrough: true, onPressed: () => pressed++),
        );
        await t.pumpAndSettle();
        // El FilledButton es un estadio: su esquina superior izquierda queda
        // fuera de su forma y fuera del círculo/estadio que deja pasar.
        final r = t.getRect(
          find.ancestor(of: find.text('Real'), matching: find.byType(FilledButton)),
        );
        await t.tapAt(r.topLeft + const Offset(1, 1));
        await t.pumpAndSettle();

        expect(pressed, 0);
        expect(
          onboardingStore.isDone('x.tap.v1'),
          isFalse,
          reason: 'sin toque real en el botón no hay «Entendido»',
        );
        expect(card, findsNothing, reason: 'cuenta como toque en el velo');
      },
    );

    testWidgets('sin tapThrough el hueco NO deja pasar el toque', (t) async {
      var pressed = 0;
      await t.pumpWidget(scene(tapThrough: false, onPressed: () => pressed++));
      await t.pumpAndSettle();

      await t.tap(find.text('Real'), warnIfMissed: false);
      await t.pumpAndSettle();

      expect(pressed, 0);
      expect(
        onboardingStore.isDone('x.tap.v1'),
        isFalse,
        reason: 'el toque en el hueco sin tapThrough es un toque en el velo',
      );
      expect(card, findsNothing);
    });
  });

  group('cabecera del tour', () {
    testWidgets('con varios pasos pinta «PASO n DE N» y avanza', (t) async {
      await t.pumpWidget(
        _host(
          const OnboardingGuide(
            guideKey: 'x.tour.v1',
            steps: [
              OnboardingStep('Uno'),
              OnboardingStep('Dos'),
              OnboardingStep('Tres'),
            ],
            child: _kDest,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('PASO 1 DE 3'), findsOneWidget);
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('PASO 2 DE 3'), findsOneWidget);
      expect(find.text('Dos'), findsOneWidget);
    });

    testWidgets('sin tour no hay cabecera', (t) async {
      await t.pumpWidget(
        _host(
          const OnboardingGuide(
            guideKey: 'x.solo.v1',
            steps: [OnboardingStep('Hola guia')],
            child: _kDest,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('PASO'), findsNothing);
    });
  });

  group('recorrido multi-ancla', () {
    Widget scene({
      required GlobalKey top,
      required GlobalKey bottom,
      required List<OnboardingStep> steps,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand, // sin esto el Stack mide 0 y «abajo» no existe
            children: [
              Positioned(
                left: 20,
                top: 20,
                child: SizedBox(
                  key: top,
                  width: 80,
                  height: 40,
                  child: const Text('arriba'),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 20,
                child: SizedBox(
                  key: bottom,
                  width: 80,
                  height: 40,
                  child: const Text('abajo'),
                ),
              ),
              OnboardingGuide(
                guideKey: 'x.multi.v1',
                steps: steps,
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('cada paso mide SU ancla: la burbuja cambia de lado', (
      t,
    ) async {
      final top = GlobalKey();
      final bottom = GlobalKey();
      await t.pumpWidget(
        scene(
          top: top,
          bottom: bottom,
          steps: [
            OnboardingStep('Uno', anchorKey: top),
            OnboardingStep('Dos', anchorKey: bottom),
          ],
        ),
      );
      await t.pumpAndSettle();
      final screenH = t.view.physicalSize.height / t.view.devicePixelRatio;
      final r1 = t.getRect(card);
      expect(
        r1.top,
        greaterThan(60),
        reason: 'paso 1: debajo del ancla de arriba',
      );

      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      final r2 = t.getRect(card);
      expect(find.text('Dos'), findsOneWidget);
      expect(
        r2.bottom,
        lessThanOrEqualTo(screenH - 60),
        reason: 'paso 2: encima del ancla de abajo',
      );
      expect(
        r2.top,
        greaterThan(r1.top),
        reason: 'el hueco viajó de arriba abajo; la burbuja lo sigue',
      );
    });

    testWidgets('un paso cuya ancla no está sale centrado, no se pierde', (
      t,
    ) async {
      final top = GlobalKey();
      final bottom = GlobalKey();
      final missing = GlobalKey(); // nunca se monta
      await t.pumpWidget(
        scene(
          top: top,
          bottom: bottom,
          steps: [
            OnboardingStep('Uno', anchorKey: top),
            OnboardingStep('Dos', anchorKey: missing),
          ],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Dos'), findsOneWidget);
      expect(card, findsOneWidget);
    });

    testWidgets(
      'si el PRIMER paso no tiene ancla montada, el recorrido sale igual',
      (t) async {
        final top = GlobalKey();
        final bottom = GlobalKey();
        final missing = GlobalKey();
        await t.pumpWidget(
          scene(
            top: top,
            bottom: bottom,
            steps: [
              OnboardingStep('Uno', anchorKey: missing),
              OnboardingStep('Dos', anchorKey: top),
            ],
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Uno'), findsOneWidget);
        expect(onboardingStore.isDone('x.multi.v1'), isFalse);
      },
    );

    testWidgets('un toque en el velo MIENTRAS el hueco viaja no cierra nada', (
      t,
    ) async {
      final top = GlobalKey();
      final bottom = GlobalKey();
      await t.pumpWidget(
        scene(
          top: top,
          bottom: bottom,
          steps: [
            OnboardingStep('Uno', anchorKey: top),
            OnboardingStep('Dos', anchorKey: bottom),
          ],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Siguiente'));
      await t.pump(const Duration(milliseconds: 80)); // a mitad del viaje
      await t.tapAt(const Offset(700, 300)); // velo, lejos de todo
      await t.pumpAndSettle();
      expect(card, findsOneWidget, reason: 'el toque impaciente no cierra');
      expect(find.text('Dos'), findsOneWidget);
    });

    testWidgets('Saltar marca el recorrido ENTERO, no un paso', (t) async {
      final top = GlobalKey();
      final bottom = GlobalKey();
      await t.pumpWidget(
        scene(
          top: top,
          bottom: bottom,
          steps: [
            OnboardingStep('Uno', anchorKey: top),
            OnboardingStep('Dos', anchorKey: bottom),
          ],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();
      expect(card, findsNothing);
      expect(onboardingStore.isDone('x.multi.v1'), isTrue);
    });

    test('anchorSteps casa copys con anclas y marca el tapThrough', () {
      final a = GlobalKey();
      final b = GlobalKey();
      final steps = anchorSteps(
        const [OnboardingStep('Uno'), OnboardingStep('Dos')],
        [a, b],
        tapThroughAt: 1,
      );
      expect(steps.map((s) => s.anchorKey), [a, b]);
      expect(steps.map((s) => s.tapThrough), [false, true]);
      expect(
        () => anchorSteps(const [OnboardingStep('Uno')], [a, b]),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('forma del hueco', () {
    test('ancla cuadrada → círculo; ancla ancha → estadio', () {
      final circle = onboardingHoleShape(const Rect.fromLTWH(0, 0, 56, 56));
      expect(circle.width, 68); // 56 + 6 por lado
      expect(circle.tlRadiusX, 34); // radio = mitad → círculo

      final pill = onboardingHoleShape(const Rect.fromLTWH(0, 0, 160, 32));
      expect(pill.width, 172);
      expect(pill.height, 44);
      expect(pill.tlRadiusX, 22); // radio = alto/2 → estadio
    });
  });
}
