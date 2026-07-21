import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/celebration.dart';

/// Contrato de las celebraciones: cada una monta un overlay por el navigator
/// raíz y se auto-cierra al terminar la animación (no fija los píxeles del
/// confeti ni del candado).
void main() {
  Widget host(void Function(BuildContext) onTap) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: ElevatedButton(
                onPressed: () => onTap(c),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

  testWidgets('aceptar: muestra el overlay y se auto-cierra', (tester) async {
    await tester.pumpWidget(host((c) => showAcceptCelebration(c)));
    await tester.tap(find.text('go'));
    await tester.pump(); // dispara la ruta
    await tester.pump(const Duration(milliseconds: 200)); // entra el overlay
    expect(find.byKey(const ValueKey('celebration-accept')), findsOneWidget);

    await tester.pumpAndSettle(); // corre toda la animación + la salida
    expect(find.byKey(const ValueKey('celebration-accept')), findsNothing);
  });

  testWidgets('desbloquear: muestra el overlay y se auto-cierra',
      (tester) async {
    await tester.pumpWidget(host((c) => showUnlockCelebration(c)));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('celebration-unlock')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration-unlock')), findsNothing);
  });

  testWidgets('tocar la pantalla salta la celebración', (tester) async {
    await tester.pumpWidget(host((c) => showAcceptCelebration(c)));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('celebration-accept')), findsOneWidget);

    // Un toque en cualquier parte la descarta antes de tiempo.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration-accept')), findsNothing);
  });
}
