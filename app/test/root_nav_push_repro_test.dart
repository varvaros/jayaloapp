import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/back_guard.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// Regresión de los 3 bugs de QA 2026-07-21 ("no abre el chat", "no abre la
/// tienda"): las rutas full-screen (`/messages/:id`, `/store/:bid`) deben vivir
/// FUERA del ShellRoute, como top-level del navigator raíz. Declararlas DENTRO
/// del shell con `parentNavigatorKey` raíz dispara un assert de go_router que
/// en release se elimina — y el push falla en silencio (la página nunca se
/// monta). Este test replica la estructura de core/router.dart y verifica que
/// el push desde una pestaña del shell de verdad monta la página.
void main() {
  setUp(() => roleStore.value = RoleState.consumer);

  GoRouter buildTestRouter(GlobalKey<NavigatorState> rootKey) => GoRouter(
        initialLocation: '/client',
        navigatorKey: rootKey,
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(
                  path: '/client',
                  builder: (_, _) => const BackGuard(child: Text('home'))),
            ],
          ),
          // Como en core/router.dart: full-screen = hermanas del shell.
          GoRoute(
              path: '/store/:bid',
              pageBuilder: (context, s) => CustomTransitionPage(
                    key: s.pageKey,
                    transitionsBuilder: (context, animation, _, child) =>
                        SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(1, 0), end: Offset.zero)
                          .animate(animation),
                      child: child,
                    ),
                    child: BackGuard(
                        child: Text('tienda ${s.pathParameters['bid']}')),
                  )),
          GoRoute(
              path: '/messages/:id',
              pageBuilder: (context, s) => CustomTransitionPage(
                    key: s.pageKey,
                    transitionsBuilder: (context, animation, _, child) =>
                        SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(1, 0), end: Offset.zero)
                          .animate(animation),
                      child: child,
                    ),
                    child: BackGuard(
                        child: Text('chat ${s.pathParameters['id']}')),
                  )),
        ],
      );

  testWidgets('push a /messages/:id y /store/:bid abre encima del shell',
      (tester) async {
    final router = buildTestRouter(GlobalKey<NavigatorState>());
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    router.push('/messages/abc');
    await tester.pumpAndSettle();
    expect(find.text('chat abc'), findsOneWidget,
        reason: 'el chat debe abrirse encima del shell');

    router.push('/store/b1');
    await tester.pumpAndSettle();
    expect(find.text('tienda b1'), findsOneWidget,
        reason: 'la tienda debe abrirse encima del chat');
  });

  testWidgets(
      'GOTCHA: parentNavigatorKey raíz DENTRO del shell revienta el assert '
      'de go_router (por eso las full-screen van top-level)', (tester) async {
    final rootKey = GlobalKey<NavigatorState>();
    expect(
        () => GoRouter(
              navigatorKey: rootKey,
              routes: [
                ShellRoute(
                  builder: (_, _, child) => child,
                  routes: [
                    GoRoute(path: '/x', builder: (_, _) => const Text('x')),
                    GoRoute(
                        path: '/y',
                        parentNavigatorKey: rootKey,
                        builder: (_, _) => const Text('y')),
                  ],
                ),
              ],
            ),
        throwsAssertionError);
  });
}
