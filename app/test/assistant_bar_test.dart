import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:jayalo_app/core/assistant_client.dart';
import 'package:jayalo_app/features/chat/widgets/assistant_bar.dart';
import 'package:jayalo_app/features/shared/moneda.dart';

AssistantClient clienteQueDevuelve(Map<String, dynamic> body) =>
    AssistantClient(inner: MockClient((_) async => http.Response(jsonEncode(body), 200)));

Widget montar(AssistantClient c) => MaterialApp(
      home: Scaffold(
        body: AssistantBar(
          conversationId: 'conv-1',
          client: c,
          tokenProvider: () => 'tok',
        ),
      ),
    );

void main() {
  testWidgets('apagado: ofrece activar con el coste del servidor',
      (tester) async {
    await tester.pumpWidget(montar(clienteQueDevuelve({
      'active': false,
      'paused': false,
      'handoverRequested': false,
      'enabled': true,
      'perChatCost': 3,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Activar'), findsOneWidget);
    expect(find.textContaining('3'), findsOneWidget);
  });

  testWidgets('activo: ofrece responder y pausar', (tester) async {
    await tester.pumpWidget(montar(clienteQueDevuelve({
      'active': true,
      'paused': false,
      'handoverRequested': false,
      'enabled': true,
      'perChatCost': 2,
    })));
    await tester.pumpAndSettle();
    expect(find.text('Asistente IA activo'), findsOneWidget);
    expect(find.byTooltip('Pausar'), findsOneWidget);
  });

  testWidgets('pausado: ofrece reactivar', (tester) async {
    await tester.pumpWidget(montar(clienteQueDevuelve({
      'active': true,
      'paused': true,
      'handoverRequested': false,
      'enabled': true,
      'perChatCost': 2,
    })));
    await tester.pumpAndSettle();
    expect(find.text('Asistente IA pausado'), findsOneWidget);
    expect(find.byTooltip('Reactivar'), findsOneWidget);
  });

  testWidgets('el cliente pidió humano se ve', (tester) async {
    await tester.pumpWidget(montar(clienteQueDevuelve({
      'active': true,
      'paused': false,
      'handoverRequested': true,
      'enabled': true,
      'perChatCost': 2,
    })));
    await tester.pumpAndSettle();
    expect(find.text('Cliente pidió humano'), findsOneWidget);
  });

  testWidgets('maestro apagado: se enciende DESDE LA APP, sin mandar a la web',
      (tester) async {
    await tester.pumpWidget(montar(clienteQueDevuelve({
      'active': true,
      'paused': false,
      'handoverRequested': false,
      'enabled': false,
      'perChatCost': 2,
    })));
    await tester.pumpAndSettle();
    expect(find.text('Asistente IA apagado'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Encender'), findsOneWidget);
    // Gratis: el chat ya se cobró al activarlo, así que NO lleva moneda.
    expect(find.byType(MonedaJayalo), findsNothing);
    // Y nada que mande al proveedor fuera de la app.
    expect(find.textContaining('web'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('si el estado falla, la barra no se pinta', (tester) async {
    final c = AssistantClient(
        inner: MockClient((_) async =>
            http.Response(jsonEncode({'error': 'Forbidden'}), 403)));
    await tester.pumpWidget(montar(c));
    await tester.pumpAndSettle();
    expect(find.textContaining('Asistente'), findsNothing);
  });

  testWidgets('sin sesión no se pinta nada', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssistantBar(
          conversationId: 'conv-1',
          client: clienteQueDevuelve(const {}),
          tokenProvider: () => null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Asistente'), findsNothing);
  });
}
