import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/features/auth/intro_reveal.dart';

void main() {
  Widget host(Widget child, {required bool reduced}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  double opacityOf(WidgetTester t, String text) {
    final el = t.element(find.text(text));
    final fades = el.findAncestorWidgetOfExactType<FadeTransition>();
    return fades?.opacity.value ?? 1;
  }

  testWidgets(
    'con reduce-motion el hijo está a la vista desde el primer frame',
    (t) async {
      await t.pumpWidget(
        host(const IntroReveal(child: Text('hola')), reduced: true),
      );
      await t.pump();
      expect(find.text('hola'), findsOneWidget);
      expect(opacityOf(t, 'hola'), 1);
    },
  );

  testWidgets(
    'con animación: invisible al montar, visible tras delay + duración',
    (t) async {
      await t.pumpWidget(
        host(
          const IntroReveal(delay: JayaloMotion.fast, child: Text('hola')),
          reduced: false,
        ),
      );
      await t.pump();
      expect(opacityOf(t, 'hola'), 0);
      // En dos tandas: `pump` solo pinta UN frame al final del salto, así que si
      // el `Future.delayed` del delay y el fin de la animación caen en el MISMO
      // salto, el ticker recién arranca en ese frame y mide 0 transcurrido. Se
      // deja que el delay venza en un `pump` propio para anclar el arranque, y
      // se mide la duración en el siguiente — mismo tiempo total, mismo assert.
      await t.pump(JayaloMotion.fast);
      await t.pump(JayaloMotion.intro + const Duration(milliseconds: 20));
      expect(opacityOf(t, 'hola'), 1);
    },
  );

  testWidgets('IntroWords parte el titular en palabras', (t) async {
    await t.pumpWidget(
      host(
        const IntroWords(
          text: 'En Jáyalo conectamos',
          style: TextStyle(fontSize: 20),
        ),
        reduced: true,
      ),
    );
    await t.pump();
    expect(find.text('En'), findsOneWidget);
    expect(find.text('Jáyalo'), findsOneWidget);
    expect(find.text('conectamos'), findsOneWidget);
  });

  testWidgets('IntroCounter con reduce-motion nace en n', (t) async {
    // Sin movimiento no hay cuenta: el número es información, y se pinta en su
    // estado FINAL desde el primer frame. (La cuenta animada la fija el caso
    // de abajo, que es quien mide el retardo real.)
    await t.pumpWidget(
      host(
        const IntroCounter(to: 5, style: TextStyle(fontSize: 20)),
        reduced: true,
      ),
    );
    await t.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('IntroCounter no cuenta hasta que vence el retardo REAL', (
    t,
  ) async {
    // El defecto que esto fija: con el tween arrancando en el montaje y el
    // fundido esperando los 360 ms, para cuando el número se veía la cuenta ya
    // iba por 4 — el usuario no veía contar, veía aparecer un 5.
    await t.pumpWidget(
      host(
        const IntroCounter(to: 5, style: TextStyle(fontSize: 20)),
        reduced: false,
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(
      find.text('3'),
      findsNothing,
      reason: 'a 300 ms el tween ni siquiera ha arrancado',
    );
    expect(find.text('0'), findsOneWidget, reason: 'reserva el ancho de cifra');

    // Vence el retardo (360 ms): aquí nace el tween, y su ticker mide desde el
    // frame siguiente.
    await t.pump(const Duration(milliseconds: 60));
    await t.pump();
    await t.pump(IntroCounter.stepPerDigit * 2); // 240 ms = exactamente 2
    expect(find.text('2'), findsOneWidget);
    await t.pump(
      IntroCounter.stepPerDigit * 3 + const Duration(milliseconds: 10),
    );
    expect(find.text('5'), findsOneWidget);
  });
}
