import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_progress.dart';

/// La barra "N de ~M" debe ser HONESTA: meta estimada por el presupuesto real
/// del prompt (5 preguntas normal, 7-8 mayorista → mostramos ~4 / ~7 porque la
/// descripción inicial ya cuenta), nunca 100 % antes del turno `ready`, y si
/// la IA pregunta más de lo estimado la meta crece en vez de mentir.
void main() {
  group('estimatedTotal', () {
    test('base 4 para flujo normal, 7 para mayorista', () {
      expect(estimatedTotal(answered: 0, wholesale: false), 4);
      expect(estimatedTotal(answered: 2, wholesale: false), 4);
      expect(estimatedTotal(answered: 0, wholesale: true), 7);
    });

    test('si las respuestas alcanzan la base, la meta crece (nunca se llena)', () {
      expect(estimatedTotal(answered: 4, wholesale: false), 5);
      expect(estimatedTotal(answered: 6, wholesale: false), 7);
      expect(estimatedTotal(answered: 7, wholesale: true), 8);
    });
  });

  group('progressFraction', () {
    test('crece con cada respuesta sin llegar a 1', () {
      final a = progressFraction(answered: 0, wholesale: false, ready: false);
      final b = progressFraction(answered: 2, wholesale: false, ready: false);
      final c = progressFraction(answered: 5, wholesale: false, ready: false);
      expect(a, 0);
      expect(b, greaterThan(a));
      expect(c, greaterThan(b));
      expect(c, lessThan(1));
    });

    test('ready = barra llena', () {
      expect(progressFraction(answered: 2, wholesale: false, ready: true), 1);
    });
  });
}
