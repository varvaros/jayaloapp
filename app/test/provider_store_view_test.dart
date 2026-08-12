import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/features/client/provider_store_screen.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// Tienda pública del cliente (pedido PO 2026-08-09): "Debería verse como
/// una sola página, con todo, y los paquetes y trabajos con scroll
/// horizontal, con todo lo que se ha hecho del lado del proveedor, pero debe
/// verse del lado del cliente" — se quitaron las pestañas
/// (`HeaderSegmented`/`_Section`) y ahora TODAS las secciones se pintan de
/// una en el mismo scroll.
///
/// `ProviderStoreView` es la parte pura (sin fetch) de la pantalla, igual
/// patrón que `MyBusinessView`/`MyBusinessScreen` — se prueba con datos ya
/// en mano, sin red.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  // La vista es un `CustomScrollView` largo (portada + chips + confianza +
  // ficha + hasta 4 secciones) — con el viewport de prueba por defecto
  // (800×600) las secciones de más abajo ni se montan (los `SliverList
  // .builder`/`ListView.builder` son perezosos, igual motivo que
  // `setTallPhoneSize` en `packages_section_test.dart`/`portfolio_edit_test
  // .dart`).
  void setTallPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const identity = (
    name: 'Ferretería Pérez',
    logoUrl: null,
    coverUrl: null,
    services: <String>[],
    raw: <String, dynamic>{'category_id': 'ferreteria', 'city': 'Santiago'},
  );

  final productos = [
    {
      'id': 'p1',
      'name': 'Martillo',
      'kind': 'producto',
      'image_urls': <String>[],
    },
  ];
  final servicios = [
    {
      'id': 's1',
      'name': 'Reparación de techos',
      'kind': 'servicio',
      'image_urls': <String>[],
    },
  ];
  final paquetes = [
    {
      'id': 'pk1',
      'name': 'Plan Básico',
      'price': 1500,
      'items': <String>[],
    },
  ];
  final trabajos = [
    {
      'id': 't1',
      'title': 'Instalación de verja',
      'image_urls': <String>[],
    },
  ];

  group('ProviderStoreView — una sola página, sin pestañas (PO 2026-08-09)', () {
    testWidgets('(a) sin HeaderSegmented y las 4 secciones se pintan a la vez',
        (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: null,
        hasPhysicalLocation: false,
        productos: productos,
        servicios: servicios,
        paquetes: paquetes,
        trabajos: trabajos,
      )));
      await tester.pumpAndSettle();

      // Nunca hay pestañas: la pantalla vieja montaba un `HeaderSegmented`
      // con Productos/Servicios/Trabajos.
      expect(find.byType(HeaderSegmented), findsNothing);

      // Las 4 secciones y su contenido conviven en el mismo árbol (con
      // scroll, no detrás de una pestaña que hay que cambiar).
      expect(find.text('PRODUCTOS'), findsOneWidget);
      expect(find.text('Martillo'), findsOneWidget);
      expect(find.text('SERVICIOS'), findsOneWidget);
      expect(find.text('Reparación de techos'), findsOneWidget);
      expect(find.text('PAQUETES'), findsOneWidget);
      expect(find.text('Plan Básico'), findsOneWidget);
      expect(find.text('TRABAJOS'), findsOneWidget);
      expect(find.text('Instalación de verja'), findsOneWidget);
    });

    testWidgets(
        '(b) los carriles de PAQUETES/TRABAJOS son horizontales, sin «+ '
        'Añadir…» y mantener presionado no dispara nada', (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: null,
        hasPhysicalLocation: false,
        productos: const [],
        servicios: const [],
        paquetes: paquetes,
        trabajos: trabajos,
      )));
      await tester.pumpAndSettle();

      // Dos `ListView` horizontales (paquetes + trabajos) — ninguno vertical
      // en este árbol porque el resto de la vista es un `CustomScrollView`
      // con slivers, no un `ListView`.
      final horizontales = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((lv) => lv.scrollDirection == Axis.horizontal);
      expect(horizontales.length, 2);

      // Solo lectura: la tienda pública no ofrece alta ni edición.
      expect(find.text('Añadir paquete'), findsNothing);
      expect(find.text('Añadir trabajo'), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);

      // Mantener presionado un tile no revienta ni ofrece borrar (no hay
      // `onLongPress` cableado en la tienda pública — sin editar ni borrar).
      // `onTap` SÍ está cableado desde el 2026-08-09 (ver los dos grupos de
      // abajo: "PAQUETES: tocar abre..." / "TRABAJOS: tocar abre...").
      await tester.longPress(find.text('Instalación de verja'));
      await tester.pumpAndSettle();

      expect(find.text('Plan Básico'), findsOneWidget);
      expect(find.text('¿Eliminar este paquete?'), findsNothing);
      expect(find.text('¿Eliminar este trabajo?'), findsNothing);
    });

    testWidgets(
        '(c) una sección vacía no pinta ni encabezado ni aviso de "aún no '
        'publica…"', (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: null,
        hasPhysicalLocation: false,
        productos: productos,
        servicios: servicios,
        paquetes: const [],
        trabajos: const [],
      )));
      await tester.pumpAndSettle();

      expect(find.text('PRODUCTOS'), findsOneWidget);
      expect(find.text('SERVICIOS'), findsOneWidget);
      // Ni encabezado ni mensaje de vacío para las secciones sin contenido.
      expect(find.text('PAQUETES'), findsNothing);
      expect(find.text('TRABAJOS'), findsNothing);
      expect(find.textContaining('aún no'), findsNothing);
    });

    testWidgets(
        '(c) las 4 secciones vacías: un único aviso, no cuatro', (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: null,
        hasPhysicalLocation: false,
        productos: const [],
        servicios: const [],
        paquetes: const [],
        trabajos: const [],
      )));
      await tester.pumpAndSettle();

      expect(find.text('PRODUCTOS'), findsNothing);
      expect(find.text('SERVICIOS'), findsNothing);
      expect(find.text('PAQUETES'), findsNothing);
      expect(find.text('TRABAJOS'), findsNothing);
      expect(find.text('Este proveedor aún no publica nada en su tienda.'),
          findsOneWidget);
    });
  });

  group('ProviderStoreView — bloque de confianza (paridad previa)', () {
    testWidgets('con stats, la tarjeta de confianza se pinta', (tester) async {
      setTallPhoneSize(tester);
      const BusinessStorefrontStats stats = (
        avgRating: 4.5,
        reviewsCount: 12,
        completedJobs: 30,
        medianResponseMinutes: 45,
        memberSinceYear: 2022,
        identityVerified: true,
        businessVerified: false,
        whatsappVerified: false,
      );
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: stats,
        hasPhysicalLocation: false,
        productos: const [],
        servicios: const [],
        paquetes: const [],
        trabajos: const [],
      )));
      await tester.pumpAndSettle();

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      // Aparece dos veces a propósito (paridad previa, sin cambios de esta
      // tarea): una vez como sello de la portada (`BusinessCoverHero`) y otra
      // en la fila de insignias de la tarjeta de confianza.
      expect(find.text('Identidad verificada'), findsNWidgets(2));
    });
  });

  // Sello "Tienda física" (PO 2026-08-12) — AUTODECLARADO: el proveedor lo
  // dice, Jayalo no lo comprueba. Debe pintarse en teal, nunca en el verde
  // de `Icons.verified`/verificación, y debe ser independiente de `stats`
  // (si la RPC de confianza falla, el sello igual se ve).
  group('ProviderStoreView — sello "Tienda física" (autodeclarado)', () {
    testWidgets('con hasPhysicalLocation, se pinta aunque stats sea null',
        (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: null,
        hasPhysicalLocation: true,
        productos: const [],
        servicios: const [],
        paquetes: const [],
        trabajos: const [],
      )));
      await tester.pumpAndSettle();

      // No se comprueba `Icons.storefront_outlined` aquí: sin logo, el
      // avatar por defecto de `BusinessCoverHero` usa el MISMO ícono, así
      // que habría dos en pantalla — el texto de la píldora ya identifica
      // sin ambigüedad que el sello se pintó.
      expect(find.text('Tienda física'), findsOneWidget);
    });

    testWidgets('sin hasPhysicalLocation, no aparece el sello',
        (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: null,
        hasPhysicalLocation: false,
        productos: const [],
        servicios: const [],
        paquetes: const [],
        trabajos: const [],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Tienda física'), findsNothing);
    });
  });

  // Pedido PO 2026-08-09: "El paquete no abre nada" / "Trabajos no abre" —
  // las tarjetas de PAQUETES/TRABAJOS ahora sí tienen `onTap` cableado.
  group('PAQUETES: tocar abre el detalle del paquete', () {
    testWidgets('navega a /package/:id (mismo patrón que ProductListCard)',
        (tester) async {
      setTallPhoneSize(tester);
      final router = GoRouter(
        initialLocation: '/store',
        routes: [
          GoRoute(
            path: '/store',
            builder: (_, _) => ProviderStoreView(
              identity: identity,
              stats: null,
              hasPhysicalLocation: false,
              productos: const [],
              servicios: const [],
              paquetes: paquetes,
              trabajos: const [],
            ),
          ),
          GoRoute(
            path: '/package/:id',
            builder: (_, s) =>
                Scaffold(body: Text('PKG:${s.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(
        theme: jayaloTheme(Brightness.light),
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Plan Básico'));
      await tester.pumpAndSettle();

      expect(find.text('PKG:pk1'), findsOneWidget);
    });
  });

  group('TRABAJOS: tocar abre la galería modal', () {
    testWidgets('muestra las fotos, el título y no ofrece editar/borrar',
        (tester) async {
      setTallPhoneSize(tester);
      await tester.pumpWidget(host(ProviderStoreView(
        identity: identity,
        stats: null,
        hasPhysicalLocation: false,
        productos: const [],
        servicios: const [],
        paquetes: const [],
        trabajos: trabajos,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Instalación de verja'));
      await tester.pumpAndSettle();

      // La galería reusa el mismo título (dentro de su propio panel) — dos
      // apariciones: la tarjeta del carril, detrás, y el panel de la galería.
      expect(find.text('Instalación de verja'), findsNWidgets(2));
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Eliminar'), findsNothing);
    });
  });
}
