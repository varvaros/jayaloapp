import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/portfolio_media.dart'
    show PortfolioMedia, imagesOf;
import 'package:jayalo_app/features/provider/add_store_item_screen.dart';
import 'package:jayalo_app/features/provider/my_business_screen.dart';

/// Task 8: editar y borrar trabajos anteriores desde "Mi negocio". Dos
/// superficies:
/// - `AddStoreItemScreen` en modo `initial` para `kind: 'trabajo'` (antes de
///   esta tarea solo prellenaba producto/servicio, nunca trabajo — Task 6
///   Step 6 dejó ese camino sin recorrer a propósito).
/// - `MyBusinessView`: tocar/mantener presionado un `_PortfolioTile` propio.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  // Mismo ajuste que `store_item_editor_test.dart`: el editor es un
  // formulario largo y en el viewport 800x600 por defecto "Guardar" queda
  // fuera del cacheExtent del ListView.
  void setTallPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

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

  Future<void> noopUpdateItem(String id, Map<String, dynamic> payload) async {}

  Future<void> noopPortfolio({
    required String businessId,
    required String title,
    String? description,
    List<PortfolioMedia> media = const [],
  }) async {}

  Future<void> noopUpdatePortfolio(
    String id, {
    required String title,
    String? description,
    required List<PortfolioMedia> media,
  }) async {}

  Future<({String? categoryId, String? rubro})> fakeCatRubro(
    String businessId,
  ) async =>
      (categoryId: 'ferreteria', rubro: 'Herramientas');

  final trabajo = <String, dynamic>{
    'id': 't1',
    'title': 'Instalación de verja',
    'description': 'Verja de 10 metros en aluminio',
    'image_urls': <String>['https://img/1.jpg', 'https://img/2.jpg'],
  };

  group('AddStoreItemScreen — trabajo, modo edición (Task 8)', () {
    testWidgets('(a) prellena título, descripción y fotos conservadas desde '
        'initial', (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        initial: trabajo,
        saveProduct: noopSave,
        updateItem: noopUpdateItem,
        savePortfolio: noopPortfolio,
        updatePortfolio: noopUpdatePortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Editar trabajo'), findsOneWidget);
      expect(find.text('Instalación de verja'), findsOneWidget);
      expect(find.text('Verja de 10 metros en aluminio'), findsOneWidget);
      // Dos fotos conservadas → dos miniaturas, cada una con su botón de
      // quitar (`Icons.close`, no depende de que la red resuelva la imagen).
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('(b) rechaza la novena foto con "Máximo 8 fotos"',
        (tester) async {
      final ocho = <String, dynamic>{
        'id': 't2',
        'title': 'Trabajo con 8 fotos',
        'description': '',
        'image_urls': List.generate(8, (i) => 'https://img/$i.jpg'),
      };
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        initial: ocho,
        saveProduct: noopSave,
        updateItem: noopUpdateItem,
        savePortfolio: noopPortfolio,
        updatePortfolio: noopUpdatePortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      // Con 8 fotos ya conservadas los botones Cámara/Galería no deben ni
      // mostrarse (mismo criterio que producto/servicio con su propio tope).
      expect(find.text('Cámara'), findsNothing);
      expect(find.text('Galería'), findsNothing);
    });

    testWidgets('(c) guardar llama a updatePortfolio con id, título, '
        'descripción y URLs conservadas', (tester) async {
      String? updatedId;
      String? capturedTitle;
      String? capturedDesc;
      List<PortfolioMedia>? capturedMedia;
      Future<void> captureUpdate(
        String id, {
        required String title,
        String? description,
        required List<PortfolioMedia> media,
      }) async {
        updatedId = id;
        capturedTitle = title;
        capturedDesc = description;
        capturedMedia = media;
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        initial: trabajo,
        saveProduct: noopSave,
        updateItem: noopUpdateItem,
        savePortfolio: noopPortfolio,
        updatePortfolio: captureUpdate,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(updatedId, 't1');
      expect(capturedTitle, 'Instalación de verja');
      expect(capturedDesc, 'Verja de 10 metros en aluminio');
      expect(capturedMedia!.map((m) => m.url).toList(),
          ['https://img/1.jpg', 'https://img/2.jpg']);
      expect(capturedMedia!.every((m) => m.kind == 'image'), isTrue);
    });

    testWidgets('quitar una foto conservada y guardar la excluye del payload',
        (tester) async {
      List<PortfolioMedia>? capturedMedia;
      Future<void> captureUpdate(
        String id, {
        required String title,
        String? description,
        required List<PortfolioMedia> media,
      }) async {
        capturedMedia = media;
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        initial: trabajo,
        saveProduct: noopSave,
        updateItem: noopUpdateItem,
        savePortfolio: noopPortfolio,
        updatePortfolio: captureUpdate,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(capturedMedia!.map((m) => m.url).toList(), ['https://img/2.jpg']);
    });
  });

  group('AddStoreItemScreen — trabajo, video (Task 13)', () {
    final trabajoConVideo = <String, dynamic>{
      'id': 't3',
      'title': 'Trabajo con foto y video',
      'description': '',
      // Legado: `media` manda si viene lleno (ver `parseMedia`); se deja
      // `image_urls` también porque así llega la fila real de la BD.
      'image_urls': <String>['https://cdn/a.webp'],
      'media': <Map<String, dynamic>>[
        {'url': 'https://cdn/a.webp', 'kind': 'image', 'poster': null, 'duration': null},
        {
          'url': 'https://cdn/b.mp4',
          'kind': 'video',
          'poster': 'https://cdn/b.jpg',
          'duration': 30,
        },
      ],
    };

    final trabajoSoloVideo = <String, dynamic>{
      'id': 't4',
      'title': 'Trabajo solo video',
      'description': '',
      'image_urls': <String>[],
      'media': <Map<String, dynamic>>[
        {
          'url': 'https://cdn/only.mp4',
          'kind': 'video',
          'poster': 'https://cdn/only.jpg',
          'duration': 12,
        },
      ],
    };

    final trabajoDosVideos = <String, dynamic>{
      'id': 't5',
      'title': 'Trabajo con dos videos',
      'description': '',
      'image_urls': <String>[],
      'media': <Map<String, dynamic>>[
        {'url': 'https://cdn/v1.mp4', 'kind': 'video', 'poster': null, 'duration': 20},
        {'url': 'https://cdn/v2.mp4', 'kind': 'video', 'poster': null, 'duration': 25},
      ],
    };

    testWidgets('guardar escribe media completo e image_urls SOLO con las '
        'fotos', (tester) async {
      ({List<PortfolioMedia> media, List<String> imageUrls})? capturado;
      Future<void> captureUpdate(
        String id, {
        required String title,
        String? description,
        required List<PortfolioMedia> media,
      }) async {
        capturado = (media: media, imageUrls: imagesOf(media));
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        initial: trabajoConVideo,
        saveProduct: noopSave,
        updateItem: noopUpdateItem,
        savePortfolio: noopPortfolio,
        updatePortfolio: captureUpdate,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(capturado!.imageUrls, ['https://cdn/a.webp']); // el espejo, sin el mp4
      expect(capturado!.media.length, 2); // media sí los lleva los dos
    });

    testWidgets('un trabajo de SOLO video guarda image_urls vacio',
        (tester) async {
      ({List<PortfolioMedia> media, List<String> imageUrls})? capturado;
      Future<void> captureUpdate(
        String id, {
        required String title,
        String? description,
        required List<PortfolioMedia> media,
      }) async {
        capturado = (media: media, imageUrls: imagesOf(media));
      }

      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        initial: trabajoSoloVideo,
        saveProduct: noopSave,
        updateItem: noopUpdateItem,
        savePortfolio: noopPortfolio,
        updatePortfolio: captureUpdate,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(capturado!.imageUrls, isEmpty);
      expect(capturado!.media.single.kind, 'video');
    });

    testWidgets('rechaza el tercer video con "Máximo 2 videos"',
        (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(AddStoreItemScreen(
        kind: 'trabajo',
        businessId: 'biz-1',
        initial: trabajoDosVideos,
        saveProduct: noopSave,
        updateItem: noopUpdateItem,
        savePortfolio: noopPortfolio,
        updatePortfolio: noopUpdatePortfolio,
        fetchCatRubro: fakeCatRubro,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Agregar video'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Máximo 2 videos'), findsOneWidget);
    });
  });

  group('MyBusinessView — trabajos, editar y borrar (Task 8)', () {
    const negocio = (
      id: 'biz-1',
      name: 'Ferretería Pérez',
      logoUrl: null,
      coverUrl: null,
      verified: true,
      categoryId: 'ferreteria',
      city: 'Santiago',
      wholesale: true,
      description: 'Todo en herramientas',
      seals: <String>['Negocio verificado'],
      services: <String>[],
      raw: <String, dynamic>{
        'is_wholesale': true,
        'experience_years': 12,
        'service_area': 'ambos',
        'warranty': '6 meses',
      },
    );

    // Sin fotos a propósito: `_PortfolioTile` pinta la miniatura con
    // `Image.network` (sin `errorBuilder`) y en `flutter_test` toda petición
    // HTTP falla con 400 — con una URL real eso desborda el `Row` en un
    // frame y saca el tile fuera del viewport (bug preexistente de esa
    // miniatura, ajeno al cableado tap/long-press de esta tarea; ver
    // "Concerns" del reporte). El prellenado de fotos SÍ se prueba arriba,
    // en el editor (`JayaloNetworkImage`, que no tiene este problema).
    final trabajos = [
      <String, dynamic>{'id': 't1', 'title': 'Instalación de verja'}
    ];

    // Mismo motivo que `bajar()` en `my_business_screen_test.dart`: la
    // portada editorial empuja TRABAJOS fuera del viewport 800x600 por
    // defecto.
    //
    // Por clave (2026-08-09, tercera vuelta): `find.byType(ListView)` dejó
    // de bastar en cuanto TRABAJOS tiene contenido — el carril horizontal de
    // tarjetas compactas monta su propio `ListView`, y `tester.drag` exige
    // un único match.
    Future<void> bajar(WidgetTester tester) async {
      await tester.drag(
          find.byKey(const Key('mi-negocio-scroll')), const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    testWidgets('(a/d) tocar un trabajo propio llama a onEditTrabajo con la '
        'fila', (tester) async {
      Map<String, dynamic>? edited;
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        trabajos: trabajos,
        reviews: const [],
        rating: null,
        onEditTrabajo: (item) async => edited = item,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      await tester.tap(find.text('Instalación de verja'));
      await tester.pumpAndSettle();

      expect(edited, trabajos.first);
    });

    testWidgets(
        'sin onEditTrabajo, tocar un trabajo propio no revienta (sigue de '
        'solo lectura)', (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        trabajos: trabajos,
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      await tester.tap(find.text('Instalación de verja'));
      await tester.pumpAndSettle();
      // No hay excepción ni diálogo — nada que verificar salvo que sigue vivo.
      expect(find.text('Instalación de verja'), findsOneWidget);
    });

    testWidgets('(d) mantener presionado un trabajo propio pide confirmar '
        '("Eliminar") antes de llamar a onDeleteTrabajo', (tester) async {
      String? deletedId;
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        trabajos: trabajos,
        reviews: const [],
        rating: null,
        onDeleteTrabajo: (item) async => deletedId = item['id'] as String?,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      await tester.longPress(find.text('Instalación de verja'));
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar este trabajo?'), findsOneWidget);
      expect(deletedId, isNull); // aún no confirmó

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(deletedId, 't1');
    });

    testWidgets('mantener presionado y CANCELAR no llama a onDeleteTrabajo',
        (tester) async {
      var called = false;
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        trabajos: trabajos,
        reviews: const [],
        rating: null,
        onDeleteTrabajo: (item) async => called = true,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      await tester.longPress(find.text('Instalación de verja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });
  });
}
