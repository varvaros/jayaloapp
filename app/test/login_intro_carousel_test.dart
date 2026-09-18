// El carrusel de primera apertura dentro de `/login`: la pregunta, la reacción
// al lado elegido y el cierre con los accesos de siempre. La secuencia sale de
// `introSteps` y el copy de `introSlideFor` — aquí nunca se re-escribe una
// frase a mano.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Se monta con las animaciones del sistema APAGADAS por dos razones:
  /// 1. es una conducta que hay que respetar igual (`JayaloMotion.reduced`), y
  /// 2. la escena de Jayi anima con un `Ticker` perpetuo — con ellas
  ///    encendidas `pumpAndSettle` no asienta NUNCA.
  Widget app({int credits = 5, bool reduced = true}) => MaterialApp(
    home: LoginScreen(fetchWelcomeCredits: () async => credits),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(disableAnimations: reduced),
      child: child!,
    ),
  );

  // Teléfono, no la ventana de 800x600 por defecto: en `flutter test` el texto
  // mide ~2× y los recuadros tienen que quedar donde se pueden tocar.
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(420 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Finder dots() => find.byKey(const Key('intro-dots'));
  int dotCount(WidgetTester t) => t.widget<Row>(dots()).children.length;

  final ask = introSlideFor(IntroStep.ask);
  const cliente = 'Soy un cliente';
  const proveedor = 'Soy un proveedor';

  testWidgets('primera apertura: la pregunta y los DOS recuadros', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    // El titular entra palabra a palabra: cada una es su propio `Text`.
    for (final w in ask.headline.split(' ')) {
      expect(find.text(w), findsWidgets, reason: 'palabra «$w» del titular');
    }
    expect(find.text(ask.sub), findsOneWidget);
    expect(find.text(cliente), findsOneWidget);
    expect(find.text(proveedor), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
    expect(dotCount(t), 3, reason: 'sin elegir se pintan 3, nunca 1');
  });

  testWidgets('tocar «Soy un proveedor» persiste la elección', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.pumpAndSettle();
    expect(await IntroRoleStore().read(), IntroRole.provider);
    expect(find.text('¡Bien!'), findsOneWidget);
  });

  testWidgets(
    'proveedor con bono: 4 puntos, la etiqueta, y la moneda con el 5 al final',
    (t) async {
      phone(t);
      await t.pumpWidget(app(credits: 5));
      await t.pumpAndSettle();
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      expect(dotCount(t), 4);
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Hacer ofertas es gratis.'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsNothing);
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.textContaining('créditos de regalo'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
    },
  );

  testWidgets(
    'proveedor SIN bono: 3 láminas y los accesos en «Hacer ofertas es gratis»',
    (t) async {
      phone(t);
      await t.pumpWidget(app(credits: 0));
      await t.pumpAndSettle();
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      expect(dotCount(t), 3);
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Hacer ofertas es gratis.'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(find.textContaining('créditos de regalo'), findsNothing);
    },
  );

  testWidgets('el bono que llega TARDE no mueve la lámina de accesos', (
    t,
  ) async {
    phone(t);
    final late = Completer<int>();
    await t.pumpWidget(
      MaterialApp(
        home: LoginScreen(fetchWelcomeCredits: () => late.future),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.pumpAndSettle();
    expect(dotCount(t), 3, reason: 'sin dato todavía, se congela en 0');
    late.complete(5);
    await t.pumpAndSettle();
    expect(dotCount(t), 3, reason: 'llegar tarde no añade lámina bajo el dedo');
  });

  testWidgets('cliente: tres láminas y «Navega con libertad» con los accesos', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text(cliente));
    await t.pumpAndSettle();
    expect(find.text('¡Genial!'), findsOneWidget);
    expect(dotCount(t), 3);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(
      find.text('Para ti, todas las funciones son gratis.'),
      findsOneWidget,
    );
    expect(find.text('Navega con libertad.'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });

  testWidgets('CON animaciones: el avance ANIMA, no salta', (t) async {
    // El camino de producción: `addPostFrameCallback` + `animateToPage`, que
    // existe justo porque el `itemCount` pasa de 1 a 3 en el mismo `setState`.
    // Aquí NO se puede usar `pumpAndSettle`: el `Ticker` perpetuo de
    // `JayiScene` no deja asentar nunca. Todo va con pumps de duración
    // explícita, tomada de los mismos tokens que usa la pantalla.
    phone(t);
    await t.pumpWidget(
      MaterialApp(home: LoginScreen(fetchWelcomeCredits: () async => 5)),
    );
    await t.pump();
    await t.pump(JayaloMotion.fast);
    await t.pump(JayaloMotion.introLand); // los recuadros ya se revelaron
    expect(find.text(cliente), findsOneWidget);
    await t.tap(find.text(cliente));
    await t.pump(); // save() resuelve
    await t.pump(); // postFrame pidió la página
    await t.pump(JayaloMotion.fast); // 150 de los 300 ms de `page`
    expect(find.text(cliente), findsOneWidget, reason: 'la lámina 0 aún sale');
    expect(
      find.text('¡Genial!'),
      findsOneWidget,
      reason: 'la reacción ya entra',
    );
    await t.pump(JayaloMotion.page + JayaloMotion.introGesture);
    expect(find.text(cliente), findsNothing);
    expect(find.text('¡Genial!'), findsOneWidget);
  });

  testWidgets('tocar los DOS recuadros seguidos: gana el primero', (t) async {
    // Sin guarda de reentrada los dos `save()` corren en paralelo y en disco
    // queda el que resuelva último, que no tiene por qué ser el que tocó el
    // usuario.
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.tap(find.text(cliente), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(await IntroRoleStore().read(), IntroRole.provider);
    expect(find.text('¡Bien!'), findsOneWidget);
  });

  testWidgets('con rol guardado arranca en la lámina de acceso', (t) async {
    // Quien ya eligió y todavía no se ha autenticado no repite el intro.
    SharedPreferences.setMockInitialValues({IntroRoleStore.kKey: 'provider'});
    phone(t);
    await t.pumpWidget(app(credits: 5));
    await t.pumpAndSettle();
    expect(find.text(proveedor), findsNothing);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.textContaining('créditos de regalo'), findsOneWidget);
  });

  group('«Saltar» sin elegir lado', () {
    testWidgets('cierra en neutro con los DOS accesos y sin rol guardado', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();
      expect(
        find.text('Entra y elige tu lado cuando quieras.'),
        findsOneWidget,
      );
      expect(find.text('¡Genial!'), findsNothing);
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(await IntroRoleStore().read(), isNull);
      expect(dotCount(t), 2);
    });
  });

  group('«Saltar» con rol ya elegido', () {
    testWidgets('cae en los accesos, no en una lámina intermedia', (t) async {
      phone(t);
      await t.pumpWidget(app(credits: 5));
      await t.pumpAndSettle();
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Saltar'), findsOneWidget);
      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();
      expect(find.text('Continuar con Google'), findsOneWidget);
    });
  });

  group('atrás de Android', () {
    testWidgets('canPop es false fuera de la lámina 0', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(
        t.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isTrue,
      );
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      expect(
        t.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isFalse,
      );
    });

    testWidgets('el chevrón retrocede una lámina y deja reelegir', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('intro-back')));
      await t.pumpAndSettle();
      expect(find.text(cliente), findsOneWidget);
      expect(find.text(proveedor), findsOneWidget);
      await t.tap(find.text(cliente));
      await t.pumpAndSettle();
      expect(await IntroRoleStore().read(), IntroRole.consumer);
      expect(find.text('¡Genial!'), findsOneWidget);
    });

    testWidgets('back machacado en plena transición no dobla la animación', (
      t,
    ) async {
      // Mismo espíritu que «tocar los DOS recuadros seguidos»: un segundo
      // back mientras el primero todavía está en vuelo no debe lanzar una
      // segunda `animateToPage` en paralelo (guarda de `_choosing`).
      phone(t);
      await t.pumpWidget(app(credits: 5));
      await t.pumpAndSettle();

      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Continuar con Google'), findsOneWidget);

      final nav = t.state<NavigatorState>(find.byType(Navigator));
      unawaited(nav.maybePop()); // primer back: en vuelo
      unawaited(nav.maybePop()); // segundo, antes de que el primero asiente
      await t.pumpAndSettle();

      // Un solo retroceso efectivo: se queda en la lámina de la etiqueta, no
      // dos atrás.
      expect(find.text('Hacer ofertas es gratis.'), findsOneWidget);
      expect(find.text(cliente), findsNothing);
    });
  });
}
