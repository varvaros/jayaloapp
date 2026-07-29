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

  // Casos NUEVOS de la revision final (2026-07-29). Van aparte de la bateria
  // canonica de 14 (que no se toca) y son los mismos, uno a uno, que
  // `src/lib/contactInfo.test.ts` de la web. Los guiones Unicode se escriben
  // con `String.fromCharCode` porque en el codigo fuente son indistinguibles
  // del `-` ASCII a simple vista.
  final bloqueaNuevos = <String, String>{
    // El SQL usa `[[:alnum:]]`, que con el lc_ctype UTF-8 de Supabase casa
    // letras acentuadas: antes la BD los rechazaba y el aviso del formulario
    // no, y el usuario perdia lo escrito.
    'correo con tilde en el nombre': 'josé@gmail.com',
    'correo con tilde en el dominio': 'ventas@ferretería.do',
    'telefono con guion largo U+2013':
        '809${String.fromCharCode(0x2013)}555${String.fromCharCode(0x2013)}1234',
    'telefono con guion U+2010':
        '809${String.fromCharCode(0x2010)}555${String.fromCharCode(0x2010)}1234',
    'telefono con signo menos U+2212':
        '809${String.fromCharCode(0x2212)}555${String.fromCharCode(0x2212)}1234',
    // Ruta de Storage con `Date.now()` que empieza por 1829: el detector SI la
    // casa (al quitar `-`/`.` el timestamp queda como bloque de digitos
    // contiguo). En la app NO es un problema porque los call sites revisan
    // listas explicitas de campos de texto, nunca URLs de imagen; en la web si
    // lo era, y por eso `payloadHasContactInfo` salta las URLs (ver
    // `src/lib/contactInfo.test.ts`). El caso se replica aqui para que las dos
    // implementaciones sigan dando el MISMO veredicto sobre la misma entrada.
    'ruta de Storage con timestamp 1829':
        'https://mfaiklvobnvgusbcssbx.supabase.co/storage/v1/object/public/'
            'business-logos/8e2b0f4a-1111-2222-3333-444455556666/requests/'
            '1829773255605-3i726g-p0.webp',
  };

  for (final entrada in bloquea) {
    test('bloquea: $entrada', () {
      expect(containsContactInfo(entrada), isTrue);
    });
  }

  bloqueaNuevos.forEach((nombre, entrada) {
    test('bloquea (caso nuevo) $nombre', () {
      expect(containsContactInfo(entrada), isTrue);
    });
  });

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
