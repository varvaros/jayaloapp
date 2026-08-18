import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/star_score.dart';

/// El widget de estrellas con medias (mockup aprobado por el PO 2026-08-17).
/// Lo que se prueba aquí es la ESCALA: la nota es 1-10 y se reparte en 5 estrellas,
/// así que cada estrella vale 2 puntos. Antes de este widget, tres pantallas de la
/// app pintaban el 1-10 sobre 5 estrellas sin dividir y saturaban desde el 5.
void main() {
  /// Fracción rellena de cada estrella, leyendo los `Align` que hacen el recorte.
  List<double> fracciones(WidgetTester tester) => tester
      .widgetList<Align>(find.descendant(
          of: find.byType(StarScore), matching: find.byType(Align)))
      .map((a) => a.widthFactor!)
      .toList();

  Widget host(double score, {bool showNumber = true}) => MaterialApp(
      home: Scaffold(
          body: Center(child: StarScore(score: score, showNumber: showNumber))));

  testWidgets('un 10 llena las cinco', (tester) async {
    await tester.pumpWidget(host(10));
    expect(fracciones(tester), [1.0, 1.0, 1.0, 1.0, 1.0]);
  });

  testWidgets('un 7 son tres y MEDIA — el caso del mockup', (tester) async {
    await tester.pumpWidget(host(7));
    expect(fracciones(tester), [1.0, 1.0, 1.0, 0.5, 0.0]);
  });

  testWidgets('un 8 son cuatro llenas: 7 y 8 NO se ven igual', (tester) async {
    await tester.pumpWidget(host(8));
    expect(fracciones(tester), [1.0, 1.0, 1.0, 1.0, 0.0]);
  });

  testWidgets('el relleno es CONTINUO, no de media en media', (tester) async {
    // 7,4 deja la cuarta al 70 %. Los promedios de las RPC son decimales y
    // redondear a media estrella tiraría precisión que sí se puede pintar.
    await tester.pumpWidget(host(7.4));
    expect(fracciones(tester)[3], closeTo(0.7, 0.0001));
  });

  testWidgets('un 1 es media estrella, no una entera', (tester) async {
    await tester.pumpWidget(host(1));
    expect(fracciones(tester), [0.5, 0.0, 0.0, 0.0, 0.0]);
  });

  testWidgets('sin nota (0) no pinta ninguna ni escribe número', (tester) async {
    await tester.pumpWidget(host(0));
    expect(fracciones(tester), [0.0, 0.0, 0.0, 0.0, 0.0]);
    expect(find.textContaining('/ 10'), findsNothing);
  });

  testWidgets('nunca satura por arriba aunque llegue basura', (tester) async {
    // `get_business_public_stats` hace COALESCE(avg,0) y hubo un `Math.min(10,…)`
    // defensivo en la web: si alguna vez llega un 12, no debe desbordar.
    await tester.pumpWidget(host(12));
    expect(fracciones(tester), [1.0, 1.0, 1.0, 1.0, 1.0]);
  });

  testWidgets('escribe la escala: entero sin decimales, promedio con uno',
      (tester) async {
    await tester.pumpWidget(host(8));
    expect(find.text('8 / 10'), findsOneWidget);
    await tester.pumpWidget(host(8.6));
    expect(find.text('8.6 / 10'), findsOneWidget);
  });

  testWidgets('showNumber:false deja solo las estrellas', (tester) async {
    await tester.pumpWidget(host(8, showNumber: false));
    expect(find.textContaining('/ 10'), findsNothing);
    expect(fracciones(tester), [1.0, 1.0, 1.0, 1.0, 0.0]);
  });

  test('la palabra cualitativa cubre toda la escala', () {
    expect(starScoreWord(0), '');
    expect(starScoreWord(3), 'Malo');
    expect(starScoreWord(5), 'Regular');
    expect(starScoreWord(7), 'Bueno');
    expect(starScoreWord(9), 'Muy bueno');
    expect(starScoreWord(10), 'Excelente');
  });

  // ── El control interactivo (trozo II) ──────────────────────────────────────
  group('StarScoreInput', () {
    late int elegido;

    Widget hostInput(int value) => MaterialApp(
        home: Scaffold(
            body: Center(
                child: StarScoreInput(
                    value: value, onChanged: (v) => elegido = v))));

    /// Toca a una fraccion del ancho de la fila.
    Future<void> tocarEn(WidgetTester tester, double frac) async {
      final r = tester.getRect(find.byType(StarScoreInput));
      await tester.tapAt(Offset(r.left + r.width * frac, r.center.dy));
      await tester.pump();
    }

    testWidgets('un TOQUE simple ya elige nota', (tester) async {
      // Con solo `onHorizontalDrag*` esto no dispararia nunca: el arrastre exige
      // superar el touch slop y ganar la arena. Por eso hay `onTapDown`.
      elegido = -1;
      await tester.pumpWidget(hostInput(8));
      await tocarEn(tester, 0.65);
      expect(elegido, 7); // ceil(0.65 * 10)
    });

    testWidgets('los extremos dan 1 y 10, sin desbordar', (tester) async {
      elegido = -1;
      await tester.pumpWidget(hostInput(5));
      await tocarEn(tester, 0.001);
      expect(elegido, 1);
      await tocarEn(tester, 0.999);
      expect(elegido, 10);
    });

    testWidgets('arrastrar en horizontal sigue al dedo', (tester) async {
      elegido = -1;
      await tester.pumpWidget(hostInput(1));
      final r = tester.getRect(find.byType(StarScoreInput));
      final g = await tester.startGesture(
          Offset(r.left + r.width * 0.25, r.center.dy));
      await tester.pump();
      // Nada todavia: con el tap compitiendo contra el arrastre, `onTapDown` se
      // DIFIERE hasta que alguien gana la arena. No es un fallo, es la arena.
      expect(elegido, -1);
      await g.moveTo(Offset(r.left + r.width * 0.85, r.center.dy));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(elegido, 9);
    });

    testWidgets('dentro de scroll: el arrastre VERTICAL scrollea y NO califica',
        (tester) async {
      // La prueba que de verdad importa: los tres formularios viven dentro de
      // scroll vertical (y uno en una hoja modal que se cierra arrastrando).
      // Con `onPanUpdate` en vez de `onHorizontalDrag*`, el control le robaria
      // el gesto al `Scrollable` y la pantalla dejaria de moverse.
      elegido = -1;
      final controller = ScrollController();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListView(
        controller: controller,
        children: [
          const SizedBox(height: 400),
          StarScoreInput(value: 5, onChanged: (v) => elegido = v),
          const SizedBox(height: 800),
        ],
      ))));
      await tester.drag(find.byType(StarScoreInput), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0)); // la lista SI se movio
      expect(elegido, -1); // y la nota NO cambio
      // Y en horizontal, sobre la misma lista, el control sigue respondiendo.
      // El rectangulo se vuelve a leer: la lista se movio y el de antes es viejo.
      final r2 = tester.getRect(find.byType(StarScoreInput));
      await tester.dragFrom(
          Offset(r2.left + r2.width * 0.15, r2.center.dy), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(elegido, isNot(-1));
    });

    testWidgets('expone un slider accesible con su valor', (tester) async {
      final handle = tester.ensureSemantics();
      elegido = -1;
      await tester.pumpWidget(hostInput(7));
      expect(
          tester.getSemantics(find.byType(StarScoreInput)),
          matchesSemantics(
            isSlider: true,
            hasIncreaseAction: true,
            hasDecreaseAction: true,
            label: 'Calificación',
            value: '7 de 10',
            increasedValue: '8 de 10',
            decreasedValue: '6 de 10',
          ));
      handle.dispose();
    });
  });
}
