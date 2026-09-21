// La lámina del bono de bienvenida del intro: las monedas vuelan de Jayi al
// contador, como en la tienda al acreditar una recarga (PO 2026-09-21,
// «pongamos la animación de las monedas volando y recargando que ya existe»).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:jayalo_app/features/shared/vuelo_monedas.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app({int credits = 5, bool reduced = false}) => MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: LoginScreen(fetchWelcomeCredits: () async => credits),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(disableAnimations: reduced),
      child: child!,
    ),
  );

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(420 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  /// Lleva el carrusel hasta la lámina de la moneda. Con las animaciones
  /// ENCENDIDAS no se puede usar `pumpAndSettle`: la escena de Jayi anima con
  /// un `Ticker` perpetuo y no asienta nunca.
  /// `pumpAndSettle` no vale: la escena de Jayi anima con un `Ticker`
  /// perpetuo y no asienta nunca. Se avanza a mano, en pasos de 100 ms.
  Future<void> correr(WidgetTester t, Duration d) async {
    var queda = d;
    const paso = Duration(milliseconds: 100);
    while (queda > Duration.zero) {
      await t.pump(paso);
      queda -= paso;
    }
  }

  Future<void> hastaLaMoneda(WidgetTester t) async {
    await correr(t, const Duration(seconds: 2));
    await t.tap(find.text('Soy un proveedor'));
    await correr(t, JayaloMotion.introHint + const Duration(seconds: 1));
    await t.tap(find.text('Siguiente'));
    await correr(t, const Duration(seconds: 2));
    await t.tap(find.text('Siguiente'));
    await correr(t, const Duration(milliseconds: 600));
  }

  testWidgets('en la lámina del bono vuelan las monedas hasta el contador', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app(credits: 5));
    await hastaLaMoneda(t);
    expect(find.textContaining('créditos de regalo'), findsOneWidget);
    expect(find.byType(VueloMonedas), findsOneWidget);
    await correr(t, const Duration(seconds: 3));
  });

  testWidgets('vuelan TANTAS monedas como créditos regala el servidor', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app(credits: 3));
    await hastaLaMoneda(t);
    expect(t.widget<VueloMonedas>(find.byType(VueloMonedas)).nMonedas, 3);
    await correr(t, const Duration(seconds: 3));
  });

  testWidgets('el vuelo se retira solo y deja el número puesto', (t) async {
    phone(t);
    await t.pumpWidget(app(credits: 5));
    await hastaLaMoneda(t);
    await correr(t, const Duration(seconds: 3));
    expect(
      find.byType(VueloMonedas),
      findsNothing,
      reason: 'terminado el vuelo, el overlay se quita',
    );
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('con «reducir animaciones» no vuela nada y el número sigue ahí', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app(credits: 5, reduced: true));
    await hastaLaMoneda(t);
    expect(find.byType(VueloMonedas), findsNothing);
    expect(find.text('5'), findsOneWidget);
  });
}
