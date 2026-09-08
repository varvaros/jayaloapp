import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/catalog_articulos.dart'
    show Proveedor;
import 'package:jayalo_app/features/client/catalog_screen.dart';
import 'package:jayalo_app/features/client/catalog_secciones.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/star_score.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// Dobles de las consultas de negocios, conteos y nombres, usados como valor
/// por defecto de `catalogo()` — deben ser funciones de nivel superior: un
/// closure local no es una "constant expression" válida para un default de
/// parámetro nombrado.
Future<Map<String, BusinessCardInfo>> sinNegocios(List<String> ids) async =>
    const {};
Future<Map<String, int>?> sinConteos() async => null;
Future<List<Proveedor>> sinNombres(String term) async => const [];

const _negocioB1 = (
  name: 'Ferretería Don Pepe',
  logoUrl: null,
  whatsappVerified: false,
  identityVerified: false,
  businessVerified: false,
  hasPhysicalLocation: true,
  description: null,
  city: 'Santiago',
);

Future<Map<String, BusinessCardInfo>> conNegocio(List<String> ids) async =>
    const {'b1': _negocioB1};

/// `/catalog` (Task 7, catálogo POR ARTÍCULOS): sin toggle Producto/Servicio
/// en la cabecera — la tira de tipo (Todos · Productos · Servicios · Paquetes
/// · Proveedores) manda sobre los MISMOS ítems ya cargados, y sin filtro el
/// cuerpo son las secciones. `fetch`/`businesses`/`counts`/`names` se inyectan
/// (mismo patrón que `ProviderInboxView`) para probar el widget sin red.
void main() {
  // Estos tests son sobre el catálogo, no sobre onboarding. La guía welcome
  // `client.catalog.v1` monta un velo a pantalla completa que intercepta los
  // taps; marcarla como vista evita que el velo se coma los taps de estos
  // tests (mismo fix que `my_requests_others_test.dart`).
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    await onboardingStore.markDone('client.catalog.v1');
  });

  Widget host(Widget child) =>
      MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

  /// `fetch` que siempre devuelve [items], sin mirar los filtros.
  CatalogFetch fija(List<Map<String, dynamic>> items) =>
      ({
        kind,
        search,
        categoryId,
        rubro,
        wholesale = false,
        conPaquetes = true,
      }) async => items;

  Future<List<Map<String, dynamic>>> vacio({
    String? kind,
    String? search,
    String? categoryId,
    String? rubro,
    bool wholesale = false,
    bool conPaquetes = true,
  }) async => [];

  /// `CatalogView` con las consultas de red dobladas: los tests que solo miran
  /// artículos no deben tocar la red.
  Widget catalogo({
    required CatalogFetch fetch,
    CatalogBusinessesFetch businesses = sinNegocios,
    CatalogCountsFetch counts = sinConteos,
    CatalogNamesFetch names = sinNombres,
  }) => host(
    CatalogView(
      fetch: fetch,
      businesses: businesses,
      counts: counts,
      names: names,
      actions: const [],
    ),
  );

  /// Viewport ALTO (400×1600): las secciones apiladas no caben en los 600 de
  /// alto del viewport por defecto y `ListView` no construye lo que no ve.
  void viewportSecciones(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
  }

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

  final paqueteItem = {
    'id': 'k1',
    'user_id': 'u1',
    'business_id': 'b1',
    'name': 'Paquete de boda',
    'description': '',
    'price': 50000,
    'price_min': null,
    'price_max': null,
    'image_urls': <String>[],
    'category_id': '',
    'kind': 'paquete',
    'items': const ['Salón', 'Comida'],
  };

  /// Toca un chip de la tira de tipo (`Todos`/`Productos`/…): con viewports
  /// estrechos la tira se desplaza en horizontal, así que primero se revela.
  Future<void> tocarTipo(WidgetTester tester, String label) async {
    final chip = find.text(label).first;
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('la primera carga pide TODOS los kinds y con paquetes', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    Future<List<Map<String, dynamic>>> recorder({
      String? kind,
      String? search,
      String? categoryId,
      String? rubro,
      bool wholesale = false,
      bool conPaquetes = true,
    }) async {
      calls.add({
        'kind': kind,
        'wholesale': wholesale,
        'conPaquetes': conPaquetes,
      });
      return [];
    }

    await tester.pumpWidget(catalogo(fetch: recorder));
    await tester.pumpAndSettle();

    expect(calls, [
      {'kind': null, 'wholesale': false, 'conPaquetes': true},
    ]);
    expect(find.byType(HeaderSegmented), findsNothing);
  });

  testWidgets('la tarjeta muestra nombre y precio fijo', (tester) async {
    await tester.pumpWidget(catalogo(fetch: fija([fixedItem])));
    await tester.pumpAndSettle();
    await tocarTipo(tester, 'Productos');

    expect(find.text('Taladro inalámbrico'), findsOneWidget);
    expect(find.text('RD\$1,500'), findsOneWidget);
  });

  testWidgets(
    'la tarjeta muestra el rango de precio cuando no hay precio fijo',
    (tester) async {
      await tester.pumpWidget(catalogo(fetch: fija([rangeItem])));
      await tester.pumpAndSettle();
      await tocarTipo(tester, 'Servicios');

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
      await tester.pumpWidget(catalogo(fetch: fija([conAtributos])));
      await tester.pumpAndSettle();
      await tocarTipo(tester, 'Productos');

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
        String? kind,
        String? search,
        String? categoryId,
        String? rubro,
        bool wholesale = false,
        bool conPaquetes = true,
      }) async {
        attempts++;
        // El `await` real importa: sin él la excepción "completa" el Future
        // antes de que el próximo frame re-adjunte el listener del
        // FutureBuilder (el `setState` de `_refetch` no reconstruye
        // sincrónicamente), y el test framework lo reporta como no
        // manejado aunque la UI sí lo capture bien vía `snapshot.hasError`.
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
      String? kind,
      String? search,
      String? categoryId,
      String? rubro,
      bool wholesale = false,
      bool conPaquetes = true,
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
    'la búsqueda pide proveedores por nombre y los pinta sobre la rejilla',
    (tester) async {
      final pedidos = <String>[];
      await tester.pumpWidget(
        catalogo(
          fetch: fija([fixedItem]),
          names: (term) async {
            pedidos.add(term);
            return const [
              (
                id: 'b9',
                name: 'Ferretería Central',
                logoUrl: null,
                hasPhysicalLocation: false,
                city: null,
                verificado: false,
                queHace: '',
              ),
            ];
          },
        ),
      );
      await tester.pumpAndSettle();
      // Sin búsqueda NO se piden nombres (una consulta de más por carga).
      expect(pedidos, isEmpty);

      await tester.enterText(find.byType(TextField), 'ferre');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(pedidos, ['ferre']);
      expect(find.text('Proveedores que coinciden:'), findsOneWidget);
      expect(find.text('Ferretería Central'), findsOneWidget);
    },
  );

  testWidgets(
    'una búsqueda que solo coincide por nombre pinta los proveedores que '
    'coinciden, no el vacío',
    (tester) async {
      await tester.pumpWidget(
        catalogo(
          fetch: vacio,
          names: (term) async => const [
            (
              id: 'b9',
              name: 'Ferretería Central',
              logoUrl: null,
              hasPhysicalLocation: false,
              city: null,
              verificado: false,
              queHace: '',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ferreter');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Ferretería Central'), findsOneWidget);
      expect(
        find.text('No hay artículos que coincidan con tu filtro.'),
        findsNothing,
      );

      await tocarTipo(tester, 'Proveedores');
      expect(find.text('Ferretería Central'), findsOneWidget);
    },
  );

  testWidgets(
    'con mayoreo encendido, cambiar a Servicios mantiene visible el chip '
    'Al por mayor',
    (tester) async {
      await tester.pumpWidget(catalogo(fetch: fija([fixedItem, rangeItem])));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Al por mayor'));
      await tester.pumpAndSettle();

      await tocarTipo(tester, 'Servicios');

      expect(find.text('Al por mayor'), findsOneWidget);
    },
  );

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
      await tester.pumpWidget(catalogo(fetch: fija([longName, rangeItem])));
      await tester.pumpAndSettle();
      await tocarTipo(tester, 'Productos');

      expect(tester.takeException(), isNull);
    },
  );

  // El catálogo es también la pantalla "Otros proveedores" a la que el
  // proveedor llega APILADA desde el menú del avatar. Empujada debe ofrecer
  // una flecha de atrás; como pestaña del cliente (sin apilar) no la muestra.
  testWidgets('sin apilar: no hay flecha de atrás', (tester) async {
    await tester.pumpWidget(catalogo(fetch: vacio));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('apilada (canPop): muestra la flecha de atrás', (tester) async {
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
                    names: sinNombres,
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
  });

  testWidgets('la tarjeta muestra la reputación (★ + promedio + conteo)', (
    tester,
  ) async {
    final rated = {...fixedItem, 'avg_rating': 8.7, 'reviews_count': 34};
    await tester.pumpWidget(catalogo(fetch: fija([rated])));
    await tester.pumpAndSettle();
    await tocarTipo(tester, 'Productos');

    // La rejilla (mockup aprobado 2026-08-10) une promedio y conteo en un solo
    // texto compacto, que desde el 2026-08-17 lleva la escala: "8.7/10 (34)".
    expect(find.text('8.7/10 (34)'), findsOneWidget);
    // El widget, no el icono: cada estrella son dos iconos apilados.
    expect(find.byType(StarScore), findsOneWidget);
  });

  testWidgets(
    'el chip Al por mayor pide kind=producto sin paquetes y pasa a la rejilla',
    (tester) async {
      final visto = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
                conPaquetes = true,
              }) async {
                visto.add({
                  'kind': kind,
                  'wholesale': wholesale,
                  'conPaquetes': conPaquetes,
                });
                return [fixedItem];
              },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CatalogSecciones), findsOneWidget);

      await tester.tap(find.text('Al por mayor'));
      await tester.pumpAndSettle();

      expect(visto.last, {
        'kind': 'producto',
        'wholesale': true,
        'conPaquetes': false,
      });
      expect(find.byType(CatalogSecciones), findsNothing);
      expect(find.byType(SliverGrid), findsOneWidget);
    },
  );

  testWidgets('sin filtro se ven las secciones y no la rejilla', (
    tester,
  ) async {
    await tester.pumpWidget(catalogo(fetch: fija([fixedItem, rangeItem])));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogSecciones), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);
  });

  testWidgets(
    'con ítems de los tres tipos pinta las cuatro secciones en orden',
    (tester) async {
      viewportSecciones(tester);
      await tester.pumpWidget(
        catalogo(
          fetch: fija([
            fixedItem,
            {...rangeItem, 'business_id': 'b1'},
            paqueteItem,
          ]),
          businesses: conNegocio,
        ),
      );
      await tester.pumpAndSettle();

      final titulos = tester
          .widgetList<SeccionTitulo>(find.byType(SeccionTitulo))
          .map((w) => w.titulo)
          .toList();
      expect(titulos, ['Proveedores', 'Productos', 'Servicios', 'Paquetes']);
    },
  );

  testWidgets('«Ver todos» de Paquetes deja la rejilla de paquetes', (
    tester,
  ) async {
    viewportSecciones(tester);
    var llamadas = 0;
    await tester.pumpWidget(
      catalogo(
        fetch:
            ({
              kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
              conPaquetes = true,
            }) async {
              llamadas++;
              return [fixedItem, rangeItem, paqueteItem];
            },
      ),
    );
    await tester.pumpAndSettle();
    expect(llamadas, 1);

    final verTodosPaquetes = find.descendant(
      of: find.ancestor(
        of: find.text('Paquetes'),
        matching: find.byType(SeccionTitulo),
      ),
      matching: find.text('Ver todos'),
    );
    await tester.ensureVisible(verTodosPaquetes);
    await tester.pumpAndSettle();
    await tester.tap(verTodosPaquetes);
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.text('Paquete de boda'), findsOneWidget);
    expect(find.text('Taladro inalámbrico'), findsNothing);
    // Misma carga, otro cuerpo: cambiar de tipo NO vuelve a pedir.
    expect(llamadas, 1);
  });

  testWidgets('el tipo Proveedores muestra la lista de proveedores', (
    tester,
  ) async {
    await tester.pumpWidget(
      catalogo(fetch: fija([fixedItem]), businesses: conNegocio),
    );
    await tester.pumpAndSettle();
    await tocarTipo(tester, 'Proveedores');

    expect(find.byType(ProveedorCard), findsOneWidget);
    expect(find.text('Ferretería Don Pepe'), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);
  });

  testWidgets(
    '«Quitar filtro» del tipo vacío vuelve a Todos y a las secciones',
    (tester) async {
      await tester.pumpWidget(
        catalogo(fetch: fija([fixedItem]), businesses: conNegocio),
      );
      await tester.pumpAndSettle();
      // Sin paquetes cargados, el tipo Paquetes deja la pantalla vacía.
      await tocarTipo(tester, 'Paquetes');
      expect(
        find.textContaining('No hay artículos que coincidan'),
        findsOneWidget,
      );

      await tester.tap(find.text('Quitar filtro'));
      await tester.pumpAndSettle();

      expect(find.byType(CatalogSecciones), findsOneWidget);
    },
  );

  testWidgets('el tipo Proveedores vacío lleva su propio copy', (tester) async {
    await tester.pumpWidget(catalogo(fetch: fija([fixedItem])));
    await tester.pumpAndSettle();
    await tocarTipo(tester, 'Proveedores');

    expect(
      find.text('No hay proveedores que coincidan con tu filtro.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'tocar un chip de categoría vuelve a pedir con ella; «Todo» la quita',
    (tester) async {
      final cats = <String?>[];
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
                conPaquetes = true,
              }) async {
                cats.add(categoryId);
                return [fixedItem];
              },
          counts: () async => {'ferreteria': 1, 'hogar': 2},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ferretería').first);
      await tester.pumpAndSettle();
      expect(cats.last, 'ferreteria');

      await tester.tap(find.text('Todo'));
      await tester.pumpAndSettle();
      expect(cats.last, isNull);
      expect(find.byType(CatalogSecciones), findsOneWidget);
    },
  );

  testWidgets('la rejilla pinta la tienda del negocio resuelto', (
    tester,
  ) async {
    await tester.pumpWidget(
      catalogo(fetch: fija([fixedItem]), businesses: conNegocio),
    );
    await tester.pumpAndSettle();
    await tocarTipo(tester, 'Productos');

    expect(find.textContaining('Ferretería Don Pepe'), findsOneWidget);
    expect(find.textContaining('Tienda física'), findsOneWidget);
  });

  testWidgets('si la consulta de negocios falla, el catálogo se pinta igual', (
    tester,
  ) async {
    await tester.pumpWidget(
      catalogo(
        fetch: fija([fixedItem]),
        businesses: (ids) async {
          await Future<void>.delayed(Duration.zero);
          throw Exception('caído');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsNothing);
    expect(find.byType(CatalogSecciones), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '«Quitar filtro» del estado vacío limpia todo y vuelve a las secciones',
    (tester) async {
      var vez = 0;
      await tester.pumpWidget(
        catalogo(
          fetch:
              ({
                kind,
                search,
                categoryId,
                rubro,
                wholesale = false,
                conPaquetes = true,
              }) async {
                vez++;
                // Primera carga: hay artículos. Con mayoreo: nada.
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
      expect(find.byType(CatalogSecciones), findsOneWidget);
      expect(vez, 3);
    },
  );

  testWidgets(
    'la cabecera lleva el título a la izquierda y ya no el segmentado',
    (tester) async {
      await tester.pumpWidget(catalogo(fetch: vacio));
      await tester.pumpAndSettle();
      final header = tester.widget<VioletHeader>(find.byType(VioletHeader));
      expect(header.title, 'Catálogo');
      expect(header.titleAlign, HeaderTitleAlign.start);
      expect(find.byType(HeaderSegmented), findsNothing);
      expect(find.text('Producto'), findsNothing);
      expect(find.text('Servicio'), findsNothing);
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
              kind,
              search,
              categoryId,
              rubro,
              wholesale = false,
              conPaquetes = true,
            }) async {
              llamadas++;
              return [fixedItem];
            },
        counts: () async => {'ferreteria': 1},
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
}
