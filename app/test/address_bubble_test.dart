import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/chat.dart';
import 'package:jayalo_app/features/chat/widgets/bubbles.dart';

Widget _host(ChatMessage m) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => buildBubble(
            ctx,
            m,
            own: false,
            groupEnd: true,
            peerAvatarUrl: null,
            onImageTap: (_) {},
            onQuickAnswer: (_, _) {},
            canAnswerQuick: false,
          ),
        ),
      ),
    );

ChatMessage _msg(String body) => ChatMessage(
      id: 'm1',
      senderId: 'u1',
      kind: 'address',
      body: body,
      createdAtRaw: '2026-08-04T12:00:00Z',
    );

void main() {
  const url = 'https://www.google.com/maps/search/?api=1&query=18.48,-69.85';

  testWidgets('con enlace: sale el boton y la URL cruda NO se pinta', (t) async {
    await t.pumpWidget(_host(_msg('Calle Primera 12\nParque del Este\n$url')));
    expect(find.text('Abrir en el mapa'), findsOneWidget);
    expect(find.text('Calle Primera 12\nParque del Este'), findsOneWidget);
    expect(find.text(url), findsNothing);
    // con enlace
    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.text('Dirección'), findsNothing);
  });

  testWidgets('sin enlace: la burbuja se ve como siempre', (t) async {
    await t.pumpWidget(_host(_msg('Calle Primera 12')));
    expect(find.text('Abrir en el mapa'), findsNothing);
    expect(find.text('Calle Primera 12'), findsOneWidget);
    // sin enlace
    expect(find.text('Dirección'), findsOneWidget);
    expect(find.text('Ubicación'), findsNothing);
  });
}
