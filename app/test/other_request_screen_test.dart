import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/other_request_screen.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

  final row = {
    'id': 'r1',
    'user_id': 'u2',
    'title': '200 auriculares Bluetooth',
    'description': 'Modelo genérico • color negro',
    'bullets': ['Modelo genérico', 'Color negro'],
    'kind': 'producto',
    'status': 'open',
    'is_wholesale': true,
    'with_shipping': true,
    'requires_fiscal_receipt': true,
    'image_url': null,
    'image_urls': <String>[],
    'created_at': DateTime.now().toIso8601String(),
  };

  testWidgets('muestra la solicitud ajena y el botón También busco esto',
      (tester) async {
    await tester.pumpWidget(host(
      OtherRequestScreen(requestId: 'r1', fetch: () async => row),
    ));
    await tester.pumpAndSettle();

    expect(find.text('200 auriculares Bluetooth'), findsOneWidget);
    // Chip titular de mayoreo, en mayúsculas (plantilla PO 2026-08-11).
    expect(find.text('AL POR MAYOR'), findsOneWidget);
    expect(find.text('También busco esto'), findsOneWidget);
  });

  testWidgets('el botón abre el diálogo de confirmación', (tester) async {
    await tester.pumpWidget(host(
      OtherRequestScreen(requestId: 'r1', fetch: () async => row),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('También busco esto'));
    await tester.pumpAndSettle();

    expect(find.text('Busco esto mismo'), findsOneWidget);
    expect(find.text('Sí, busco lo mismo'), findsOneWidget);
  });

  testWidgets('muestra los requisitos que el cliente exige', (tester) async {
    await tester.pumpWidget(host(
      OtherRequestScreen(requestId: 'r1', fetch: () async => row),
    ));
    await tester.pumpAndSettle();

    // Tarjetas teal de requisito (plantilla PO 2026-08-11): etiqueta arriba
    // y «Requerido» debajo, ya no chips "Requiere …".
    expect(find.text('REQUISITOS'), findsOneWidget);
    expect(find.text('ENVÍO'), findsOneWidget);
    expect(find.text('COMPROBANTE FISCAL'), findsOneWidget);
    expect(find.text('Requerido (NCF)'), findsOneWidget);
    expect(find.text('INSTALACIÓN'), findsNothing);
  });
}
