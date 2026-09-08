import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart'
    show BusinessCardInfo, negocioCatalogoDe;
import 'package:jayalo_app/features/client/catalog_articulos.dart';
import 'package:jayalo_app/features/client/catalog_secciones.dart';

// Helpers copiados de `catalog_portada_test.dart` (no se importa un test
// desde otro test). `biz()` ya trae `description`/`city` (Task 2). `item()`
// gana `kind` (Task 6 lo necesita para armar Productos/Servicios/Paquetes;
// no vivía en el helper original de la portada).
BusinessCardInfo biz(String name, {bool local = false}) => (
  name: name,
  logoUrl: null,
  whatsappVerified: false,
  identityVerified: false,
  businessVerified: false,
  hasPhysicalLocation: local,
  description: null,
  city: null,
);

Map<String, dynamic> item(
  String id, {
  String? biz = 'b1',
  String? cat = 'belleza',
  String kind = 'producto',
}) => {
  'id': id,
  'name': 'Artículo $id',
  'business_id': biz,
  'category_id': cat,
  'kind': kind,
  'price': 100,
};

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: Scaffold(body: child),
  );

  /// Viewport ALTO: ver gotcha 2026-09-04 en `catalog_portada_test.dart` —
  /// con 800×600 un `ListView` perezoso no llega a construir las últimas
  /// secciones y un `findsNothing` pasaría en falso.
  void alto(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
  }

  testWidgets(
    'cuatro secciones en orden fijo, con conteo y Ver todos; sección vacía no se pinta',
    (tester) async {
      alto(tester);
      final items = [item('p1'), item('s1', kind: 'servicio')]; // sin paquetes
      final negocios = {'b1': biz('getto', local: true)};
      final proveedores = proveedoresDeItems(items, {
        'b1': negocioCatalogoDe(negocios['b1']!),
      });
      String? verTodos;
      await tester.pumpWidget(
        host(
          CatalogSecciones(
            items: items,
            negocios: negocios,
            proveedores: proveedores,
            conteos: (productos: 1, servicios: 1, paquetes: 0, proveedores: 1),
            onVerTodos: (t) => verTodos = t,
            onStore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final titulos = tester
          .widgetList<Text>(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  [
                    'Proveedores',
                    'Productos',
                    'Servicios',
                    'Paquetes',
                  ].contains(w.data),
            ),
          )
          .map((t) => t.data)
          .toList();
      expect(titulos, ['Proveedores', 'Productos', 'Servicios']);
      await tester.tap(find.text('Ver todos').at(2));
      expect(verTodos, 'servicio');
    },
  );

  testWidgets('ProveedorCard pinta Verificado y Tienda física', (tester) async {
    await tester.pumpWidget(
      host(
        ProveedorCard(
          p: (
            id: 'b',
            name: 'Dra',
            logoUrl: null,
            hasPhysicalLocation: true,
            city: 'Santiago',
            verificado: true,
            queHace: 'Medicina general',
          ),
          onTap: () {},
        ),
      ),
    );
    expect(find.text('Verificado'), findsOneWidget);
    expect(find.textContaining('Tienda física'), findsOneWidget);
    expect(find.text('Medicina general'), findsOneWidget);
  });
}
