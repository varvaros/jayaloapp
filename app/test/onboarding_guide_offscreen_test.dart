import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';

/// Reporte del PO (2026-08-22): "cuando la oferta se está creando ... se pone
/// oscuro pero no sale texto". El botón de enviar la oferta vive al final de un
/// formulario largo; su `RenderBox` SÍ se mide (el scroll lo dispone entero),
/// solo que a 1.000+ px del borde inferior. La guía anclaba ahí: velo oscuro,
/// hueco fuera de cuadro y tarjeta fuera de cuadro.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  final scrim = find.byKey(const Key('onboardingScrim'));
  final card = find.byKey(const Key('onboardingCard'));

  const guide = OnboardingGuide(
    guideKey: 'x.offscreen.v1',
    steps: [OnboardingStep('Enviar tu oferta es gratis')],
    child: SizedBox(width: 200, height: 48, child: Text('Enviar oferta')),
  );

  Future<void> pumpLongForm(WidgetTester t, {required double lead}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [SizedBox(height: lead), guide]),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('ancla bajo el pliegue: NO se pinta el velo y NO se quema',
      (t) async {
    await pumpLongForm(t, lead: 2000);
    expect(scrim, findsNothing, reason: 'pantalla oscura sin texto');
    expect(card, findsNothing);
    expect(onboardingStore.isDone('x.offscreen.v1'), isFalse,
        reason: 'la guía se marcó vista sin haberse visto nunca');
  });

  testWidgets('al scrollear hasta el botón, la guía aparece encima y se lee',
      (t) async {
    await pumpLongForm(t, lead: 2000);
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -1600));
    await t.pumpAndSettle();

    expect(find.text('Enviar oferta'), findsOneWidget);
    expect(card, findsOneWidget, reason: 'la guía no despertó con el scroll');
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    final r = t.getRect(card);
    expect(r.top, greaterThanOrEqualTo(0.0), reason: 'tarjeta fuera: $r');
    expect(r.bottom, lessThanOrEqualTo(screen.height),
        reason: 'tarjeta fuera: $r pantalla=$screen');
    expect(find.text('Enviar tu oferta es gratis'), findsOneWidget);
  });

  // Red de seguridad: da igual dónde caiga el ancla — la tarjeta SIEMPRE se
  // lee dentro de la pantalla. Cubre el ancla pegada al borde de abajo (el
  // botón de la barra con teclado abierto) y el ancla que ocupa casi todo.
  for (final caso in const [
    ('ancla pegada arriba', 0.0, 48.0),
    ('ancla pegada abajo', 552.0, 48.0),
    ('ancla que ocupa casi toda la pantalla', 20.0, 560.0),
    ('ancla en el centro', 280.0, 48.0),
  ]) {
    testWidgets('tarjeta dentro de la pantalla: ${caso.$1}', (t) async {
      onboardingStore.reset();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Positioned(
              left: 20,
              top: caso.$2,
              width: 200,
              height: caso.$3,
              child: OnboardingGuide(
                guideKey: 'x.pos.v1',
                steps: const [
                  OnboardingStep('Un texto de guía razonablemente largo para '
                      'que la tarjeta ocupe varias líneas y se note si se sale '
                      'de la pantalla por arriba o por abajo.')
                ],
                child: const SizedBox.expand(child: Text('destino')),
              ),
            ),
          ]),
        ),
      ));
      await t.pumpAndSettle();

      final screen = t.view.physicalSize / t.view.devicePixelRatio;
      expect(card, findsOneWidget);
      final r = t.getRect(card);
      expect(r.top, greaterThanOrEqualTo(0.0),
          reason: 'tarjeta por encima del borde: $r');
      expect(r.bottom, lessThanOrEqualTo(screen.height),
          reason: 'tarjeta por debajo del borde: $r pantalla=$screen');
      // Y el texto tiene que estar realmente pintado, no solo montado.
      expect(find.textContaining('Un texto de guía'), findsOneWidget);
    });
  }

  testWidgets('ancla TAPADA por el teclado: el texto se lee ENCIMA del teclado',
      (t) async {
    final dpr = t.view.devicePixelRatio;
    t.view.viewInsets = FakeViewPadding(bottom: 300 * dpr); // teclado abierto
    addTearDown(t.view.resetViewInsets);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        // Como el formulario real: el Scaffold sube el contenido y le QUITA
        // los viewInsets al MediaQuery del cuerpo.
        body: Stack(children: [
          Positioned(
            left: 20,
            top: 520, // debajo del borde del teclado (600 - 300 = 300)
            width: 200,
            height: 48,
            child: OnboardingGuide(
              guideKey: 'x.teclado.v1',
              steps: const [OnboardingStep('No se puede leer bajo el teclado')],
              child: const SizedBox.expand(child: Text('destino')),
            ),
          ),
        ]),
      ),
    ));
    await t.pumpAndSettle();

    // El ancla no vive en ningún scroll: no hay nada que esperar, así que la
    // guía se muestra igual — pero el texto tiene que quedar en la franja que
    // el teclado NO tapa, no debajo de él.
    expect(card, findsOneWidget);
    final r = t.getRect(card);
    expect(r.bottom, lessThanOrEqualTo(300.0),
        reason: 'tarjeta debajo del teclado: $r');
    expect(r.top, greaterThanOrEqualTo(0.0));
  });

  testWidgets('ancla fuera de pantalla y SIN scroll: se muestra igual, centrada',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 20,
            top: 900, // fuera de la pantalla de 600, sin scroll que la suba
            width: 200,
            height: 48,
            child: OnboardingGuide(
              guideKey: 'x.sinscroll.v1',
              steps: const [OnboardingStep('Texto que no se puede perder')],
              child: const SizedBox.expand(),
            ),
          ),
        ]),
      ),
    ));
    await t.pumpAndSettle();

    expect(card, findsOneWidget, reason: 'la guía se perdió por callada');
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    final r = t.getRect(card);
    expect(r.top, greaterThanOrEqualTo(0.0));
    expect(r.bottom, lessThanOrEqualTo(screen.height), reason: 'fuera: $r');
  });
}
