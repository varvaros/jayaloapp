import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/contact_info.dart'
    show contactInfoCode, contactInfoMessage;
import 'package:jayalo_app/features/provider/add_store_item_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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
    String? brand,
    String? warranty,
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

      // Traslado/instalación/evaluación: el campo de costo NO se ve hasta
      // activar el interruptor.
      expect(find.text('Ofrezco traslado'), findsOneWidget);
      expect(find.text('Costo del traslado (RD\$)'), findsNothing);
      await tester.tap(find.byKey(const Key('switch-envio')));
      await tester.pumpAndSettle();
      expect(find.text('Costo del traslado (RD\$)'), findsOneWidget);

      expect(find.text('Ofrezco instalación'), findsOneWidget);
      expect(find.text('Requiere evaluación'), findsOneWidget);

      // Marca, estado, colores, garantía, entrega.
      expect(find.byKey(const Key('campo-marca')), findsOneWidget);
      expect(find.text('Nuevo'), findsOneWidget);
      expect(find.text('Usado'), findsOneWidget);
      expect(find.text('Negro'), findsOneWidget); // preset de color
      expect(find.text('Sin garantía'), findsOneWidget); // kWarrantyOptions
      // '5 días' (no '7 días': kWarrantyOptions y kDeliveryOptions comparten
      // vocabulario a propósito desde el Fix round 1 — '7 días'/'15 días'
      // están en las DOS listas y `find.text` sería ambiguo aquí).
      expect(find.text('5 días'), findsOneWidget); // kDeliveryOptions
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
        String? brand,
        String? warranty,
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
          'brand': brand,
          'warranty': warranty,
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
      // '5 días' (no '7 días'/'15 días': están en las DOS listas).
      await tester.tap(find.text('5 días')); // kDeliveryOptions
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('switch-envio')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.labelText == 'Costo del traslado (RD\$)'),
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
      // Fix round 1 (Important 4): brand/warranty viajan TAMBIÉN como
      // columnas reales, no solo dentro de offerDefaults.
      expect(captured!['brand'], 'Bosch');
      expect(captured!['warranty'], '1 año');
      expect(captured!['offerDefaults'], {
        'pricing_mode': 'fixed',
        'brand': 'Bosch',
        'warranty': '1 año',
        'delivery': '5 días',
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

      // Nada de producto — salvo garantía (hallazgo I-1, revisión final: la
      // web SÍ permite garantía en servicios; `productOnly: false`).
      expect(find.text('Ofrezco traslado'), findsNothing);
      expect(find.byKey(const Key('campo-marca')), findsNothing);
      expect(find.text('Tiempo de entrega'), findsNothing); // solo producto
      expect(find.text('Hoy'), findsNothing); // kDeliveryOptions, único ahí

      // I-1: garantía SÍ se muestra para servicio (paridad con producto).
      expect(find.text('Garantía'), findsOneWidget);
      expect(find.text('Sin garantía'), findsOneWidget); // kWarrantyOptions
    });

    // Fix round 1 (Critical 2): caso exacto de revisión — un servicio
    // creado ANTES de la Task 6 (sin `offer_defaults`) pero con
    // price_min/price_max ya guardados (modo rango). Sin la derivación desde
    // los datos reales, `_svcMode` caía a 'fixed' y "Guardar" sin tocar nada
    // mandaba price_min/price_max = null, borrando el rango en silencio.
    testWidgets(
        'servicio legacy sin offer_defaults con price_min/max: Guardar sin '
        'tocar conserva el rango', (tester) async {
      final legacyServicio = <String, dynamic>{
        'id': 's1',
        'name': 'Instalación eléctrica',
        'description': '',
        'color': '',
        'price': null,
        'price_min': 1000,
        'price_max': 3000,
        'image_urls': <String>[],
        'category_id': 'ferreteria',
        'rubro': 'Herramientas',
        'kind': 'servicio',
        'condition': null,
        'offers_shipping': false,
        'offers_installation': false,
        'requires_evaluation': false,
        // Sin 'offer_defaults': el caso legacy.
      };
      Map<String, dynamic>? updatedPayload;
      Future<void> captureUpdate(
          String id, Map<String, dynamic> payload) async {
        updatedPayload = payload;
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'servicio',
        businessId: 'biz-1',
        initial: legacyServicio,
        saveProduct: noopSave,
        updateItem: captureUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      // El molde detectó 'Rango' solo (sin tocar nada el usuario).
      expect(find.text('Instalación eléctrica'), findsOneWidget);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(updatedPayload, isNotNull);
      expect(updatedPayload!['price'], isNull);
      expect(updatedPayload!['price_min'], 1000.0);
      expect(updatedPayload!['price_max'], 3000.0);
    });

    // Hallazgo I-1 (revisión final): `updateStoreItem` mandaba
    // `warranty: null` SIEMPRE al editar un servicio, aunque el editor no
    // mostrara garantía — borrando en silencio lo que se hubiera puesto
    // desde la web (que sí permite garantía en servicios). El fix: el campo
    // se ve, se prellena desde la columna real y viaja en el payload.
    testWidgets(
        'editar servicio con warranty en columna: se prellena y el payload '
        'la conserva', (tester) async {
      final servicioConGarantia = <String, dynamic>{
        'id': 's2',
        'name': 'Instalación eléctrica',
        'description': '',
        'color': '',
        'price': 1500,
        'price_min': null,
        'price_max': null,
        'image_urls': <String>[],
        'category_id': 'ferreteria',
        'rubro': 'Herramientas',
        'kind': 'servicio',
        'condition': null,
        'offers_shipping': false,
        'offers_installation': false,
        'requires_evaluation': false,
        'warranty': '1 año',
        'offer_defaults': {'pricing_mode': 'fixed'},
      };
      Map<String, dynamic>? updatedPayload;
      Future<void> captureUpdate(
          String id, Map<String, dynamic> payload) async {
        updatedPayload = payload;
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'servicio',
        businessId: 'biz-1',
        initial: servicioConGarantia,
        saveProduct: noopSave,
        updateItem: captureUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // Sin tocar el chip de garantía: si el prellenado (columna real →
      // `_warranty.text`) no funcionara, esto viajaría vacío/null en vez de
      // conservar '1 año'.
      expect(updatedPayload, isNotNull);
      expect(updatedPayload!['warranty'], '1 año');
    });

    // Hallazgo I-3 (revisión final): un `catch (_)` genérico en `_save`
    // convertía el JY422 del trigger `enforce_no_contact_info` en el mismo
    // "No se pudo guardar" de cualquier otro fallo. Mismo patrón que
    // `package_editor_screen.dart` (`isContactInfoError`/`contactInfoMessage`).
    testWidgets(
        'guardar con un dato de contacto en el texto muestra el mensaje de '
        'contacto, no el genérico', (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'servicio',
        businessId: 'biz-1',
        saveProduct: noopSave,
        updateItem: (id, payload) async {
          throw const PostgrestException(
              message: 'contains contact info', code: contactInfoCode);
        },
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
        initial: const {
          'id': 's3',
          'name': 'Instalación',
          'description': '',
          'kind': 'servicio',
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text(contactInfoMessage), findsOneWidget);
      expect(find.text('No se pudo guardar. Intenta de nuevo.'), findsNothing);
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
      // Columnas reales (Fix round 1, Important 4) — mismo valor que el
      // jsonb: el caso normal, un ítem guardado ya con el fix.
      'brand': 'Bosch',
      'warranty': '1 año',
      'offer_defaults': {
        'pricing_mode': 'fixed',
        'brand': 'Bosch',
        'warranty': '1 año',
        'delivery': '7 días',
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
      // Fix round 1 (Important 4): brand/warranty también en sus columnas.
      expect(updatedPayload!['brand'], 'Bosch');
      expect(updatedPayload!['warranty'], '1 año');
      expect(updatedPayload!['offer_defaults'], {
        'pricing_mode': 'fixed',
        'brand': 'Bosch',
        'warranty': '1 año',
        'delivery': '7 días',
        'colors': ['Negro', 'Rojo'],
        'shipping_price': 300.0,
      });
    });

    // Fix round 1 (Important 4): al prellenar, la columna real gana sobre
    // offer_defaults — un ítem cuya columna diverge del jsonb (dato viejo, o
    // editado alguna vez desde la web) debe mostrar lo que pinta la ficha
    // pública, no una copia stale del molde.
    testWidgets('brand/warranty: la columna real gana sobre offer_defaults '
        'al prellenar', (tester) async {
      final item = <String, dynamic>{
        ...itemProducto,
        'brand': 'Marca de la columna',
        'warranty': 'Garantía de la columna',
        'offer_defaults': {
          ...itemProducto['offer_defaults'] as Map<String, dynamic>,
          'brand': 'Marca vieja del jsonb',
          'warranty': 'Garantía vieja del jsonb',
        },
      };
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'producto',
        businessId: 'biz-1',
        initial: item,
        saveProduct: noopSave,
        updateItem: noopUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<TextField>(find.byKey(const Key('campo-marca')))
              .controller!
              .text,
          'Marca de la columna');
    });

    // Y el fallback: sin columna (dato viejo escrito solo con la primera
    // versión de esta tarea, antes del fix), el jsonb sigue sirviendo.
    testWidgets('brand/warranty: sin columna, cae al valor de offer_defaults',
        (tester) async {
      final item = <String, dynamic>{
        ...itemProducto,
        'brand': null,
        'warranty': null,
      };
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'producto',
        businessId: 'biz-1',
        initial: item,
        saveProduct: noopSave,
        updateItem: noopUpdate,
        savePortfolio: noopPortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<TextField>(find.byKey(const Key('campo-marca')))
              .controller!
              .text,
          'Bosch'); // valor del jsonb en itemProducto
    });
  });
}
