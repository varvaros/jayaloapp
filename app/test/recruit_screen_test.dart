import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/admin/recruit_screen.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart'
    show timeAgo;

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
    // 🔴 "Sin proveedor" sale DOS veces en pantalla (la pastilla del filtro
    // y el chip de la fila) siempre que la cobertura cargó bien — acotar al
    // `ListTile` es lo único que distingue el chip de la fila. Sin el
    // `descendant`, esto cuenta la pastilla también y falla en falso (dice
    // 2 cuando la intención era comprobar 1 fila con chip).
    expect(
        find.descendant(
            of: find.byType(ListTile), matching: find.text('Sin proveedor')),
        findsOneWidget);
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
    // Aquí SÍ vale `find.text` sin acotar: con la cobertura caída no se
    // pinta ni la pastilla (va tras `if (_coberturaOk)`) ni ningún chip.
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
    // 🔴 La pastilla del filtro SIGUE diciendo "Sin proveedor" aquí (la
    // cobertura cargó bien, solo cambió qué segmento está seleccionado):
    // un `find.text` sin acotar encontraría la pastilla y este `findsNothing`
    // fallaría en falso. Acotar al `ListTile` es lo que de verdad comprueba
    // que NINGUNA fila visible lleva el chip (r1 quedó sin entrada en el
    // mapa de cobertura, así que no pinta chip; ver el `containsKey` de
    // `_visibles`).
    expect(
        find.descendant(
            of: find.byType(ListTile), matching: find.text('Sin proveedor')),
        findsNothing);
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

  // `created_at` viaja en `kAdminListCols` desde siempre "para pintar la
  // fecha" pero la fila nunca la usaba. Se fija a 5 días: lo bastante lejos
  // de "ahora" para que los milisegundos que tarda el test en correr no
  // puedan empujarla a un día distinto (un `hace 0 min` sí sería frágil).
  testWidgets('la fila pinta la fecha relativa de created_at', (t) async {
    final creadaEn = DateTime.now().subtract(const Duration(days: 5));
    await t.pumpWidget(_app(
      filas: [
        {..._fila('r1', 'Silla de caoba'), 'created_at': creadaEn.toIso8601String()},
      ],
      cobertura: {'r1': 0},
    ));
    await t.pumpAndSettle();
    expect(find.text(timeAgo(creadaEn)), findsOneWidget);
  });

  group('pull-to-refresh', () {
    testWidgets(
        'refrescar NO reemplaza la lista por un spinner a pantalla completa',
        (t) async {
      var llamadas = 0;
      final segundaCarga = Completer<List<Map<String, dynamic>>>();
      await t.pumpWidget(MaterialApp(
        home: RecruitScreen(
          load: ({int limit = 100}) {
            llamadas++;
            if (llamadas == 1) {
              return Future.value([_fila('r1', 'Silla de caoba')]);
            }
            return segundaCarga.future;
          },
          coverage: (ids) async => {'r1': 0},
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Silla de caoba'), findsOneWidget);

      // Gesto real de pull-to-refresh (mismo patrón que
      // conversations_screen_test.dart) sobre la lista ya montada.
      await t.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      // La segunda carga (llamadas == 2) sigue PENDIENTE (el Completer no se
      // ha resuelto): si `_cargar` hubiera vuelto a poner `_cargando = true`,
      // el body entero se reemplazaría por el `CircularProgressIndicator`
      // centrado y esta fila desaparecería.
      expect(llamadas, 2);
      expect(find.text('Silla de caoba'), findsOneWidget);

      segundaCarga.complete([_fila('r1', 'Silla de caoba')]);
      await t.pumpAndSettle();
      expect(find.text('Silla de caoba'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('el vacío también admite el gesto y recarga', (t) async {
      var llamadas = 0;
      await t.pumpWidget(MaterialApp(
        home: RecruitScreen(
          load: ({int limit = 100}) async {
            llamadas++;
            return llamadas == 1 ? const [] : [_fila('r1', 'Silla de caoba')];
          },
          // Cobertura 0 para lo que venga: sigue visible en "Sin proveedor"
          // (el filtro con el que arranca la pantalla) tras la recarga.
          coverage: (ids) async => {for (final id in ids) id: 0},
        ),
      ));
      await t.pumpAndSettle();
      // "Sin proveedor" (el filtro que arranca por defecto) con la lista
      // vacía: antes esta rama no tenía ningún `RefreshIndicator`.
      expect(find.text('Ninguna solicitud abierta se quedó sin proveedor'),
          findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);

      await t.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();

      expect(llamadas, 2);
      expect(find.text('Silla de caoba'), findsOneWidget);
    });
  });
}
