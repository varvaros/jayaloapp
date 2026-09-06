import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/product_list_card.dart';
import 'package:jayalo_app/features/shared/star_score.dart';

void main() {
  const negocio = (
    name: 'TecnoCentro',
    logoUrl: null,
    whatsappVerified: false,
    identityVerified: false,
    businessVerified: false,
    hasPhysicalLocation: true,
  );
  const item = {
    'id': 'p3',
    'name': 'Audífonos inalámbricos con estuche de carga',
    'category_id': 'electronica',
    'price_min': 1200,
    'avg_rating': 8.4,
    'reviews_count': 6,
  };

  Widget host(Widget child, {double scale = 1}) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [child, child],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('mide 138 de ancho y pinta nombre, tienda (sin sello) y «desde»',
      (tester) async {
    await tester.pumpWidget(
        host(const ProductCarouselCard(item: item, negocio: negocio)));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(ProductCarouselCard).first);
    expect(size.width, 138);
    expect(find.textContaining('Audífonos'), findsNWidgets(2));
    expect(find.textContaining('TecnoCentro'), findsNWidgets(2));
    // En el carrusel no cabe el sello: solo el nombre.
    expect(find.textContaining('Tienda física'), findsNothing);
    expect(find.text('desde '), findsNWidgets(2));
    expect(find.textContaining('1,200'), findsNWidgets(2));
    // Sin estrellas: el carrusel es de un vistazo.
    expect(find.byType(StarScore), findsNothing);
  });

  testWidgets('con la fuente al doble no desborda', (tester) async {
    await tester.pumpWidget(host(
        const ProductCarouselCard(item: item, negocio: negocio),
        scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
