import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phone.dart';

void main() {
  test('10 dígitos asume RD (+1)', () => expect(normalizePhone('8095551234'), '+18095551234'));
  test('respeta + existente', () => expect(normalizePhone('+34 600 111 222'), '+34600111222'));
  test('limpia caracteres', () => expect(normalizePhone('(809) 555-1234'), '+18095551234'));
  test('vacío', () => expect(normalizePhone('  '), ''));
  test('no-10-dígitos sin + devuelve solo dígitos', () => expect(normalizePhone('555 1234'), '5551234'));
  test('isValidPhone exige 8 dígitos', () {
    expect(isValidPhone('8095551'), false);
    expect(isValidPhone('80955512'), true);
  });
}
