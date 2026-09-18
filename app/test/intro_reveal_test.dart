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

  testWidgets('IntroCounter cuenta hasta n y con reduce-motion nace en n', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const IntroCounter(to: 5, style: TextStyle(fontSize: 20)),
        reduced: true,
      ),
    );
    await t.pump();
    expect(find.text('5'), findsOneWidget);

    await t.pumpWidget(
      host(
        const IntroCounter(
          to: 5,
          style: TextStyle(fontSize: 20),
          delay: Duration.zero,
        ),
        reduced: false,
      ),
    );
    await t.pump();
    expect(find.text('0'), findsOneWidget);
    await t.pump(
      JayaloMotion.fast * 2 + const Duration(milliseconds: 10),
    ); // 310 ms
    expect(
      find.text('3'),
      findsOneWidget,
      reason: 'a 120 ms por cifra, 310 ms son 3',
    );
    await t.pump(JayaloMotion.fast * 3);
    expect(find.text('5'), findsOneWidget);
  });
}
