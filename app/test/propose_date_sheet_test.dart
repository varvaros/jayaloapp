import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/widgets/propose_date_sheet.dart';

void main() {
  // 24/08/2026 es LUNES; el reloj de la hoja se inyecta para que «pasada» no
  // dependa de cuándo corra la prueba.
  final now = DateTime(2026, 8, 24, 10, 0);

  Future<Map<String, dynamic>?> lunesNueveACinco(String _) async => {
        'mon': {'open': '09:00', 'close': '17:00'},
      };

  ({String subject, DateTime startsAt})? resultado;

  Widget host({
    required Future<Map<String, dynamic>?> Function(String) loadHours,
    String defaultSubject = 'la entrega',
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  resultado = await showProposeDateSheet(ctx,
                      convId: 'c1',
                      defaultSubject: defaultSubject,
                      now: now,
                      loadHours: loadHours);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

  // En `flutter test` el texto mide ~2×: con la superficie por defecto
  // (800×600) la hoja se desborda y el test moriría en el overflow.
  void surfaceAlta(WidgetTester t) {
    t.view.physicalSize = const Size(600, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  // La tira de horas es una lista PEREZOSA: las horas de más allá del borde ni
  // se construyen, así que hay que traerlas antes de medirlas (falso-negativo
  // que ya mordió en este proyecto con `ensureVisible`).
  Future<Finder> hora(WidgetTester t, String label) async {
    final f = find.widgetWithText(OutlinedButton, label);
    await t.scrollUntilVisible(f, 300,
        scrollable: find.descendant(
            of: find.byKey(const Key('appt.slots')),
            matching: find.byType(Scrollable)));
    return f;
  }

  Future<void> abrirYElegirDia(WidgetTester t) async {
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Elegir el día'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK')); // el picker abre en `now` = 24/08/2026
    await t.pumpAndSettle();
  }

  setUp(() => resultado = null);

  testWidgets('elige día y hora y devuelve el instante LOCAL elegido',
      (t) async {
    surfaceAlta(t);
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();

    expect(find.text('Proponer fecha pautada'), findsOneWidget);
    expect(find.text('la entrega'), findsOneWidget); // asunto prellenado
    // Sin día ni hora no se puede proponer.
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Proponer fecha'))
            .onPressed,
        isNull);

    await t.tap(find.text('Elegir el día'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Día: 24/08/2026'), findsOneWidget);

    await t.tap(await hora(t, '10:30'));
    await t.pumpAndSettle();
    // El instante elegido se devuelve en hora de RD ANTES de mandarlo, para
    // que un teléfono con otro huso enseñe el desfase aquí y no en la tarjeta.
    expect(find.textContaining('hora de República Dominicana.'), findsOneWidget);

    await t.tap(find.widgetWithText(FilledButton, 'Proponer fecha'));
    await t.pumpAndSettle();
    expect(resultado?.subject, 'la entrega');
    expect(resultado?.startsAt, DateTime(2026, 8, 24, 10, 30));
    expect(resultado?.startsAt.isUtc, isFalse);
  });

  testWidgets('lo PASADO se deshabilita; lo fuera de horario solo se anota',
      (t) async {
    surfaceAlta(t);
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await abrirYElegirDia(t);

    // Con el reloj en las 10:00 de ese mismo día, las 09:30 ya no se pueden
    // proponer: el servidor las rechaza («La fecha debe ser futura»).
    expect(t.widget<OutlinedButton>(await hora(t, '09:30')).onPressed, isNull);
    expect(
        t.widget<OutlinedButton>(await hora(t, '10:30')).onPressed, isNotNull);

    // Fuera del horario publicado (09:00–17:00) se ANOTA pero se puede elegir:
    // el horario es una sugerencia, no una reja.
    final fuera = await hora(t, '18:00 (fuera de horario)');
    expect(fuera, findsOneWidget);
    expect(t.widget<OutlinedButton>(fuera).onPressed, isNotNull);
    expect(find.textContaining('Horario publicado ese día: 09:00 a 17:00'),
        findsOneWidget);
  });

  testWidgets('sin horario (o si la RPC falla) no hay error ni anotaciones',
      (t) async {
    surfaceAlta(t);
    // `null` es el caso NORMAL hoy (ningún negocio tiene horario) y además no
    // se distingue de «no participas»: jamás debe salir como error.
    await t.pumpWidget(host(loadHours: (_) async => throw Exception('boom')));
    await abrirYElegirDia(t);

    expect(t.takeException(), isNull);
    expect(await hora(t, '18:00'), findsOneWidget);
    expect(find.textContaining('(fuera de horario)'), findsNothing);
    expect(find.textContaining('Horario publicado'), findsNothing);
  });

  testWidgets('la hora elegida se marca con ✓ y en la semántica, no solo con '
      'color', (t) async {
    // Regla de la casa: nada de estado llevado SOLO por el color. En la web el
    // `<select>` nativo anuncia la selección a los lectores de pantalla de
    // balde; estos botones tienen que decirlo a mano.
    surfaceAlta(t);
    final semantica = t.ensureSemantics();
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await abrirYElegirDia(t);

    final f = await hora(t, '10:30');
    expect(t.getSemantics(f), isSemantics(isSelected: false));

    await t.tap(f);
    await t.pumpAndSettle();
    expect(find.text('✓ 10:30'), findsOneWidget);
    expect(t.getSemantics(find.widgetWithText(OutlinedButton, '✓ 10:30')),
        isSemantics(isSelected: true));
    semantica.dispose();
  });

  testWidgets('un asunto prellenado larguísimo se corta al tope de la RPC',
      (t) async {
    surfaceAlta(t);
    await t.pumpWidget(
        host(loadHours: lunesNueveACinco, defaultSubject: 'x' * 90));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(find.text('x' * 60), findsOneWidget);
  });
}
