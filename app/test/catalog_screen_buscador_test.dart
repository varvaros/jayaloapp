import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/buscador_catalogo.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/catalog_articulos.dart'
    show Proveedor;
import 'package:jayalo_app/features/client/catalog_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// El buscador del catálogo pasa por `buscar_catalogo` (la RPC pública que ya
/// usa `/buscar` en la web), no por el `like('search_norm', …)` de antes.
/// Aquí se dobla la RPC entera: ningún test toca la red.
Future<Map<String, BusinessCardInfo>> sinNegocios(List<String> ids) async =>
    const {};
Future<Map<String, int>?> sinConteos() async => null;
Future<List<Proveedor>> sinNombres(String term) async => const [];

Future<List<Map<String, dynamic>>> sinItems({
  String? kind,
  String? search,
  String? categoryId,
  String? rubro,
  bool wholesale = false,
  bool conPaquetes = true,
}) async => const [];

Map<String, dynamic> _item(String id, String name) => {
  'id': id,
  'user_id': 'u1',
  'business_id': 'b1',
  'name': name,
  'description': '',
  'price': 1500,
  'price_min': null,
  'price_max': null,
  'image_urls': <String>[],
  'category_id': 'ferreteria',
  'rubro': 'Cables y conectores',
  'kind': 'producto',
  'condition': 'nuevo',
};

Proveedor _prov(String id, String name) => (
  id: id,
  name: name,
  logoUrl: null,
  hasPhysicalLocation: true,
  city: 'Santiago',
  verificado: false,
  queHace: 'Ferretería',
);

BusquedaCatalogo _busqueda({
  String termino = 'cable',
  String? corregidoA,
  List<RubroSugerido> rubros = const [],
  List<Map<String, dynamic>> items = const [],
  List<Proveedor> directos = const [],
  List<Proveedor> probables = const [],
}) => (
  termino: termino,
  corregidoA: corregidoA,
  motivo: null,
  rubros: rubros,
  items: items,
  total: items.length,
  negocios: const {},
  directos: directos,
  probables: probables,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    await onboardingStore.markDone('client.catalog.v1');
  });

  /// El device del PO mide 388 dp de ancho (no los 800 del viewport por
  /// defecto de flutter_test): las tiras de chips se miden ahí.
  void viewportDelPO(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(388, 1400);
    tester.view.devicePixelRatio = 1;
  }

  Widget catalogo({
    CatalogFetch fetch = sinItems,
    required CatalogBuscar buscar,
  }) => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: CatalogView(
      fetch: fetch,
      buscar: buscar,
      businesses: sinNegocios,
      counts: sinConteos,
      names: sinNombres,
      actions: const [],
    ),
  );

  /// Escribe [termino] en el buscador y lo envía.
  Future<void> buscarEn(WidgetTester tester, String termino) async {
    await tester.enterText(find.byType(TextField).first, termino);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('al buscar, los artículos salen de la RPC y no del LIKE', (
    tester,
  ) async {
    viewportDelPO(tester);
    var pedidoAlLike = 0;
    var terminoPedido = '';
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
              if (search != null) pedidoAlLike++;
              return const [];
            },
        buscar: (termino, {kind, ciudad, exacto = false}) async {
          terminoPedido = termino;
          return _busqueda(items: [_item('p1', 'Cable USB de 2 metros')]);
        },
      ),
    );
    await tester.pumpAndSettle();
    await buscarEn(tester, 'cable');

    expect(terminoPedido, 'cable');
    expect(
      pedidoAlLike,
      0,
      reason: 'con término, el LIKE viejo ya no se consulta',
    );
    expect(find.text('Cable USB de 2 metros'), findsOneWidget);
  });

  testWidgets('sin búsqueda, el catálogo sigue saliendo del LIKE de siempre', (
    tester,
  ) async {
    viewportDelPO(tester);
    var pedidoALaRpc = 0;
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
            }) async => [_item('p9', 'Taladro inalámbrico')],
        buscar: (termino, {kind, ciudad, exacto = false}) async {
          pedidoALaRpc++;
          return _busqueda();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(pedidoALaRpc, 0);
  });

  testWidgets('los rubros entendidos salen como chips', (tester) async {
    viewportDelPO(tester);
    await tester.pumpWidget(
      catalogo(
        buscar: (termino, {kind, ciudad, exacto = false}) async => _busqueda(
          rubros: const [
            (
              id: 'r9',
              name: 'Cables y conectores',
              categoryId: 'ferreteria',
              kind: 'producto',
            ),
          ],
          items: [_item('p1', 'Cable USB')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await buscarEn(tester, 'cable');
    expect(find.text('Cables y conectores'), findsOneWidget);
  });

  testWidgets('cuando el servidor corrige el tecleo lo dice con su literal', (
    tester,
  ) async {
    viewportDelPO(tester);
    await tester.pumpWidget(
      catalogo(
        buscar: (termino, {kind, ciudad, exacto = false}) async => _busqueda(
          termino: 'libreta',
          corregidoA: 'libretas',
          items: [_item('p1', 'Libreta rayada')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await buscarEn(tester, 'libreta');
    // Literal de la web (`composer.ts`, `lineaResultadosPara`), no inventada.
    expect(find.text('Resultados para «libretas»'), findsOneWidget);
  });

  testWidgets('directos y probables van en bloques distintos', (tester) async {
    viewportDelPO(tester);
    await tester.pumpWidget(
      catalogo(
        buscar: (termino, {kind, ciudad, exacto = false}) async => _busqueda(
          items: [_item('p1', 'Cable USB')],
          directos: [_prov('b1', 'Ferretería Don Pepe')],
          probables: [_prov('b3', 'Casa Cable')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await buscarEn(tester, 'cable');
    expect(find.text('Proveedores que coinciden:'), findsOneWidget);
    expect(find.text('Ferretería Don Pepe'), findsOneWidget);
    // Literal de la web (`BloqueNegocios`): los probables NO son directos.
    expect(find.text('Podrían tenerlo:'), findsOneWidget);
    expect(find.text('Casa Cable'), findsOneWidget);
  });
}
