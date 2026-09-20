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

  testWidgets('con targetBusinessId abre el creador con ?business=', (
    tester,
  ) async {
    String? ultimaRuta;
    final router = GoRouter(
      initialLocation: '/client',
      routes: [
        GoRoute(
          path: '/client',
          builder: (context, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  pushCreateRequestOnce(context, targetBusinessId: 'b-123'),
              child: const Text('cotizar'),
            ),
          ),
        ),
        GoRoute(
          path: '/client/create',
          builder: (_, state) {
            ultimaRuta = state.uri.toString();
            return const Scaffold(body: Text('ventana'));
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cotizar'));
    await tester.pumpAndSettle();
    expect(find.text('ventana'), findsOneWidget);
    expect(ultimaRuta, '/client/create?business=b-123');
  });

  testWidgets(
    // Bug M-16 (revisión final 09-20): `?seedFrom` (spread null-aware de
    // mapa) dejaba pasar la cadena vacía, mientras `business` exigía
    // `isNotEmpty` — dos criterios distintos para "ausente". Con
    // `seedFrom: ''` el guard viejo mandaba `?seedFrom=` a la pantalla
    // destino en vez de omitirlo.
    'con seedFrom vacío ("") NO manda el parámetro, igual que con business vacío',
    (tester) async {
      String? ultimaRuta;
      final router = GoRouter(
        initialLocation: '/client',
        routes: [
          GoRoute(
            path: '/client',
            builder: (context, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () => pushCreateRequestOnce(context, seedFrom: ''),
                child: const Text('crear'),
              ),
            ),
          ),
          GoRoute(
            path: '/client/create',
            builder: (_, state) {
              ultimaRuta = state.uri.toString();
              return const Scaffold(body: Text('ventana'));
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('crear'));
      await tester.pumpAndSettle();
      expect(find.text('ventana'), findsOneWidget);
      expect(ultimaRuta, '/client/create');
    },
  );

  testWidgets(
    'business Y seedFrom juntos sobreviven los dos, sin que uno pise al otro',
    (tester) async {
      String? ultimaRuta;
      final router = GoRouter(
        initialLocation: '/client',
        routes: [
          GoRoute(
            path: '/client',
            builder: (context, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () => pushCreateRequestOnce(
                  context,
                  targetBusinessId: 'b-123',
                  seedFrom: 'abc-123',
                ),
                child: const Text('crear'),
              ),
            ),
          ),
          GoRoute(
            path: '/client/create',
            builder: (_, state) {
              ultimaRuta = state.uri.toString();
              return const Scaffold(body: Text('ventana'));
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('crear'));
      await tester.pumpAndSettle();
      expect(find.text('ventana'), findsOneWidget);
      // La pantalla destino lee `business` y `seedFrom` por CLAVE
      // (`core/router.dart`), así que lo que importa es que las dos lleguen
      // con su valor — se ancla también la forma exacta de la URL (mismo
      // orden con el que las arma `pushCreateRequestOnce`).
      expect(ultimaRuta, '/client/create?business=b-123&seedFrom=abc-123');
    },
  );
}
