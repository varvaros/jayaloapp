import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/catalog_portada.dart';
import 'package:jayalo_app/features/client/catalog_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/star_score.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// Dobles de las consultas de negocios y conteos, usados como valor por
/// defecto de `catalogo()` — deben ser funciones de nivel superior: un
/// closure local no es una "constant expression" válida para un default de
/// parámetro nombrado.
Future<Map<String, BusinessCardInfo>> sinNegocios(List<String> ids) async =>
    const {};
Future<Map<String, int>?> sinConteos(String kind) async => null;

/// `/catalog` (Task 6, listado): el toggle Producto/Servicio decide el
/// `kind` que se le pide a `fetch` (paridad con `productHitsQ` de la web,
/// que SIEMPRE filtra por `kind`), las tarjetas muestran nombre/precio
/// (fijo y rango, `catalogPriceLabel`), y hay estado vacío con guía y
/// estado de error con reintento. `fetch` se inyecta (mismo patrón que
/// `ProviderInboxView`) para probar el widget sin tocar la red.
void main() {
  // Estos tests son sobre el catálogo, no sobre onboarding. La guía welcome
  // `client.catalog.v1` (Task 6) monta un velo a pantalla completa que
  // intercepta los taps; marcarla como vista evita que el velo se coma los
  // taps de estos tests (mismo fix que `my_requests_others_test.dart`).
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    await onboardingStore.markDone('client.catalog.v1');
  });

  Widget host(Widget child) =>
      MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

  // Desde Task 5 hay DOS `HeaderSegmented` en pantalla (Producto/Servicio y
  // Al detalle/Al por mayor) — este finder aísla el primero para los tests
  // que ya existían y solo les interesa el toggle de tipo.
  Finder kindSegmented() => find.byWidgetPredicate(
    (w) => w is HeaderSegmented && w.options.first == 'Producto',
  );

  Future<List<Map<String, dynamic>>> vacio({
    required String kind,
    String? search,
    String? categoryId,
    String? rubro,
    bool wholesale = false,
  }) async => [];

  /// `CatalogView` con las consultas de negocios y conteos dobladas: los
  /// tests que solo miran productos no deben tocar la red.
  Widget catalogo({
    required CatalogFetch fetch,
    CatalogBusinessesFetch businesses = sinNegocios,
    CatalogCountsFetch counts = sinConteos,
  }) => host(
    CatalogView(
      fetch: fetch,
      businesses: businesses,
      counts: counts,
      actions: const [],
    ),
  );

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

  testWidgets('arranca en Producto y le pide a fetch kind=producto', (
    tester,
  ) async {
    final calls = <String>[];
    Future<List<Map<String, dynamic>>> recorder({
      required String kind,
      String? search,
      String? categoryId,
      String? rubro,
      bool wholesale = false,
    }) async {
      calls.add(kind);
      return [];
    }

    await tester.pumpWidget(catalogo(fetch: recorder));
    await tester.pumpAndSettle();

    expect(calls, ['producto']);
    final toggle = tester.widget<HeaderSegmented>(kindSegmented());
    expect(toggle.index, 0);
  });

  testWidgets('tocar "Servicio" vuelve a pedir el catálogo con kind=servicio', (
    tester,
  ) async {
    final calls = <String>[];
    Future<List<Map<String, dynamic>>> recorder({
      required String kind,
      String? search,
      String? categoryId,
      String? rubro,
      bool wholesale = false,
    }) async {
      calls.add(kind);
      return [];
    }

    await tester.pumpWidget(catalogo(fetch: recorder));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();

    expect(calls, ['producto', 'servicio']);
  });

  testWidgets('la tarjeta muestra nombre y precio fijo', (tester) async {
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async => [fixedItem],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todo').first);
    await tester.pumpAndSettle();

    expect(find.text('Taladro inalámbrico'), findsOneWidget);
    expect(find.text('RD\$1,500'), findsOneWidget);
  });

  testWidgets(
    'la tarjeta muestra el rango de precio cuando no hay precio fijo',
    (tester) async {
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                required kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
              }) async => [rangeItem],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver todo').first);
      await tester.pumpAndSettle();

      expect(find.text('Instalación eléctrica'), findsOneWidget);
      expect(find.text('RD\$1,000 - RD\$2,500'), findsOneWidget);
    },
  );

  testWidgets(
    'la rejilla ya no pinta envío/estado/color (PO 2026-09-05: viven en la ficha)',
    (tester) async {
      final conAtributos = {
        ...fixedItem,
        'condition': 'nuevo',
        'offers_shipping': true,
        'offer_defaults': {
          'colors': ['Rojo', 'Azul'],
        },
      };
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                required kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
              }) async => [conAtributos],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver todo').first);
      await tester.pumpAndSettle();

      expect(find.text('Taladro inalámbrico'), findsOneWidget);
      expect(find.text('Traslado'), findsNothing);
      expect(find.text('Nuevo'), findsNothing);
      expect(find.text('Rojo, Azul'), findsNothing);
    },
  );

  testWidgets('estado vacío muestra una guía, no una rejilla en blanco', (
    tester,
  ) async {
    await tester.pumpWidget(catalogo(fetch: vacio));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aún no hay artículos'), findsOneWidget);
  });

  testWidgets(
    'estado de error muestra Reintentar y reintentar vuelve a pedir',
    (tester) async {
      var attempts = 0;
      Future<List<Map<String, dynamic>>> fallando({
        required String kind,
        String? search,
        String? categoryId,
        String? rubro,
        bool wholesale = false,
      }) async {
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

      await tester.pumpWidget(catalogo(fetch: fallando));
      await tester.pumpAndSettle();

      expect(find.text('Reintentar'), findsOneWidget);
      expect(attempts, 1);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
    },
  );

  testWidgets('escribir y enviar la búsqueda se la pasa a fetch', (
    tester,
  ) async {
    final searches = <String?>[];
    Future<List<Map<String, dynamic>>> recorder({
      required String kind,
      String? search,
      String? categoryId,
      String? rubro,
      bool wholesale = false,
    }) async {
      searches.add(search);
      return [];
    }

    await tester.pumpWidget(catalogo(fetch: recorder));
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
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                required kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
              }) async => [longName, rangeItem],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver todo').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  // El catálogo es también la pantalla "Otros proveedores" a la que el
  // proveedor llega APILADA desde el menú del avatar. Empujada debe ofrecer
  // una flecha de atrás (sin perder el toggle Producto/Servicio); como
  // pestaña del cliente (sin apilar) no muestra flecha.
  testWidgets('sin apilar: no hay flecha de atrás, sí el segmentado', (
    tester,
  ) async {
    await tester.pumpWidget(catalogo(fetch: vacio));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(kindSegmented(), findsOneWidget);
  });

  testWidgets('apilada (canPop): muestra atrás y conserva el segmentado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CatalogView(
                    fetch: vacio,
                    businesses: sinNegocios,
                    counts: sinConteos,
                    actions: const [],
                  ),
                ),
              ),
              child: const Text('ir al catálogo'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ir al catálogo'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(kindSegmented(), findsOneWidget);
  });

  testWidgets('la tarjeta muestra la reputación (★ + promedio + conteo)', (
    tester,
  ) async {
    final rated = {...fixedItem, 'avg_rating': 8.7, 'reviews_count': 34};
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async => [rated],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todo').first);
    await tester.pumpAndSettle();

    // La rejilla (mockup aprobado 2026-08-10) une promedio y conteo en un solo
    // texto compacto, que desde el 2026-08-17 lleva la escala: "8.7/10 (34)".
    expect(find.text('8.7/10 (34)'), findsOneWidget);
    // El widget, no el icono: cada estrella son dos iconos apilados.
    expect(find.byType(StarScore), findsOneWidget);
  });

  testWidgets('cambiar de kind limpia categoría, rubro, mayoreo y Ver todo', (
    tester,
  ) async {
    final seen = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async {
              seen.add({
                'kind': kind,
                'categoryId': categoryId,
                'wholesale': wholesale,
              });
              return [fixedItem];
            },
        counts: (_) async => {'ferreteria': 1},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ferretería').first); // el chip, no el tile
    await tester.pumpAndSettle();
    expect(seen.last['categoryId'], 'ferreteria');

    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();

    expect(seen.last['kind'], 'servicio');
    expect(seen.last['categoryId'], isNull);
    expect(seen.last['wholesale'], isFalse);
    expect(find.byType(CatalogPortada), findsOneWidget);
  });

  testWidgets('el chip Al por mayor filtra el catálogo y pasa a la rejilla', (
    tester,
  ) async {
    final wholesaleSeen = <bool>[];
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async {
              wholesaleSeen.add(wholesale);
              return [fixedItem];
            },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CatalogPortada), findsOneWidget);

    await tester.tap(find.text('Al por mayor'));
    await tester.pumpAndSettle();

    expect(wholesaleSeen.last, isTrue);
    expect(find.byType(CatalogPortada), findsNothing);
    expect(find.byType(SliverGrid), findsOneWidget);
  });

  testWidgets('en Servicio se oculta el toggle de mayoreo y se re-pide con '
      'wholesale=false (mayoreo es solo productos)', (tester) async {
    final wholesaleSeen = <bool>[];
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async {
              wholesaleSeen.add(wholesale);
              return [];
            },
      ),
    );
    await tester.pumpAndSettle();
    // En Producto el toggle está visible.
    expect(find.text('Al por mayor'), findsOneWidget);
    // Enciende mayoreo y luego cambia a Servicio.
    await tester.tap(find.text('Al por mayor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();
    // El toggle desaparece y el catálogo se re-pide sin mayoreo.
    expect(find.text('Al por mayor'), findsNothing);
    expect(wholesaleSeen.last, isFalse);
  });

  testWidgets('sin filtro se ve la portada y no la rejilla', (tester) async {
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async => [fixedItem, rangeItem],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CatalogPortada), findsOneWidget);
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);
  });

  testWidgets(
    'tocar un chip de categoría filtra y pasa a la rejilla; «Todo» vuelve',
    (tester) async {
      final cats = <String?>[];
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                required kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
              }) async {
                cats.add(categoryId);
                return [fixedItem];
              },
          counts: (_) async => {'ferreteria': 1, 'hogar': 2},
        ),
      );
      await tester.pumpAndSettle();
      // El chip Y el tile de «Por categoría» dicen «Ferretería»; el chip va
      // primero en el árbol (cabecera de la lista).
      expect(find.text('Ferretería'), findsWidgets);

      await tester.tap(find.text('Ferretería').first);
      await tester.pumpAndSettle();
      expect(cats.last, 'ferreteria');
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.byType(CatalogPortada), findsNothing);

      await tester.tap(find.text('Todo'));
      await tester.pumpAndSettle();
      expect(cats.last, isNull);
      expect(find.byType(CatalogPortada), findsOneWidget);
    },
  );

  testWidgets(
    '«Ver todo» enseña la rejilla sin re-pedir ni filtrar; «Todo» vuelve',
    (tester) async {
      var llamadas = 0;
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                required kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
              }) async {
                llamadas++;
                expect(categoryId, isNull);
                expect(wholesale, isFalse);
                return [fixedItem];
              },
        ),
      );
      await tester.pumpAndSettle();
      expect(llamadas, 1);

      await tester.tap(find.text('Ver todo').first);
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(llamadas, 1); // misma carga, otro cuerpo

      await tester.tap(find.text('Todo'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogPortada), findsOneWidget);
      expect(llamadas, 1);
    },
  );

  testWidgets('la rejilla pinta la tienda del negocio resuelto', (
    tester,
  ) async {
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async => [fixedItem],
        businesses: (ids) async => {
          'b1': (
            name: 'Ferretería Don Pepe',
            logoUrl: null,
            whatsappVerified: false,
            identityVerified: false,
            businessVerified: false,
            hasPhysicalLocation: true,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todo').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ferretería Don Pepe'), findsOneWidget);
    expect(find.textContaining('Tienda física'), findsOneWidget);
  });

  testWidgets('si la consulta de negocios falla, el catálogo se pinta igual', (
    tester,
  ) async {
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async => [fixedItem],
        businesses: (ids) async {
          await Future<void>.delayed(Duration.zero);
          throw Exception('caído');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.text('Tiendas'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '«Quitar filtro» del estado vacío limpia todo y vuelve a la portada',
    (tester) async {
      var vez = 0;
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                required kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
              }) async {
                vez++;
                // Primera carga: hay artículos. Con filtro: nada.
                return wholesale ? [] : [fixedItem];
              },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Al por mayor'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No hay artículos que coincidan'),
        findsOneWidget,
      );

      await tester.tap(find.text('Quitar filtro'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogPortada), findsOneWidget);
      expect(vez, 3);
    },
  );

  testWidgets(
    'la cabecera lleva el título a la izquierda y el segmentado compacto',
    (tester) async {
      await tester.pumpWidget(catalogo(fetch: vacio));
      await tester.pumpAndSettle();
      final header = tester.widget<VioletHeader>(find.byType(VioletHeader));
      expect(header.title, 'Catálogo');
      expect(header.titleAlign, HeaderTitleAlign.start);
      final seg = tester.widget<HeaderSegmented>(kindSegmented());
      expect(seg.compact, isTrue);
      expect(find.text('Al detalle'), findsNothing);
    },
  );

  testWidgets('tocar el chip de categoría ya activo no vuelve a pedir', (
    tester,
  ) async {
    var llamadas = 0;
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async {
              llamadas++;
              return [fixedItem];
            },
        counts: (_) async => {'ferreteria': 1},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ferretería').first);
    await tester.pumpAndSettle();
    expect(llamadas, 2);
    await tester.tap(find.text('Ferretería').first);
    await tester.pumpAndSettle();
    expect(llamadas, 2);
  });

  testWidgets('tocar el segmento de kind ya activo no vuelve a pedir', (
    tester,
  ) async {
    var llamadas = 0;
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              required kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
            }) async {
              llamadas++;
              return [fixedItem];
            },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Producto'));
    await tester.pumpAndSettle();
    expect(llamadas, 1);
  });
}
