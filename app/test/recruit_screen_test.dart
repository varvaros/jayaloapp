import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/admin/recruit_screen.dart';

Map<String, dynamic> _fila(String id, String titulo) => {
      'id': id,
      'title': titulo,
      'zone': 'Piantini',
      'description': 'Descripcion',
      'budget_min': 1000,
      'budget_max': 2000,
      'urgency': 'normal',
      'kind': 'product',
      'created_at': '2026-09-14T10:00:00Z',
    };

Widget _app({
  List<Map<String, dynamic>>? filas,
  Map<String, int>? cobertura,
  Future<Map<String, int>> Function(List<String>)? coverage,
}) =>
    MaterialApp(
      home: RecruitScreen(
        load: ({int limit = 100}) async => filas ?? const [],
        coverage: coverage ?? (ids) async => cobertura ?? const {},
      ),
    );

void main() {
  testWidgets('arranca en "Sin proveedor" y solo pinta las de cobertura 0',
      (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r1', 'Silla de caoba'), _fila('r2', 'Nevera')],
      cobertura: {'r1': 0, 'r2': 3},
    ));
    await t.pumpAndSettle();
    expect(find.text('Silla de caoba'), findsOneWidget);
    expect(find.text('Nevera'), findsNothing);
    expect(find.text('Sin proveedor'), findsOneWidget);
  });

  testWidgets('en "Todas" salen las dos y LA CABECERA CAMBIA DE TEXTO',
      (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r1', 'Silla de caoba'), _fila('r2', 'Nevera')],
      cobertura: {'r1': 0, 'r2': 3},
    ));
    await t.pumpAndSettle();
    expect(find.text('1 sin proveedor'), findsOneWidget);

    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('Nevera'), findsOneWidget);
    // 🔴 La cabecera no puede seguir diciendo "sin proveedor" en "Todas": ese
    // fue uno de los siete defectos de la tanda del 2026-09-13.
    expect(find.text('2 abiertas'), findsOneWidget);
    expect(find.text('2 sin proveedor'), findsNothing);
    expect(find.text('3 proveedores'), findsOneWidget);
  });

  testWidgets('los dos vacios dicen cosas DISTINTAS', (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r2', 'Nevera')],
      cobertura: {'r2': 3},
    ));
    await t.pumpAndSettle();
    expect(find.text('Ninguna solicitud abierta se quedó sin proveedor'),
        findsOneWidget);

    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('Nevera'), findsOneWidget);
  });

  testWidgets('sin ninguna solicitud abierta, el vacio de "Todas" es el suyo',
      (t) async {
    await t.pumpWidget(_app(filas: const []));
    await t.pumpAndSettle();
    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('No hay solicitudes abiertas'), findsOneWidget);
  });

  testWidgets('si la cobertura falla, la lista se pinta SIN chips y sin reventar',
      (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r1', 'Silla de caoba')],
      coverage: (ids) async => throw Exception('sin red'),
    ));
    await t.pumpAndSettle();
    // Cae a "Todas" porque sin cobertura no se puede saber que es un hueco.
    expect(find.text('Silla de caoba'), findsOneWidget);
    expect(find.text('Sin proveedor'), findsNothing);
    // `pumpAndSettle` no falla por una excepcion que el framework ya capturo;
    // esto la hace explicita (idioma de la suite: brand_kit_test.dart:174).
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'un id AUSENTE del mapa de cobertura es desconocido, no un hueco',
      (t) async {
    // r1 no aparece en `cobertura`: simula que dejo de existir entre listar
    // y pedir cobertura. NO puede pintarse como "Sin proveedor" (eso seria
    // afirmar un hueco que no se pudo comprobar), asi que en "Sin proveedor"
    // no debe salir, y en "Todas" no debe llevar chip.
    await t.pumpWidget(_app(
      filas: [_fila('r1', 'Silla de caoba'), _fila('r2', 'Nevera')],
      cobertura: {'r2': 3},
    ));
    await t.pumpAndSettle();
    expect(find.text('Silla de caoba'), findsNothing);
    expect(find.text('0 sin proveedor'), findsOneWidget);
    expect(find.text('Ninguna solicitud abierta se quedó sin proveedor'),
        findsOneWidget);

    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('Silla de caoba'), findsOneWidget);
    expect(find.text('Sin proveedor'), findsNothing);
    expect(find.text('3 proveedores'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('si la lista falla, ofrece reintentar', (t) async {
    await t.pumpWidget(MaterialApp(
      home: RecruitScreen(
        load: ({int limit = 100}) async => throw Exception('sin red'),
        coverage: (ids) async => const {},
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
