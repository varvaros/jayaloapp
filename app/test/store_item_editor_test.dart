import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/add_store_item_screen.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  // El editor es un formulario largo: con la surface de prueba por defecto
  // (800x600, apaisada) los campos de más abajo (chips + Guardar) quedan
  // fuera del cacheExtent del ListView y ni se construyen — mismo ajuste que
  // `product_detail_screen_test.dart`. Alto de sobra para no tener que
  // scrollear en los tests que tocan el molde entero.
  void setTallPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // Dobles que nunca tocan la red: [saveProduct]/[updateItem] no se llaman en
  // los tests de solo-render, así que basta con que existan.
  Future<void> noopSave({
    required String businessId,
    required String name,
    required String description,
    required String categoryId,
    required String rubro,
    required String kind,
    String color = '',
    double? price,
    double? priceMin,
    double? priceMax,
    List<String> imageUrls = const [],
    String? condition,
    bool offersShipping = false,
    bool offersInstallation = false,
    bool requiresEvaluation = false,
    Map<String, dynamic>? offerDefaults,
  }) async {}

  Future<void> noopUpdate(String id, Map<String, dynamic> payload) async {}

  Future<void> noopPortfolio({
    required String businessId,
    required String title,
    String? description,
    List<String> imageUrls = const [],
  }) async {}

  Future<({String? categoryId, String? rubro})> fakeCatRubro(
    String businessId,
  ) async =>
      (categoryId: 'ferreteria', rubro: 'Herramientas');

  group('AddStoreItemScreen — producto (Task 6)', () {
    testWidgets('(a) muestra fijo/rango, envío/instalación/evaluación con '
        'campo de precio al activarse, marca, estado, colores, garantía y '
        'entrega', (tester) async {
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'producto',
        businessId: 'biz-1',
        saveProduct: noopSave,
        updateItem: noopUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      // El molde de precio (producto).
      expect(find.text('Precio fijo'), findsOneWidget);
      expect(find.text('Rango'), findsOneWidget);
      expect(find.byKey(const Key('campo-precio')), findsOneWidget);

      // Envío/instalación/evaluación: el campo de costo NO se ve hasta
      // activar el interruptor.
      expect(find.text('Ofrezco envío'), findsOneWidget);
      expect(find.text('Costo de envío (RD\$)'), findsNothing);
      await tester.tap(find.byKey(const Key('switch-envio')));
      await tester.pumpAndSettle();
      expect(find.text('Costo de envío (RD\$)'), findsOneWidget);

      expect(find.text('Ofrezco instalación'), findsOneWidget);
      expect(find.text('Requiere evaluación'), findsOneWidget);

      // Marca, estado, colores, garantía, entrega.
      expect(find.byKey(const Key('campo-marca')), findsOneWidget);
      expect(find.text('Nuevo'), findsOneWidget);
      expect(find.text('Usado'), findsOneWidget);
      expect(find.text('Negro'), findsOneWidget); // preset de color
      expect(find.text('Sin garantía'), findsOneWidget); // kWarrantyOptions
      expect(find.text('A coordinar'), findsOneWidget); // kDeliveryOptions
    });

    testWidgets('(c) guardar producto llama al doble con offerDefaults '
        'campo por campo', (tester) async {
      Map<String, dynamic>? captured;
      Future<void> captureSave({
        required String businessId,
        required String name,
        required String description,
        required String categoryId,
        required String rubro,
        required String kind,
        String color = '',
        double? price,
        double? priceMin,
        double? priceMax,
        List<String> imageUrls = const [],
        String? condition,
        bool offersShipping = false,
        bool offersInstallation = false,
        bool requiresEvaluation = false,
        Map<String, dynamic>? offerDefaults,
      }) async {
        captured = {
          'businessId': businessId,
          'name': name,
          'categoryId': categoryId,
          'rubro': rubro,
          'kind': kind,
          'color': color,
          'price': price,
          'condition': condition,
          'offersShipping': offersShipping,
          'offerDefaults': offerDefaults,
        };
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'producto',
        businessId: 'biz-1',
        saveProduct: captureSave,
        updateItem: noopUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Taladro Bosch');
      await tester.enterText(find.byKey(const Key('campo-precio')), '2500');
      await tester.enterText(
          find.byKey(const Key('campo-marca')), '  Bosch  ');
      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Negro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 año')); // kWarrantyOptions
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 semana')); // kDeliveryOptions
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('switch-envio')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.labelText == 'Costo de envío (RD\$)'),
          '300');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!['businessId'], 'biz-1');
      expect(captured!['name'], 'Taladro Bosch');
      expect(captured!['categoryId'], 'ferreteria');
      expect(captured!['rubro'], 'Herramientas');
      expect(captured!['kind'], 'producto');
      expect(captured!['color'], 'Negro');
      expect(captured!['price'], 2500.0);
      expect(captured!['condition'], 'nuevo');
      expect(captured!['offersShipping'], isTrue);
      expect(captured!['offerDefaults'], {
        'pricing_mode': 'fixed',
        'brand': 'Bosch',
        'warranty': '1 año',
        'delivery': '1 semana',
        'colors': ['Negro'],
        'shipping_price': 300.0,
      });
    });
  });

  group('AddStoreItemScreen — servicio (Task 6)', () {
    testWidgets('(b) muestra los 4 modos + disponibilidad + duración y NO '
        'los campos de producto', (tester) async {
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'servicio',
        businessId: 'biz-1',
        saveProduct: noopSave,
        updateItem: noopUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Fijo'), findsOneWidget);
      expect(find.text('Rango'), findsOneWidget);
      expect(find.text('Por hora'), findsOneWidget);
      expect(find.text('A evaluar'), findsOneWidget);
      expect(find.byKey(const Key('campo-disponibilidad')), findsOneWidget);
      expect(find.byKey(const Key('campo-duracion')), findsOneWidget);

      // Nada de producto.
      expect(find.text('Ofrezco envío'), findsNothing);
      expect(find.byKey(const Key('campo-marca')), findsNothing);
      expect(find.text('Sin garantía'), findsNothing);
      expect(find.text('A coordinar'), findsNothing); // kDeliveryOptions
    });
  });

  group('AddStoreItemScreen — trabajo (Task 6)', () {
    testWidgets('(d) queda EXACTO como hoy (sin campos nuevos)',
        (tester) async {
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        saveProduct: noopSave,
        updateItem: noopUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Título del trabajo'), findsOneWidget);
      expect(find.text('Descripción (opcional)'), findsOneWidget);
      // Sin molde de oferta ni campo de precio para trabajos.
      expect(find.text('Detalles para tus ofertas (opcional)'), findsNothing);
      expect(find.text('Precio en RD\$ (opcional)'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('AddStoreItemScreen — modo edición (Task 6, Step 6)', () {
    final itemProducto = <String, dynamic>{
      'id': 'p1',
      'name': 'Taladro Bosch',
      'description': 'Taladro percutor',
      'color': 'Negro',
      'price': 2500,
      'price_min': null,
      'price_max': null,
      'image_urls': <String>['https://img/1.jpg'],
      'category_id': 'ferreteria',
      'rubro': 'Herramientas',
      'kind': 'producto',
      'condition': 'nuevo',
      'offers_shipping': true,
      'offers_installation': false,
      'requires_evaluation': false,
      'offer_defaults': {
        'pricing_mode': 'fixed',
        'brand': 'Bosch',
        'warranty': '1 año',
        'delivery': '1 semana',
        'colors': ['Negro', 'Rojo'],
        'shipping_price': 300,
      },
    };

    testWidgets('prellena todos los campos desde initial', (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'producto',
        businessId: 'biz-1',
        initial: itemProducto,
        saveProduct: noopSave,
        updateItem: noopUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Editar producto'), findsOneWidget);
      expect(find.text('Taladro Bosch'), findsOneWidget);
      expect(find.text('Taladro percutor'), findsOneWidget);
      expect(
          (tester
                  .widget<TextField>(find.byKey(const Key('campo-precio')))
                  .controller!
                  .text),
          '2500');
      expect(
          (tester
                  .widget<TextField>(find.byKey(const Key('campo-marca')))
                  .controller!
                  .text),
          'Bosch');
    });

    testWidgets('guardar en edición llama a updateItem con el payload',
        (tester) async {
      String? updatedId;
      Map<String, dynamic>? updatedPayload;
      Future<void> captureUpdate(String id, Map<String, dynamic> payload) async {
        updatedId = id;
        updatedPayload = payload;
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'producto',
        businessId: 'biz-1',
        initial: itemProducto,
        saveProduct: noopSave,
        updateItem: captureUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(updatedId, 'p1');
      expect(updatedPayload, isNotNull);
      expect(updatedPayload!['name'], 'Taladro Bosch');
      expect(updatedPayload!['price'], 2500.0);
      expect(updatedPayload!['offer_defaults'], {
        'pricing_mode': 'fixed',
        'brand': 'Bosch',
        'warranty': '1 año',
        'delivery': '1 semana',
        'colors': ['Negro', 'Rojo'],
        'shipping_price': 300.0,
      });
    });
  });
}
