import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/catalog_portada.dart';
import 'package:jayalo_app/features/shared/product_list_card.dart';

BusinessCardInfo biz(String name, {bool local = false}) => (
  name: name,
  logoUrl: null,
  whatsappVerified: false,
  identityVerified: false,
  businessVerified: false,
  hasPhysicalLocation: local,
);

Map<String, dynamic> item(String id, {String? biz, String? cat}) => {
  'id': id,
  'name': 'Artículo $id',
  'business_id': biz,
  'category_id': cat,
  'price': 100,
};

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: Scaffold(body: child),
  );

  /// Viewport ALTO: la portada es un `ListView` perezoso y con 800×600 el
  /// carrusel por categoría (el último) no llega a construirse — un
  /// `findsNothing` pasaría en falso (gotcha 2026-09-04). Llamar al inicio
  /// de CADA test.
  void alto(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
  }

  final items = [
    item('1', biz: 'b1', cat: 'belleza'),
    item('2', biz: 'b2', cat: 'belleza'),
    item('3', biz: 'b1', cat: 'hogar'),
  ];
  final negocios = {
    'b1': biz('Barbería El Conde', local: true),
    'b2': biz('Glam'),
  };
  final counts = {'belleza': 2, 'hogar': 1};

  testWidgets('pinta las cuatro secciones y el header arriba', (tester) async {
    alto(tester);
    await tester.pumpWidget(
      host(
        CatalogPortada(
          items: items,
          negocios: negocios,
          counts: counts,
          onVerTodo: () {},
          onCategory: (_) {},
          onStore: (_) {},
          header: const Text('CHIPS'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CHIPS'), findsOneWidget);
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.text('Tiendas'), findsOneWidget);
    expect(find.text('Por categoría'), findsOneWidget);
    // Carrusel de la categoría con ≥2 ítems; hogar (1) no tiene carrusel.
    expect(find.text('Belleza'), findsWidgets); // tile + título de carrusel
    // Tiles con conteo.
    expect(find.text('2 artículos'), findsOneWidget);
    expect(find.text('1 artículo'), findsOneWidget);
    // Tiendas distintas (el nombre sale también en la línea de tienda de las
    // tarjetas, por eso `findsWidgets`; el círculo se comprueba por su inicial
    // en el último test).
    expect(find.text('Barbería El Conde'), findsWidgets);
    expect(find.text('Glam'), findsWidgets);
    // Recién publicados (3) + carrusel belleza (2) = 5 tarjetas de carrusel.
    expect(find.byType(ProductCarouselCard), findsNWidgets(5));
  });

  testWidgets('«Ver todo» de Recién publicados llama onVerTodo', (
    tester,
  ) async {
    alto(tester);
    var llamado = false;
    await tester.pumpWidget(
      host(
        CatalogPortada(
          items: items,
          negocios: negocios,
          counts: counts,
          onVerTodo: () => llamado = true,
          onCategory: (_) {},
          onStore: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todo').first);
    expect(llamado, isTrue);
  });

  testWidgets('tocar un tile o el «Ver todo» de un carrusel avisa con el id', (
    tester,
  ) async {
    alto(tester);
    final ids = <String>[];
    await tester.pumpWidget(
      host(
        CatalogPortada(
          items: items,
          negocios: negocios,
          counts: counts,
          onVerTodo: () {},
          onCategory: ids.add,
          onStore: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 artículo')); // tile de Hogar
    await tester.tap(find.text('Ver todo').last); // carrusel de Belleza
    expect(ids, ['hogar', 'belleza']);
  });

  testWidgets('tocar una tienda avisa con su business_id', (tester) async {
    alto(tester);
    String? tocada;
    await tester.pumpWidget(
      host(
        CatalogPortada(
          items: items,
          negocios: negocios,
          counts: counts,
          onVerTodo: () {},
          onCategory: (_) {},
          onStore: (id) => tocada = id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Se toca la INICIAL del círculo («G» de Glam): es única; el nombre
    // «Glam» sale además en las tarjetas.
    await tester.tap(find.text('G'));
    expect(tocada, 'b2');
  });

  testWidgets('con un solo ítem: Recién publicados sí, carruseles no', (
    tester,
  ) async {
    alto(tester);
    await tester.pumpWidget(
      host(
        CatalogPortada(
          items: [items.first],
          negocios: negocios,
          counts: counts,
          onVerTodo: () {},
          onCategory: (_) {},
          onStore: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.byType(ProductCarouselCard), findsOneWidget);
  });

  testWidgets(
    'sin conteos no hay «Por categoría»; sin negocios no hay «Tiendas»',
    (tester) async {
      alto(tester);
      await tester.pumpWidget(
        host(
          CatalogPortada(
            items: items,
            negocios: const {},
            counts: null,
            onVerTodo: () {},
            onCategory: (_) {},
            onStore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Por categoría'), findsNothing);
      expect(find.text('Tiendas'), findsNothing);
      expect(find.text('Recién publicados'), findsOneWidget);
    },
  );

  testWidgets('sin logo el círculo lleva la inicial del negocio', (
    tester,
  ) async {
    alto(tester);
    await tester.pumpWidget(
      host(
        CatalogPortada(
          items: items,
          negocios: negocios,
          counts: counts,
          onVerTodo: () {},
          onCategory: (_) {},
          onStore: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // «B»: el círculo de Barbería Y la pastilla del tile «Belleza».
    expect(find.text('B'), findsNWidgets(2));
    expect(find.text('G'), findsOneWidget); // solo el círculo de Glam
    expect(find.text('H'), findsOneWidget); // solo la pastilla del tile Hogar
  });
  testWidgets(
    'la rejilla «Por categoría» no hereda el padding del MediaQuery (hueco)',
    (tester) async {
      alto(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: MediaQuery(
            // Insets como los del shell real: barra de estado arriba y la
            // reserva de la navbar flotante abajo. Un scrollable anidado sin
            // `padding` explícito se los apropia y deja un hueco (PO 09-06).
            data: const MediaQueryData(
              size: Size(400, 1600),
              padding: EdgeInsets.only(top: 40, bottom: 130),
            ),
            child: Scaffold(
              body: CatalogPortada(
                items: items,
                negocios: negocios,
                counts: counts,
                onVerTodo: () {},
                onCategory: (_) {},
                onStore: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = tester.getSize(find.byType(GridView));
      // Dos tiles caben en UNA fila de 56: nada de insets heredados.
      expect(grid.height, 56);
    },
  );
}
