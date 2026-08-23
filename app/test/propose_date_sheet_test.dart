import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/chat/widgets/propose_date_sheet.dart';

/// Texto del botón del día cuando aún no hay ninguno elegido.
const String _diaSinElegir = 'Elegir el día';

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
        // MISMA localización que el `MaterialApp` de verdad (`app.dart`). No es
        // decorado: sin estos delegados el calendario y el RELOJ de Material
        // salen en inglés, que es justo lo que se vino a arreglar. Al tomarlos
        // de `app.dart` en vez de copiarlos, quitarlos de la app rompe estas
        // pruebas en vez de pasar callando.
        localizationsDelegates: jayaloLocalizationsDelegates,
        supportedLocales: jayaloSupportedLocales,
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
  // (800×600) la hoja (y sobre todo el diálogo del reloj) se desbordan y el
  // test moriría en el overflow.
  void surfaceAlta(WidgetTester t) {
    t.view.physicalSize = const Size(600, 1900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Future<void> abrir(WidgetTester t) async {
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
  }

  /// Elige un día del calendario. `dia` nulo = acepta el que viene abierto
  /// (`now`); si no, toca ese número del mes en curso.
  Future<void> elegirDia(WidgetTester t, {int? dia}) async {
    final boton = find.text(_diaSinElegir).evaluate().isNotEmpty
        ? find.text(_diaSinElegir)
        : find.textContaining('Día: ');
    await t.tap(boton);
    await t.pumpAndSettle();
    if (dia != null) {
      await t.tap(find.text('$dia').last);
      await t.pumpAndSettle();
    }
    await t.tap(find.text('ACEPTAR'));
    await t.pumpAndSettle();
  }

  /// Elige una hora en el reloj de Material. Va por el modo TECLADO (el botón
  /// del teclado del propio diálogo) porque tocar la esfera a ciegas mediría
  /// coordenadas, no comportamiento; lo que se prueba —el reloj devuelve una
  /// hora y la hoja la asume— es lo mismo por los dos modos.
  Future<void> elegirHora(
    WidgetTester t, {
    required String hora,
    required String minuto,
    required String periodo, // 'a.m.' o 'p.m.'
  }) async {
    await t.tap(find.byKey(const Key('appt.time')));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.keyboard_outlined));
    await t.pumpAndSettle();
    // El campo 0 es el «¿Para qué?» de la hoja, que sigue montado detrás.
    final campos = find.byType(TextField);
    await t.enterText(campos.at(1), hora);
    await t.enterText(campos.at(2), minuto);
    await t.tap(find.text(periodo));
    await t.pumpAndSettle();
    await t.tap(find.text('ACEPTAR'));
    await t.pumpAndSettle();
  }

  Finder botonProponer() => find.widgetWithText(FilledButton, 'Proponer fecha');

  setUp(() => resultado = null);

  testWidgets('el calendario y el reloj salen en ESPAÑOL', (t) async {
    // La app no declaraba ninguna localización, así que todo lo que pinta
    // Material por su cuenta salía en inglés («OK», «Select date»…). Estrenar
    // un reloj en inglés habría sido peor que la tira de fichas que sustituye.
    surfaceAlta(t);
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await abrir(t);

    await t.tap(find.text(_diaSinElegir));
    await t.pumpAndSettle();
    expect(find.text('Elige el día'), findsOneWidget); // helpText propio
    expect(find.text('agosto de 2026'), findsOneWidget);
    expect(find.text('ACEPTAR'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    await t.tap(find.text('ACEPTAR'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('appt.time')));
    await t.pumpAndSettle();
    expect(find.text('Elige la hora'), findsOneWidget); // helpText propio
    expect(find.text('ACEPTAR'), findsOneWidget);
    // Y en 12 h: la esfera trae el conmutador AM/PM. Sin el `Localizations`
    // de `es_US` que fija el selector, `flutter_localizations` daría "H:mm"
    // (24 h) para cualquier `es_*` y este conmutador ni existiría.
    expect(find.text('a.m.'), findsOneWidget);
    expect(find.text('p.m.'), findsOneWidget);
    // `.last` = el «Cancelar» del diálogo; el primero es el de la hoja, que
    // sigue montada detrás.
    await t.tap(find.text('Cancelar').last);
    await t.pumpAndSettle();
  });

  testWidgets('elige día y hora y devuelve el instante LOCAL elegido',
      (t) async {
    surfaceAlta(t);
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await abrir(t);

    expect(find.text('Proponer fecha pautada'), findsOneWidget);
    expect(find.text('la entrega'), findsOneWidget); // asunto prellenado
    // Sin día ni hora no se puede proponer.
    expect(t.widget<FilledButton>(botonProponer()).onPressed, isNull);

    await elegirDia(t);
    expect(find.text('Día: 24/08/2026'), findsOneWidget);

    // 15:45 NO es media hora: la tira de fichas de antes no la ofrecía. El
    // reloj admite cualquier minuto a propósito (el servidor guarda el
    // `timestamptz` que le llegue).
    await elegirHora(t, hora: '3', minuto: '45', periodo: 'p.m.');
    // La hora elegida se LEE en 12 h, igual que la tarjeta del chat. Antes el
    // selector decía "15:45" y la tarjeta de al lado "3:45 de la tarde".
    expect(find.text('Hora: 3:45 de la tarde'), findsOneWidget);
    // El instante elegido se devuelve en hora de RD ANTES de mandarlo, para
    // que un teléfono con otro huso enseñe el desfase aquí y no en la tarjeta.
    expect(find.textContaining('hora de República Dominicana.'), findsOneWidget);
    expect(find.textContaining('3:45 de la tarde'),
        findsNWidgets(2)); // botón + eco

    await t.tap(botonProponer());
    await t.pumpAndSettle();
    expect(resultado?.subject, 'la entrega');
    expect(resultado?.startsAt, DateTime(2026, 8, 24, 15, 45));
    expect(resultado?.startsAt.isUtc, isFalse);
  });

  testWidgets('una hora YA PASADA no se puede proponer, y no se pierde',
      (t) async {
    // Con un reloj libre no se puede «apagar» una hora como se apagaba una
    // ficha: se comprueba después de elegir. El servidor también la rechaza
    // («La fecha debe ser futura»), pero rebotar contra el servidor algo que
    // la pantalla ya sabe es de mala educación.
    surfaceAlta(t);
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await abrir(t);
    await elegirDia(t); // hoy, 24/08/2026, con el reloj de la hoja en las 10:00

    await elegirHora(t, hora: '9', minuto: '30', periodo: 'a.m.');
    expect(find.byKey(const Key('appt.past')), findsOneWidget);
    expect(find.text('Esa hora ya pasó. Elige una más tarde o cambia el día.'),
        findsOneWidget);
    expect(t.widget<FilledButton>(botonProponer()).onPressed, isNull);
    // Lo elegido NO se borra: sigue en el botón, listo para corregirlo.
    expect(find.text('Hora: 9:30 de la mañana'), findsOneWidget);
    // Y no se anuncia una propuesta que no se puede hacer.
    expect(find.textContaining('Se propondrá para'), findsNothing);

    // Corregir la hora limpia el aviso y desbloquea el botón.
    await elegirHora(t, hora: '10', minuto: '30', periodo: 'a.m.');
    expect(find.byKey(const Key('appt.past')), findsNothing);
    expect(t.widget<FilledButton>(botonProponer()).onPressed, isNotNull);
  });

  testWidgets('cambiar el DÍA a hoy también destapa el aviso de hora pasada',
      (t) async {
    // El otro camino a la misma trampa: la hora valía para mañana y deja de
    // valer al mover el día a hoy. Antes la hora se borraba en silencio y el
    // usuario se quedaba mirando un formulario que se vació solo.
    surfaceAlta(t);
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await abrir(t);

    await elegirDia(t, dia: 25); // martes 25: las 09:30 aún no han pasado
    await elegirHora(t, hora: '9', minuto: '30', periodo: 'a.m.');
    expect(t.widget<FilledButton>(botonProponer()).onPressed, isNotNull);

    await elegirDia(t, dia: 24); // hoy, con el reloj de la hoja en las 10:00
    expect(find.byKey(const Key('appt.past')), findsOneWidget);
    expect(t.widget<FilledButton>(botonProponer()).onPressed, isNull);
    expect(find.text('Hora: 9:30 de la mañana'), findsOneWidget); // no se perdió
  });

  testWidgets('lo fuera de horario solo se ANOTA: se puede proponer igual',
      (t) async {
    // El horario del negocio es una SUGERENCIA (y hoy ningún negocio vivo
    // tiene ninguno): se anota, nunca se cierra el paso.
    surfaceAlta(t);
    await t.pumpWidget(host(loadHours: lunesNueveACinco));
    await abrir(t);
    await elegirDia(t);

    await elegirHora(t, hora: '6', minuto: '00', periodo: 'p.m.');
    expect(find.text('Hora: 6:00 de la tarde (fuera de horario)'),
        findsOneWidget);
    expect(t.widget<FilledButton>(botonProponer()).onPressed, isNotNull);
    expect(find.textContaining('Horario publicado ese día: 09:00 a 17:00'),
        findsOneWidget);
    // Y el eco de RD sigue ahí: fuera de horario no impide nada.
    expect(find.textContaining('hora de República Dominicana.'), findsOneWidget);
  });

  testWidgets('sin horario (o si la RPC falla) no hay error ni anotaciones',
      (t) async {
    surfaceAlta(t);
    // `null` es el caso NORMAL hoy (ningún negocio tiene horario) y además no
    // se distingue de «no participas»: jamás debe salir como error.
    await t.pumpWidget(host(loadHours: (_) async => throw Exception('boom')));
    await abrir(t);
    await elegirDia(t);

    await elegirHora(t, hora: '6', minuto: '00', periodo: 'p.m.');
    expect(t.takeException(), isNull);
    expect(find.text('Hora: 6:00 de la tarde'), findsOneWidget);
    expect(find.textContaining('(fuera de horario)'), findsNothing);
    expect(find.textContaining('Horario publicado'), findsNothing);
    expect(t.widget<FilledButton>(botonProponer()).onPressed, isNotNull);
  });

  testWidgets('un asunto prellenado larguísimo se corta al tope de la RPC',
      (t) async {
    surfaceAlta(t);
    await t.pumpWidget(
        host(loadHours: lunesNueveACinco, defaultSubject: 'x' * 90));
    await abrir(t);
    expect(find.text('x' * 60), findsOneWidget);
  });
}
