import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/ai_question_options.dart';

/// Espejo de `jayalo-main/src/lib/aiQuestionOptions.test.ts`: los dos clientes
/// consumen el mismo endpoint de IA, así que la detección debe coincidir.
void main() {
  group('isCatchAllOption', () {
    test('detecta las variantes que la IA genera para "otra"', () {
      expect(isCatchAllOption('Otra marca'), isTrue);
      expect(isCatchAllOption('Otro modelo'), isTrue);
      expect(isCatchAllOption('Otra'), isTrue);
      expect(isCatchAllOption('Otro'), isTrue);
      expect(isCatchAllOption('Otra opción'), isTrue);
      expect(isCatchAllOption('Otra opción…'), isTrue);
      expect(isCatchAllOption('  otra MARCA  '), isTrue);
    });

    test('detecta el PLURAL y el paréntesis de ayuda (bug PO 2026-07-28)', () {
      expect(isCatchAllOption('Otros'), isTrue);
      expect(isCatchAllOption('Otras'), isTrue);
      expect(isCatchAllOption('Otras marcas'), isTrue);
      expect(isCatchAllOption('Otros modelos'), isTrue);
      expect(isCatchAllOption('Otras opciones'), isTrue);
      expect(isCatchAllOption('Otros colores'), isTrue);
      expect(isCatchAllOption('Otras medidas'), isTrue);
      expect(isCatchAllOption('Otro tamaño'), isTrue);
      expect(isCatchAllOption('Otro (especifica)'), isTrue);
      expect(isCatchAllOption('Otra marca (escríbela)'), isTrue);
      expect(isCatchAllOption('Otro:'), isTrue);
    });

    test('NO confunde marcas ni respuestas reales que empiezan parecido', () {
      expect(isCatchAllOption('Otro Mundo Cerveza'), isFalse);
      expect(isCatchAllOption('Otros Mundos Cerveza'), isFalse);
      expect(isCatchAllOption('Otras marcas japonesas'), isFalse);
      expect(isCatchAllOption('Motorola'), isFalse);
      expect(isCatchAllOption('Toyota'), isFalse);
      expect(isCatchAllOption('Nosotros lo instalamos'), isFalse);
    });

    test('no marca como catch-all valores vacíos', () {
      expect(isCatchAllOption(''), isFalse);
      expect(isCatchAllOption('   '), isFalse);
    });
  });
}
