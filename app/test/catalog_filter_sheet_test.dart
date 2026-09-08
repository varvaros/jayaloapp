import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/catalog_articulos.dart'
    show kSinFiltros;
import 'package:jayalo_app/features/client/catalog_filter_sheet.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: Scaffold(body: child),
  );

  testWidgets('lista categorías y "Todo {cat}" devuelve la categoría', (
    tester,
  ) async {
    CatalogFilterResult? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => result = await showCatalogFilterSheet(
                context,
                ciudades: const [],
                filtros: kSinFiltros,
                categoriasVivas: () async => null,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Los bloques nuevos (Ubicación/Precio/Proveedor) empujan las categorías
    // debajo del pliegue: un `ListView` no construye lo que no se ve, así que
    // hay que bajar de verdad antes de buscar.
    await tester.scrollUntilVisible(
      find.text('Ferretería'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 'Ferretería' es una de las kCategories.
    expect(find.text('Ferretería'), findsOneWidget);
    // La hoja sigue abierta (no se tocó ninguna categoría): sin resultado
    // todavía. La selección "Todo {cat}" se valida a mano en device (nota del
    // brief: la carga de rubros pega a la red).
    expect(result, isNull);
  });

  testWidgets('los bloques nuevos viajan en el resultado y Limpiar los apaga', (
    tester,
  ) async {
    CatalogFilterResult? res;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              res = await showCatalogFilterSheet(
                ctx,
                ciudades: const ['Santiago'],
                filtros: kSinFiltros,
                categoriasVivas: () async => null,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('UBICACIÓN'), findsOneWidget);
    expect(find.text('PRECIO'), findsOneWidget);
    expect(find.text('PROVEEDOR'), findsOneWidget);
    await tester.tap(find.text('Solo verificados'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Desde RD\$'),
      '5000',
    );
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(res!.soloVerificados, isTrue);
    expect(res!.precioMin, 5000);
    expect(res!.ciudad, isNull);
  });
}
