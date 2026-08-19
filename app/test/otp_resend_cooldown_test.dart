import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/verification/otp_sheet.dart';

/// El contador de «Reenviar código» solo arrancaba en el camino de ÉXITO. Tras
/// un fallo de envío el botón volvía a quedar habilitado en el mismo frame, sin
/// cuenta atrás: el servidor no devuelve el intento cuando el envío falla, así
/// que cinco toques seguidos agotaban el tope de 5/15 min y dejaban al usuario
/// bloqueado un cuarto de hora con la cuenta recién creada.
void main() {
  Future<void> pump(WidgetTester tester,
      {required Future<String> Function({required String phone, String? businessId}) send}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OtpSheet(phone: '+18090000000', send: send),
      ),
    ));
  }

  testWidgets('si el envío FALLA, el botón queda frenado 15 s', (tester) async {
    await pump(tester,
        send: ({required String phone, String? businessId}) =>
            Future<String>.error(Exception('sin red')));
    await tester.pump();

    // Frenado y con la cuenta atrás a la vista.
    expect(find.text('Reenviar código (15s)'), findsOneWidget);
    final boton = tester.widget<TextButton>(
        find.ancestor(of: find.text('Reenviar código (15s)'),
            matching: find.byType(TextButton)));
    expect(boton.onPressed, isNull, reason: 'debe estar deshabilitado');

    // Corre el reloj: a los 15 s vuelve a estar disponible.
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('Reenviar código'), findsOneWidget);
  });

  testWidgets('si el envío va bien, el freno es el de siempre (60 s)',
      (tester) async {
    await pump(tester,
        send: ({required String phone, String? businessId}) async => 'sms');
    await tester.pump();

    expect(find.text('Reenviar código (60s)'), findsOneWidget);
  });

  testWidgets('el error del envío sigue viéndose', (tester) async {
    await pump(tester,
        send: ({required String phone, String? businessId}) =>
            Future<String>.error(Exception('sin red')));
    await tester.pump();

    expect(find.textContaining('sin red'), findsOneWidget);
  });
}
