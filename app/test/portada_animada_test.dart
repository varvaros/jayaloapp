import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jayalo_app/features/auth/jayalo_imagotipo.dart';
import 'package:jayalo_app/features/auth/portada_animada.dart';

void main() {
  group('imagotipo', () {
    test('los seis paths del SVG parsean y tienen área', () {
      for (final p in [
        ImagotipoPaths.wordmark,
        ImagotipoPaths.reg,
        ImagotipoPaths.isoTick,
        ImagotipoPaths.cuerpo,
        ImagotipoPaths.ojo,
        ImagotipoPaths.iris,
      ]) {
        final b = p.getBounds();
        expect(b.isEmpty, isFalse);
        // Todo cae dentro del viewBox 374×136 (con margen por los trazos).
        expect(b.left, greaterThan(-10));
        expect(b.top, greaterThan(-10));
        expect(b.right, lessThan(384));
        expect(b.bottom, lessThan(146));
      }
    });

    test('el parser rechaza comandos que el imagotipo no usa', () {
      // Una 'C' tras una M se intenta leer como coordenada → FormatException.
      expect(() => parseImagotipoPath('M 0 0 C 1 1 2 2 3 3'),
          throwsFormatException);
      // Datos sin comando inicial → StateError del propio parser.
      expect(() => parseImagotipoPath('7 7'), throwsA(isA<StateError>()));
    });
  });

  group('PortadaAnimada', () {
    testWidgets('pinta sin excepciones a lo largo del loop de 10 s',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: PortadaAnimada()),
      ));
      expect(find.byType(CustomPaint), findsWidgets);
      // Momentos clave del loop: reposo, sorbo, salto, aterrizaje y cierre.
      for (final ms in [500, 2700, 3750, 3000, 850, 1500]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
