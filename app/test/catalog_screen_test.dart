import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/catalog_screen.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// `/catalog` (Task 6, listado): el toggle Producto/Servicio decide el
/// `kind` que se le pide a `fetch` (paridad con `productHitsQ` de la web,
/// que SIEMPRE filtra por `kind`), las tarjetas muestran nombre/precio
/// (fijo y rango, `catalogPriceLabel`), y hay estado vacío con guía y
/// estado de error con reintento. `fetch` se inyecta (mismo patrón que
/// `ProviderInboxView`) para probar el widget sin tocar la red.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  // Desde Task 5 hay DOS `HeaderSegmented` en pantalla (Producto/Servicio y
  // Al detalle/Al por mayor) — este finder aísla el primero para los tests
  // que ya existían y solo les interesa el toggle de tipo.
  Finder kindSegmented() => find.byWidgetPredicate(
      (w) => w is HeaderSegmented && w.options.first == 'Producto');

  Future<List<Map<String, dynamic>>> vacio(
          {required String kind,
          String? search,
          String? categoryId,
          String? rubro,
          bool wholesale = false}) async =>
      [];

  final fixedItem = {
    'id': 'p1',
    'user_id': 'u1',
    'business_id': 'b1',
    'name': 'Taladro inalámbrico',
    'description': '',
    'price': 1500,
    'price_min': null,
    'price_max': null,
    'image_urls': <String>[],
    'category_id': 'ferreteria',
    'rubro': 'Herramientas',
    'kind': 'producto',
  };

  final rangeItem = {
    'id': 'p2',
    'user_id': 'u2',
    'business_id': 'b2',
    'name': 'Instalación eléctrica',
    'description': '',
    'price': null,
    'price_min': 1000,
    'price_max': 2500,
    'image_urls': <String>[],
    'category_id': 'electricidad',
    'rubro': 'Electricistas',
    'kind': 'servicio',
  };

  testWidgets('arranca en Producto y le pide a fetch kind=producto',
      (tester) async {
    final calls = <String>[];
    Future<List<Map<String, dynamic>>> recorder(
        {required String kind,
        String? search,
        String? categoryId,
        String? rubro,
        bool wholesale = false}) async {
      calls.add(kind);
      return [];
    }

    await tester.pumpWidget(
        host(CatalogView(fetch: recorder, actions: const [])));
    await tester.pumpAndSettle();

    expect(calls, ['producto']);
    final toggle = tester.widget<HeaderSegmented>(kindSegmented());
    expect(toggle.index, 0);
  });

  testWidgets('tocar "Servicio" vuelve a pedir el catálogo con kind=servicio',
      (tester) async {
    final calls = <String>[];
    Future<List<Map<String, dynamic>>> recorder(
        {required String kind,
        String? search,
        String? categoryId,
        String? rubro,
        bool wholesale = false}) async {
      calls.add(kind);
      return [];
    }

    await tester.pumpWidget(
        host(CatalogView(fetch: recorder, actions: const [])));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();

    expect(calls, ['producto', 'servicio']);
  });

  testWidgets('la tarjeta muestra nombre y precio fijo', (tester) async {
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [fixedItem],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Taladro inalámbrico'), findsOneWidget);
    expect(find.text('RD\$1,500'), findsOneWidget);
  });

  testWidgets('la tarjeta muestra el rango de precio cuando no hay precio fijo',
      (tester) async {
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [rangeItem],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Instalación eléctrica'), findsOneWidget);
    expect(find.text('RD\$1,000 - RD\$2,500'), findsOneWidget);
  });

  testWidgets('estado vacío muestra una guía, no una rejilla en blanco',
      (tester) async {
    await tester
        .pumpWidget(host(CatalogView(fetch: vacio, actions: const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aún no hay artículos'), findsOneWidget);
  });

  testWidgets('estado de error muestra Reintentar y reintentar vuelve a pedir',
      (tester) async {
    var attempts = 0;
    Future<List<Map<String, dynamic>>> fallando(
        {required String kind,
        String? search,
        String? categoryId,
        String? rubro,
        bool wholesale = false}) async {
      attempts++;
      // El `await` real importa: sin él la excepción "completa" el Future
      // antes de que el próximo frame re-adjunte el listener del
      // FutureBuilder (el `setState` de `_refetch` no reconstruye
      // sincrónicamente), y el test framework lo reporta como no
      // manejado aunque la UI sí lo capture bien vía `snapshot.hasError`.
      // Cualquier llamada de red real (como `catalogProducts`) ya tiene
      // ese respiro asíncrono de por sí.
      await Future<void>.delayed(Duration.zero);
      throw Exception('caído');
    }

    await tester.pumpWidget(
        host(CatalogView(fetch: fallando, actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
  });

  testWidgets('escribir y enviar la búsqueda se la pasa a fetch',
      (tester) async {
    final searches = <String?>[];
    Future<List<Map<String, dynamic>>> recorder(
        {required String kind,
        String? search,
        String? categoryId,
        String? rubro,
        bool wholesale = false}) async {
      searches.add(search);
      return [];
    }

    await tester.pumpWidget(
        host(CatalogView(fetch: recorder, actions: const [])));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'taladro');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(searches.last, 'taladro');
  });

  testWidgets(
      'la lista no desborda con un nombre largo en un ancho de teléfono típico',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    final longName = {
      ...fixedItem,
      'id': 'p3',
      'name': 'Set de destornilladores de precisión de 32 piezas',
    };
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [longName, rangeItem],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // El catálogo es también la pantalla "Otros proveedores" a la que el
  // proveedor llega APILADA desde el menú del avatar. Empujada debe ofrecer
  // una flecha de atrás (sin perder el toggle Producto/Servicio); como
  // pestaña del cliente (sin apilar) no muestra flecha.
  testWidgets('sin apilar: no hay flecha de atrás, sí el segmentado',
      (tester) async {
    await tester.pumpWidget(host(CatalogView(fetch: vacio, actions: const [])));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(kindSegmented(), findsOneWidget);
  });

  testWidgets('apilada (canPop): muestra atrás y conserva el segmentado',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    CatalogView(fetch: vacio, actions: const []))),
            child: const Text('ir al catálogo'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ir al catálogo'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(kindSegmented(), findsOneWidget);
  });

  testWidgets('la tarjeta muestra la reputación (★ + promedio + conteo)',
      (tester) async {
    final rated = {...fixedItem, 'avg_rating': 8.7, 'reviews_count': 34};
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [rated],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('8.7'), findsOneWidget);
    expect(find.text('(34)'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });

  testWidgets('cambiar de kind limpia categoría y rubro', (tester) async {
    final seen = <Map<String, dynamic>>[];
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        seen.add({'kind': kind, 'categoryId': categoryId, 'rubro': rubro});
        return [];
      },
      actions: const [],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();

    expect(seen.last['kind'], 'servicio');
    expect(seen.last['categoryId'], isNull);
    expect(seen.last['rubro'], isNull);
  });

  testWidgets('el toggle Al por mayor filtra el catálogo', (tester) async {
    final wholesaleSeen = <bool>[];
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        wholesaleSeen.add(wholesale);
        return [];
      },
      actions: const [],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al por mayor'));
    await tester.pumpAndSettle();

    expect(wholesaleSeen.last, isTrue);
  });
}
