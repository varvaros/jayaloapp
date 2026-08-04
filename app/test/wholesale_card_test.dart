import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/wholesale_card.dart';

void main() {
  Future<void> montar(WidgetTester tester, WholesaleCard tarjeta,
      {Brightness brillo = Brightness.light}) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(brillo),
      home: Scaffold(body: tarjeta),
    ));
  }

  testWidgets('el rotulo es el encabezado y va grande', (tester) async {
    await montar(tester, const WholesaleCard(quantity: 500));
    final rotulo = tester.widget<Text>(find.text('Al por mayor'));
    expect(rotulo.style!.fontSize, 16);
  });

  testWidgets('solo pinta las filas que tienen dato', (tester) async {
    await montar(tester, const WholesaleCard(quantity: 500));
    expect(find.text('Cantidad'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('División'), findsNothing);
    expect(find.text('Empaque'), findsNothing);
    expect(find.text('Detalle'), findsNothing);
  });

  testWidgets('traduce los slugs de division y empaque', (tester) async {
    await montar(
      tester,
      const WholesaleCard(
          quantity: 500, split: 'todo_junto', packaging: 'caja'),
    );
    expect(find.text('División'), findsOneWidget);
    expect(find.text('Todo junto'), findsOneWidget);
    expect(find.text('Empaque'), findsOneWidget);
    expect(find.text('Caja'), findsOneWidget);
    // No se filtra el slug crudo a la pantalla.
    expect(find.text('todo_junto'), findsNothing);
    expect(find.text('caja'), findsNothing);
  });

  testWidgets('el detalle va aparte y completo', (tester) async {
    await montar(
      tester,
      const WholesaleCard(
          quantity: 500, note: 'Que sean apilables y del mismo color.'),
    );
    expect(find.text('Detalle'), findsOneWidget);
    expect(find.text('Que sean apilables y del mismo color.'), findsOneWidget);
  });

  testWidgets('sin ningun dato sigue mostrando el rotulo', (tester) async {
    // Una solicitud puede estar marcada como mayoreo sin haber rellenado
    // nada: el rotulo es la identidad y no puede desaparecer.
    await montar(tester, const WholesaleCard());
    expect(find.text('Al por mayor'), findsOneWidget);
  });

  testWidgets('en oscuro pinta sin reventar', (tester) async {
    await montar(tester, const WholesaleCard(quantity: 500),
        brillo: Brightness.dark);
    expect(find.text('Al por mayor'), findsOneWidget);
  });
}
