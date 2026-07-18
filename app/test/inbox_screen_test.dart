import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/inbox_screen.dart';

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
    await tester.pumpWidget(host(ProviderInboxView(fetch: vacio, actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Solicitudes para ti'), findsOneWidget);
    expect(find.text('Todas las solicitudes'), findsNothing);
    final toggle =
        tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(toggle.selected, {false});
  });

  testWidgets('el estado vacío de "Para ti" habla del rubro del proveedor',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(fetch: vacio, actions: const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('coinciden con tu negocio'), findsOneWidget);
  });

  testWidgets(
      'tocar "Todas" cambia el título del AppBar y el mensaje del estado vacío',
      (tester) async {
    await tester.pumpWidget(host(ProviderInboxView(fetch: vacio, actions: const [])));
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

    await tester.pumpWidget(host(ProviderInboxView(fetch: recorder, actions: const [])));
    await tester.pumpAndSettle();
    expect(calls, [false]);

    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    expect(calls, [false, true]);
  });
}
