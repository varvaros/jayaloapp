import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessReview, BusinessRating;
import 'package:jayalo_app/features/provider/my_business_screen.dart';

/// "Mi tienda" (spec 2026-07-20): Mi negocio es el escaparate de solo lectura —
/// detalles + productos + servicios + opiniones. Sin edición (V2/web).
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );


  /// La portada editorial (2026-08-01) es MUCHO más alta que la cabecera de
  /// tarjeta que sustituyó, así que en el viewport de 800x600 de los tests las
  /// secciones de abajo ya no nacen construidas. Se baja como bajaría alguien.
  Future<void> bajar(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
  }

  const negocio = (
    id: 'biz-1',
    name: 'Ferretería Pérez',
    logoUrl: null,
    coverUrl: null,
    verified: true,
    categoryId: 'ferreteria',
    city: 'Santiago',
    wholesale: true,
    description: 'Todo en herramientas',
    seals: ['Negocio verificado'],
    raw: {
      'is_wholesale': true,
      'experience_years': 12,
      'service_area': 'ambos',
      'warranty': '6 meses',
    },
  );

  final unProducto = [
    {'id': 'p1', 'name': 'Taladro', 'price': 2500, 'kind': 'producto'}
  ];
  final unServicio = [
    {'id': 's1', 'name': 'Instalación', 'price': 800, 'kind': 'servicio'}
  ];
  final unaResena = <BusinessReview>[
    (rating: 5.0, comment: 'Muy bueno', createdAt: DateTime(2026, 7, 1))
  ];

  Widget view({
    List<Map<String, dynamic>> productos = const [],
    List<Map<String, dynamic>> servicios = const [],
    List<BusinessReview> reviews = const [],
    BusinessRating? rating,
  }) =>
      host(MyBusinessView(
        business: negocio,
        productos: productos,
        servicios: servicios,
        reviews: reviews,
        rating: rating,
      ));

  // Rediseño 2026-08-01 (pedido PO: la tienda de la app no tenía el diseño
  // coordinado con la web). La cabecera de tarjeta y los tres chips dejan
  // paso a la portada editorial + la ficha de detalles completa.
  testWidgets('la portada trae nombre, categoría, ciudad y sellos',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('Ferretería Pérez'), findsOneWidget);
    expect(find.text('Negocio verificado'), findsOneWidget);
    // Categoría y ciudad ya no son dos chips sueltos: van en una línea.
    expect(find.textContaining('Santiago'), findsOneWidget);
  });

  testWidgets('la ficha de detalles enseña lo que la web, no tres chips',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('DETALLES DEL PROVEEDOR'), findsOneWidget);
    expect(find.text('12 años'), findsOneWidget);
    expect(find.text('En taller y a domicilio'), findsOneWidget);
    expect(find.text('6 meses'), findsOneWidget);
    // "Mayorista" pasa a ser una fila con etiqueta, no un chip suelto.
    expect(find.text('Al por mayor'), findsOneWidget);
    expect(find.text('Mayorista'), findsNothing);
  });

  testWidgets('lista productos y servicios', (tester) async {
    await tester
        .pumpWidget(view(productos: unProducto, servicios: unServicio));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text('PRODUCTOS'), findsOneWidget);
    expect(find.text('SERVICIOS'), findsOneWidget);
    expect(find.text('Taladro'), findsOneWidget);
    expect(find.text('Instalación'), findsOneWidget);
  });

  testWidgets('secciones vacías muestran aviso, no CTA de crear',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.textContaining('Aún no tienes productos'), findsOneWidget);
    expect(find.textContaining('Aún no tienes servicios'), findsOneWidget);
    // Nunca ofrece crear (eso es V2/web).
    expect(find.textContaining('Crear'), findsNothing);
  });

  testWidgets('opiniones: promedio, conteo y texto de la reseña',
      (tester) async {
    await tester.pumpWidget(
        view(reviews: unaResena, rating: (avg: 4.8, count: 12)));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text('OPINIONES'), findsOneWidget);
    expect(find.textContaining('4.8'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('Muy bueno'), findsOneWidget);
  });

  testWidgets('sin opiniones muestra aviso', (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.textContaining('Aún no tienes opiniones'), findsOneWidget);
  });

  testWidgets('sin negocio muestra un aviso en vez de reventar',
      (tester) async {
    await tester.pumpWidget(host(const MyBusinessView(
        business: null,
        productos: [],
        servicios: [],
        reviews: [],
        rating: null)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No encontramos tu negocio'), findsOneWidget);
  });

  // PO 2026-08-08: "debe permitir editar el producto desde la app". El
  // escaparate sigue siendo de solo lectura para los datos del NEGOCIO (eso
  // es "Editar en la web"), pero cada ficha estrena su lápiz.
  testWidgets('el lápiz de una ficha abre el editor con SU id',
      (tester) async {
    String? pedido;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: unProducto,
      servicios: unServicio,
      reviews: const [],
      rating: null,
      onEditProduct: (id) => pedido = id,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);
    await tester.tap(find.byTooltip('Editar').first);
    await tester.pump();
    expect(pedido, 'p1');
  });

  testWidgets('sin onEditProduct las fichas no muestran lápiz',
      (tester) async {
    await tester.pumpWidget(view(productos: unProducto));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text('Taladro'), findsOneWidget);
    expect(find.byTooltip('Editar'), findsNothing);
  });

  testWidgets('el botón Editar en la web invoca el callback', (tester) async {
    var called = false;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      reviews: const [],
      rating: null,
      onEditWeb: () async => called = true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar en la web'));
    await tester.pump();
    expect(called, isTrue);
  });
}
