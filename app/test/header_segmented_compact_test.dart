import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: ColoredBox(color: Colors.deepPurple, child: child),
          ),
        ),
      );

  testWidgets('compact ocupa menos ancho que el normal con las mismas opciones',
      (tester) async {
    await tester.pumpWidget(host(HeaderSegmented(
      options: const ['Producto', 'Servicio'],
      index: 0,
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    final normal = tester.getSize(find.byType(HeaderSegmented)).width;

    await tester.pumpWidget(host(HeaderSegmented(
      compact: true,
      options: const ['Producto', 'Servicio'],
      index: 0,
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    final compact = tester.getSize(find.byType(HeaderSegmented)).width;

    expect(compact, lessThan(normal));
    // Sigue siendo tocable: cambiar de segmento avisa con el índice.
    var got = -1;
    await tester.pumpWidget(host(HeaderSegmented(
      compact: true,
      options: const ['Producto', 'Servicio'],
      index: 0,
      onChanged: (i) => got = i,
    )));
    await tester.tap(find.text('Servicio'));
    expect(got, 1);
  });
}
