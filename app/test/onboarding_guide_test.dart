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
}
