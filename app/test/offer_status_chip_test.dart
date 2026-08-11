import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/request_status_screen.dart';

/// Chip de estado de una oferta en la hoja "Ver ofertas" del cliente.
///
/// El caso que motivó el fichero (pedido PO 2026-08-10): una oferta aceptada
/// cuyo CHAT murió por inactividad seguía diciendo "En contacto" — mentira que
/// además acompañaba al bug de fase (la solicitud entera se pintaba "Cerrada"
/// aunque tuviera ofertas pendientes vivas; ver phase_test.dart).
void main() {
  Future<void> pump(WidgetTester tester, Widget chip) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) => chip))),
      );

  Widget chip(
    BuildContext context,
    Map<String, dynamic> o, {
    ClosedReason? closedReason,
  }) =>
      offerStatusChip(context, o, false, closedReason: closedReason);

  testWidgets('aceptada con chat vivo y desbloqueada → "En contacto"',
      (tester) async {
    await pump(
      tester,
      Builder(
        builder: (c) =>
            chip(c, {'status': 'accepted', 'unlocked_at': '2026-08-07'}),
      ),
    );
    expect(find.text('En contacto'), findsOneWidget);
  });

  testWidgets('aceptada con chat muerto por inactividad → "Chat cerrado"',
      (tester) async {
    await pump(
      tester,
      Builder(
        builder: (c) => chip(
          c,
          {'status': 'accepted', 'unlocked_at': '2026-08-07'},
          closedReason: ClosedReason.inactivity,
        ),
      ),
    );
    expect(find.text('Chat cerrado'), findsOneWidget);
    expect(find.text('En contacto'), findsNothing);
  });

  testWidgets('aceptada marcada como no concretada → "No concretada"',
      (tester) async {
    await pump(
      tester,
      Builder(
        builder: (c) => chip(
          c,
          {'status': 'accepted', 'unlocked_at': null},
          closedReason: ClosedReason.notAgreed,
        ),
      ),
    );
    expect(find.text('No concretada'), findsOneWidget);
  });

  testWidgets('pendiente sigue diciendo "Pendiente" (sin razón de cierre)',
      (tester) async {
    await pump(
      tester,
      Builder(builder: (c) => chip(c, {'status': 'pending'})),
    );
    expect(find.text('Pendiente'), findsOneWidget);
  });
}
