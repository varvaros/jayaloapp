import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// C2 (revisión final de rama, iteración 2 de la barra): `HomeShell` leía
/// `GoRouterState.of(context).matchedLocation`, que DENTRO del builder de un
/// `ShellRoute` solo se actualiza con `go` — no con `push`. El camino REAL de
/// la app usa `push` para entrar a un chat (`conversations_screen.dart`,
/// "Abrir chat" de `inbox_screen.dart`) y para abrir notificaciones
/// (`notifications_screen.dart`, rutas fuera de `_tabRoots`). Con el bug, la
/// barra flotante seguía viva DENTRO del chat (tapando el campo de escribir
/// con el teclado abierto) y `/provider/stats`/`/notifications` heredaban la
/// pestaña de abajo en vez de dar -1.
///
/// Cada caso se prueba con LOS DOS VERBOS a propósito: todos los tests
/// anteriores de este archivo (y de `home_shell_nav_visibility_test.dart`)
/// solo usaban `go` — el único verbo con el que el bug NO se manifiesta — así
/// que la suite entera pasaba con el código roto. Los casos marcados "con
/// push" deben fallar contra `matchedLocation` y pasar tras leer la ubicación
/// EFECTIVA del router.
void main() {
  setUp(() => roleStore.value = RoleState.provider);

  GoRouter router({required String initial}) => GoRouter(
        initialLocation: initial,
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(
                  path: '/provider',
                  builder: (_, _) => const Text('bandeja de solicitudes')),
              GoRoute(
                  path: '/provider/stats',
                  builder: (_, _) => const Text('estadisticas')),
              GoRoute(
                  path: '/notifications',
                  builder: (_, _) => const Text('notificaciones')),
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

  int currentNavIndex(WidgetTester tester) =>
      tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).currentIndex;

  group('la barra se oculta dentro de un chat', () {
    testWidgets('con go', (tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router(initial: '/messages')));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingNavBar), findsOneWidget);

      final ctx = tester.element(find.text('lista de conversaciones'));
      GoRouter.of(ctx).go('/messages/abc-123');
      await tester.pumpAndSettle();

      expect(find.byType(FloatingNavBar), findsNothing);
    });

    testWidgets('con push (el camino real de la app)', (tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router(initial: '/messages')));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingNavBar), findsOneWidget);

      final ctx = tester.element(find.text('lista de conversaciones'));
      GoRouter.of(ctx).push('/messages/abc-123');
      await tester.pumpAndSettle();

      expect(find.byType(FloatingNavBar), findsNothing,
          reason: 'con matchedLocation la ubicación efectiva se queda en '
              '/messages tras el push: la barra sigue viva encima del chat, '
              'tapando el campo de escribir');
    });
  });

  group('/provider/stats no enciende ninguna pestaña', () {
    testWidgets('con go', (tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router(initial: '/provider')));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('bandeja de solicitudes'));
      GoRouter.of(ctx).go('/provider/stats');
      await tester.pumpAndSettle();

      expect(currentNavIndex(tester), -1);
    });

    testWidgets('con push (el camino real: se llega por el avatar)',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router(initial: '/provider')));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('bandeja de solicitudes'));
      GoRouter.of(ctx).push('/provider/stats');
      await tester.pumpAndSettle();

      expect(currentNavIndex(tester), -1,
          reason: 'con matchedLocation la ubicación efectiva se queda en '
              '/provider tras el push: la barra enciende "Solicitudes" '
              'estando en Estadísticas');
    });
  });

  group('/notifications tampoco enciende ninguna pestaña', () {
    testWidgets('con go', (tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router(initial: '/provider')));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('bandeja de solicitudes'));
      GoRouter.of(ctx).go('/notifications');
      await tester.pumpAndSettle();

      expect(currentNavIndex(tester), -1);
    });

    testWidgets('con push (el camino real: campana del AppBar)',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router(initial: '/provider')));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('bandeja de solicitudes'));
      GoRouter.of(ctx).push('/notifications');
      await tester.pumpAndSettle();

      expect(currentNavIndex(tester), -1,
          reason: 'con matchedLocation la ubicación efectiva se queda en '
              '/provider tras el push: la barra enciende "Solicitudes" '
              'estando en Notificaciones');
    });
  });

  group('query string: /messages?c=<id> no rompe la comparación', () {
    testWidgets(
        'una ubicación con query se compara por su ruta, no revienta '
        'showsNavBar/activeIndex', (tester) async {
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router(initial: '/provider')));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('bandeja de solicitudes'));
      // mapLinkToRoute ya traduce esta forma a `/messages/<id>` antes de
      // navegar (domain/notifications.dart), pero la ubicación EFECTIVA no
      // debe depender de eso: si algo navegara alguna vez con la query
      // pegada, `uri.path` (no `uri.toString()`) es lo que hay que leer.
      GoRouter.of(ctx).push('/messages?c=abc-123');
      await tester.pumpAndSettle();

      // La ruta real (sin query) es `/messages`, que SÍ muestra la barra
      // (es la lista, no el detalle) y enciende la pestaña de Mensajes.
      expect(find.byType(FloatingNavBar), findsOneWidget,
          reason: 'una query colgada de /messages no debe leerse como si '
              'fuera /messages/<algo> (el detalle que oculta la barra)');
      expect(currentNavIndex(tester), 3);
    });
  });
}
