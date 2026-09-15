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

  testWidgets(
      'maestro apagado explica el alcance: no es solo este chat, es el negocio',
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
    expect(find.textContaining('No responderá en ningún chat de este negocio'),
        findsOneWidget);
  });

  testWidgets('apagado sin coste válido: no pinta un «Activar 🪙 0»',
      (tester) async {
    await tester.pumpWidget(montar(clienteQueDevuelve({
      'active': false,
      'paused': false,
      'handoverRequested': false,
      'enabled': true,
      'perChatCost': 0,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Asistente'), findsNothing);
  });

  testWidgets('si activar falla (p. ej. timeout), la barra se refresca igual',
      (tester) async {
    var lecturas = 0;
    final client = AssistantClient(inner: MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (body['action'] == 'activate') {
        return http.Response(jsonEncode({'error': 'timeout'}), 504);
      }
      // El primer estado (antes de pulsar) sale apagado; el servidor SÍ
      // activó el chat pese a que la respuesta de `activate` no llegó, así
      // que la lectura siguiente ya lo ve activo.
      lecturas++;
      final activo = lecturas > 1;
      return http.Response(
          jsonEncode({
            'active': activo,
            'paused': false,
            'handoverRequested': false,
            'enabled': true,
            'perChatCost': 2,
          }),
          200);
    }));
    await tester.pumpWidget(montar(client));
    await tester.pumpAndSettle();
    expect(find.textContaining('Activar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Activar'));
    await tester.pumpAndSettle();

    // El POST de activar falló, pero la barra volvió a preguntar por el
    // estado y ahora sabe que el chat SÍ quedó activo: no puede seguir
    // mintiendo con «Activar».
    expect(find.text('Asistente IA activo'), findsOneWidget);
  });

  testWidgets('si no hay respuesta, dice el motivo traducido — no el crudo',
      (tester) async {
    final client = AssistantClient(inner: MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (body['action'] == 'reply') {
        return http.Response(
            jsonEncode({'sent': false, 'reason': 'handover'}), 200);
      }
      return http.Response(
          jsonEncode({
            'active': true,
            'paused': false,
            'handoverRequested': false,
            'enabled': true,
            'perChatCost': 2,
          }),
          200);
    }));
    await tester.pumpWidget(montar(client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Responder ahora'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('pidió hablar con una persona'), findsOneWidget);
    expect(find.textContaining('(handover)'), findsNothing);
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
