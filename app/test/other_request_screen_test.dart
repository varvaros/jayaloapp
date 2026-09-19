import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/request_share_message.dart';
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
    expect(find.text('TRASLADO'), findsOneWidget);
    expect(find.text('COMPROBANTE FISCAL'), findsOneWidget);
    expect(find.text('Requerido (NCF)'), findsOneWidget);
    expect(find.text('INSTALACIÓN'), findsNothing);
  });

  group('CTA del admin', () {
    Widget hostAdmin(
      Map<String, dynamic> fila,
      void Function(ShareableRequest) onSend,
    ) =>
        host(OtherRequestScreen(
          requestId: 'r1',
          fetch: () async => fila,
          esAdmin: () async => true,
          onSend: onSend,
        ));

    testWidgets('al admin le sale "Enviar a proveedor", NO "También busco esto"',
        (tester) async {
      await tester.pumpWidget(hostAdmin(row, (_) {}));
      await tester.pumpAndSettle();

      expect(find.text('Enviar a proveedor'), findsOneWidget);
      // "En lugar de" (PO 2026-09-18): el admin no viene a copiarse la
      // solicitud, así que el CTA del cliente no puede seguir ahí.
      expect(find.text('También busco esto'), findsNothing);
    });

    testWidgets('el botón manda ESA solicitud', (tester) async {
      final enviadas = <String>[];
      await tester.pumpWidget(hostAdmin(row, (r) => enviadas.add(r.id)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar a proveedor'));
      await tester.pumpAndSettle();
      expect(enviadas, ['r1']);
    });

    testWidgets('una solicitud DIRIGIDA no se puede enviar', (tester) async {
      final enviadas = <String>[];
      await tester.pumpWidget(hostAdmin(
        {...row, 'target_business_id': 'b9'},
        (r) => enviadas.add(r.id),
      ));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'Esta solicitud va dirigida a un negocio: el enlace no abre para quien no tenga cuenta.'),
          findsOneWidget);
      // 🔴 El botón apagado no basta como prueba: lo que muerde es que NO
      // salga un enlace muerto por WhatsApp, así que se toca de verdad.
      await tester.tap(find.text('Enviar a proveedor'));
      await tester.pumpAndSettle();
      expect(enviadas, isEmpty);
    });

    testWidgets('una solicitud CERRADA tampoco', (tester) async {
      final enviadas = <String>[];
      await tester.pumpWidget(hostAdmin(
        {...row, 'status': 'completed'},
        (r) => enviadas.add(r.id),
      ));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'Solo se pueden enviar las solicitudes abiertas: el enlace de una cerrada no abre sin cuenta.'),
          findsOneWidget);
      await tester.tap(find.text('Enviar a proveedor'));
      await tester.pumpAndSettle();
      expect(enviadas, isEmpty);
    });

    testWidgets('quien no es admin sigue viendo el CTA de siempre',
        (tester) async {
      await tester.pumpWidget(host(OtherRequestScreen(
        requestId: 'r1',
        fetch: () async => row,
        esAdmin: () async => false,
      )));
      await tester.pumpAndSettle();

      expect(find.text('También busco esto'), findsOneWidget);
      expect(find.text('Enviar a proveedor'), findsNothing);
    });
  });
}
