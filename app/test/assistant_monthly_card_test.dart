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

  testWidgets('con UN negocio nada cambia en pantalla (ni selector ni aviso)',
      (tester) async {
    await tester.pumpWidget(montar(
        respuesta: {'monthly_active_until': null, 'monthlyCost': 20}));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.textContaining('Se aplica a'), findsNothing);
  });

  testWidgets(
      'con DOS negocios: NUNCA un selector — dice a cuál se aplica (el '
      'primero, el mismo que usaría el servidor)', (tester) async {
    await tester.pumpWidget(montar(
      respuesta: {'monthly_active_until': null, 'monthlyCost': 20},
      negocios: const [(id: 'b1', name: 'Gigio'), (id: 'b2', name: 'Otra')],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.textContaining('Se aplica a Gigio'), findsOneWidget);
  });

  testWidgets('sin costo mensual válido no se pinta el botón con un 0',
      (tester) async {
    await tester.pumpWidget(
        montar(respuesta: {'monthly_active_until': null, 'monthlyCost': 0}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin suscripción'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('Activar'), findsNothing);
  });

  testWidgets('sin negocio la tarjeta no se pinta', (tester) async {
    await tester.pumpWidget(montar(
      respuesta: {'monthly_active_until': null, 'monthlyCost': 20},
      negocios: const [],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('mensual'), findsNothing);
  });

  testWidgets(
      'si la PRIMERA lectura falla (nunca se pintó nada), la tarjeta no se '
      'pinta y la tienda sigue', (tester) async {
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

  testWidgets(
      'un fallo al RECARGAR (tras suscribirse) no borra lo ya pintado',
      (tester) async {
    var lecturas = 0;
    final client = AssistantClient(inner: MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (body['action'] == 'subscribe') {
        return http.Response(
            jsonEncode(
                {'charged': 20, 'expires_at': '2026-10-15T00:00:00.000Z'}),
            200);
      }
      // La carga inicial (initState) sale bien; la recarga posterior — la
      // que dispara `_suscribir` al terminar — se cae.
      lecturas++;
      if (lecturas == 1) {
        return http.Response(
            jsonEncode({'monthly_active_until': null, 'monthlyCost': 20}),
            200);
      }
      return http.Response(jsonEncode({'error': 'Forbidden'}), 403);
    }));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssistantMonthlyCard(
          client: client,
          loadBusinesses: () async => const [(id: 'b1', name: 'Gigio')],
          tokenProvider: () => 'tok',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Activar'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Se cobró y se avisó, pero la recarga posterior falló: la tarjeta
    // sigue mostrando lo último que supo en vez de desaparecer, y ofrece
    // reintentar.
    expect(find.textContaining('mensual'), findsWidgets);
    expect(find.textContaining('No se pudo actualizar'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
  });
}
