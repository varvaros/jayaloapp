import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/error_reporter.dart';
import 'package:jayalo_app/features/provider/unlock_flow.dart';
// `HoldToConfirmButton` vive aquí: el segundo test lo busca para hacer el hold.
import 'package:jayalo_app/features/shared/brand_kit.dart';

/// El teléfono NO se pide al pintar. En las ofertas, la RPC que lo devuelve
/// (`get_unlocked_offer_contact`) MARCA `whatsapp_revealed_at` y con eso el
/// proveedor pierde el derecho a la devolución de créditos: pedirlo antes del
/// hold se lo quitaba sin que hubiera visto nada (bug 2026-09-04).
Widget _host(Future<String?> Function() loadPhone) => MaterialApp(
      home: Scaffold(
        body: WhatsappReveal(
          loadPhone: loadPhone,
          firstName: 'Ana',
          refundApplies: true,
        ),
      ),
    );

void main() {
  testWidgets('no pide el teléfono al pintar', (tester) async {
    var llamadas = 0;
    await tester.pumpWidget(_host(() async {
      llamadas++;
      return '8095551234';
    }));
    expect(llamadas, 0,
        reason: 'pedir el teléfono al pintar quema la devolución');
  });

  testWidgets('sin teléfono avisa y no cierra el aviso', (tester) async {
    await tester.pumpWidget(_host(() async => null));

    final boton = find.byType(HoldToConfirmButton);
    final gesto = await tester.startGesture(tester.getCenter(boton));
    // El hold dura JayaloMotion.holdConfirm (2,5 s); se pasa de largo.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await gesto.up();
    await tester.pumpAndSettle();

    expect(find.text('No pudimos abrir WhatsApp. Intenta de nuevo.'),
        findsOneWidget);
    expect(find.byType(WhatsappReveal), findsOneWidget,
        reason: 'el aviso sigue en pantalla para reintentar');
  });

  testWidgets('un loadPhone que lanza avisa y reporta el error',
      (tester) async {
    final reportes = <Object>[];
    debugOnReport = reportes.add;
    addTearDown(() => debugOnReport = null);

    await tester.pumpWidget(_host(() async => throw Exception('boom')));

    final boton = find.byType(HoldToConfirmButton);
    final gesto = await tester.startGesture(tester.getCenter(boton));
    // El hold dura JayaloMotion.holdConfirm (2,5 s); se pasa de largo.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await gesto.up();
    await tester.pumpAndSettle();

    expect(find.text('No pudimos abrir WhatsApp. Intenta de nuevo.'),
        findsOneWidget);
    expect(find.byType(WhatsappReveal), findsOneWidget,
        reason: 'el aviso sigue en pantalla para reintentar');
    expect(reportes, isNotEmpty,
        reason: 'un fallo de loadPhone debe llegar al reporter');
  });
}
