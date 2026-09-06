import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('muestra la guia la primera vez y la oculta al Saltar', (t) async {
    // Tras reset() el store no está suprimido (_suppressed=false) y isDone es
    // falso: la guía se muestra. NO llamar ensureLoaded aquí (sin login suprime).
    await t.pumpWidget(_host(
      const OnboardingGuide(
        guideKey: 'x.demo.v1',
        steps: [OnboardingStep('Hola guia')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Hola guia'), findsOneWidget);

    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();
    expect(find.text('Hola guia'), findsNothing);
    expect(onboardingStore.isDone('x.demo.v1'), isTrue);
  });

  testWidgets('no reaparece si ya esta hecha', (t) async {
    await onboardingStore.markDone('x.demo.v1');
    await t.pumpWidget(_host(
      const OnboardingGuide(
        guideKey: 'x.demo.v1',
        steps: [OnboardingStep('Hola guia')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Hola guia'), findsNothing);
    expect(find.text('destino'), findsOneWidget);
  });

  testWidgets('multi-paso avanza con Siguiente y cierra en el ultimo', (t) async {
    await t.pumpWidget(_host(
      const OnboardingGuide(
        guideKey: 'x.multi.v1',
        steps: [OnboardingStep('Paso 1'), OnboardingStep('Paso 2')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Paso 1'), findsOneWidget);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('Paso 2'), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(find.text('Paso 2'), findsNothing);
    expect(onboardingStore.isDone('x.multi.v1'), isTrue);
  });

  testWidgets('enabled=false solo renderiza el hijo', (t) async {
    await t.pumpWidget(_host(
      const OnboardingGuide(
        enabled: false,
        guideKey: 'x.off.v1',
        steps: [OnboardingStep('No sale')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('No sale'), findsNothing);
    expect(find.text('destino'), findsOneWidget);
    expect(onboardingStore.isDone('x.off.v1'), isFalse);
  });

  testWidgets('libera el coordinador cuando enabled pasa a false mientras se muestra',
      (t) async {
    await t.pumpWidget(_host(
      const OnboardingGuide(
        guideKey: 'x.rel.v1',
        steps: [OnboardingStep('Hola guia')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);

    await t.pumpWidget(_host(
      const OnboardingGuide(
        enabled: false,
        guideKey: 'x.rel.v1',
        steps: [OnboardingStep('Hola guia')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('onboardingCard')), findsNothing);
    onboardingStore.requestSlot('other.key.v1', 0);
    onboardingStore.resolvePending();
    expect(onboardingStore.isActive('other.key.v1'), isTrue);
  });

  testWidgets('orden: la guia de menor order se muestra primero', (t) async {
    await t.pumpWidget(_host(
      Column(mainAxisSize: MainAxisSize.min, children: const [
        OnboardingGuide(
          guideKey: 'x.b.v1',
          order: 2,
          steps: [OnboardingStep('Segunda')],
          child: SizedBox(width: 80, height: 30, child: Text('b')),
        ),
        OnboardingGuide(
          guideKey: 'x.a.v1',
          order: 1,
          steps: [OnboardingStep('Primera')],
          child: SizedBox(width: 80, height: 30, child: Text('a')),
        ),
      ]),
    ));
    await t.pumpAndSettle();
    // aunque 'b' va antes en el árbol, gana 'a' (order menor)
    expect(find.text('Primera'), findsOneWidget);
    expect(find.text('Segunda'), findsNothing);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(find.text('Segunda'), findsOneWidget);
  });

  testWidgets('ancla externa: mide un widget por anchorKey sin envolverlo', (t) async {
    final anchor = GlobalKey();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 20,
            top: 20,
            child: SizedBox(
              key: anchor,
              width: 60,
              height: 40,
              child: const Text('target'),
            ),
          ),
          OnboardingGuide(
            guideKey: 'x.ext.v1',
            steps: [OnboardingStep('Externa', anchorKey: anchor)],
            order: 1,
            child: const SizedBox.shrink(),
          ),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Externa'), findsOneWidget);
    expect(find.text('target'), findsOneWidget);
  });
}
