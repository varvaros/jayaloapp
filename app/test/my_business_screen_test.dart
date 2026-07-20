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

  const negocio = (
    id: 'biz-1',
    name: 'Ferretería Pérez',
    logoUrl: null,
    verified: true,
    categoryId: 'ferreteria',
    city: 'Santiago',
    wholesale: true,
    description: 'Todo en herramientas',
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

  testWidgets('muestra nombre, verificación y detalles', (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('Ferretería Pérez'), findsOneWidget);
    expect(find.textContaining('verificado'), findsOneWidget);
    expect(find.textContaining('Ferretería'), findsWidgets); // nombre + categoría
    expect(find.textContaining('Santiago'), findsOneWidget); // zona
    expect(find.text('Mayorista'), findsOneWidget); // chip mayorista
  });

  testWidgets('lista productos y servicios', (tester) async {
    await tester
        .pumpWidget(view(productos: unProducto, servicios: unServicio));
    await tester.pumpAndSettle();
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
    expect(find.text('OPINIONES'), findsOneWidget);
    expect(find.textContaining('4.8'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('Muy bueno'), findsOneWidget);
  });

  testWidgets('sin opiniones muestra aviso', (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
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
