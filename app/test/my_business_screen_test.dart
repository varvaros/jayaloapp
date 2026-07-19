import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/my_business_screen.dart';

/// Task 4: "Mi negocio" recibe lo que se MUEVE desde Estadísticas — catálogo
/// (productos/servicios) y trabajos realizados. NO hay edición en v1.
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
  );

  testWidgets('muestra el nombre del negocio y el sello de verificación',
      (tester) async {
    await tester.pumpWidget(host(MyBusinessView(
        business: negocio, productos: 4, servicios: 2, completados: 7)));
    await tester.pumpAndSettle();
    expect(find.text('Ferretería Pérez'), findsOneWidget);
    expect(find.textContaining('verificado'), findsOneWidget);
  });

  testWidgets('sin sello de verificación no muestra la insignia',
      (tester) async {
    await tester.pumpWidget(host(MyBusinessView(
        business: (
          id: 'biz-1',
          name: 'Ferretería Pérez',
          logoUrl: null,
          verified: false,
        ),
        productos: 4,
        servicios: 2,
        completados: 7)));
    await tester.pumpAndSettle();
    expect(find.textContaining('verificado'), findsNothing);
  });

  testWidgets('muestra productos y servicios (catálogo movido de Estadísticas)',
      (tester) async {
    await tester.pumpWidget(host(MyBusinessView(
        business: negocio, productos: 4, servicios: 2, completados: 7)));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 productos'), findsOneWidget);
    expect(find.textContaining('2 servicios'), findsOneWidget);
    // El catálogo sigue INERTE: se administra desde jayalo.com, sin edición v1.
    final catalogo = tester.widget<CatalogCard>(find.byType(CatalogCard));
    expect(catalogo.onTap, isNull);
    expect(find.textContaining('Se administran desde jayalo.com'),
        findsOneWidget);
  });

  testWidgets('muestra trabajos realizados (movido de Estadísticas)',
      (tester) async {
    await tester.pumpWidget(host(MyBusinessView(
        business: negocio, productos: 4, servicios: 2, completados: 7)));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.textContaining('trabajos realizados'), findsOneWidget);
  });

  testWidgets('sin negocio muestra un aviso en vez de reventar',
      (tester) async {
    await tester.pumpWidget(host(const MyBusinessView(
        business: null, productos: 0, servicios: 0, completados: 0)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No encontramos tu negocio'), findsOneWidget);
  });
}
