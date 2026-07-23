import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/celebration.dart';

// Humo: los dos assets Lottie de Jayi celebrando parsean y montan sin lanzar
// (valida que el conversor propio produce JSON que lottie-flutter acepta).
void main() {
  testWidgets('JayiCelebration monta ambas variantes', (tester) async {
    for (final v in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: JayiCelebration(onViolet: v, size: 160)),
        ),
      ));
      // deja que el asset (AssetBundle) resuelva y el composition se cargue
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(JayiCelebration), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
