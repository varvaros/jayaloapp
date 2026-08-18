import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/product_list_card.dart';
import 'package:jayalo_app/features/shared/star_score.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  testWidgets('muestra nombre y precio', (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
      'category_id': 'ferreteria',
    })));
    await tester.pumpAndSettle();
    expect(find.text('Taladro'), findsOneWidget);
    expect(find.textContaining('2,500'), findsOneWidget);
  });

  testWidgets('sin avg_rating/reviews_count no dibuja la línea de reputación',
      (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
    })));
    await tester.pumpAndSettle();
    expect(find.byType(StarScore), findsNothing);
  });

  testWidgets('con reputación dibuja las estrellas con su escala',
      (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
      'avg_rating': 8.6, // 1-10; era 4.5, de cuando esto se leía como /5
      'reviews_count': 8,
    })));
    await tester.pumpAndSettle();
    // Se busca el WIDGET, no el icono: cada estrella son DOS iconos apilados
    // (gris debajo, dorada recortada encima), así que `find.byIcon` cuenta 10.
    expect(find.byType(StarScore), findsOneWidget);
    // Y la escala escrita, que es lo que impide leer el 8,6 como si fuera /5.
    expect(find.text('8.6/10'), findsOneWidget);
  });

  group('ProductGridCard no desborda la celda de la rejilla', () {
    // El caso peor real que reportó el PO (2026-08-14): nombre a 2 líneas,
    // reputación y TRES atributos (envío + estado + color), que en media
    // tarjeta se parten en dos renglones.
    const peor = {
      'id': 'p1',
      'name': 'Máquina de cortar pelo Remington profesional',
      'category_id': 'ferreteria',
      'price': 7500,
      'avg_rating': 8.0,
      'reviews_count': 1,
      'offers_shipping': true,
      'condition': 'nuevo',
      'color': 'Rojo',
    };

    /// Reproduce la celda de `catalog_screen`: ancho de media pantalla y alto
    /// el que pide [catalogGridCardExtent] para esa escala tipográfica.
    Widget celda(double width, double scale) => MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Builder(
                  builder: (context) => Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      height: catalogGridCardExtent(context),
                      child: const ProductGridCard(item: peor),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    // 158 = teléfono de 360dp; 138 = uno de 320dp (el que menos ancho deja).
    for (final width in const [158.0, 138.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('ancho $width, fuente ×$scale', (tester) async {
          await tester.pumpWidget(celda(width, scale));
          await tester.pumpAndSettle();
          // Un RenderFlex desbordado se reporta como excepción en tests.
          expect(tester.takeException(), isNull);
          // Y el precio —lo que se estaba recortando— cae DENTRO de la celda.
          final celdaRect = tester.getRect(find.byType(ProductGridCard));
          final precio = tester.getRect(find.textContaining('7,500'));
          expect(precio.bottom, lessThanOrEqualTo(celdaRect.bottom));
        });
      }
    }
  });
}
