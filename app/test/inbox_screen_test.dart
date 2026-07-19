import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    await tester.tap(find.text('Todas'));
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

    await tester.tap(find.text('Todas'));
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
        leading: const SizedBox.shrink(), actions: const [],
        balanceFetch: () async => 5)));
    await tester.pumpAndSettle();

    expect(find.text('Interesado en tu producto'), findsOneWidget);
    expect(find.text('Taladro inalámbrico'), findsOneWidget);
  });

  testWidgets('la tarjeta de interés bloqueada muestra el costo',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: fetchOnly(interestRow()),
        leading: const SizedBox.shrink(), actions: const [],
        balanceFetch: () async => 5)));
    await tester.pumpAndSettle();

    expect(find.text('Conversar · 1 crédito'), findsOneWidget);
  });

  testWidgets('la tarjeta de interés desbloqueada muestra "Abrir chat"',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: fetchOnly(interestRow(unlocked: true)),
        leading: const SizedBox.shrink(), actions: const [],
        balanceFetch: () async => 5)));
    await tester.pumpAndSettle();

    expect(find.text('Abrir chat'), findsOneWidget);
    expect(find.text('Conversar · 1 crédito'), findsNothing);
  });

  testWidgets(
      'saldo insuficiente ofrece recargar en vez de lanzar al cobro',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: fetchOnly(interestRow()),
        leading: const SizedBox.shrink(), actions: const [],
        balanceFetch: () async => 0)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conversar · 1 crédito'));
    await tester.pumpAndSettle();

    expect(find.text('Saldo insuficiente'), findsOneWidget);
    expect(find.text('Recargar'), findsOneWidget);
    expect(find.textContaining('Mantén presionado'), findsNothing);
  });

  testWidgets(
      'saldo suficiente muestra la confirmación de desbloqueo (mantener presionado)',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(
        fetch: fetchOnly(interestRow()),
        leading: const SizedBox.shrink(), actions: const [],
        balanceFetch: () async => 5)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conversar · 1 crédito'));
    await tester.pumpAndSettle();

    expect(find.text('Conversar con el comprador'), findsOneWidget);
    expect(find.textContaining('Mantén presionado'), findsOneWidget);
    expect(find.text('Saldo insuficiente'), findsNothing);
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
        fetch: mixed, leading: const SizedBox.shrink(), actions: const [], balanceFetch: () async => 0)));
    await tester.pumpAndSettle();

    expect(find.text('Necesito un plomero'), findsOneWidget);
    expect(find.text('Interesado en tu producto'), findsOneWidget);
    expect(find.text('Conversar · 1 crédito'), findsOneWidget);
  });
}
