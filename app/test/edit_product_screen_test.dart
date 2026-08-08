import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/edit_product_screen.dart';

/// Editor de un producto de la tienda EN LA APP (PO 2026-08-08: "debe permitir
/// editar el producto desde la app"). Se prueba [EditProductForm], que no toca
/// la red: recibe la fila cruda de `provider_products` y entrega el
/// [ProductEdit] que se guardaría — mismo patrón que `MyBusinessView`.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  Map<String, dynamic> producto({
    String kind = 'producto',
    num? price = 2500,
    num? priceMin,
    num? priceMax,
    String? condition,
    List<String> imageUrls = const [],
    String? brand,
    String? warranty,
  }) =>
      {
        'id': 'p1',
        'user_id': 'u1',
        'name': 'Taladro Bosch',
        'description': 'Taladro percutor de 800W',
        'color': 'Azul',
        'price': price,
        'price_min': priceMin,
        'price_max': priceMax,
        'image_urls': imageUrls,
        'category_id': 'ferreteria',
        'rubro': 'Herramientas',
        'kind': kind,
        'condition': condition,
        'brand': brand,
        'warranty': warranty,
        'offers_shipping': false,
        'offers_installation': false,
        'requires_evaluation': false,
      };

  /// El formulario es más alto que el viewport de 800x600 de los tests, así que
  /// lo de abajo (chips, fotos, el botón de guardar) todavía no está
  /// construido: se baja como bajaría alguien.
  /// `scrollable:` es obligatorio: cada `TextField` trae su propio `Scrollable`
  /// interno, así que sin él `scrollUntilVisible` revienta con "Too many
  /// elements". El del formulario es el primero en el árbol (el `ListView` es
  /// la raíz de la pantalla, por encima de cualquier campo).
  Future<void> bajarHasta(WidgetTester tester, Finder f) async {
    if (f.evaluate().isNotEmpty) return;
    await tester.scrollUntilVisible(f, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  /// Monta el formulario y devuelve un lector del último [ProductEdit]
  /// entregado a `onSave` (null si todavía no se guardó).
  Future<ProductEdit? Function()> montar(
    WidgetTester tester,
    Map<String, dynamic> p,
  ) async {
    ProductEdit? capturado;
    await tester.pumpWidget(host(EditProductForm(
      product: p,
      onSave: (edit) async {
        capturado = edit;
        return true;
      },
    )));
    await tester.pumpAndSettle();
    return () => capturado;
  }

  Future<void> guardar(WidgetTester tester) async {
    await bajarHasta(tester, find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
  }

  Finder campo(String label) => find.widgetWithText(TextField, label);

  testWidgets('precarga nombre, descripción y precio fijo', (tester) async {
    await montar(tester, producto());
    expect(find.text('Taladro Bosch'), findsOneWidget);
    expect(find.text('Taladro percutor de 800W'), findsOneWidget);
    expect(find.text('2500'), findsOneWidget);
  });

  testWidgets('un producto con rango abre en modo Rango con desde y hasta',
      (tester) async {
    await montar(tester, producto(price: null, priceMin: 500, priceMax: 1200));
    expect(find.text('500'), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);
  });

  testWidgets('un producto sin precio abre en Consultar', (tester) async {
    await montar(tester, producto(price: null));
    expect(find.textContaining('Consultar precio'), findsOneWidget);
  });

  testWidgets('guardar entrega el nombre y el precio editados',
      (tester) async {
    final leer = await montar(tester, producto());
    await tester.enterText(campo('Nombre'), 'Taladro Makita');
    await tester.enterText(campo('Precio (RD\$)'), '3100');
    await tester.pumpAndSettle();
    await guardar(tester);
    final edit = leer();
    expect(edit, isNotNull);
    expect(edit!.name, 'Taladro Makita');
    expect(edit.price, 3100);
  });

  // Regresión del `UPDATE`: en Postgres, omitir una columna la deja como
  // estaba. Si al pasar de rango a precio fijo no viajara `price_min`/
  // `price_max` en null, el rango viejo se quedaría colgando — y el rango es
  // justo lo que la tarjeta del catálogo pinta cuando existe.
  testWidgets('pasar de rango a fijo limpia price_min y price_max',
      (tester) async {
    final leer =
        await montar(tester, producto(price: null, priceMin: 500, priceMax: 1200));
    await tester.tap(find.text('Fijo'));
    await tester.pumpAndSettle();
    await tester.enterText(campo('Precio (RD\$)'), '900');
    await tester.pumpAndSettle();
    await guardar(tester);
    final edit = leer()!;
    expect(edit.price, 900);
    expect(edit.priceMin, isNull);
    expect(edit.priceMax, isNull);
  });

  testWidgets('pasar de fijo a Consultar deja los tres precios en null',
      (tester) async {
    final leer = await montar(tester, producto());
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();
    await guardar(tester);
    final edit = leer()!;
    expect(edit.price, isNull);
    expect(edit.priceMin, isNull);
    expect(edit.priceMax, isNull);
  });

  testWidgets('sin nombre no se puede guardar', (tester) async {
    await montar(tester, producto());
    await tester.enterText(campo('Nombre'), '   ');
    await tester.pumpAndSettle();
    await bajarHasta(tester, find.text('Guardar cambios'));
    final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guardar cambios'));
    expect(boton.onPressed, isNull);
  });

  // `condition` viaja en minúsculas en la BD y los chips son capitalizados:
  // el viaje de ida y vuelta tiene que conservar el valor.
  testWidgets('el estado precarga el chip y se guarda en minúsculas',
      (tester) async {
    final leer = await montar(tester, producto(condition: 'usado'));
    await guardar(tester);
    expect(leer()!.condition, 'usado');
  });

  testWidgets('des-seleccionar el estado lo guarda como null', (tester) async {
    final leer = await montar(tester, producto(condition: 'usado'));
    await bajarHasta(tester, find.text('Usado'));
    await tester.tap(find.text('Usado'));
    await tester.pumpAndSettle();
    await guardar(tester);
    expect(leer()!.condition, isNull);
  });

  testWidgets('un SERVICIO no muestra los campos de producto', (tester) async {
    await montar(tester, producto(kind: 'servicio'));
    expect(find.text('Estado'), findsNothing);
    expect(find.text('Color'), findsNothing);
    expect(find.text('Garantía'), findsNothing);
    expect(find.text('Ofrezco envío'), findsNothing);
    // La evaluación previa SÍ aplica a los dos (igual que en la oferta).
    await bajarHasta(tester, find.text('Requiere evaluación previa'));
    expect(find.text('Requiere evaluación previa'), findsOneWidget);
  });

  testWidgets('quitar una foto publicada la saca del guardado', (tester) async {
    final leer = await montar(
      tester,
      producto(imageUrls: const [
        'https://x.test/a.jpg',
        'https://x.test/b.jpg',
      ]),
    );
    // Se baja hasta el rótulo de la sección (único) y no hasta el botón
    // "Quitar": hay uno por foto y `scrollUntilVisible` exige un solo destino.
    await bajarHasta(tester, find.text('Fotos (hasta $maxProductPhotos)'));
    await tester.tap(find.byTooltip('Quitar').first);
    await tester.pumpAndSettle();
    await guardar(tester);
    expect(leer()!.keptUrls, ['https://x.test/b.jpg']);
  });

  testWidgets('un servicio nunca arrastra estado, color ni garantía',
      (tester) async {
    final leer = await montar(
      tester,
      producto(kind: 'servicio', condition: 'usado', warranty: '1 año'),
    );
    await guardar(tester);
    final edit = leer()!;
    expect(edit.condition, isNull);
    expect(edit.color, '');
    expect(edit.warranty, isNull);
    expect(edit.offersShipping, isFalse);
  });

  // Sin `pumpAndSettle` NI scroll: con `busy` el botón lleva dentro el
  // `JayaloSpinner`, que gira para siempre y haría que `pumpAndSettle` expire.
  // El viewport alto evita tener que bajar (el `ListView` construye perezoso).
  testWidgets('busy deshabilita el guardado', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(EditProductForm(
      product: producto(),
      busy: true,
      onSave: (_) async => true,
    )));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
}
