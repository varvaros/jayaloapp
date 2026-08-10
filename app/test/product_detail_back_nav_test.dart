import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/back_guard.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// Pedido PO 2026-08-09: "Si estoy en el perfil de un proveedor y veo el
/// producto o servicio y le doy atrás, debe caer en el mismo perfil". Antes
/// del fix, `/product/:id` (ruta top-level empujada SOLO desde `/store/:bid`
/// — ver `product_list_card.dart`) no tenía caso propio en `backActionFor` y
/// caía en la regla general `goHome`, que hacía `context.go(home)` y se
/// saltaba la tienda por completo. Réplica de la estructura real de
/// `core/router.dart` (mismo patrón que `root_nav_push_repro_test.dart`), con
/// stubs de texto en vez de las pantallas reales — lo que se prueba es el
/// CABLEADO de navegación, no el contenido de las pantallas.
void main() {
  setUp(() => roleStore.value = RoleState.consumer);

  GoRouter buildTestRouter() => GoRouter(
        initialLocation: '/client',
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(
                  path: '/client',
                  builder: (_, _) => const BackGuard(child: Text('home'))),
              GoRoute(
                  path: '/catalog',
                  builder: (_, _) =>
                      const BackGuard(child: Text('catálogo'))),
              GoRoute(
                  path: '/catalog/:id',
                  builder: (_, s) => BackGuard(
                      child:
                          Text('detalle catálogo ${s.pathParameters['id']}'))),
            ],
          ),
          // Top-level, como en core/router.dart: la tienda y el detalle de
          // producto abierto desde ella viven FUERA del ShellRoute.
          GoRoute(
              path: '/store/:bid',
              builder: (_, s) => BackGuard(
                  child: Text('tienda ${s.pathParameters['bid']}'))),
          GoRoute(
              path: '/product/:id',
              builder: (_, s) => BackGuard(
                  child:
                      Text('detalle producto ${s.pathParameters['id']}'))),
        ],
      );

  testWidgets(
      'tienda→detalle→ATRÁS DEL SISTEMA deja la tienda visible',
      (tester) async {
    final router = buildTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/store/b1');
    await tester.pumpAndSettle();
    expect(find.text('tienda b1'), findsOneWidget);

    router.push('/product/p1');
    await tester.pumpAndSettle();
    expect(find.text('detalle producto p1'), findsOneWidget);

    final atendido = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(atendido, isTrue);
    expect(find.text('tienda b1'), findsOneWidget,
        reason: 'el atrás del sistema debe volver a la MISMA tienda de la '
            'que se vino, no saltar al home');
    expect(find.text('detalle producto p1'), findsNothing);
  });

  testWidgets(
      'tienda→detalle→botón de atrás EN PANTALLA (context.pop) deja la '
      'tienda visible', (tester) async {
    final router = buildTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/store/b1');
    await tester.pumpAndSettle();
    router.push('/product/p1');
    await tester.pumpAndSettle();
    expect(find.text('detalle producto p1'), findsOneWidget);

    // Mismo camino que `productBackButton` en product_detail_screen.dart:
    // `context.pop()` directo, no pasa por BackGuard.
    final ctx = tester.element(find.text('detalle producto p1'));
    GoRouter.of(ctx).pop();
    await tester.pumpAndSettle();

    expect(find.text('tienda b1'), findsOneWidget);
    expect(find.text('detalle producto p1'), findsNothing);
  });

  testWidgets('catálogo→detalle→ATRÁS DEL SISTEMA deja el catálogo visible',
      (tester) async {
    final router = buildTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go('/catalog');
    await tester.pumpAndSettle();
    router.push('/catalog/p1');
    await tester.pumpAndSettle();
    expect(find.text('detalle catálogo p1'), findsOneWidget);

    final atendido = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(atendido, isTrue);
    expect(find.text('catálogo'), findsOneWidget,
        reason: 'no debe caer en "Solicitudes" — regresión ya cubierta por '
            'backActionFor, replicada aquí a nivel widget');
    expect(find.text('detalle catálogo p1'), findsNothing);
  });

  testWidgets(
      'detalle de producto SIN tienda debajo (deep-link directo): ATRÁS no '
      'queda atrapado, sigue la regla general (goHome)', (tester) async {
    final router = GoRouter(
      initialLocation: '/product/p1',
      routes: [
        ShellRoute(
          builder: (_, _, child) => HomeShell(child: child),
          routes: [
            GoRoute(
                path: '/client',
                builder: (_, _) => const BackGuard(child: Text('home'))),
          ],
        ),
        GoRoute(
            path: '/product/:id',
            builder: (_, s) => BackGuard(
                child: Text('detalle producto ${s.pathParameters['id']}'))),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('detalle producto p1'), findsOneWidget);

    final atendido = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(atendido, isTrue);
    expect(find.text('home'), findsOneWidget,
        reason: 'sin nada debajo que revelar, cae a la regla general en vez '
            'de quedarse atrapado en el detalle');
  });
}
