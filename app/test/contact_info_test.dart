import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/contact_info.dart';

void main() {
  const bloquea = [
    'Llámame al 809-555-1234',
    '8095551234',
    '8 0 9 5 5 5 1 2 3 4',
    '+1 (829) 555-1234',
    '849.555.1234',
    '809,555,1234',
    '８０９５５５１２３４',
    'Escríbeme a wa.me/18095551234',
    'Contáctame: ventas@ferreteria.do',
  ];
  const pasa = [
    'Garantía de 12 meses',
    'RNC 130123456',
    'Medida 809 x 1234567 mm',
    'modelo 809, pieza 5551234',
    '',
  ];

  for (final entrada in bloquea) {
    test('bloquea: $entrada', () {
      expect(containsContactInfo(entrada), isTrue);
    });
  }

  for (final entrada in pasa) {
    test('deja pasar: $entrada', () {
      expect(containsContactInfo(entrada), isFalse);
    });
  }

  test('tolera null', () => expect(containsContactInfo(null), isFalse));
}
