import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/features/chat/conversations_screen.dart';

/// Regresión del bug PO 2026-07-21: "el contador de pendientes de la
/// conversación no desaparece al entrar al chat".
///
/// Causa raíz: el atrás del chat hace `go('/messages')` y en go_router un
/// `go` REMUEVE la ruta apilada SIN completar el future de `context.push`
/// (solo `pop` lo completa) — así que el viejo `await push → _load()` de la
/// lista nunca corría y el unread_count quedaba viejo en pantalla aunque la
/// BD ya estuviera marcada leída. El fix escucha el delegate del router y
/// recarga cuando la lista vuelve a ser la ruta actual, venga por pop o go.
void main() {
  testWidgets('volver del chat con go(/messages) recarga la lista',
      (tester) async {
    var loads = 0;
    final router = GoRouter(
      initialLocation: '/messages',
      routes: [
        GoRoute(
          path: '/messages',
          builder: (_, _) => ConversationsScreen(
            leading: const SizedBox.shrink(),
            actions: const [],
            loadConversations: () async {
              loads++;
              return const <Map<String, dynamic>>[];
            },
          ),
        ),
        GoRoute(
          path: '/messages/:id',
          builder: (_, _) => const Scaffold(body: Text('chat')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(loads, 1, reason: 'carga inicial');

    // Entra a un chat (push apilado, como hace _open).
    router.push('/messages/abc');
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsOneWidget);
    expect(loads, 1, reason: 'entrar al chat no recarga la lista');

    // Atrás del chat = go('/messages') (pedido PO 2026-07-21). El future del
    // push NO se completa con esto — la recarga debe venir del listener.
    router.go('/messages');
    await tester.pumpAndSettle();
    expect(loads, 2,
        reason: 'al volver a la lista se recarga (badge/último mensaje)');

    // Y por pop también (el camino viejo sigue cubierto).
    router.push('/messages/abc');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(loads, 3, reason: 'volver por pop también recarga');
  });
}
