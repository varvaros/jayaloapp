// El carrusel de primera apertura dentro de `/login`: bifurca por rol, guarda
// la elección ANTES de que haya sesión y cierra con los accesos de siempre.
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
  /// 2. la escena de cada lámina anima con un `Ticker` perpetuo — con ellas
  ///    encendidas `pumpAndSettle` no asienta NUNCA.
  Widget app() => MaterialApp(
    home: const LoginScreen(),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
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

  testWidgets('primera apertura: lámina común y los DOS recuadros de rol', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.text(kIntroCommon.headline), findsOneWidget);
    expect(find.text(kIntroCommon.sub), findsOneWidget);
    expect(find.text('Busco algo'), findsOneWidget);
    expect(find.text('Vendo algo'), findsOneWidget);
    // Sin rol elegido no hay lámina de acceso a la que deslizarse.
    expect(find.text('Continuar con Google'), findsNothing);
  });

  testWidgets('tocar «Vendo algo» persiste la elección de proveedor', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Vendo algo'));
    await t.pumpAndSettle();

    expect(await IntroRoleStore().read(), IntroRole.provider);
  });

  testWidgets('proveedor: dos láminas después están los DOS accesos', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Vendo algo'));
    await t.pumpAndSettle();
    expect(
      find.text(kIntroSlides[IntroRole.provider]![0].headline),
      findsOneWidget,
    );

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();

    expect(
      find.text('Ofertar es gratis. Solo pagas cuando ya te aceptaron.'),
      findsOneWidget,
    );
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
  });

  testWidgets('CON animaciones: el avance ANIMA, no salta', (t) async {
    // El camino de producción: `addPostFrameCallback` + `animateToPage`, que
    // existe justo porque el `itemCount` pasa de 1 a 3 en el mismo `setState`.
    // Los demás tests van con reduce-motion, o sea por `jumpToPage`.
    //
    // Aquí NO se puede usar `pumpAndSettle`: el `Ticker` perpetuo de
    // `JayiScene` no deja asentar nunca. Todo va con pumps de duración
    // explícita, tomada de los mismos tokens que usa la pantalla.
    phone(t);
    await t.pumpWidget(const MaterialApp(home: LoginScreen()));
    await t.pump(); // primer frame
    await t.pump(JayaloMotion.fast); // el read() de prefs resuelve (vacío)
    expect(find.text('Busco algo'), findsOneWidget);

    await t.tap(find.text('Busco algo'));
    await t.pump(); // el save() resuelve y el carrusel pasa a 3 páginas
    await t.pump(); // el postFrame ya pidió la página: la animación arranca

    // A MITAD del recorrido se ven las DOS láminas a la vez — es exactamente
    // lo que distingue animar de saltar.
    await t.pump(JayaloMotion.fast); // 150 de los 300 ms de JayaloMotion.page
    expect(
      find.text('Busco algo'),
      findsOneWidget,
      reason: 'la lámina común todavía está saliendo',
    );
    expect(
      find.text(kIntroSlides[IntroRole.consumer]![0].headline),
      findsOneWidget,
      reason: 'la lámina del cliente ya está entrando',
    );

    // Y al terminar (+ margen) solo queda la lámina 2.
    await t.pump(JayaloMotion.page);
    expect(
      find.text(kIntroSlides[IntroRole.consumer]![0].headline),
      findsOneWidget,
    );
    expect(find.text('Siguiente'), findsOneWidget);
    expect(find.text('Busco algo'), findsNothing);
  });

  testWidgets('tocar los DOS recuadros seguidos: gana el primero', (t) async {
    // Sin guarda de reentrada los dos `save()` corren en paralelo y en disco
    // queda el que resuelva último, que no tiene por qué ser el que tocó el
    // usuario.
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Vendo algo'));
    // Sin dejar que resuelva el guardado, el segundo toque va al otro recuadro.
    await t.tap(find.text('Busco algo'), warnIfMissed: false);
    await t.pumpAndSettle();

    expect(await IntroRoleStore().read(), IntroRole.provider);
    expect(
      find.text(kIntroSlides[IntroRole.provider]![0].headline),
      findsOneWidget,
    );
  });

  testWidgets('con rol ya guardado arranca en la lámina de acceso', (t) async {
    // Quien ya eligió y todavía no se ha autenticado no repite el intro.
    SharedPreferences.setMockInitialValues({
      IntroRoleStore.kKey: IntroRole.consumer.name,
    });
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
    expect(find.text('Busco algo'), findsNothing);
  });

  // FIX 2 (I-2): «Saltar» sin elegir rol NO debe entregar el cierre de
  // cliente — antes `_slidesRole` caía por defecto en `IntroRole.consumer` y
  // quien saltaba veía «¡Aceptas la oferta que más te convenga!» aunque
  // nunca hubiera dicho ser cliente.
  group('saltar sin elegir rol', () {
    testWidgets('la lámina final es el cierre NEUTRO, no el de cliente', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();

      // El titular y el sub son los de la lámina común, reutilizados —
      // ningún copy nuevo.
      expect(find.text(kIntroCommon.headline), findsOneWidget);
      expect(find.text(kIntroCommon.sub), findsOneWidget);

      // Y NO el cierre de cliente que asumía un rol nunca elegido.
      expect(
        find.text('¡Aceptas la oferta que más te convenga!'),
        findsNothing,
      );
      expect(find.text(kIntroSlides[IntroRole.consumer]![1].sub), findsNothing);
    });

    testWidgets('están los DOS accesos y no queda rol guardado', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();

      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
      // Saltar no guarda nada: el alta cae en `ChooseRoleScreen`, la red de
      // seguridad prevista.
      expect(await IntroRoleStore().read(), isNull);
    });

    testWidgets('los puntos son 2, no 3 — no queda el del medio encendido', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();

      // El widget de los puntos es el único `AnimatedContainer` de la
      // pantalla: antes pintaba fijo 3, y con el camino sin rol (2 láminas)
      // el del medio quedaba encendido como si faltara una lámina.
      expect(find.byType(AnimatedContainer), findsNWidgets(2));
    });
  });

  // Regresión encontrada en la re-revisión: `_skip()` tenía la última lámina
  // hardcodeada en el índice 1, correcto SOLO para el carrusel sin rol (2
  // láminas). Con rol ya elegido (3 láminas) y volviendo a la lámina 0, ese
  // hardcode dejaba «Saltar» a medio camino, en la lámina de contenido del
  // rol en vez de en los accesos.
  group('saltar con rol ya elegido, desde la lámina 0', () {
    testWidgets('cae en los DOS accesos, no en la lámina de contenido', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      await t.tap(find.text('Vendo algo'));
      await t.pumpAndSettle();
      expect(
        find.text(kIntroSlides[IntroRole.provider]![0].headline),
        findsOneWidget,
      );

      // Vuelve a la lámina 0 por el mismo camino que el atrás de Android
      // (FIX 1): un `maybePop` con `canPop` en false.
      final nav = t.state<NavigatorState>(find.byType(Navigator));
      await nav.maybePop();
      await t.pumpAndSettle();
      expect(find.text('Busco algo'), findsOneWidget);

      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();

      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
      expect(
        find.text(kIntroSlides[IntroRole.provider]![0].headline),
        findsNothing,
      );
    });
  });

  // FIX 1 (I-2): el atrás de Android no debe sacar de la app desde las
  // láminas 2-3 — debe retroceder una lámina, igual que en iOS con el gesto
  // de borde. `PopScope` intercepta el pop; `Navigator.maybePop()` es la
  // misma vía que usa el framework para el back del sistema cuando
  // `canPop` es false (ver `ModalRoute.popDisposition`), así que dispara el
  // mismo camino de código que un back real.
  group('atrás de Android dentro del carrusel', () {
    testWidgets('canPop es false fuera de la lámina 0', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(
        t.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isTrue,
      );

      await t.tap(find.text('Vendo algo'));
      await t.pumpAndSettle();
      expect(
        t.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isFalse,
      );
    });

    testWidgets('en una lámina intermedia, retrocede en vez de salir', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      await t.tap(find.text('Vendo algo'));
      await t.pumpAndSettle();
      expect(
        find.text(kIntroSlides[IntroRole.provider]![0].headline),
        findsOneWidget,
      );

      final nav = t.state<NavigatorState>(find.byType(Navigator));
      await nav.maybePop();
      await t.pumpAndSettle();

      // Volvió a la lámina de elección — la pantalla sigue montada, no se
      // salió de la app.
      expect(find.text('Busco algo'), findsOneWidget);
      expect(find.text('Vendo algo'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('back machacado en plena transición no dobla la animación', (
      t,
    ) async {
      // Mismo espíritu que «tocar los DOS recuadros seguidos»: un segundo
      // back mientras el primero todavía está en vuelo no debe lanzar una
      // segunda `animateToPage` en paralelo (guarda de `_choosing`).
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      await t.tap(find.text('Vendo algo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Continuar con Google'), findsOneWidget);

      final nav = t.state<NavigatorState>(find.byType(Navigator));
      unawaited(nav.maybePop()); // primer back: en vuelo
      unawaited(nav.maybePop()); // segundo, antes de que el primero asiente
      await t.pumpAndSettle();

      // Un solo retroceso efectivo: se queda en la lámina intermedia, no en
      // la de elección.
      expect(
        find.text(kIntroSlides[IntroRole.provider]![0].headline),
        findsOneWidget,
      );
      expect(find.text('Busco algo'), findsNothing);
    });
  });
}
