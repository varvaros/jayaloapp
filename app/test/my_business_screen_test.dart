import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessReview, BusinessRating;
import 'package:jayalo_app/features/provider/my_business_screen.dart';

/// "Mi tienda" (spec 2026-07-20): Mi negocio es el escaparate de solo lectura —
/// detalles + productos + servicios + opiniones. Sin edición (V2/web).
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );


  /// La portada editorial (2026-08-01) es MUCHO más alta que la cabecera de
  /// tarjeta que sustituyó, así que en el viewport de 800x600 de los tests las
  /// secciones de abajo ya no nacen construidas. Se baja como bajaría alguien.
  ///
  /// Por clave (2026-08-09, tercera vuelta): `find.byType(ListView)` dejó de
  /// bastar desde que PAQUETES y TRABAJOS montan su propio `ListView`
  /// horizontal (carril de tarjetas compactas) — sin la clave, `tester.drag`
  /// revienta con "too many elements" en cuanto esas secciones tienen
  /// contenido.
  Future<void> bajar(WidgetTester tester) async {
    await tester.drag(
        find.byKey(const Key('mi-negocio-scroll')), const Offset(0, -600));
    await tester.pumpAndSettle();
  }

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
    seals: ['Negocio verificado'],
    services: <String>[],
    raw: {
      'is_wholesale': true,
      'experience_years': 12,
      'service_area': 'ambos',
      'warranty': '6 meses',
    },
  );

  final unProducto = [
    {'id': 'p1', 'name': 'Taladro', 'price': 2500, 'kind': 'producto'}
  ];
  final unServicio = [
    {'id': 's1', 'name': 'Instalación', 'price': 800, 'kind': 'servicio'}
  ];
  final unaResena = <BusinessReview>[
    (rating: 5.0, comment: 'Muy bueno', createdAt: DateTime(2026, 7, 1))
  ];

  Widget view({
    List<Map<String, dynamic>> productos = const [],
    List<Map<String, dynamic>> servicios = const [],
    List<BusinessReview> reviews = const [],
    BusinessRating? rating,
  }) =>
      host(MyBusinessView(
        business: negocio,
        productos: productos,
        servicios: servicios,
        reviews: reviews,
        rating: rating,
      ));

  // Rediseño 2026-08-01 (pedido PO: la tienda de la app no tenía el diseño
  // coordinado con la web). La cabecera de tarjeta y los tres chips dejan
  // paso a la portada editorial + la ficha de detalles completa.
  testWidgets('la portada trae nombre, categoría, ciudad y sellos',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('Ferretería Pérez'), findsOneWidget);
    expect(find.text('Negocio verificado'), findsOneWidget);
    // Categoría y ciudad ya no son dos chips sueltos: van en una línea.
    expect(find.textContaining('Santiago'), findsOneWidget);
  });

  testWidgets('la ficha de detalles enseña lo que la web, no tres chips',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('DETALLES DEL PROVEEDOR'), findsOneWidget);
    expect(find.text('12 años'), findsOneWidget);
    expect(find.text('En taller y a domicilio'), findsOneWidget);
    expect(find.text('6 meses'), findsOneWidget);
    // "Mayorista" pasa a ser una fila con etiqueta, no un chip suelto.
    expect(find.text('Al por mayor'), findsOneWidget);
    expect(find.text('Mayorista'), findsNothing);
  });

  testWidgets('lista productos y servicios', (tester) async {
    await tester
        .pumpWidget(view(productos: unProducto, servicios: unServicio));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text('PRODUCTOS'), findsOneWidget);
    expect(find.text('SERVICIOS'), findsOneWidget);
    expect(find.text('Taladro'), findsOneWidget);
    expect(find.text('Instalación'), findsOneWidget);
  });

  // Task 6 (2026-08-09): tocar una tarjeta PROPIA abre el editor; mantener
  // presionada la borra tras confirmar. Sin los callbacks, las tarjetas
  // siguen navegando como el catálogo público (cubierto por que el resto de
  // los tests de este archivo, sin `onEditItem`/`onDeleteItem`, no revientan
  // al no montar un GoRouter).
  testWidgets('tocar una tarjeta propia llama a onEditItem con la fila',
      (tester) async {
    Map<String, dynamic>? edited;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: unProducto,
      servicios: const [],
      reviews: const [],
      rating: null,
      onEditItem: (item) async => edited = item,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);

    await tester.tap(find.text('Taladro'));
    await tester.pumpAndSettle();

    expect(edited, unProducto.first);
  });

  testWidgets(
      'mantener presionada una tarjeta propia pide confirmar antes de '
      'llamar a onDeleteItem', (tester) async {
    String? deletedId;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: unProducto,
      servicios: const [],
      reviews: const [],
      rating: null,
      onDeleteItem: (item) async => deletedId = item['id'] as String?,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);

    await tester.longPress(find.text('Taladro'));
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar de tu tienda?'), findsOneWidget);
    expect(deletedId, isNull); // aún no confirmó

    // Borrado PERMANENTE: 'Eliminar', no 'Quitar' (hallazgo COPY, revisión
    // final — unificado con paquetes/trabajos, que ya usaban 'Eliminar').
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(deletedId, 'p1');
  });

  testWidgets(
      'mantener presionada y CANCELAR no llama a onDeleteItem',
      (tester) async {
    var called = false;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: unProducto,
      servicios: const [],
      reviews: const [],
      rating: null,
      onDeleteItem: (item) async => called = true,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);

    await tester.longPress(find.text('Taladro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });

  testWidgets('secciones vacías muestran aviso, no CTA de crear',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    // Task 4 (2026-08-09) sumó la sección "Sobre el negocio" bajo la
    // portada: PRODUCTOS/SERVICIOS ya no nacen construidos en el viewport
    // de 800x600 de los tests, mismo motivo que `bajar()` arriba.
    await bajar(tester);
    expect(find.textContaining('Aún no tienes productos'), findsOneWidget);
    expect(find.textContaining('Aún no tienes servicios'), findsOneWidget);
    // Nunca ofrece crear (eso es V2/web).
    expect(find.textContaining('Crear'), findsNothing);
  });

  testWidgets('opiniones: promedio, conteo y texto de la reseña',
      (tester) async {
    await tester.pumpWidget(
        view(reviews: unaResena, rating: (avg: 4.8, count: 12)));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text('OPINIONES'), findsOneWidget);
    expect(find.textContaining('4.8'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('Muy bueno'), findsOneWidget);
  });

  testWidgets('sin opiniones muestra aviso', (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.textContaining('Aún no tienes opiniones'), findsOneWidget);
  });

  testWidgets('sin negocio muestra un aviso en vez de reventar',
      (tester) async {
    await tester.pumpWidget(host(const MyBusinessView(
        business: null,
        productos: [],
        servicios: [],
        reviews: [],
        rating: null)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No encontramos tu negocio'), findsOneWidget);
  });

  testWidgets('«Editar en la web» ya no existe (pedido PO 2026-08-10)',
      (tester) async {
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      reviews: const [],
      rating: null,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text('Editar en la web'), findsNothing);
  });

  // El agregador (PO 2026-08-05): tarjeta vacía con ＋ que abre el chooser.
  // Rompe a propósito el "sin CTA de crear" del spec 2026-07-20 — pero SOLO
  // cuando el dueño puede crear (onAddItem cableado); sin callback, la vista
  // sigue siendo la de solo lectura de siempre (los tests de arriba lo cubren).
  const labelAgregador =
      'Haz ofertas más rápidas con tus productos en tus tiendas';

  testWidgets('el agregador abre el chooser y devuelve el kind elegido',
      (tester) async {
    String? chosen;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      reviews: const [],
      rating: null,
      onAddItem: (kind) async => chosen = kind,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text(labelAgregador), findsOneWidget);

    await tester.tap(find.text(labelAgregador));
    await tester.pumpAndSettle();
    expect(find.text('Producto'), findsOneWidget);
    expect(find.text('Servicio'), findsOneWidget);
    expect(find.text('Trabajo realizado'), findsOneWidget);

    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();
    expect(chosen, 'servicio');
  });

  testWidgets('sin onAddItem la tarjeta del agregador no existe',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text(labelAgregador), findsNothing);
  });

  // Hallazgo I-2 (revisión final): «+ Añadir …» al final de CADA sección de
  // catálogo con contenido, y «+» con etiqueta en las vacías — antes solo
  // Paquetes lo tenía. Cablea al `onAddItem` del kind correcto (mismo
  // callback del agregador, sin pasar por el chooser: el kind ya se sabe).
  group('«+ Añadir …» por sección (I-2, revisión final)', () {
    testWidgets(
        'PRODUCTOS vacío con onAddItem: «+ Añadir producto» reemplaza el '
        'aviso y llama a onAddItem con kind producto', (tester) async {
      String? chosen;
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        onAddItem: (kind) async => chosen = kind,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      expect(find.text('Añadir producto'), findsOneWidget);
      // La fila «+» sustituye el aviso de texto cuando hay alta disponible.
      expect(find.textContaining('Aún no tienes productos'), findsNothing);

      await tester.tap(find.text('Añadir producto'));
      await tester.pump();
      expect(chosen, 'producto');
    });

    testWidgets(
        'PRODUCTOS con contenido y onAddItem: la fila «+ Añadir producto» '
        'sigue disponible al final', (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: unProducto,
        servicios: const [],
        reviews: const [],
        rating: null,
        onAddItem: (kind) async {},
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      expect(find.text('Taladro'), findsOneWidget);
      expect(find.text('Añadir producto'), findsOneWidget);
    });

    testWidgets(
        'SERVICIOS vacío con onAddItem: «+ Añadir servicio» llama a '
        'onAddItem con kind servicio', (tester) async {
      String? chosen;
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        onAddItem: (kind) async => chosen = kind,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      expect(find.text('Añadir servicio'), findsOneWidget);
      expect(find.textContaining('Aún no tienes servicios'), findsNothing);

      await tester.tap(find.text('Añadir servicio'));
      await tester.pump();
      expect(chosen, 'servicio');
    });

    testWidgets(
        'sin onAddItem, PRODUCTOS/SERVICIOS vacíos siguen mostrando el '
        'aviso de texto (sin fila «+»)', (tester) async {
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      await bajar(tester);

      expect(find.textContaining('Aún no tienes productos'), findsOneWidget);
      expect(find.textContaining('Aún no tienes servicios'), findsOneWidget);
      expect(find.text('Añadir producto'), findsNothing);
      expect(find.text('Añadir servicio'), findsNothing);
    });
  });

  testWidgets('TRABAJOS lista el portafolio o avisa que está vacío',
      (tester) async {
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      trabajos: const [
        {'id': 't1', 'title': 'Instalación de verja', 'image_urls': <String>[]}
      ],
      reviews: const [],
      rating: null,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(find.text('TRABAJOS'), findsOneWidget);
    expect(find.text('Instalación de verja'), findsOneWidget);

    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    await bajar(tester);
    expect(
        find.textContaining('Aún no tienes trabajos'), findsOneWidget);
  });

  // Pedido PO 2026-08-09 (TERCERA vuelta, tras mostrar un ejemplo — grid de
  // tarjetas tipo "match" de una app de citas — y pedir «los paquetes y
  // trabajos deben hacer scroll HORIZONTAL, que la foto sea más pequeña»):
  // la sección TRABAJOS es un carril con `scrollDirection: Axis.horizontal`
  // y la tarjeta de un trabajo sigue con la foto ARRIBA a todo el ancho DE
  // LA TARJETA (`width: double.infinity`), pero con la tarjeta angosta y la
  // foto más chica que la iteración anterior (168 → 120).
  //
  // Video en portafolio (2026-08-20): la tarjeta pasó de una foto fija a un
  // mini-carrusel (`PageView`) — la imagen ya no cuelga directo del
  // `ClipRRect`, cuelga de la página del `PageView`. El finder busca la
  // `Image` DENTRO del `PageView` a propósito, para seguir comprobando lo
  // mismo que antes (la foto pinta a todo el ancho de la tarjeta) en la
  // estructura nueva, no un `Image` cualquiera de la pantalla.
  testWidgets(
      'TRABAJOS es un carril horizontal y la tarjeta pinta la foto arriba, '
      'a todo el ancho de la tarjeta', (tester) async {
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      trabajos: const [
        {
          'id': 't1',
          'title': 'Instalación de verja',
          'image_urls': ['https://x/verja.jpg'],
        }
      ],
      reviews: const [],
      rating: null,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);
    await tester.drag(
        find.byKey(const Key('mi-negocio-scroll')), const Offset(0, -600));
    await tester.pumpAndSettle();

    // El carril de TRABAJOS es un `ListView` horizontal (el otro `ListView`
    // en pantalla es el vertical de toda la vista, con la clave de arriba).
    final carril = tester.widgetList<ListView>(find.byType(ListView)).firstWhere(
        (lv) => lv.scrollDirection == Axis.horizontal);
    expect(carril.scrollDirection, Axis.horizontal);

    final img = tester.widget<Image>(find
        .descendant(of: find.byType(PageView), matching: find.byType(Image))
        .first);
    expect(img.width, double.infinity);
    expect(img.height, 120);
  });

  testWidgets('TRABAJOS: un trabajo con 2 archivos pinta los puntos del carrusel',
      (t) async {
    // Monta la vista con un item cuyo `media` trae 2 elementos y comprueba que
    // hay un PageView y exactamente 2 puntos.
    await t.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      trabajos: const [
        {
          'id': 't1',
          'title': 'Instalación de verja',
          'image_urls': <String>[],
          'media': [
            {'url': 'https://x/verja.jpg', 'kind': 'image'},
            {
              'url': 'https://x/verja.mp4',
              'kind': 'video',
              'poster': 'https://x/verja-poster.jpg',
            },
          ],
        }
      ],
      reviews: const [],
      rating: null,
    )));
    await t.pumpAndSettle();
    await t.drag(
        find.byKey(const Key('mi-negocio-scroll')), const Offset(0, -600));
    await t.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);

    // Los puntos del carrusel son `Container` de 6px de alto con
    // `BoxDecoration` redondeada — combinación que en esta pantalla solo
    // pinta la fila de puntos (nada más en TRABAJOS/PAQUETES mide 6 de alto
    // con decoración). Se cuentan así en vez de por `Key` porque el punto no
    // lleva una — es puramente decorativo.
    final puntos = t.widgetList<Container>(find.byType(Container)).where((c) =>
        c.decoration is BoxDecoration &&
        (c.decoration as BoxDecoration).borderRadius != null &&
        c.constraints?.maxHeight == 6);
    expect(puntos.length, 2);
  });

  testWidgets(
      'TRABAJOS vacío con onAddItem: «+ Añadir trabajo» llama a onAddItem '
      'con kind trabajo (I-2, revisión final)', (tester) async {
    String? chosen;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      trabajos: const [],
      reviews: const [],
      rating: null,
      onAddItem: (kind) async => chosen = kind,
    )));
    await tester.pumpAndSettle();
    await bajar(tester);
    await tester.drag(
        find.byKey(const Key('mi-negocio-scroll')), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Añadir trabajo'), findsOneWidget);
    expect(find.textContaining('Aún no tienes trabajos'), findsNothing);

    await tester.tap(find.text('Añadir trabajo'));
    await tester.pump();
    expect(chosen, 'trabajo');
  });
}
