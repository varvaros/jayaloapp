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
/// H1 (revisión final de rama, iteración 2 de la barra): la versión anterior
/// de este archivo navegaba con `go()` en los tres tests — el ÚNICO verbo con
/// el que C2 (matchedLocation vs. ubicación efectiva) NO se manifestaba, así
/// que la suite pasaba igual con o sin el bug. El camino REAL para entrar a
/// un chat es `push` (`conversations_screen.dart`, "Abrir chat" de
/// `inbox_screen.dart`); se corrige aquí. Además, `pump(Duration(milliseconds:
/// 50))` llamado INMEDIATAMENTE tras el `push()`/`go()` no alcanza a avanzar
/// la animación: hace falta un `pump()` de duración cero primero para que el
/// `AnimatedSwitcher` reaccione al cambio de ubicación y arranque su
/// controlador — sin eso, ese primer `pump(50ms)` mide el frame INICIAL (alto
/// completo, 132.0), no "a mitad de camino" como decía el test.
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

  /// El alto REAL que ocupa el `SizeTransition` que envuelve la barra —no el
  /// de `FloatingNavBar` mismo: ese widget siempre se layoutea a su tamaño
  /// natural completo, aunque el `SizeTransition` que lo envuelve lo esté
  /// revelando a medias (recorta el render, no reduce las restricciones del
  /// hijo). El alto que de verdad "se reserva" en el `Scaffold` es el de este
  /// `SizeTransition`, que sí encoge en sincronía con `sizeFactor`.
  double reservedHeight(WidgetTester tester) => tester
      .getSize(find.ancestor(
          of: find.byType(FloatingNavBar), matching: find.byType(SizeTransition)))
      .height;

  testWidgets(
      'al entrar a un chat la barra se desvanece: sigue presente a mitad '
      'de la transición, no desaparece en el mismo frame', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsOneWidget);

    final ctx = tester.element(find.text('lista de conversaciones'));
    // C2: el camino real de la app usa `push`, no `go` — con el bug viejo
    // (`matchedLocation`) este test habría pasado igual sin detectarlo.
    GoRouter.of(ctx).push('/messages/abc-123');
    // Un `pump()` de duración cero deja que el `AnimatedSwitcher` reaccione
    // al cambio de ubicación y arranque su controlador ANTES de medir nada
    // — sin este paso, el siguiente `pump(125ms)` se comería esos 125ms
    // dentro del mismo frame en el que la animación recién empieza.
    await tester.pump();
    final fullHeight = reservedHeight(tester);

    // JayaloMotion.base = 250ms: 125ms es la mitad exacta del recorrido.
    await tester.pump(const Duration(milliseconds: 125));

    expect(find.byType(FloatingNavBar), findsOneWidget,
        reason: 'a mitad de la transición (JayaloMotion.base = 250ms) la '
            'barra debe seguir montada, desvaneciéndose — con el swap '
            'instantáneo viejo ya habría desaparecido en este mismo frame');

    // La aserción que faltaba (H1): lo que justifica usar `SizeTransition` en
    // vez de una traslación es que el ALTO RESERVADO baja gradualmente, no
    // que la barra simplemente se desvanezca en el sitio. Sin esto, nada ata
    // la propiedad por la que se eligió `SizeTransition`.
    final halfwayHeight = reservedHeight(tester);
    expect(halfwayHeight, lessThan(fullHeight * .5),
        reason: 'a mitad de camino el alto reservado ($halfwayHeight) debe '
            'haber bajado bastante del alto completo ($fullHeight) — '
            'easeInCubic (JayaloMotion.exit) acelera al irse, así que a '
            't=0.5 ya está bien por debajo de la mitad lineal');

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
    // Entrar por el camino real (push); salir de un chat SÍ es `go` en esta
    // app — `BackGuard`/`backActionFor` siempre resuelve el atrás fuera del
    // home como `context.go(home)`, nunca como un pop crudo (ver
    // `back_intent.dart`), así que este `go()` no es el verbo equivocado.
    GoRouter.of(ctxMsgs).push('/messages/abc-123');
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsNothing);

    final ctxChat = tester.element(find.text('conversación abc-123'));
    GoRouter.of(ctxChat).go('/messages');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));

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
    GoRouter.of(ctx).push('/messages/abc-123');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));

    expect(find.byType(FloatingNavBar), findsNothing,
        reason: 'con reducir animaciones la duración es Duration.zero: no '
            'debe quedar ningún frame con la barra todavía presente');
  });
}
