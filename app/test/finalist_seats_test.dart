import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/provider/request_detail_screen.dart'
    show FinalistSeats;

/// Los 3 cupos de finalista como asientos (mockup aprobado 2026-08-11).
void main() {
  Future<void> pump(WidgetTester tester, int accepted) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinalistSeats(accepted: accepted, color: Colors.amber),
          ),
        ),
      );

  testWidgets('1 de 3: un asiento lleno (check) y dos aros', (tester) async {
    await pump(tester, 1);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('0 de 3: ningún check', (tester) async {
    await pump(tester, 0);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('el conteo se recorta al tope de 3', (tester) async {
    // La columna materializada podría traer cualquier cosa.
    await pump(tester, 7);
    expect(find.byIcon(Icons.check), findsNWidgets(3));
  });
}
