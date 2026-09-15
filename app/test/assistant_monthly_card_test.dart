import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:jayalo_app/core/assistant_client.dart';
import 'package:jayalo_app/features/provider/assistant_monthly_card.dart';

Widget montar({
  required Map<String, dynamic> respuesta,
  List<({String id, String name})> negocios = const [(id: 'b1', name: 'Gigio')],
}) =>
    MaterialApp(
      home: Scaffold(
        body: AssistantMonthlyCard(
          client: AssistantClient(
              inner: MockClient(
                  (_) async => http.Response(jsonEncode(respuesta), 200))),
          loadBusinesses: () async => negocios,
          tokenProvider: () => 'tok',
        ),
      ),
    );

void main() {
  testWidgets('sin suscripción: ofrece activar con el coste del servidor',
      (tester) async {
    await tester.pumpWidget(montar(
        respuesta: {'monthly_active_until': null, 'monthlyCost': 20}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin suscripción'), findsOneWidget);
    expect(find.textContaining('Activar'), findsOneWidget);
    expect(find.textContaining('20'), findsWidgets);
  });

  testWidgets('el coste NO es un literal', (tester) async {
    await tester.pumpWidget(montar(
        respuesta: {'monthly_active_until': null, 'monthlyCost': 35}));
    await tester.pumpAndSettle();
    expect(find.textContaining('35'), findsWidgets);
  });

  testWidgets('con suscripción: dice hasta cuándo y ofrece renovar',
      (tester) async {
    await tester.pumpWidget(montar(respuesta: {
      'monthly_active_until': '2026-10-15T00:00:00.000Z',
      'monthlyCost': 20,
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('activa hasta'), findsOneWidget);
    expect(find.textContaining('Renovar'), findsOneWidget);
  });

  testWidgets('con UN negocio no se pinta ningún selector', (tester) async {
    await tester.pumpWidget(montar(
        respuesta: {'monthly_active_until': null, 'monthlyCost': 20}));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('con DOS negocios sí se pinta el selector', (tester) async {
    await tester.pumpWidget(montar(
      respuesta: {'monthly_active_until': null, 'monthlyCost': 20},
      negocios: const [(id: 'b1', name: 'Gigio'), (id: 'b2', name: 'Otra')],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsOneWidget);
  });

  testWidgets('sin negocio la tarjeta no se pinta', (tester) async {
    await tester.pumpWidget(montar(
      respuesta: {'monthly_active_until': null, 'monthlyCost': 20},
      negocios: const [],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('mensual'), findsNothing);
  });

  testWidgets('si la lectura falla, la tarjeta no se pinta y la tienda sigue',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssistantMonthlyCard(
          client: AssistantClient(
              inner: MockClient((_) async =>
                  http.Response(jsonEncode({'error': 'Forbidden'}), 403))),
          loadBusinesses: () async => const [(id: 'b1', name: 'Gigio')],
          tokenProvider: () => 'tok',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('mensual'), findsNothing);
  });
}
