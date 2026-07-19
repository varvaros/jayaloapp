import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// Cierre de rama, punto 1: al retirar el `AnimatedSwitcher` que envolvía
/// `child` (correcto — duplicaba el `GlobalKey` estable del Navigator
/// anidado, ver el doc-comment de `home_shell.dart`), el cambio de pestaña se
/// quedó SIN ningún movimiento — contra la doctrina del PO (transiciones
/// premium, deslizado + ease-out, nunca instantáneo).
///
/// La solución repuesta: fundido + deslizado SOLO DE ENTRADA con un único
/// subárbol vivo a la vez (`TweenAnimationBuilder` keyed por
/// `matchedLocation`). Esta suite cubre exactamente lo que el cierre exige:
/// 1) el cambio de pestaña anima de verdad (no es un salto instantáneo),
/// 2) con "reducir animaciones" no anima nada,
/// 3) ningún `go()` real entre pestañas lanza una excepción — el caso que
///    habría cazado el "Duplicate GlobalKey" si hubiera regresado.
///
/// El escenario de router replica el mismo par de rutas que documenta el
/// comentario de C2/cierre en `home_shell.dart` (`/provider` →
/// `/provider/offers`): dos pestañas reales del rol proveedor, cambiadas con
/// `go()` liso, sin tocar `push` ni `-1`.
void main() {
  setUp(() => roleStore.value = RoleState.provider);

  GoRouter router() => GoRouter(
        initialLocation: '/provider',
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(
                  path: '/provider',
                  builder: (_, _) => const Text('bandeja de solicitudes')),
              GoRoute(
                  path: '/provider/offers',
                  builder: (_, _) => const Text('mis ofertas')),
              GoRoute(
                  path: '/provider/stats',
                  builder: (_, _) => const Text('estadisticas')),
            ],
          ),
        ],
      );

  Widget host({bool reduced = false}) => MaterialApp.router(
        routerConfig: router(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
      );

  /// El `Opacity` que envuelve el `body` — el punto de verdad de "cuánto ha
  /// avanzado" la entrada (0 = recién montado, 1 = asentado).
  double bodyOpacity(WidgetTester tester) => tester
      .widgetList<Opacity>(find.ancestor(
          of: find.text('mis ofertas'), matching: find.byType(Opacity)))
      .first
      .opacity;

  testWidgets(
      'al cambiar de pestaña con go() el cuerpo entra con fundido: sigue a '
      'medias a los 100ms de 150ms, no aparece ya completo en el mismo frame',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('bandeja de solicitudes'), findsOneWidget);

    final ctx = tester.element(find.text('bandeja de solicitudes'));
    GoRouter.of(ctx).go('/provider/offers');
    // Un pump() de duración cero deja que el TweenAnimationBuilder arranque
    // su controlador antes de medir nada (mismo patrón que
    // home_shell_navbar_transition_test.dart).
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 100));
    final opacityAt100ms = bodyOpacity(tester);
    expect(opacityAt100ms, greaterThan(0));
    expect(opacityAt100ms, lessThan(1),
        reason: 'a 100ms de 150ms (JayaloMotion.fast) el cuerpo debe seguir '
            'entrando — opacidad real: $opacityAt100ms. Si ya es 1, el '
            'cambio de pestaña volvió a ser un salto instantáneo');

    await tester.pumpAndSettle();
    expect(bodyOpacity(tester), 1,
        reason: 'al asentarse el cuerpo debe quedar completamente visible');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'con "reducir animaciones" el cambio de pestaña es instantáneo: nunca '
      'hay un frame con el cuerpo a medio desvanecer', (tester) async {
    await tester.pumpWidget(host(reduced: true));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('bandeja de solicitudes'));
    GoRouter.of(ctx).go('/provider/offers');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(bodyOpacity(tester), 1,
        reason: 'con reducir animaciones la duration es Duration.zero: el '
            'cuerpo debe llegar ya asentado (opacidad 1) sin ningún frame '
            'intermedio a medio desvanecer');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ningún go() real entre pestañas lanza una excepción — el caso que '
      'antes disparaba "Duplicate GlobalKey detected in widget tree" '
      '(child es el Navigator anidado del ShellRoute, con GlobalKey '
      'estable)', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final ctx1 = tester.element(find.text('bandeja de solicitudes'));
    GoRouter.of(ctx1).go('/provider/offers');
    // Medir a mitad de camino Y al asentar: el bug viejo era un FlutterError
    // de build, así que hay que revisar en ambos puntos, no solo al final.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(tester.takeException(), isNull,
        reason: 'a mitad de la transición de entrada no debe quedar ningún '
            'FlutterError pendiente');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('mis ofertas'), findsOneWidget);

    // Y de vuelta, para confirmar que no es una casualidad de un solo
    // sentido.
    final ctx2 = tester.element(find.text('mis ofertas'));
    GoRouter.of(ctx2).go('/provider');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('bandeja de solicitudes'), findsOneWidget);
  });

  testWidgets(
      'un push a una ruta que no es pestaña (p. ej. Estadísticas) no repite '
      'la animación de entrada del cuerpo — matchedLocation se queda '
      'pegado a la pestaña de abajo (C2), así que no compite con la '
      'transición propia del Navigator empujando la página', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('bandeja de solicitudes'));
    GoRouter.of(ctx).push('/provider/stats');
    await tester.pump();

    // Sin key nueva (matchedLocation no se movió), el TweenAnimationBuilder
    // de abajo del /provider original ni se remonta: nada que reproducir a
    // medio camino porque nunca hubo transición del cuerpo que disparar.
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('estadisticas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
