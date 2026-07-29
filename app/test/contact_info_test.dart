import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/contact_info.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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

  // Añadido en el fix round 1 (hallazgo del guardado en tienda,
  // request_detail_screen.dart:_maybeSaveToStore): isContactInfoError es la
  // parte que decide si el catch de un envío traduce el SQLSTATE al mensaje
  // humano o cae al genérico — sin tests propios hasta ahora, aunque ya se
  // usaba en dos call sites.
  group('isContactInfoError', () {
    test('true para JY422 — el rechazo real del trigger', () {
      expect(
        isContactInfoError(const PostgrestException(
          message: 'contact_info_not_allowed',
          code: 'JY422',
        )),
        isTrue,
      );
    });

    test(
        'false para JY500 — error de PROGRAMACIÓN nuestro, nunca se traduce '
        'al mensaje de "no incluyas teléfonos ni correos"', () {
      expect(
        isContactInfoError(const PostgrestException(
          message:
              'enforce_no_contact_info: la tabla no tiene la columna esperada',
          code: 'JY500',
        )),
        isFalse,
      );
    });

    test('false para otro SQLSTATE cualquiera (p. ej. JY429, anti-flood)', () {
      expect(
        isContactInfoError(const PostgrestException(
          message: 'Vas muy rápido, espera un momento.',
          code: 'JY429',
        )),
        isFalse,
      );
    });

    test('false para un error que no es PostgrestException', () {
      expect(isContactInfoError(Exception('red caída')), isFalse);
    });
  });
}
