import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// M2 (revisión final de rama): `home_shell.dart` alternaba
/// `bottomNavigationBar` entre `FloatingNavBar` y `null` con un swap
/// instantáneo — al entrar y salir de un chat la barra aparecía/desaparecía
/// de golpe, contra la doctrina de movimiento (transiciones premium,
/// deslizado + ease-out; regla permanente del PO, 2026-07-18). Este test
/// cubre el contrato nuevo: el cambio se anima (fundido + colapso de alto
/// vía `SizeTransition`, sincronizados en el mismo `AnimatedSwitcher`) y con
/// "reducir animaciones" es instantáneo.
///
/// Deliberadamente NO toca `nav_bar_reserved_space_test.dart` (ese test
/// monta su propio `Scaffold` con `FloatingNavBar` directo, sin pasar por
/// `HomeShell`): esta suite solo prueba que el widget CAMBIA con transición,
/// nunca el alto reservado por las pantallas ni el alto real de la barra en
/// reposo.
void main() {
  setUp(() => roleStore.value = RoleState.consumer);

  GoRouter router() => GoRouter(
        initialLocation: '/messages',
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(
                  path: '/messages',
                  builder: (_, _) => const Text('lista de conversaciones')),
              GoRoute(
                  path: '/messages/:id',
                  builder: (_, s) =>
                      Text('conversación ${s.pathParameters['id']}')),
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

  testWidgets(
      'al entrar a un chat la barra se desvanece: sigue presente a mitad '
      'de la transición, no desaparece en el mismo frame', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsOneWidget);

    final ctx = tester.element(find.text('lista de conversaciones'));
    GoRouter.of(ctx).go('/messages/abc-123');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FloatingNavBar), findsOneWidget,
        reason: 'a mitad de la transición (JayaloMotion.base = 250ms) la '
            'barra debe seguir montada, desvaneciéndose — con el swap '
            'instantáneo viejo ya habría desaparecido en este mismo frame');

    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsNothing,
        reason: 'una vez completa la transición, la barra no debe dejar '
            'espacio muerto dentro del chat (tapa el campo de escribir)');
  });

  testWidgets(
      'al salir de un chat la barra reaparece con transición (no aparece '
      'ya completa en el mismo frame)', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final ctxMsgs = tester.element(find.text('lista de conversaciones'));
    GoRouter.of(ctxMsgs).go('/messages/abc-123');
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsNothing);

    final ctxChat = tester.element(find.text('conversación abc-123'));
    GoRouter.of(ctxChat).go('/messages');
    await tester.pump(const Duration(milliseconds: 50));

    // A mitad de camino las DOS entradas del `AnimatedSwitcher` coexisten:
    // la saliente (el placeholder que ocupaba el lugar de la barra dentro
    // del chat, `nav-bar-hidden`) todavía no terminó de desvanecerse cuando
    // la entrante (`FloatingNavBar`) ya empezó a aparecer — un cruce real,
    // no un salto instantáneo. (No se mide el alto de `FloatingNavBar`
    // mismo: ese widget siempre se layoutea a su tamaño natural completo,
    // aunque el `SizeTransition` que lo envuelve lo esté revelando a
    // medias — el widget en sí no es la señal útil aquí.)
    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-bar-hidden')), findsOneWidget,
        reason: 'a mitad de la transición de entrada el placeholder '
            'saliente debe seguir montado (desvaneciéndose) al mismo '
            'tiempo que la barra entrante — si ya desapareció, la barra '
            'apareció de golpe en vez de cruzar-desvanecer');

    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-bar-hidden')), findsNothing);
  });

  testWidgets(
      'con "reducir animaciones" el cambio es instantáneo: ningún frame '
      'intermedio con la barra a medio desvanecer', (tester) async {
    await tester.pumpWidget(host(reduced: true));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsOneWidget);

    final ctx = tester.element(find.text('lista de conversaciones'));
    GoRouter.of(ctx).go('/messages/abc-123');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FloatingNavBar), findsNothing,
        reason: 'con reducir animaciones la duración es Duration.zero: no '
            'debe quedar ningún frame con la barra todavía presente');
  });
}
