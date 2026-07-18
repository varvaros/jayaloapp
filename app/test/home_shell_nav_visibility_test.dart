import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// `HomeShell` decide si monta `FloatingNavBar` según `showsNavBar` (lógica
/// pura probada en `nav_destinations_test.dart`). Este test cubre el cableado
/// real: que el `Scaffold` de verdad deja de montar la barra en el detalle de
/// una conversación, y sí la monta en la lista — necesita un `GoRouter` de
/// verdad porque `HomeShell` lee `GoRouterState.of(context).matchedLocation`.
///
/// Las pantallas reales del shell (chat, lista de conversaciones) cargan
/// Supabase; aquí bastan hijos de mentira, así que el router se arma con las
/// dos rutas mínimas que hacen falta para el contraste.
void main() {
  setUp(() => roleStore.value = RoleState.consumer);

  GoRouter routerAt(String location) => GoRouter(
        initialLocation: location,
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

  testWidgets('la lista de conversaciones sí monta la barra',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp.router(routerConfig: routerAt('/messages')));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavBar), findsOneWidget);
  });

  testWidgets('el detalle de una conversación no monta la barra',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp.router(routerConfig: routerAt('/messages/abc-123')));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavBar), findsNothing);
  });
}
