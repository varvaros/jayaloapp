import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/create_request_nav.dart';

/// Regresión del bug del PO (2026-07-28): "si le doy varias veces al botón de
/// crear solicitud, la ventana sale varias veces una arriba de la otra".
///
/// El guardia viejo leía la ruta del `build` (un frame por detrás), así que dos
/// toques seguidos entraban ambos. El helper decide con la ruta VIVA del
/// router, que sí se actualiza síncrona dentro del `push`.
void main() {
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/client',
        routes: [
          GoRoute(
            path: '/client',
            builder: (context, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => pushCreateRequestOnce(context),
                  child: const Text('crear'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/client/create',
            builder: (_, _) => const Scaffold(body: Text('ventana')),
          ),
        ],
      );

  testWidgets('tres toques seguidos apilan UNA sola ventana', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Sin bombear frames entre toques: reproduce el doble/triple tap real.
    await tester.tap(find.text('crear'));
    await tester.tap(find.text('crear'), warnIfMissed: false);
    await tester.tap(find.text('crear'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('ventana'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.matches
          .where((m) => m.matchedLocation == '/client/create')
          .length,
      1,
      reason: 'solo puede haber una copia de la ventana en la pila',
    );
  });

  testWidgets('un solo toque sí abre la ventana', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('crear'));
    await tester.pumpAndSettle();

    expect(find.text('ventana'), findsOneWidget);
  });

  testWidgets('seedFrom viaja como query param', (tester) async {
    // No se verifica con `currentConfiguration.uri`: en go_router 17.3.0 esa
    // propiedad documenta explícitamente que excluye los `ImperativeRouteMatch`
    // (los que vienen de `push`, ver `match.dart:546-547`) — se queda
    // congelada en la ruta de base ('/client') aunque el `push` haya
    // funcionado. Se verifica lo que de verdad le llega a la pantalla
    // destino: `GoRouterState.of(context).uri`, la misma fuente que leería
    // `create_request_screen.dart` para extraer `seedFrom`.
    String? capturedUri;
    final router = GoRouter(
      initialLocation: '/client',
      routes: [
        GoRoute(
          path: '/client',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    pushCreateRequestOnce(context, seedFrom: 'abc-123'),
                child: const Text('crear'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/client/create',
          builder: (_, state) {
            capturedUri = state.uri.toString();
            return const Scaffold(body: Text('ventana'));
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('crear'));
    await tester.pumpAndSettle();

    expect(capturedUri, '/client/create?seedFrom=abc-123');
  });
}
