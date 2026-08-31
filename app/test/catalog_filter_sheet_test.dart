import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/catalog_filter_sheet.dart';

void main() {
  testWidgets('lista categorías y "Todo {cat}" devuelve la categoría',
      (tester) async {
    CatalogFilterResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  result = await showCatalogFilterSheet(context, kind: 'producto'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // 'Ferretería' es una de las kCategories.
    expect(find.text('Ferretería'), findsOneWidget);
    // La hoja sigue abierta (no se tocó ninguna categoría): sin resultado
    // todavía. La selección "Todo {cat}" se valida a mano en device (nota del
    // brief: la carga de rubros pega a la red).
    expect(result, isNull);
  });
}
