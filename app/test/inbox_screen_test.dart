import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/inbox_screen.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// El toggle "Para ti / Todas" del inbox del proveedor. `fetch` se inyecta
/// (ver doc de [ProviderInboxView]) para poder probar el widget sin red.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  Future<List<Map<String, dynamic>>> vacio(
          {String? kind, required bool todas}) async =>
      [];

  testWidgets('arranca en "Para ti", no en "Todas": no persiste entre sesiones',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(fetch: vacio, leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Solicitudes para ti'), findsOneWidget);
    expect(find.text('Todas las solicitudes'), findsNothing);
    // El primer segmento del header (Para ti/Todas) arranca en índice 0.
    final toggle = tester
        .widgetList<HeaderSegmented>(find.byType(HeaderSegmented))
        .first;
    expect(toggle.index, 0);
  });

  testWidgets('el estado vacío de "Para ti" habla del rubro del proveedor',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(fetch: vacio, leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('coinciden con tu negocio'), findsOneWidget);
  });

  testWidgets(
      'tocar "Todas" cambia el título del AppBar y el mensaje del estado vacío',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(fetch: vacio, leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();

    // "Todas" aparece en 2 segmentos (el toggle Para ti/Todas y el filtro de
    // estado Todas/Abiertas/…); se apunta al primero, el toggle superior.
    await tester.tap(find.descendant(
        of: find.byType(HeaderSegmented).first, matching: find.text('Todas')));
    await tester.pumpAndSettle();

    expect(find.text('Todas las solicitudes'), findsOneWidget);
    expect(find.text('Solicitudes para ti'), findsNothing);
    expect(
        find.textContaining('Ahora mismo no hay solicitudes abiertas'),
        findsOneWidget);
  });

  testWidgets(
      '"Para ti" pide fetch con todas=false y "Todas" con todas=true',
      (tester) async {
    final calls = <bool>[];
    Future<List<Map<String, dynamic>>> recorder(
        {String? kind, required bool todas}) async {
      calls.add(todas);
      return [];
    }

    await tester.pumpWidget(host(ProviderInboxView(fetch: recorder, leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();
    expect(calls, [false]);

    // "Todas" aparece en 2 segmentos (el toggle Para ti/Todas y el filtro de
    // estado Todas/Abiertas/…); se apunta al primero, el toggle superior.
    await tester.tap(find.descendant(
        of: find.byType(HeaderSegmented).first, matching: find.text('Todas')));
    await tester.pumpAndSettle();
    expect(calls, [false, true]);
  });

  // ── Task 9: intereses de producto en el inbox + desbloqueo ────────────────

  Map<String, dynamic> interestRow({bool unlocked = false}) => {
        'id': 'int-1',
        'source': 'store',
        'title': 'Taladro inalámbrico',
        'description': 'Cantidad: 2\nCuándo quiere comprar: Esta semana',
        'image_url': '',
        'created_at': DateTime.now().toIso8601String(),
        'kind': 'producto',
        'product_id': 'prod-1',
        'unlocked': unlocked,
      };

  InboxFetch fetchOnly(Map<String, dynamic> row) =>
      ({String? kind, required bool todas}) async => todas ? [] : [row];

  testWidgets(
      'las filas source=="store" (bug corregido) se pintan como tarjeta de interés, no de solicitud',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: fetchOnly(interestRow()),
        leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Interesado en tu producto'), findsOneWidget);
    expect(find.text('Taladro inalámbrico'), findsOneWidget);
  });

  // Pedido PO 2026-08-01: la tarjeta de interés se comporta como las de
  // solicitud — se toca la tarjeta y se entra al detalle. NADA de botón en la
  // lista; el estado se comunica con un chip, igual que "Ya ofertaste" /
  // "Aceptada" / "Desbloqueado" en `_RequestCard`.

  testWidgets(
      'la tarjeta de interés bloqueada muestra el costo en un chip, no en un botón',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: fetchOnly(interestRow()),
        leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('1 crédito'), findsOneWidget);
    // El copy viejo del botón no debe sobrevivir en ninguna forma.
    expect(find.textContaining('Conversar'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
      'la tarjeta de interés desbloqueada NO ofrece "Abrir chat": hay que entrar',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: fetchOnly(interestRow(unlocked: true)),
        leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Desbloqueado'), findsOneWidget);
    expect(find.text('Abrir chat'), findsNothing);
    expect(find.textContaining('Conversar'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
      'tocar la tarjeta de interés navega al detalle y le pasa la fila cargada',
      (tester) async {
    // Sin botón en la tarjeta (T1), la ÚNICA vía al detalle es tocarla — y el
    // detalle ya no es una hoja, es una pantalla (T2). Si el push se rompiera,
    // el interés quedaría inalcanzable.
    Object? extraRecibido;
    final router = GoRouter(
      initialLocation: '/provider',
      routes: [
        GoRoute(
          path: '/provider',
          builder: (_, _) => ProviderInboxView(
              fetch: fetchOnly(interestRow()),
              leading: const SizedBox.shrink(),
              actions: const []),
        ),
        GoRoute(
          path: '/provider/interest/:id',
          builder: (_, s) {
            extraRecibido = s.extra;
            return Scaffold(
                body: Text('detalle ${s.pathParameters['id']}'));
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
        theme: jayaloTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Taladro inalámbrico'));
    await tester.pumpAndSettle();

    expect(find.text('detalle int-1'), findsOneWidget);
    // La fila viaja en `extra` para que el detalle pinte sin esperar a la red.
    expect((extraRecibido as Map?)?['title'], 'Taladro inalámbrico');
  });

  testWidgets(
      'una lista mixta pinta la solicitud y el interés con sus tarjetas propias',
      (tester) async {
    Future<List<Map<String, dynamic>>> mixed(
            {String? kind, required bool todas}) async =>
        todas
            ? []
            : [
                {
                  'id': 'req-1',
                  'source': 'marketplace',
                  'title': 'Necesito un plomero',
                  'description': 'Fuga de agua',
                  'kind': 'servicio',
                  'created_at': DateTime.now().toIso8601String(),
                },
                interestRow(),
              ];
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: mixed, leading: const SizedBox.shrink(), actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Necesito un plomero'), findsOneWidget);
    expect(find.text('Interesado en tu producto'), findsOneWidget);
    expect(find.text('1 crédito'), findsOneWidget);
  });

  testWidgets('la tarjeta pinta los símbolos de los requisitos del cliente',
      (tester) async {
    // Los requisitos salen de la oleada B, que en un test siempre falla
    // (`requirementsForRequests` toca `supa`) y `loadInboxData` se la traga por
    // diseño. Que los símbolos aparezcan igual es la prueba de que la tarjeta
    // cae a los de su propia fila.
    Future<List<Map<String, dynamic>>> conRequisitos(
            {String? kind, required bool todas}) async =>
        todas
            ? []
            : [
                {
                  'id': 'req-req',
                  'source': 'marketplace',
                  'title': 'Necesito 30 sillas',
                  'description': 'Para un salón',
                  'kind': 'producto',
                  'created_at': DateTime.now().toIso8601String(),
                  'with_shipping': true,
                  'requires_fiscal_receipt': true,
                },
              ];

    await tester.pumpWidget(host(ProviderInboxView(
        fetch: conRequisitos,
        leading: const SizedBox.shrink(),
        actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Necesito 30 sillas'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(
      find.byIcon(Icons.account_balance_outlined),
      findsNothing,
      reason: 'no marcó suplidor del Estado: no debe salir su símbolo',
    );
  });

  testWidgets('una solicitud sin requisitos no pinta ningún símbolo',
      (tester) async {
    Future<List<Map<String, dynamic>>> sinRequisitos(
            {String? kind, required bool todas}) async =>
        todas
            ? []
            : [
                {
                  'id': 'req-plano',
                  'source': 'marketplace',
                  'title': 'Necesito un plomero',
                  'description': 'Fuga de agua',
                  'kind': 'servicio',
                  'created_at': DateTime.now().toIso8601String(),
                },
              ];

    await tester.pumpWidget(host(ProviderInboxView(
        fetch: sinRequisitos,
        leading: const SizedBox.shrink(),
        actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Necesito un plomero'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
  });

  // Pedido PO 2026-08-09: la tarjeta de "Solicitudes para ti" ya NO muestra
  // la descripción (se sigue viendo en el detalle) y usa ese espacio para una
  // foto más grande. Solo la lista del PROVEEDOR cambia — la del cliente
  // ("Tus solicitudes") no se toca.
  group('tarjeta del proveedor sin descripción, foto más grande (08-09)', () {
    Future<List<Map<String, dynamic>>> conFotoYDescripcion(
            {String? kind, required bool todas}) async =>
        todas
            ? []
            : [
                {
                  'id': 'req-foto',
                  'source': 'marketplace',
                  'title': 'Necesito un plomero',
                  'description': 'Fuga de agua en la cocina, urge',
                  'kind': 'servicio',
                  'image_url': 'https://x/foto.jpg',
                  'created_at': DateTime.now().toIso8601String(),
                },
              ];

    testWidgets('la descripción de la solicitud NO se pinta en la tarjeta',
        (tester) async {
      await tester.pumpWidget(host(ProviderInboxView(
          fetch: conFotoYDescripcion,
          leading: const SizedBox.shrink(),
          actions: const [])));
      await tester.pumpAndSettle();

      expect(find.text('Necesito un plomero'), findsOneWidget);
      expect(find.text('Fuga de agua en la cocina, urge'), findsNothing);
    });

    testWidgets('la miniatura crece a 64x64 (antes 44x44)', (tester) async {
      await tester.pumpWidget(host(ProviderInboxView(
          fetch: conFotoYDescripcion,
          leading: const SizedBox.shrink(),
          actions: const [])));
      await tester.pumpAndSettle();

      final img = tester.widget<Image>(find.byType(Image).first);
      expect(img.width, 64);
      expect(img.height, 64);
    });

    testWidgets(
        'sin foto: el placeholder también crece a 64x64 y sigue mostrando el ícono',
        (tester) async {
      Future<List<Map<String, dynamic>>> sinFoto(
              {String? kind, required bool todas}) async =>
          todas
              ? []
              : [
                  {
                    'id': 'req-sinfoto',
                    'source': 'marketplace',
                    'title': 'Necesito un electricista',
                    'description': 'Cambiar breaker',
                    'kind': 'servicio',
                    'created_at': DateTime.now().toIso8601String(),
                  },
                ];
      await tester.pumpWidget(host(ProviderInboxView(
          fetch: sinFoto, leading: const SizedBox.shrink(), actions: const [])));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
      final placeholder = tester.widget<Container>(find
          .ancestor(
              of: find.byIcon(Icons.handyman_outlined),
              matching: find.byType(Container))
          .first);
      expect(placeholder.constraints?.maxWidth, 64);
      expect(placeholder.constraints?.maxHeight, 64);
    });
  });
}
