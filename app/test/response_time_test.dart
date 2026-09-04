import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/response_time.dart';

/// El umbral y el paso a palabras salieron de `reputation_screen.dart` cuando
/// apareció una SEGUNDA superficie que los usa (la sección "Como comprador" de
/// Estadísticas, PO 2026-09-04). Al ser compartidos, el criterio tiene que
/// quedar fijado en un sitio: si una pantalla lo cambiara por su cuenta, las
/// dos dejarían de decir lo mismo del mismo usuario.
void main() {
  group('responseTimeCopy', () {
    test('se calla por debajo del umbral de muestras', () {
      expect(responseTimeCopy(45, kMinResponseSamples - 1), isNull);
    });

    test('habla justo al alcanzar el umbral', () {
      expect(responseTimeCopy(45, kMinResponseSamples),
          'Regularmente respondes en 45 minutos');
    });

    test('se calla sin mediana, por muchas muestras que haya', () {
      expect(responseTimeCopy(null, 50), isNull);
    });

    test('se calla ante una mediana negativa (dato imposible)', () {
      expect(responseTimeCopy(-3, 50), isNull);
    });
  });

  group('humanMinutes', () {
    test('menos de una hora, en minutos', () {
      expect(humanMinutes(45), '45 minutos');
      expect(humanMinutes(59), '59 minutos');
    });

    test('una hora se dice en singular', () {
      expect(humanMinutes(60), 'una hora');
    });

    test('horas en plural, redondeadas', () {
      expect(humanMinutes(150), 'unas 3 horas');
    });

    test('a partir de un día, en días', () {
      expect(humanMinutes(1440), 'un día');
      expect(humanMinutes(2880), '2 días');
    });

    test('nunca abrevia: ni "min" ni "h"', () {
      for (final m in [5, 90, 1500, 10000]) {
        final s = humanMinutes(m);
        expect(s, isNot(contains('min ')));
        expect(s, isNot(matches(RegExp(r'\dh\b'))));
      }
    });
  });
}
